class_name LoadingScreen
extends CanvasLayer
## 全屏加载遮罩：世界构建（资源预加载/地形/植被/自然物/角色）期间显示真实进度，避免主线程
## 同步加载被玩家误认为"卡死"。由 Main 挂到 Dynamic 下并驱动：
##   set_progress(0.0~1.0, 文案) 推进进度 → fade_out() 淡出 → queue_free()。
## layer = 100 盖住选图/选种（CanvasLayer 默认 layer 1）与 HUD；
## PROCESS_MODE_ALWAYS 保证即使场景处于暂停状态也能显示；全屏 Control 拦截触摸防误触。

@onready var _background: ColorRect = $Control/Background
@onready var _progress_text: Label = $Control/ProgressText
@onready var _bar: ProgressBar = $Control/ProgressBar


func _ready() -> void:
	# 暂停残留（PauseMenu 的 process_mode 为 WHEN_PAUSED 子树）不影响本界面渲染
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 全屏拦截：加载期间触摸/鼠标不会穿透到下层选种界面或 HUD
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0


## 推进进度（0.0~1.0 小数）并更新进度条与百分比文字；ratio 会被夹取到合法区间
func set_progress(ratio: float, text: String = "") -> void:
	var v: float = clampf(ratio, 0.0, 1.0)
	_bar.value = v
	var pct: int = int(roundf(v * 100.0))
	if text.is_empty():
		_progress_text.text = "%d%%" % pct
	else:
		_progress_text.text = "%d%% · %s" % [pct, text]


## 淡出整块遮罩（含背景与文字），返回时已完成补间，调用方可直接 queue_free
func fade_out(duration: float = 0.35) -> void:
	var tw := create_tween()
	tw.tween_property($Control, "modulate:a", 0.0, duration)
	await tw.finished
