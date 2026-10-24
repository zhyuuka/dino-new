#!/usr/bin/env bash
# 一键验证闭环：环境自检 → 导入 → 单测 → 冒烟 →（可选）APK → 归档带时间戳的记录
#
# 用法：
#   bash scripts/verify.sh          # 只跑导入/单测/冒烟
#   bash scripts/verify.sh --apk    # 额外导出 build/DinoWorld-verify.apk
#
# 退出码：0 = PASS，1 = FAIL，2 = 环境不可用
#
# 所有 Godot 调用都带 --headless 与 timeout，日志先落到 /tmp/verify-<step>.log 再解析，
# 避免把引擎噪声刷满终端。

set -u

# ---------- 顶部配置 ----------
ROOT=/workspace/dino-new
GODOT=/workspace/tools/Godot_v4.4.1-stable_linux.x86_64
export XDG_DATA_HOME=/workspace/tools/godotdata
export XDG_CONFIG_HOME=/workspace/tools/godotconfig

ANDROID_SDK=/workspace/tools/android-sdk
JDK_HOME=/workspace/tools/jdk17

IMPORT_LOG=/tmp/verify-import.log
UNIT_LOG=/tmp/verify-unit.log
SMOKE_LOG=/tmp/verify-smoke.log
APK_LOG=/tmp/verify-apk.log

REPORTS_DIR="$ROOT/docs/reports"
APK_PATH="$ROOT/build/DinoWorld-verify.apk"

now_ms() { date +%s%3N; }
ms_to_s() { awk -v ms="$1" 'BEGIN { printf "%.1f", ms / 1000.0 }'; }

# ---------- 参数 ----------
WITH_APK=0
for arg in "$@"; do
	case "$arg" in
		--apk)
			WITH_APK=1
			;;
		-h|--help)
			echo "用法: bash scripts/verify.sh [--apk]"
			exit 0
			;;
		*)
			echo "ERROR: 未知参数 $arg（仅支持 --apk）"
			exit 2
			;;
	esac
done

# ---------- 环境自检 ----------
if [ ! -x "$GODOT" ]; then
	echo "ERROR: Godot 不存在或不可执行：$GODOT"
	exit 2
fi

if [ ! -d "$ANDROID_SDK" ]; then
	echo "WARN: Android SDK 缺失（$ANDROID_SDK）。单测/冒烟不需要 SDK，仅 APK 导出不可用。"
fi

if [ "$WITH_APK" -eq 1 ]; then
	if [ ! -d "$JDK_HOME" ]; then
		echo "ERROR: --apk 需要 JDK，但未找到 $JDK_HOME"
		exit 2
	fi
	export JAVA_HOME="$JDK_HOME"
	export PATH="$JAVA_HOME/bin:$PATH"
fi

# ---------- 第 1 步：仓库与版本信息 ----------
GIT_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
VERSION=$(grep -m1 '^config/version=' "$ROOT/project.godot" | cut -d'"' -f2)
VERSION=${VERSION:-unknown}

VERIFY_TS=$(date '+%Y-%m-%d %H:%M:%S %Z')
REPORT_TS=$(date +%Y%m%d-%H%M%S)
REPORT="$REPORTS_DIR/verify-$REPORT_TS.md"
mkdir -p "$REPORTS_DIR"

TOTAL_T0=$(now_ms)

echo "=== Dino World 验证闭环 ==="
echo "时间   : $VERIFY_TS"
echo "分支   : $GIT_BRANCH"
echo "提交   : $GIT_COMMIT"
echo "版本   : $VERSION"
echo "模式   : $([ "$WITH_APK" -eq 1 ] && echo '完整（含 APK）' || echo '快速（导入+单测+冒烟）')"
echo

# ---------- 第 2 步：导入 ----------
echo "[1/3] 导入资源…"
T0=$(now_ms)
timeout 600 "$GODOT" --headless --path "$ROOT" --import > "$IMPORT_LOG" 2>&1
IMPORT_RC=$?
IMPORT_MS=$(( $(now_ms) - T0 ))
IMPORT_ERRORS=$(grep -cE 'SCRIPT ERROR|Parse Error' "$IMPORT_LOG" 2>/dev/null || true)
IMPORT_ERRORS=${IMPORT_ERRORS:-0}
echo "      退出码=$IMPORT_RC 耗时=$(ms_to_s "$IMPORT_MS")s 脚本/解析错误=$IMPORT_ERRORS"

# ---------- 第 3 步：单测 ----------
echo "[2/3] 数据层单测…"
T0=$(now_ms)
timeout 300 "$GODOT" --headless --path "$ROOT" -s res://tests/run_tests.gd > "$UNIT_LOG" 2>&1
UNIT_RC=$?
UNIT_MS=$(( $(now_ms) - T0 ))
UNIT_PASSED=$(awk '/^PASSED: [0-9]+ \/ FAILED: [0-9]+$/{print $2}' "$UNIT_LOG" | tail -n1)
UNIT_FAILED=$(awk '/^PASSED: [0-9]+ \/ FAILED: [0-9]+$/{print $5}' "$UNIT_LOG" | tail -n1)
UNIT_PASSED=${UNIT_PASSED:-}
UNIT_FAILED=${UNIT_FAILED:-}
echo "      退出码=$UNIT_RC 耗时=$(ms_to_s "$UNIT_MS")s PASSED=${UNIT_PASSED:-?} / FAILED=${UNIT_FAILED:-?}"

# ---------- 第 4 步：冒烟 ----------
echo "[3/3] 主场景冒烟（SMOKE_SECONDS 默认 40）…"
T0=$(now_ms)
timeout 180 "$GODOT" --headless --path "$ROOT" -s res://tests/smoke.gd > "$SMOKE_LOG" 2>&1
SMOKE_RC=$?
SMOKE_MS=$(( $(now_ms) - T0 ))
SMOKE_ERRORS=$(grep -c 'SCRIPT ERROR' "$SMOKE_LOG" 2>/dev/null || true)
SMOKE_ERRORS=${SMOKE_ERRORS:-0}

SMOKE_JSON_LINE=$(grep -m1 '^SMOKE_JSON:' "$SMOKE_LOG" 2>/dev/null || true)
SMOKE_JSON=${SMOKE_JSON_LINE#SMOKE_JSON:}
SMOKE_OK=false
if [ -n "$SMOKE_JSON" ]; then
	if command -v jq >/dev/null 2>&1; then
		SMOKE_OK=$(printf '%s\n' "$SMOKE_JSON" | jq -r 'if .ok == true then "true" else "false" end' 2>/dev/null || echo "false")
	else
		printf '%s\n' "$SMOKE_JSON" | grep -q '"ok":true' && SMOKE_OK=true
	fi
fi
echo "      退出码=$SMOKE_RC 耗时=$(ms_to_s "$SMOKE_MS")s ok=$SMOKE_OK 脚本错误=$SMOKE_ERRORS"

# ---------- 第 6 步（可选）：APK 导出 ----------
APK_RC=-1
APK_MS=0
APK_SIZE_TEXT="未执行"
if [ "$WITH_APK" -eq 1 ]; then
	echo "[附加] 导出 APK（不签名发布）…"
	mkdir -p "$ROOT/build"
	T0=$(now_ms)
	timeout 600 "$GODOT" --headless --path "$ROOT" --export-release "Android Debug" "$APK_PATH" > "$APK_LOG" 2>&1
	APK_RC=$?
	APK_MS=$(( $(now_ms) - T0 ))
	if [ -f "$APK_PATH" ]; then
		APK_BYTES=$(stat -c%s "$APK_PATH" 2>/dev/null || echo 0)
		APK_SIZE_TEXT="$APK_BYTES B（$(awk -v b="$APK_BYTES" 'BEGIN { printf "%.2f MiB", b / 1048576.0 }')）"
	else
		APK_SIZE_TEXT="未生成"
	fi
	echo "      退出码=$APK_RC 耗时=$(ms_to_s "$APK_MS")s 体积=$APK_SIZE_TEXT"
fi

# ---------- 第 5 步：判定 ----------
VERDICT=PASS
[ "$IMPORT_ERRORS" -eq 0 ] || VERDICT=FAIL
{ [ -n "$UNIT_FAILED" ] && [ "$UNIT_FAILED" -eq 0 ]; } || VERDICT=FAIL
[ "$UNIT_RC" -eq 0 ] || VERDICT=FAIL
[ "$SMOKE_OK" = "true" ] || VERDICT=FAIL
[ "$SMOKE_ERRORS" -eq 0 ] || VERDICT=FAIL
[ "$SMOKE_RC" -eq 0 ] || VERDICT=FAIL
if [ "$WITH_APK" -eq 1 ]; then
	{ [ "$APK_RC" -eq 0 ] && [ -f "$APK_PATH" ]; } || VERDICT=FAIL
fi

TOTAL_MS=$(( $(now_ms) - TOTAL_T0 ))

# ---------- 第 7 步：生成带时间戳的记录 ----------
SMOKE_PRETTY="（无 SMOKE_JSON 输出）"
if [ -n "$SMOKE_JSON" ]; then
	SMOKE_PRETTY="$SMOKE_JSON"
	if command -v jq >/dev/null 2>&1; then
		SMOKE_PRETTY=$(printf '%s\n' "$SMOKE_JSON" | jq . 2>/dev/null || printf '%s\n' "$SMOKE_JSON")
	fi
fi

{
	echo "# 验证记录 · $REPORT_TS"
	echo
	echo "| 项 | 值 |"
	echo "|---|---|"
	echo "| 时间戳 | $VERIFY_TS |"
	echo "| Git 分支 | $GIT_BRANCH |"
	echo "| Git commit | $GIT_COMMIT |"
	echo "| 项目版本 | $VERSION |"
	echo "| 总耗时 | $(ms_to_s "$TOTAL_MS") s |"
	echo "| 结论 | **$VERDICT** |"
	echo
	echo "## 步骤结果"
	echo
	echo "| 步骤 | 耗时 | 退出码 | 关键数字 |"
	echo "|---|---|---|---|"
	echo "| 导入 | $(ms_to_s "$IMPORT_MS") s | $IMPORT_RC | SCRIPT ERROR/Parse Error = $IMPORT_ERRORS |"
	echo "| 单测 | $(ms_to_s "$UNIT_MS") s | $UNIT_RC | PASSED: ${UNIT_PASSED:-?} / FAILED: ${UNIT_FAILED:-?} |"
	echo "| 冒烟 | $(ms_to_s "$SMOKE_MS") s | $SMOKE_RC | ok=$SMOKE_OK，SCRIPT ERROR = $SMOKE_ERRORS |"
	if [ "$WITH_APK" -eq 1 ]; then
		echo "| APK 导出 | $(ms_to_s "$APK_MS") s | $APK_RC | 体积 $APK_SIZE_TEXT |"
	fi
	echo
	echo "## 冒烟 JSON"
	echo
	echo '```json'
	printf '%s\n' "$SMOKE_PRETTY"
	echo '```'
	echo
	echo "## 判定规则"
	echo
	echo "- 导入：SCRIPT ERROR / Parse Error 行数必须为 0"
	echo "- 单测：退出码 0 且 FAILED 为 0"
	echo "- 冒烟：SMOKE_JSON.ok 为 true，且进程输出 SCRIPT ERROR 行数为 0"
	if [ "$WITH_APK" -eq 1 ]; then
		echo "- APK：导出退出码 0 且产物存在"
	fi
	echo "- script_errors 字段固定为 -1，真实值以本记录「冒烟」行的 SCRIPT ERROR 计数为准"
	echo
	echo "## 日志位置"
	echo
	echo "- 导入：\`$IMPORT_LOG\`"
	echo "- 单测：\`$UNIT_LOG\`"
	echo "- 冒烟：\`$SMOKE_LOG\`"
	if [ "$WITH_APK" -eq 1 ]; then
		echo "- APK：\`$APK_LOG\`"
	fi

	if [ "$VERDICT" = "FAIL" ]; then
		echo
		echo "## 失败关键日志（最多 30 行）"
		echo
		echo '```text'
		FAIL_LOG=$(grep -hE 'SCRIPT ERROR|Parse Error|FAIL:|SMOKE_FATAL|ERROR:' "$IMPORT_LOG" "$UNIT_LOG" "$SMOKE_LOG" 2>/dev/null | tail -n 30 || true)
		if [ -z "$FAIL_LOG" ]; then
			FAIL_LOG=$(tail -n 30 "$SMOKE_LOG" 2>/dev/null || true)
		fi
		printf '%s\n' "$FAIL_LOG"
		echo '```'
	fi
} > "$REPORT"

# ---------- 第 8 步：终端结论 ----------
echo
echo "记录: $REPORT"
echo "VERIFY_RESULT: $VERDICT | report: $REPORT"

# ---------- 第 9 步：退出码 ----------
if [ "$VERDICT" = "PASS" ]; then
	exit 0
fi
exit 1
