class_name DebugOverlay
extends CanvasLayer
## 调试性能浮层（仅 debug build 由 Main 挂载）：F3 切换显示。
## 数据来自 FrameProfiler autoload；本层只读展示，不修改任何渲染设置。
## CanvasLayer.layer=50，PROCESS_MODE_ALWAYS：暂停时也能查看；默认隐藏，不影响正常游玩。

## 刷新间隔（秒）：性能文本无需每帧重排
const REFRESH_INTERVAL: float = 0.25
## 画质建议文案下标：与 FrameProfiler.suggest_quality() 的 0/1/2 对应
const QUALITY_NAMES: Array[String] = ["高", "中", "低"]

@onready var _text: RichTextLabel = $Panel/Margin/Text

var _elapsed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	visible = false
	set_process(false)


## F3 切换显隐；_input 不受 set_process(false) 影响，隐藏时仍能响应切换键
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F3:
		return
	visible = not visible
	_elapsed = 0.0
	set_process(visible)
	if visible:
		_refresh()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


func _refresh() -> void:
	var snap: Dictionary = FrameProfiler.get_snapshot()
	if not bool(snap.get("enabled", false)):
		_text.text = "[color=#ff8866]FrameProfiler 未启用（release build 不采集）[/color]"
		return
	var p50: Dictionary = snap["p50"] as Dictionary
	var p95: Dictionary = snap["p95"] as Dictionary
	var frame_p95: float = float(p95.get("frame_ms", 0.0))
	var frame_p50: float = float(p50.get("frame_ms", 0.0))
	var fps: float = float(snap["fps"])
	var budget_ms: float = float(snap.get("budget_ms", 16.6))
	# p95 超预算标黄、超 1.25 倍预算标红，便于真机快速判断
	var p95_color: String = "#66dd88"
	if frame_p95 > budget_ms:
		p95_color = "#ffcc55"
	if frame_p95 > budget_ms * 1.25:
		p95_color = "#ff6655"
	var suggest: int = int(snap["suggest"])
	var quality: String = QUALITY_NAMES[clampi(suggest, 0, QUALITY_NAMES.size() - 1)]
	_text.text = "\n".join(PackedStringArray([
		"[b]FPS[/b] %.1f" % fps,
		"process %.2f ms  |  physics %.2f ms" % [float(snap["process_ms"]), float(snap["physics_ms"])],
		"draw calls %d  |  primitives %d" % [int(snap["draw_calls"]), int(snap["primitives"])],
		"nodes %d  |  VRAM %.1f MB" % [int(snap["nodes"]), float(snap["vram_mb"])],
		"[color=%s]p95 frame %.2f ms[/color]  |  p50 %.2f ms" % [p95_color, frame_p95, frame_p50],
		"[color=%s]p95 draw calls %.0f[/color]" % [p95_color, float(p95.get("draw_calls", 0.0))],
		"[color=#8fc7ff]建议画质：%s（仅建议，不会自动切换）[/color]" % quality,
	]))
