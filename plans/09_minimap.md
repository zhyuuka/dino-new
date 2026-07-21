# T9 — 小地图 / 罗盘 HUD

## 目标
为手机玩家提供导航小地图（北朝上，玩家居中）：显示水源、草食(绿)、肉食(红)、
霸主霸王龙(大红)、资源点(黄)，提升大地图上的方向感与策略性。

## 方案
### 新增 scripts/ui/Minimap.gd（+ HUD.tscn 中 Minimap 节点，右上菜单下方）
- `extends Control`；`_ready` 设 `mouse_filter=2`（不拦截触摸）。
- `_process` 每帧 `queue_redraw()`；`_draw` 以玩家为中心绘制：
  - 圆形底 + 白边；水源蓝点、资源点黄点、草食绿点、肉食红点、霸王龙大红点；玩家白心蓝点。
  - 超出半径的点不绘制；`MAP_SCALE=135` 与地图半径对应。
- 通过 group "player"/"water"/"ai"/"resource" 取世界对象位置。

### scripts/world/ResourcePoint.gd
- `_ready` 中 `add_to_group("resource")`，供小地图识别。

## 效果预期
- 右上角出现小地图，实时反映附近威胁与资源，手机导航更友好。
- 不拦截触摸（mouse_filter=2），不影响摇杆/按钮。
- headless 运行零报错；绘制调用安全（对象失效保护）。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误。
- 代码审查：group 查询安全；Minimap 不修改游戏状态。
