# 质量保障与发布基线

> 适用版本：v0.2.6。所有命令默认在 `/workspace/dino-new` 执行。
> 原则：**可自动化的不手工，不能自动化的必须留可复现步骤与判定标准**。

---

## 一、当前测试覆盖矩阵

图例：**有** = 有且稳定；**部分** = 间接覆盖或仅冒烟；**无** = 无覆盖。

| 模块 | 单测 | 集成冒烟 | 手工 | 结论 |
|---|---|---|---|---|
| `Groups` / `PhysicsLayers` | 有 常量与掩码断言 | 无 | 无 | 常量断言已覆盖 |
| `Maps` | 有 4 图、字段、回退 | 部分 开局间接使用 | 无 | 数量上限变更需补断言 |
| `DinoSpecies` | 有 6 物种、越界钳制 | 部分 开局间接使用 | 无 | 数值平衡无断言 |
| `SaveManager` | 有 门面转发/无档/往返/损坏/未来版本 | 部分 死亡续关间接使用 | 既有 | 已退化为兼容门面，IO 逻辑见下一条 |
| `PlayerProfile` / `SaveRepository`（Persistence） | 有 迁移链/往返/备份轮换/未来版本/损坏隔离 | 部分 死亡→续关→重开间接使用 | 有 | 存档唯一 IO 已收口；写入时机矩阵仍靠手工验证 |
| `PlayerDino` 生存数值（饥/渴/体力） | 无 | 部分 headless 跑帧但不校验 | 有 | **业务 0 断言**，历史缺陷高发区 |
| `PlayerDino` 战斗/技能/受击 | 无 | 部分 AI 会触发战斗 | 有 | 伤害公式、减伤、仇恨无断言 |
| `PlayerDino` 成长/产蛋/跨代 | 无 | 部分 需长局才触发 | 有 | 无自动化 |
| `PlayerDino` 拖拽 | 无 | 无 | 有 | 仅手感验证 |
| `AIDino` 决策/感知/领地 | 无 | 部分 0.25s 决策会跑 | 有 | 无策略单测 |
| `AIDino` 战斗/仇恨/兽群 | 无 | 部分 随机触发 | 有 | 无自动化 |
| `AIDino` 产蛋/偷蛋 | 无 | 部分 45s 孵化窗口 | 有 | 无自动化 |
| `EcosystemDirector` 补员/Boss | 无 | 部分 headless 补员 | 有 | 无断言 |
| `DinoEgg` | 无 | 部分 孵化链路 | 有 | 无断言 |
| `Main` 选图/选种/加载/重开 | 无 | 部分 只覆盖到选图界面 | 有 | 全流程无自动化 |
| `HUD` / `PauseMenu` / `TouchControls` | 无 | 无 | 有 | 层级、暂停、输入残留靠手测 |
| 存档全链路（死亡→续关→回菜单） | 无 | 无 | 有 | 双写风险无法自动发现 |
| `NatureBatch` / `FoliageSpawner` / `TerrainGenerator` | 无 | 部分 生成期跑通 | 有 | 合批/重生无断言 |
| Android 导出/签名/安装 | 无 | 无 | 有 | 每次发版人工执行 |

**量化结论**：40 个业务脚本中仅 5 组纯逻辑/常量被单测覆盖（约 12.5%）；AI、生存、战斗、繁殖、GameFlow 五条主链的自动化覆盖率为 **0**。因此现阶段“单测全过”只能证明数据层未被改坏，不能证明游戏可玩。

---

## 二、冒烟基线（一键验证）

> 标准入口只有两个文件：`tests/smoke.gd`（标准冒烟，长期维护）与 `scripts/verify.sh`（一键编排）。
> **任何提交前必须 PASS**：终端出现 `VERIFY_RESULT: PASS`，且带时间戳的记录已落到 `docs/reports/verify-*.md`。
> 禁止再使用"用完即删"的临时冒烟脚本，否则各轮验证口径不一致、结果无法纵向比较。

### 2.1 日常命令

```bash
cd /workspace/dino-new
bash scripts/verify.sh          # 导入 + 单测 + 冒烟
bash scripts/verify.sh --apk    # 追加导出 build/DinoWorld-verify.apk（不签名发布）
```

脚本内已固化环境，无需手工 export：

```bash
ROOT=/workspace/dino-new
GODOT=/workspace/tools/Godot_v4.4.1-stable_linux.x86_64
export XDG_DATA_HOME=/workspace/tools/godotdata
export XDG_CONFIG_HOME=/workspace/tools/godotconfig
```

- Godot 存在且可执行：缺失直接退出（退出码 2）。
- Android SDK（`/workspace/tools/android-sdk`）：缺失只警告，单测/冒烟不需要。
- JDK（`/workspace/tools/jdk17`）：仅 `--apk` 时必需。

### 2.2 自动步骤（已由 `scripts/verify.sh` 固化）

| 编号 | 步骤 | 脚本内实际命令 | 判定标准 |
|---|---|---|---|
| SMK-01 | 导入 | `timeout 600 $GODOT --headless --path $ROOT --import` | 日志 `/tmp/verify-import.log` 中 `SCRIPT ERROR\|Parse Error` 行数为 **0** |
| SMK-02 | 单测 | `timeout 300 $GODOT --headless --path $ROOT -s res://tests/run_tests.gd` | 退出码 0 且 `PASSED: n / FAILED: 0` |
| SMK-03 | 冒烟 | `timeout 180 $GODOT --headless --path $ROOT -s res://tests/smoke.gd` | 退出码 0、`SMOKE_JSON.ok=true`，且 `/tmp/verify-smoke.log` 中 `SCRIPT ERROR` 行数为 **0** |
| SMK-09 | 打包 | `timeout 600 $GODOT --headless --path $ROOT --export-release "Android Debug" "$ROOT/build/DinoWorld-verify.apk"` | 仅 `--apk` 时执行；退出码 0 且产物存在，体积记入记录 |

所有 Godot 调用都带 `--headless` 与 `timeout`，日志先落 `/tmp/verify-<step>.log` 再解析，不污染终端。

### 2.3 `tests/smoke.gd` 契约

```bash
SMOKE_SECONDS=40 SMOKE_MAP=forest SMOKE_SPECIES=raptor \
  $GODOT --headless --path $ROOT -s res://tests/smoke.gd
```

- 环境变量：`SMOKE_SECONDS`（默认 40）、`SMOKE_MAP`（默认 forest）、`SMOKE_SPECIES`（默认 raptor）。
- 流程：打印 `SMOKE_START map=... species=... seconds=...` → 加载 `Main.tscn` → 0.5s 后调用 `_on_map_selected` + `_on_species_selected(species, false)` → 观察指定秒数 → 输出单行 `SMOKE_JSON:`。
- 输出字段：`ok, seconds, player, ai, plants, eggs, corpses, nodes, hunger, thirst, hp, pos_y, mmi, script_errors`。
  - `mmi` = Main 子树内 `MultiMeshInstance3D` 数量（自然物/植物合批是否正常）。
  - `script_errors` 固定为 `-1`：脚本读不到引擎 stderr，真实值由 `scripts/verify.sh` 从进程输出统计。
- `ok` 判定：`player == 1` 且 `pos_y ∈ (-50, 200)`（未掉穿地形）且 `nodes > 100`。
- 失败 `quit(1)`，成功 `quit(0)`。

### 2.4 记录归档与结论

- 每次运行生成 `docs/reports/verify-$(date +%Y%m%d-%H%M%S).md`，含：时间戳、git commit/分支、版本、各步骤耗时、导入错误数、单测数字、格式化冒烟 JSON、结论、失败时最多 30 行关键日志。
- 判定：导入错误 = 0 **且** 单测 FAILED = 0 **且** 冒烟 `ok=true` **且** 冒烟 `SCRIPT ERROR` = 0 → PASS，否则 FAIL。
- 终端最后一行固定为 `VERIFY_RESULT: PASS|FAIL | report: <路径>`；FAIL 退出码 1。
- 记录可纵向比较：同口径、带时间戳、带 commit，禁止手工改写结论。

### 2.5 手工用例（自动冒烟覆盖不到，发版前人工执行）

| 编号 | 类型 | 步骤 | 预期输出 | 判定标准 |
|---|---|---|---|---|
| SMK-04 | 开局流程 | 编辑器/真机：启动 → 选图 → 选种 → 加载 → 进入世界 | 加载条推进到 100% 并淡出；玩家可移动；无界面残留 | 加载界面 `queue_free`；选图/选种不再可见；HUD 数值正常 |
| SMK-05 | 死亡重开 | 控制台执行 `player.take_damage(99999)`，等待 3.5s | 死亡屏 → 自动重开；第 N+1 代；世界地形/植被保留 | 无整场景卡顿；HUD/触屏只有一份；存档 `generation` 已 +1 |
| SMK-06 | 暂停/设置 | 暂停 → 调音量/灵敏度 → 继续；重启后复查 | 暂停时世界停止；设置即时生效并跨重启保留 | `get_tree().paused` 正确切换；无输入残留；设置文件值合法 |
| SMK-07 | 输入冲突 | 长按咬键 0.2s 叼尸；按 E 喝水；右半屏拖动视角 | 叼尸/放下正常；E 只触发喝水；转视角不自动咬 | 无“拖视角误咬/误叼”；轻点咬键只咬不叼 |
| SMK-08 | 繁殖链路 | AI 巢边产蛋 → 45s 孵化；玩家产蛋 → 死亡 → 从蛋重生 | AI 幼体落地；玩家从蛋位置重生且旧蛋清理 | 蛋总数不持续增长；AI 不咬自己刚产的蛋 |

### 2.6 导出与校验命令

```bash
$GODOT --headless --path "$ROOT" --export-release "Android Debug" \
  "$ROOT/build/DinoWorld-v0.2.6.apk"

/workspace/tools/android-sdk/build-tools/34.0.0/aapt2 dump badging \
  "$ROOT/build/DinoWorld-v0.2.6.apk" | grep -E "package:|native-code"
/workspace/tools/android-sdk/build-tools/34.0.0/apksigner verify --verbose \
  "$ROOT/build/DinoWorld-v0.2.6.apk"
ls -l "$ROOT/build/DinoWorld-v0.2.6.apk"
```

---

## 三、缺陷登记表（近三个版本已修）

> 版本列为**修复落盘轮次**；未单独发版的修复并入相邻版本。根因分类固定为：数值 / 生命周期 / 输入 / UI 层级 / 资源。

| ID | 版本 | 缺陷 | 现象与后果 | 根因分类 | 根因 | 修复位置 | 回归验证 |
|---|---|---|---|---|---|---|---|
| BUG-001 | v0.2.4 | 口渴/体力永远不下降 | 生存系统形同虚设，玩家可无限冲刺 | 数值 | `int(速率 * delta)` 在 1/60 步长下恒为 0（如 `45/60=0.75`） | `PlayerDino.gd:127-132`、`329-333`、`395-399` 改为浮点累加器 | 连续 10s 冲刺体力下降；静止口渴按 12s/点恢复 |
| BUG-002 | v0.2.4 | 植物被吃后永不重生 | 区域资源耗尽，玩家无法继续觅食 | 生命周期 | `eaten` 信号无节点参数，按下标扫描在实例仍有效时匹配失败 | `Foliage.gd:12/56`、`FoliageSpawner._on_foliage_eaten` | 吃光一片后 30s 内重生 |
| BUG-003 | v0.2.4 | 高度图导出后静默失效 | 峡谷图退化为噪声地形，地图设计失效 | 资源 | `Image.load_from_file` 在导出包内读不到未打包 PNG | `TerrainGenerator._generate_heights` 改 `load() as Texture2D` | 导出 APK 后峡谷地形与编辑器一致 |
| BUG-004 | v0.2.4 | MultiMesh TypedArray 报错 | 自然物合批中断，植被/岩石缺失 | 资源 | 强类型数组赋值与 `MultiMesh` 实例数据格式不匹配 | `NatureBatch.gd` 合批写入路径 | headless 无 `TypedArray` 错误；树木数量与配置一致 |
| BUG-005 | v0.2.4 | 自然物落位报错 | 日志刷 `!is_inside_tree()`，物件偶发落位错误 | 资源 | 先设 `global_position` 再 `add_child` | `WorldBuilder.spawn_nature` 调整入树顺序 | SMK-03 无该报错 |
| BUG-006 | v0.2.5 | 拖尸穿地/碰撞异常 | 尸体拖拽时抖动、卡进地形或推飞玩家 | 生命周期 | 尸体拖拽期间未切换碰撞层/未贴地跟随 | `PlayerDino._update_dragging`、`AICorpse` 碰撞层恢复 | 拖尸过坡不穿地；松手恢复腐烂 |
| BUG-007 | v0.2.5 | 玩家蛋跨代堆积 | 多代后蛋永久占位，蛋总数上限被旧蛋吃满 | 生命周期 | `_restart_run` 只消费一枚蛋，旧蛋未销毁 | `Main.gd:566-576` 统一清理 `owner_player` 蛋 | 连续死亡 5 次后场上玩家蛋 ≤1 |
| BUG-008 | v0.2.5 | AI 吃自己刚产的蛋 | 刚产蛋即被自己咬破，繁殖链断裂 | 生命周期 | 缺少“产蛋者/保护期/巢边半径”守卫 | `DinoEgg.gd:19`、`AIDino.gd:50-51` | 产蛋后 6s 内同巢蛋不被咬 |
| BUG-009 | v0.2.6 | E 键冲突 | 按 E 既喝水又触发咬/技能，行为不可控 | 输入 | 直接轮询 `KEY_E`，与 InputMap 动作并存 | `PlayerDino.gd:318-325` 改走 `drink` 动作层 | E 仅喝水；改键后仍生效 |
| BUG-010 | v0.2.6 | 菜单按钮被触控层遮挡 | “开始狩猎/继续”点不到，玩家卡在选种界面 | UI 层级 | `TouchControls` 全屏根 `Control` 的 `mouse_filter=STOP` | `TouchControls.tscn:16/29/37` 改 `mouse_filter=0` | 选种按钮可点；游戏中摇杆正常 |
| BUG-011 | v0.2.6 | 选图界面残留 | 进入游戏后选图/选种仍叠在画面上 | UI 层级 | 界面节点未在开局时释放 | `Main.gd:110-114`、`548-553` | 开局后 `map_select/species_select` 为空 |
| BUG-012 | v0.2.6 | 事件横幅被覆盖 | 成就/事件提示互相顶掉，玩家看不到关键信息 | UI 层级 | 单一 `Banner` 与 Tween，后到文案直接覆写 | `HUD.gd:243-263` 成就横幅延后 2.5s，事件横幅优先 | 同帧触发事件+成就时事件先播、成就后播 |
| BUG-013 | v0.2.6 | 暂停输入残留 | 暂停期间按键仍被消费，恢复后角色自动移动/咬 | 输入 | 暂停切换顺序与输入状态未清理 | `PauseMenu.gd:36/42`、`Main._on_menu` | 暂停 5s 后恢复无自动动作 |

**防复发要求**

1. 数值类缺陷必须补“固定 delta 序列”的纯函数单测，禁止只靠手感。
2. 生命周期类缺陷必须补“重复 N 次”的回归用例（重开、产蛋、孵化、重生）。
3. 输入类缺陷必须同时验证键盘与触屏两条路径。
4. UI 层级缺陷必须记录节点 `layer` 与 `mouse_filter` 的预期值。

---

## 四、发布前检查清单

发布包命名：`build/DinoWorld-v<version>.apk`；版本号唯一来源为 `project.godot` 的 `config/version`。

| # | 检查项 | 执行方式 | 通过标准 | 阻塞级别 |
|---|---|---|---|---|
| 1 | 导入零错误 | SMK-01 | `SCRIPT ERROR / Parse Error / Compile Error` = 0 | 阻塞 |
| 2 | 单测全过 | SMK-02 | `PASSED: 166 / FAILED: 0`，退出码 0 | 阻塞 |
| 3 | 冒烟零脚本错误 | SMK-03 | 过滤后无输出 | 阻塞 |
| 4 | 核心流程冒烟 | SMK-04～SMK-08 | 全部通过，无界面残留/输入残留 | 阻塞 |
| 5 | APK 体积 | `ls -l build/*.apk` | ≤ **110 MB**；较上版增长 >10% 必须说明原因 | 警告 |
| 6 | 签名 | `apksigner verify --verbose` | v1/v2/v3 全过；RSA 2048 | 阻塞 |
| 7 | 包名/版本/架构 | `aapt2 dump badging` | `com.dinoworld.game`；`versionName` 与 `config/version` 一致；`arm64-v8a`；minSdk 21 / targetSdk 34 | 阻塞 |
| 8 | 图标 | 检查 `export_presets.cfg` 与导入缓存 | 主图标 `icon_432.png`、自适应前景/背景均已导入且配置生效 | 警告 |
| 9 | 版本标签 | 打开暂停菜单 | 底部版本号与 APK `versionName` 一致 | 警告 |
| 10 | 真机安装 | `adb install -r build/*.apk` | 冷启动 ≤5s；横屏锁定；运行 5 分钟无崩溃；切后台再回来正常 | 阻塞 |
| 11 | 文档同步 | 人工 | `PROGRESS.md` 记录本轮改动与验证数字；`QA.md` 覆盖矩阵/缺陷表已更新 | 警告 |

**发版记录必须包含**：版本号、APK 字节数、SHA256、`apksigner` 结果、单测数字、冒烟结论、已知遗留。缺任一项不得对外发布。
