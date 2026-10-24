# 项目状态锚（STATE）

> 本文件是**跨会话的唯一状态真相源**。任何会话开始前必须读它；任何会话结束前必须更新它。
> 规则：只写**可验证的事实**。推断必须标 `[推断]`，未验证必须标 `[未验证]`。

## 时间锚（每次会话结束更新）

| 项 | 值 |
|---|---|
| 最后更新 | 2026-10-24 12:50 CST |
| 项目版本 | 0.2.7 |
| Git commit | 见 `git log -1`（PROGRESS 记录每轮提交） |
| 最近验证 | `docs/reports/verify-20261024-124853.md`（PASS，49.9s） |
| APK | DinoWorld-v0.2.7.apk / 94MB / arm64-v8a / targetSdk 34 |
| 单测 | 166 断言全过（PASSED 166 / FAILED 0） |
| 运行时冒烟 | 0 SCRIPT ERROR（tests/smoke.gd 标准冒烟，40s，14 AI / 30 植物 / 677 节点） |
| 验证命令 | `bash scripts/verify.sh`（导入+单测+冒烟，自动归档带时间戳记录） |
| 引擎/工具链 | Godot 4.4.1 stable；SDK/JDK/模板持久化于 /workspace/tools（见 HANDOVER 第十四节） |

## 当前能力清单（已验证可玩）

- 6 种恐龙（raptor/trike/trex/anky/carno/galli），5 段成长，食性区分
- 生存：饥饿/口渴/体力衰减、饮水、进食、饿死渴死
- 生态：食物链、威压、兽群、领地、仇恨反击、产蛋孵化、偷蛋、尸体拖拽
- 3 个相机模式、触屏摇杆/视角/动作键、桌面键鼠
- 昼夜循环、4 张地图（专属物种）、随机事件（兽群迁徙/风暴/丰饶）
- 系统：暂停、设置（音量/灵敏度）、成就 8 项、四步新手引导、存档（原子写+备份+迁移）
- 渲染：地形高度场碰撞、自然物/植物 MultiMesh 合批、可见距离、异步预加载

## 架构位置（详见 ARCHITECTURE.md）

| 层 | 状态 |
|---|---|
| Domain（Vitals/CombatRules/GrowthRules） | 已抽取，纯逻辑可测 |
| 数据/持久化（PlayerProfile/SaveRepository/SaveManager facade） | 已统一，有迁移链 |
| 表现层（PlayerDino/AIDino 节点） | 仍有 13/10 类职责，待组件化（P0） |
| 流程（Menu/Loading/Playing/Paused/Dead） | 仍是分散标志，GameFlow 状态机待做（P0） |

## 已知风险与未决项

| 编号 | 事项 | 等级 | 状态 |
|---|---|---|---|
| R1 | PlayerDino/AIDino 上帝类未拆 | P0 | 待做（Phase 4） |
| R2 | GameFlow 状态机未落地，重开靠手工清理 | P0 | 待做 |
| R3 | 玩家进化写盘为"先读再写"，极端时序可能滞后 | P2 | 观察中 |
| R4 | 减面后近景树皮/岩石细节变软 | P3 | 可接受取舍 |
| R5 | v0.2.7 存档迁移未在真机验证 | P0 | 待真机确认（旧档是否保留） |
| R6 | APK versionCode 恒为 1 | P2 | 上架前需递增 |

## 下一步（按优先级）

1. 固化验证闭环：`tests/smoke.gd` + `scripts/verify.sh`（一键：导入→单测→冒烟→记录）
2. GameFlow 状态机（先补状态转移测试）
3. SpeciesDef 资源化（.tres + facade 保留 133 处调用）
4. PlayerDino/AIDino 拆分为 DinoActor + 组件
