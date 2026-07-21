class_name LookControl
extends Control
## 触屏视角控制区：捕获本区域内的拖动，输出像素增量 (dx, dy) 供玩家旋转摄像机。
## 设计：右半屏上半部作为"看"的区域；左半屏留给摇杆，右下留给动作按钮。
## 仅响应"拖动"（press 记录起点，drag 发出相对增量并刷新参考点，release 不发出）。

signal look_input_changed(delta: Vector2)

var _drag_index: int = -1
var _last_pos: Vector2 = Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _drag_index == -1:
			_drag_index = t.index
			_last_pos = t.position
			accept_event()
		elif not t.pressed and t.index == _drag_index:
			_drag_index = -1
			accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _drag_index:
			var delta: Vector2 = d.position - _last_pos
			_last_pos = d.position
			look_input_changed.emit(delta)
			accept_event()
