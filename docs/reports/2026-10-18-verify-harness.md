# 验证闭环固化：`tests/smoke.gd` + `scripts/verify.sh`

> 日期：2026-10-18（仓库既有报告命名口径）
> 实际执行时间：2026-10-24 12:48:53 CST（Asia/Shanghai）
> 引擎：Godot 4.4.1 stable；项目版本：0.2.7；commit：`c7e61c6`（分支 `main`）

## 1. 背景与目标

此前冒烟用例是临时脚本（`tests/_smoke_tmp.gd`，运行后即删），导致：

- 每轮验证的命令、观察时长、采集字段不一致，结果无法纵向比较；
- 验证结果只停留在终端输出，没有带时间戳的归档；
- "开局是否真的进入世界"只能靠人看日志，缺少机器可读判定。

本轮把验证闭环固化为两个长期资产：

| 文件 | 角色 |
|---|---|
| `tests/smoke.gd` | 标准冒烟：自动走完选图→选种→进入世界，输出单行机器可读 JSON |
| `scripts/verify.sh` | 一键编排：环境自检 → 导入 → 单测 → 冒烟 →（可选）APK → 归档记录 |

## 2. `tests/smoke.gd` 设计

### 2.1 契约

- 入口：`extends SceneTree`，由 `-s res://tests/smoke.gd` 启动。
- 环境变量：
  - `SMOKE_SECONDS`：进入世界后的观察秒数，默认 `40`；
  - `SMOKE_MAP`：地图 id，默认 `forest`；
  - `SMOKE_SPECIES`：物种 id，默认 `raptor`。
- 启动时先打印 `SMOKE_START map=... species=... seconds=...`，便于在日志中定位区间。
- 流程：`load("res://scenes/Main.tscn")` → 挂到 `root` → 等 0.5s 让选图界面完成 `_ready` → 调用 `_on_map_selected(map)` 与 `_on_species_selected(species, false)`（等价玩家两次点击，不续档）→ 观察指定秒数 → 采样 → 输出单行 `SMOKE_JSON:`。
- `_initialize()` 只负责启动协程；`await create_timer(...)` 的续行由 SceneTree 正常帧循环驱动，不覆盖 `SceneTree._process`，避免破坏引擎内部调度。

### 2.2 采集字段

| 字段 | 来源 | 说明 |
|---|---|---|
| `ok` | 判定结果 | 见 2.3 |
| `seconds` | 选种后到采样前的实测墙钟 | 保留 2 位小数 |
| `player` / `ai` / `plants` / `eggs` / `corpses` | `get_nodes_in_group(Groups.*)` | 对应 `player/ai/plant/egg/corpse` 组 |
| `nodes` | Main 子树的递归节点数 | 未加载成功时退回整棵树 |
| `hunger` / `thirst` / `hp` | 玩家 `current_hunger/current_thirst/current_health` | 玩家不存在时为 0 |
| `pos_y` | 玩家 `global_position.y` | 玩家不存在时为 `-9999.0` |
| `mmi` | Main 子树内 `MultiMeshInstance3D` 数量 | 自然物/植物合批是否正常生成的量化指标 |
| `script_errors` | 固定 `-1` | 脚本读不到引擎 stderr，真实值由 `scripts/verify.sh` 从进程输出统计 |

### 2.3 判定规则

`ok = player == 1 且 pos_y ∈ (-50, 200) 且 nodes > 100`

- `player == 1`：世界确实进入了运行态且玩家存活（死亡自动重开也会重建玩家）；
- `pos_y` 区间：排除掉穿地形（地形高度为负值也不会误判）；
- `nodes > 100`：排除"场景加载了但世界没生成"的空壳状态。

采样后统一走 `_finish()` 输出 JSON 再退出：成功 `quit(0)`，失败 `quit(1)`；加载/实例化失败等致命路径也会输出 `ok=false` 的 JSON，保证 verify.sh 始终有东西可解析。

脚本头部注释已明确标注：**长期资产，不要改成临时脚本**。

## 3. `scripts/verify.sh` 设计

### 3.1 结构

- `set -u`（不启用 `-e`，逐步骤自行判定，保证失败也能生成记录）。
- 顶部固化：`ROOT=/workspace/dino-new`、`GODOT=/workspace/tools/Godot_v4.4.1-stable_linux.x86_64`、`XDG_DATA_HOME`、`XDG_CONFIG_HOME`。
- 环境自检：
  - Godot 不存在/不可执行 → 退出码 2；
  - Android SDK 缺失 → 仅警告（单测/冒烟不需要）；
  - JDK 仅 `--apk` 时必需，缺失 → 退出码 2，并注入 `JAVA_HOME`/`PATH`。
- 所有 Godot 调用统一 `--headless` + `timeout`，日志落到 `/tmp/verify-<step>.log` 再解析，终端只打印摘要。
- 步骤：仓库信息 → 导入（600s）→ 单测（300s）→ 冒烟（180s）→（可选）APK 导出（600s）→ 判定 → 生成记录 → 打印结论。

### 3.2 解析与判定

| 步骤 | 解析方式 | 通过条件 |
|---|---|---|
| 导入 | `grep -cE 'SCRIPT ERROR\|Parse Error' /tmp/verify-import.log` | 行数 = 0 |
| 单测 | `awk` 抓末行 `PASSED: n / FAILED: m` | 退出码 0 且 `FAILED = 0` |
| 冒烟 | 抓 `^SMOKE_JSON:` 行，用 `jq -r '.ok'` 判定 | 退出码 0、`ok=true`、`/tmp/verify-smoke.log` 中 `SCRIPT ERROR` 行数 = 0 |
| APK | 导出退出码 + 产物是否存在 | 退出码 0 且文件存在（仅 `--apk`） |

全部满足 → `PASS`，否则 `FAIL`；`FAIL` 退出码 1。

### 3.3 记录归档

- 路径：`docs/reports/verify-$(date +%Y%m%d-%H%M%S).md`；
- 内容：时间戳、分支/commit/版本、总耗时、各步骤耗时与退出码、导入错误数、单测数字、格式化冒烟 JSON、判定规则、日志位置；
- `FAIL` 时追加最多 30 行关键日志（优先 `SCRIPT ERROR|Parse Error|FAIL:|SMOKE_FATAL|ERROR:`，无命中则回落到冒烟日志尾部）；
- 终端最后一行：`VERIFY_RESULT: PASS|FAIL | report: <路径>`。

## 4. 首跑输出（2026-10-24 12:48:53 CST）

命令：

```bash
cd /workspace/dino-new && bash scripts/verify.sh
```

终端摘要：

```text
=== Dino World 验证闭环 ===
时间   : 2026-10-24 12:48:53 CST
分支   : main
提交   : c7e61c6
版本   : 0.2.7
模式   : 快速（导入+单测+冒烟）

[1/3] 导入资源…
      退出码=0 耗时=6.3s 脚本/解析错误=0
[2/3] 数据层单测…
      退出码=0 耗时=1.3s PASSED=166 / FAILED=0
[3/3] 主场景冒烟（SMOKE_SECONDS 默认 40）…
      退出码=0 耗时=42.3s ok=true 脚本错误=0

记录: /workspace/dino-new/docs/reports/verify-20261024-124853.md
VERIFY_RESULT: PASS | report: /workspace/dino-new/docs/reports/verify-20261024-124853.md
```

冒烟原始行：

```text
SMOKE_START map=forest species=raptor seconds=40.0
SMOKE_JSON:{"ai":14,"corpses":0,"eggs":0,"hp":35,"hunger":98,"mmi":88,"nodes":677,"ok":true,"plants":30,"player":1,"pos_y":9.281,"script_errors":-1,"seconds":40.23,"thirst":98}
```

关键数字：

| 项 | 首跑值 |
|---|---|
| 导入错误（SCRIPT ERROR / Parse Error） | 0 |
| 单测 | PASSED 166 / FAILED 0（1.3s） |
| 冒烟 | ok=true，SCRIPT ERROR = 0（42.3s） |
| 玩家 / AI / 植物 / 蛋 / 尸体 | 1 / 14 / 30 / 0 / 0 |
| 节点数 / MultiMeshInstance3D | 677 / 88 |
| 玩家位置 pos_y | 9.281 |
| 饥饿 / 口渴 / 血量 | 98 / 98 / 35 |
| 总耗时 | 49.9s |

首跑结论 **PASS**，记录已归档至 `/workspace/dino-new/docs/reports/verify-20261024-124853.md`。

> 注：`hp=35` 是 40 秒窗口内被 14 只 AI 围攻后的真实值。当前判定不包含血量，因此"存活但重伤"仍算通过；如需更严格，可在后续版本把 `hp > 0` 或在窗口内死亡计入失败。

## 5. 文档同步

- `docs/QA.md` 第二章由"冒烟基线模板"改写为"冒烟基线（一键验证）"：
  - 明确唯一入口为 `tests/smoke.gd` 与 `scripts/verify.sh`；
  - 写明 **任何提交前必须 PASS**，记录必须归档到 `docs/reports/verify-*.md`；
  - SMK-01/02/03/09 改为脚本内真实命令与判定标准；
  - 新增 smoke JSON 字段契约、`ok` 判定、记录格式；
  - 手工用例保留为 SMK-04～SMK-08，并标明"自动冒烟覆盖不到，发版前人工执行"。

## 6. 风险与后续

1. **40 秒窗口对冷启动可能偏紧**：本轮导入缓存已热，冒烟 42.3s 通过；若换机器或首次导入后立刻冒烟，加载可能吃掉大半窗口。可用 `SMOKE_SECONDS=60 bash scripts/verify.sh` 放宽，但跨轮比较时必须记录同一口径。
2. **`script_errors=-1` 依赖外部统计**：单独运行 `tests/smoke.gd` 时拿不到真实脚本错误数，只有 `verify.sh` 会补上 `SCRIPT ERROR` 计数。禁止绕过 `verify.sh` 用裸 JSON 当最终结论。
3. **判定偏粗**：`ok` 只看玩家数/高度/节点数，不校验 AI 种群、饥饿口渴曲线、蛋与尸体链路；这些仍由单测与手工用例兜底。`hp=35` 仍 PASS 即为示例。
4. **随机性导致数字波动**：`Main._ready` 调用 `randomize()`，AI 数量（本轮 14）、植物数（30）会随局变化。纵向比较应看区间与趋势，不应要求逐字段完全相等。
5. **`mmi` 口径**：定义为 Main 子树内 `MultiMeshInstance3D` 节点数（自然物 + 植物合批），不含 MultiMesh 实例总数；后续若改成实例总数需在 QA.md 同步口径。
6. **导入错误统计是行级 grep**：只统计含 `SCRIPT ERROR|Parse Error` 的行，多行堆栈的后续行不计入；若出现堆栈但首行被引擎吞掉，可能低估。发现异常时应直接翻 `/tmp/verify-import.log`。
7. **超时即失败**：`timeout` 返回 124 会进入 FAIL，日志保留在 `/tmp` 便于复盘；`/tmp` 可能被清理，需要长期留证时应保存记录与原始日志。
8. **`--apk` 本轮未执行**：只验证了快速链路。APK 导出仍受 SDK/JDK/导出模板环境约束，JDK 缺失时脚本会直接退出（退出码 2），不会产生误报 PASS。
9. **引擎自动生成 `tests/smoke.gd.uid`**：Godot 4.4 导入时为新脚本生成 UID 侧车文件，与既有 `run_tests.gd.uid` 同类；属于导入步骤的正常产物，不是手工新增文件。
10. **未做 git 写操作**：本轮仅新增/修改工作区文件，未 commit、未 push。

## 7. 交付物清单

| 路径 | 状态 |
|---|---|
| `/workspace/dino-new/tests/smoke.gd` | 新增（标准冒烟，长期维护） |
| `/workspace/dino-new/scripts/verify.sh` | 新增（一键验证，已 `chmod +x`） |
| `/workspace/dino-new/docs/QA.md` | 修改（冒烟基线章节） |
| `/workspace/dino-new/docs/reports/verify-20261024-124853.md` | 首跑记录（自动生成） |
| `/workspace/dino-new/docs/reports/2026-10-18-verify-harness.md` | 本报告 |
| `/workspace/dino-new/tests/smoke.gd.uid` | 导入步骤自动生成的 UID 侧车文件 |
