# 第二轮需求（2026-07-22 用户醒来后提出）

## 需求清单
1. **横屏游戏**：`project.godot` 已 `window/handheld/orientation=1`（landscape 锁定），APK manifest 已 landscape。无需改，仅验证确认。
2. **指南卡死 bug**：`TouchControls.tscn` 根 Control `mouse_filter=2` 全屏拦截，盖在 HUD 之上吃掉"开始狩猎"点击。→ 改为 `0`（pass）。
3. **三种相机**：第一人称 / 第二人称(越肩近身跟随) / 第三人称，加切换按钮 + 切换提示。
4. **地形与地图资源**：下载免费 CC0 资源（树木/岩石/植被 + 至少一张现成地形场景），程序化生成高山，撒成森林；做多张地图预设 + 地图选择界面。
5. **画面真实度 + 体积**：提升光照/雾/天空/地形材质，引入真实模型与纹理，APK 堆到 80MB+。

## 已确认决策（AskUserQuestion）
- 第二人称 = **越肩近身跟随**（相机贴右肩后方、比第三人称更近，角色始终在画面里）。
- 山体 = **两者都要**（程序化噪声高山 + 下载现成地形场景作为其中一张地图）。

## 分阶段执行
### A 阶段：bug + 相机（低风险，先做先验证）
- A1：TouchControls 根 `mouse_filter 2→0`；headless 验证点击路径修复。
- A2：PlayerDino 加 `CameraMode{FIRST,SHOULDER,THIRD}` + `cycle_camera_mode()` + 按模式算 spring_length/eye/侧偏/俯仰范围；TouchControls 加"视角"按钮接 `cycle_camera_mode`；切换时 HUD 提示当前模式。
- A3：确认横屏 manifest（导出时核对）。

### B 阶段：地形 / 资源 / 多地图 / 画质
- B1：WebSearch 找 CC0 .glb（树木/岩石/植被 + 现成地形场景），直接 curl 下载到 `assets/models/` 与 `assets/terrain/`。逐个验证能导入（headless 无报错）。
- B2：新增 `TerrainGenerator.gd`：用噪声生成高度图网格（PlaneMesh 细分 + 顶点位移），按高度上色（草地/岩石/雪），碰撞用高度图 shape；参数可由地图预设驱动（山高/频率/雪线）。
- B3：森林散布：用下载的树/岩模型在地形上按密度撒点（避开水源/出生点）；替换原 CSG 树石。
- B4：地图预设 `MapDef`：定义 3~4 张（森林谷地 / 高山雪岭 / 荒原 / 下载地形），含地形参数、植被密度、水源、天空/雾色调。
- B5：`MapSelect` 界面（开场先选地图，再选物种，或同一屏）。存档记录所选地图。
- B6：画质：方向光+环境光+雾（距离雾）+ 更好天空；地形用高度混合材质；恐龙材质微调；移动端安全（不超预算）。

### C 阶段：验证 + 导出 + 文档 + 推送
- headless 30s 零错误；导出 APK（预期明显增大，目标 80MB+）；更新 PROGRESS/HANDOVER；提交并 `git push private main`。

## 验收红线
- 零 `SCRIPT ERROR` / 编译 / 动画报错（headless，忽略 is_inside_tree）。
- "开始狩猎" 可关闭指南。
- 三种相机可切换且无抖动/穿地。
- 地图选择可进对应地形，无卡死。
- APK 可装安卓、横屏、体积显著增大。
