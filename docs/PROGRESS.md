# 进度日志

> 记录规则：每轮结束必须写“改了什么、验证数字、还剩什么”。版本号唯一来源为 `project.godot` 的 `config/version`；APK 体积为实际文件字节数，无打包记录写“未记录”，不估算。

---

## 一、版本历史（v0.2.0 → v0.2.6）

| 版本 | 主题 | 关键改动 | APK 体积 | 验证结果 |
|---|---|---|---|---|
| v0.2.0 | 架构加固第一批 + 玩法扩展 | 新增 `GameState` / `AudioManager` 两个 autoload；`Main` 由 529 行拆为编排器 + `DayNightCycle` / `ScoreKeeper` / `WorldBuilder` / `EcosystemDirector`；暂停菜单 + 设置面板；`tests/run_tests.gd` + GitHub Actions；AI 受击仇恨/反击与攻击动画；地图专属物种；随机事件三件套；自适应图标与版本号 | 未记录（该阶段基线约 29.7 MB） | 导入 0 脚本错误；47 条数据层断言已落地（首跑待 CI 归档）；headless 16s 冒烟通过 |
| v0.2.1 | 繁殖 / 领地 / 拖拽 / 成就 / 引导 | `DinoEgg` 蛋系统（AI 45s 孵化、玩家蛋跨代锚点）；AI 产蛋/偷蛋；`Achievements` 8 项成就；`TutorialGuide` 四步引导；成年 AI 领地（游荡 40m、防御 25m、惊逃 12m）；长按咬键拖尸 | 未记录（该阶段基线约 29.7 MB） | 静态交叉审查通过；蛋/拖拽/领地需真机实测项已登记 |
| v0.2.2 | 修复选种后整机卡死 | 从 `Maps` 剔除 `fir_tree_01` / `jacaranda_tree`，`fir_sapling_medium` 限 1 图 15 棵；新增 `LoadingScreen`；`_start_game` 改分帧协程；`WorldBuilder.spawn_nature` 支持分帧与进度回调 | **732,345,505 B（约 699 MiB）** | 导入 0 错误；加载界面开局后淡出释放；`_restart_run` 不显示加载界面；森林 3 个去重树模 `load()` 合计 1268ms，地形 `setup` 105–117ms，静态内存 304.7MB |
| v0.2.3 | 性能专项 | `NatureBatch` 64m 分块 MultiMesh 合批；`FoliageSpawner` 植物 MultiMesh 池；`TerrainGenerator` `HeightMapShape3D` 257² 升采样以对齐 1m 物理格距；`ResourceLoader` 线程预加载；`AIDino` 0.25s 决策节流；物理层常量化；`FrameProfiler` | 未记录（v0.2.5 实测 93.74 MiB） | headless 16s 冒烟通过；森林树模加载 1268ms、地形 105–117ms 为后续优化基线 |
| v0.2.4 | 资源瘦身 + 数值/生命周期缺陷修复 | 删除未引用高模、约束单图模型体积 <180MB；修复口渴/体力 `int(速率*delta)` 恒 0、植物被吃不重生、高度图导出失效、MultiMesh TypedArray、自然物落位报错 | 未记录（v0.2.5 已降至约 94MB） | 导入 0 错误；生存数值恢复衰减；植物重生与导出地形回归通过 |
| v0.2.5 | 生命周期 / 资源缺陷修复批次 | 拖尸碰撞层与贴地；玩家蛋跨代清理；AI 不咬自己刚产的蛋；存档原子写与版本校验；`map_id` 默认值统一 | **93.74 MiB** | 连续重开蛋数稳定；拖尸过坡不穿地；存档损坏/未来版本回退通过 |
| v0.2.6 | 输入 / UI 层级缺陷修复 + 工具链持久化 | 饮水改走 `drink` 动作层（解 E 键冲突）；触控层 `mouse_filter=0`（解菜单遮挡）；选图/选种开局释放；横幅重入保护；暂停输入清理；工具链与导出模板迁至 `/workspace/tools` 持久目录 | **98,305,858 B（93.75 MiB）** | 导入 0 错误；`versionName=0.2.6`、`arm64-v8a`、minSdk 21 / targetSdk 34；`apksigner` v1/v2/v3 全过 |

> 说明：v0.2.2 的 699 MiB 来自未引用高模全部打入包内；v0.2.5/v0.2.6 的体积下降来自资源瘦身，不是功能删减。

---

## 二、本轮详细日志：2026-10-18 架构加固

### 2.1 本轮目标

1. 把 `Main` 从“什么都做”的上帝脚本降为流程编排器。
2. 建立可自动化的数据层测试与 CI。
3. 补齐暂停/设置/成就/引导等工程化能力。
4. 修复数值、生命周期、输入、UI 层级、资源五类高频缺陷。
5. 把构建工具链迁出易失目录，保证可重复打包。

### 2.2 实际完成

| 批次 | 内容 | 落地文件 |
|---|---|---|
| 架构拆分 | `Main` 529 → 316 行；昼夜/计分/世界构建/AI 生态拆为四个子系统；Node 型子系统挂树随场景释放 | `Main.gd`、`DayNightCycle.gd`、`ScoreKeeper.gd`、`WorldBuilder.gd`、`EcosystemDirector.gd` |
| 全局设置 | `GameState` 负责 `user://settings.json` 类型/范围校验与原子写；`AudioManager` 幂等创建 SFX/Ambient 总线 | `GameState.gd`、`AudioManager.gd`、`project.godot` |
| 暂停/设置 UI | HUD 内嵌 `PauseMenu`（`WHEN_PAUSED`，layer 10）；四滑条实时生效 | `PauseMenu.gd`、`SettingsPanel.gd`、`HUD.gd` |
| 测试/CI | `tests/run_tests.gd` 入口 `_initialize()`；47 条断言覆盖 Groups/PhysicsLayers/Maps/DinoSpecies/SaveManager；GitHub Actions headless 工作流 | `tests/run_tests.gd`、`.github/workflows/ci.yml` |
| AI 表现 | 受击 6s 仇恨窗口；体型规则决定反击/逃跑；攻击动画 1s 节流；尸体猎食失败回游荡 | `AIDino.gd` |
| 地图/事件 | 地图专属物种 `extra_roster`；随机事件 IDLE/ACTIVE 状态机（兽群迁徙/风暴/丰饶期） | `Maps.gd`、`EcosystemDirector.gd`、`RandomEvents.gd` |
| 繁殖/领地/拖拽 | 蛋系统闭环；玩家跨代重生；成年 AI 领地；长按咬键拖尸 | `DinoEgg.gd`、`AIDino.gd`、`PlayerDino.gd` |
| 成就/引导 | 8 项成就幂等解锁；四步引导自动重连死亡后的新玩家/HUD | `Achievements.gd`、`TutorialGuide.gd` |
| 加载优化 | 资产数量与体积硬上限；`LoadingScreen` + 分帧协程；线程预加载 + 0.70 进度分段 | `Maps.gd`、`LoadingScreen.gd`、`Main.gd` |
| 性能专项 | 64m 分块 MultiMesh、植物 MultiMesh 池、257² 高度图碰撞、0.25s 决策节流、物理层常量、`FrameProfiler` | `NatureBatch.gd`、`FoliageSpawner.gd`、`TerrainGenerator.gd`、`AIDino.gd`、`PhysicsLayers.gd`、`FrameProfiler.gd` |
| 工具链 | Godot/JDK/SDK/模板/keystore 全部迁至 `/workspace/tools`；重建步骤文档化 | `HANDOVER.md` 第十四节、`export_presets.cfg` |

### 2.3 验证数字

| 项 | 实测值 | 判定 |
|---|---|---|
| 导入 | `SCRIPT ERROR` = 0 | 通过 |
| 单测 | 47 条断言已落地；本地无运行日志，CI 首跑待核对 | 待确认 |
| 运行时冒烟 | headless `--quit-after 16`，过滤后无脚本错误 | 通过 |
| 开局链路 | 选图→选种→加载→世界就绪；加载界面已淡出并释放 | 通过 |
| 死亡重开 | `_restart_run` 重建玩家/HUD/触屏，不重建世界资产 | 通过 |
| 森林加载 | 3 个去重树模 `load()` 合计 1268ms；静态内存 304.7MB | 记录为基线 |
| 地形生成 | `TerrainGenerator.setup` 105–117ms（128×128，约 3.2 万三角面 + trimesh 碰撞） | 记录为基线 |
| APK v0.2.2 | 732,345,505 B | 已归档 |
| APK v0.2.6 | 98,305,858 B；`apksigner` v1/v2/v3 通过 | 可发布 |

### 2.4 本轮遗留

| 遗留项 | 现状 | 风险 | 下一步 |
|---|---|---|---|
| Domain 未抽取 | 生存/战斗/成长/繁殖仍在 `PlayerDino` / `AIDino` | 后续每次玩法改动都集中在大文件 | 阶段 A |
| 存档双写 | `Main` 与 `PlayerDino` 各自写盘 | 字段覆盖顺序不可控 | 阶段 B |
| 状态标志分散 | 6 个标志（`skip_select/is_over/_game_started/paused/_is_dead/is_dead`） | 组合态不可枚举，输入/UI 残留易复发 | 阶段 D |
| `_restart_run` 手工清理 | 11 项清理清单 | 新增运行期节点易漏 | 阶段 D |
| 业务 0 单测 | AI/生存/战斗/繁殖无断言 | 回归只能真机试玩 | 阶段 A |
| 高度图碰撞格距 | Godot 4.4 不支持自定义格距，用 257² 升采样把 2m 视觉网格对齐到 1m 物理格距 | 内存约 258KB，构建约 10ms，属可接受成本 | 引擎支持 `cell_size` 后去掉升采样 |
| CI 首跑 | 工作流已提交，未经 GitHub 实跑 | import 步骤 `continue-on-error` 可能掩盖真实错误 | 首次 push 后核对 |
| 真机验证 | 随机事件/拖拽/领地/成就横幅仅静态审查 | 手感与性能未知 | 发版前 SMK-04～08 |
| APK 体积 | 93.75 MiB，仍含未引用资源 | 下载与安装成本 | 导出过滤/资源审计 |

---

## 三、下一轮计划

### 3.1 优先级与范围

| 优先级 | 任务 | 范围 | 验收条件 | 预估 |
|---|---|---|---|---|
| P0 | Domain 抽取（进行中） | `DinoActor` 浅基类 + `Health/Vitals/Combat/Growth/Repro` 纯逻辑类；节点只做输入/动画/物理适配 | `PlayerDino` ≤600 行、`AIDino` ≤500 行；Domain 单测 ≥25 条；总断言 ≥72；headless 16s 0 错误 | 8–12 人日 |
| P0 | 存档 Repository | 唯一 `SaveRepository` 读写 `user://save.json`；键名常量 + 快照；拆除双写 | 全仓仅 Repository 访问 `user://`；键名裸字符串 0；死亡→续关→回菜单三路径一致 | 3–5 人日 |
| P0 | GameFlow 状态机 | BOOT/MAP_SELECT/SPECIES_SELECT/LOADING/PLAYING/PAUSED/DEAD/MENU；收敛 6 个布尔标志 | 状态迁移全覆盖单测；`skip_select/is_over/_game_started` 删除或只读；重开只走一个入口 | 4–6 人日 |
| P1 | 运行域容器 | 运行期节点挂 `RunScope`，`_restart_run` 只重建容器 | 连续重开 20 次节点数稳定、无悬挂连接 | 3–4 人日 |
| P1 | 业务单测补齐 | `Vitals/Combat/Growth/Repro` 固定 delta 序列与重复 N 次回归 | 五条主链自动化覆盖；CI 全绿 | 6–8 人日 |
| P2 | 数据资源化 | `SpeciesDef.tres` / `MapDef.tres`，静态 API 薄封装 | 6 物种/4 地图字段完整；加载耗时 ≤ 旧版 +10% | 4–6 人日 |

### 3.2 推进顺序与可运行中间态

1. **先抽 `Vitals`**：不改任何外部签名，只把累加器搬进纯类；节点每帧 `tick`。此时游戏可正常玩，单测可先覆盖饥/渴/体力。
2. **再抽 `Combat`**：保持 `take_damage` 签名，玩家/AI/尸体/蛋所有调用点零改动。冒烟重点回归互咬与减伤。
3. **同步建 `SaveRepository`**：`SaveManager` 退化为门面，先兼容旧档，再删双写。
4. **最后上 `GameFlow`**：状态机必须建立在 Domain 与存档收口之后，否则会把旧标志的复杂度带进新状态机。

### 3.3 本轮不做

- 不上 ECS、不引入 DI 容器、不做万能 EventBus、不做 6 物种 6 子类、不新增第 4 个以上 autoload。
- 不在 Domain 抽取期间同时改数值平衡；先保证行为等价，再调平衡。

### 3.4 风险与回退

| 风险 | 触发信号 | 回退方式 |
|---|---|---|
| 抽取后数值不等价 | 同一进食/冲刺序列差值 >1 点 | 保留旧实现为 `_legacy` 分支，按物种对比 24h |
| 存档迁移丢字段 | 旧档升级后缺 `map_id/generation` | 迁移前备份 `save.json`；失败回退 v1 只读 |
| 状态机迁移漏路径 | 死亡/暂停/回菜单出现叠加态 | 保留旧标志只读镜像，逐路径切换，禁止一次性删除 |
| 重构期无法发版 | 冒烟失败 | 每阶段独立分支，主干始终可导出 APK |

---

## 四、本轮详细日志：2026-10-24 存档 Repository 收口

### 4.1 本轮目标

把散落在 `Main` / `PlayerDino` / `SpeciesSelect` / `SaveManager` 的存档读写收口为
**单一 `SaveRepository` + 强类型 `PlayerProfile` + 显式版本迁移链**，行为等价，不引入新 autoload。

### 4.2 实际完成

| 批次 | 内容 | 落地文件 |
|---|---|---|
| 内存模型 | 6 字段强类型快照；键名常量集中；默认值/钳制；物种与地图非法值回退 | `scripts/data/PlayerProfile.gd`（新增） |
| 唯一 IO | JSON 单文件 `user://save.json`；`SAVE_VERSION=2`；v1→v2 迁移链 + v3 占位；原子写（tmp+回读+rename）；写前 `save.bak`；未来/损坏隔离副本 | `scripts/data/SaveRepository.gd`（新增） |
| 兼容门面 | `SaveManager` 只转发，不再持有 IO 逻辑 | `scripts/data/SaveManager.gd` |
| 调用方收口 | 新开局/死亡结算/续关/重开统一走 Repository；进化只“先读再写” `growth_stage` | `Main.gd`、`PlayerDino.gd`、`SpeciesSelect.gd` |
| 测试 | Repository 用例：无档/往返/备份/两种 v1/未来版本/损坏/备份保护；门面版本断言改读原始 JSON | `tests/run_tests.gd` |
| 文档 | 迁移链、备份策略、写入时机矩阵、风险与回退 | `docs/reports/2026-10-18-save-repository.md`（新增） |

### 4.3 验证数字

| 项 | 实测值 | 判定 |
|---|---|---|
| 导入 | `SCRIPT ERROR / Parse Error / Compile Error` = 0（exit 0） | 通过 |
| 单测 | `PASSED: 166 / FAILED: 0`（exit 0；较上轮 47 条净增 119） | 通过 |
| 运行时冒烟 | headless `--quit-after 16`；过滤脚本/资源/类型错误 = 0 | 通过 |
| 存档矩阵 | 无档/完整档/缺字段/损坏/未来版本/两种 v1 共 7 条路径 | 通过（单测覆盖） |

### 4.4 本轮遗留

| 遗留项 | 现状 | 风险 | 下一步 |
|---|---|---|---|
| PlayerDino 仍写盘 | 进化时只写 `growth_stage`，先读再写 | 非真正单写者；极端时序下物种/代际可能滞后 | 改为发信号由 Main 合并写入 |
| 迁移即落盘 | v1 档读取时会就地升级为 v2 | 读操作产生一次写 | 视需要改为纯内存迁移 |
| 自动存档/后台保存 | 未实现 | Android 后台被杀可能丢本局进度 | 接入 `APPLICATION_PAUSED` + 定时脏写 |
| `save.bak` 仅一份 | 不滚动多代 | 连续坏写缺少更早副本 | 扩为 `.bak.1/.bak.2` |
| GameFlow 状态机 | 未开始 | 流程布尔仍分散 | 下一轮按研究报告落地 |

---

## 五、维护节奏

- 每次提交前：SMK-01～SMK-03 本地跑通。
- 每次发版前：`docs/QA.md` 第四节清单逐项打勾。
- 每轮结束：更新本文件“本轮详细日志”和 `ARCHITECTURE.md` 技术债状态。
- 文档中的行号以当前 HEAD 为准；大改后校正。
