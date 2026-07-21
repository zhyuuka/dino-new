# T1 — 手机摄像机转向控制

## 目标
触屏右侧区域拖动可旋转摄像机（偏航 yaw + 受限俯仰 pitch），让手机玩家能自由转身/环顾，
应对来自任意方向的威胁。桌面端保留 Q/E 键转向作为兼容。

## 方案
1. 新增 `scripts/ui/LookControl.gd`（extends Control）：
   - 捕获 `_gui_input` 的 ScreenTouch/ScreenDrag；拖动时发出 `look_input_changed(Vector2(dx, dy))`（屏幕像素增量）。
   - 仅捕获"拖动"（press 记录起点，drag 发出增量并刷新参考点；release 不发出）。
2. `scenes/TouchControls.tscn`：新增 `LookZone` Control 节点，覆盖**右半屏上半部**
   （anchor_left=0.45, anchor_right=1.0, anchor_top=0.0, anchor_bottom=0.60），mouse_filter=0（可捕获触摸）。
3. `scripts/ui/TouchControls.gd`：
   - 新增 `signal look_input_changed(delta: Vector2)`
   - `_ready` 中连接 `look_zone.look_input_changed -> look_input_changed.emit`
4. `scripts/game/Main.gd`：`touch_controls.look_input_changed.connect(player.add_look_delta)`
5. `scripts/player/PlayerDino.gd`：
   - `const` 的 `CAM_PITCH` 改为 `var cam_pitch`（默认 -0.35）
   - 新增 `var _look_delta: Vector2 = Vector2.ZERO` 与 `func add_look_delta(d: Vector2) -> void`
   - `_physics_process` 中在更新相机前：`camera_yaw += _look_delta.x * LOOK_SENS;
     cam_pitch = clamp(cam_pitch + _look_delta.y * PITCH_SENS, -1.15, -0.05); _look_delta = Vector2.ZERO`
   - `_update_camera_position()` 使用 `cam_pitch` 替代 `CAM_PITCH`
   - 新增 `const LOOK_SENS := 0.005`（每像素弧度），`const PITCH_SENS := 0.004`
   - 桌面 Q/E 仍写入 `camera_yaw`（保持兼容）

## 效果预期
- 右半屏上半部拖动 → 视角平滑旋转；松手停在当前角度。
- 拖动时不影响摇杆移动（左右分区）。
- 按钮区（右下）在 LookZone 之外，按钮仍可正常点击。
- headless 运行零报错；桌面仍可键盘转向。

## 验证
- `godot --headless --quit-after 12` 无 SCRIPT ERROR / Animation not found。
- 代码审查：信号链路 TouchControls→Main→PlayerDino 一致；LookControl 不拦截按钮。
