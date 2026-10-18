class_name SettingsPanel
extends Control
## 设置面板：主音量 / 音效 / 环境音 / 视角灵敏度四个滑条，供 PauseMenu 内嵌切换。
## 滑条变化立即落盘（GameState.set_setting 内部持久化）并应用到音频总线
## （AudioManager.apply_settings），拖动实时生效。
## UI 风格与 MapSelect / SpeciesSelect 一致：半透明背景 + 居中标题 + 垂直滑条行。

## 用户点击"返回"时发出（由 PauseMenu 切回主层）
signal back_pressed

## 滑条行配置：key 对应 GameState 设置键，min/max/step 为滑条范围与步长，default 为缺省值
const ROWS: Array[Dictionary] = [
	{"key": "master_volume", "label": "主音量", "min": 0.0, "max": 1.0, "step": 0.05, "default": 1.0},
	{"key": "sfx_volume", "label": "音效", "min": 0.0, "max": 1.0, "step": 0.05, "default": 1.0},
	{"key": "ambient_volume", "label": "环境音", "min": 0.0, "max": 1.0, "step": 0.05, "default": 1.0},
	{"key": "look_sensitivity", "label": "视角灵敏度", "min": 0.2, "max": 3.0, "step": 0.1, "default": 1.0},
]


func _ready() -> void:
	_build_ui()


# ================= UI 构建（代码动态构建，风格同 MapSelect） =================
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 深色背景（与选图/选种界面同色，完整覆盖暂停主层）
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 居中标题
	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_top = 0.5
	title.anchor_right = 0.5
	title.anchor_bottom = 0.5
	title.offset_left = -300.0
	title.offset_right = 300.0
	title.offset_top = -250.0
	title.offset_bottom = -210.0
	add_child(title)

	# 垂直滑条行 + 返回按钮（以屏幕中心锚定）
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -300.0
	vbox.offset_right = 300.0
	vbox.offset_top = -180.0
	vbox.offset_bottom = 220.0
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 20)
	add_child(vbox)

	for row: Dictionary in ROWS:
		vbox.add_child(_make_row(row))

	vbox.add_child(_make_back_button())


## 构建单个滑条行：名称 | 滑条 | 数值
func _make_row(row: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)

	var name_label := Label.new()
	name_label.text = String(row["label"])
	name_label.custom_minimum_size = Vector2(130, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = float(row["min"])
	slider.max_value = float(row["max"])
	slider.step = float(row["step"])
	# 初始值读已加载的设置（GameState._ready 时已从磁盘回退校验过）
	slider.value = float(GameState.get_setting(String(row["key"]), row["default"]))
	slider.custom_minimum_size = Vector2(320, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.text = _format_value(String(row["key"]), slider.value)
	hbox.add_child(value_label)

	# 变化即落盘并应用（bind 携带键名与数值 Label 用于刷新显示）
	slider.value_changed.connect(_on_value_changed.bind(String(row["key"]), value_label))
	return hbox


func _make_back_button() -> Button:
	var btn := Button.new()
	btn.text = "返回"
	btn.custom_minimum_size = Vector2(400, 80)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): back_pressed.emit())
	return btn


# ================= 数值变更 =================
func _on_value_changed(value: float, key: String, value_label: Label) -> void:
	# 立即写盘（GameState 内部持久化）并应用到音频总线，拖动实时生效
	GameState.set_setting(key, value)
	AudioManager.apply_settings(GameState.settings)
	value_label.text = _format_value(key, value)


## 数值显示：音量按百分比（如 80%），灵敏度按倍率（如 ×1.0）
func _format_value(key: String, value: float) -> String:
	if key == "look_sensitivity":
		return "×%.1f" % value
	return "%d%%" % roundi(value * 100.0)
