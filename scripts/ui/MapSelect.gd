class_name MapSelect
extends CanvasLayer
## 开局地图选择界面：列出 4 张地图预设（森林谷地 / 高山雪岭 / 荒原丘陵 / 峡谷群峰），
## 点击某张地图即进入选种流程。结构参考 SpeciesSelect。

signal selected(map_id: String)

@onready var list: VBoxContainer = $Control/MapList


func _ready() -> void:
	for def in Maps.all():
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(400, 80)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.focus_mode = Control.FOCUS_NONE

		# 两行文本：第一行地图名（20px 粗体白字），第二行简介（14px 灰字）
		var vb: VBoxContainer = VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var l1: Label = Label.new()
		l1.text = def.name
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l1.add_theme_font_size_override("font_size", 20)
		l1.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

		var l2: Label = Label.new()
		l2.text = def.blurb
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.add_theme_font_size_override("font_size", 14)
		l2.add_theme_color_override("font_color", Color(0.66, 0.7, 0.74))

		vb.add_child(l1)
		vb.add_child(l2)
		btn.add_child(vb)

		btn.pressed.connect(_on_pressed.bind(def.id))
		list.add_child(btn)


func _on_pressed(id: String) -> void:
	selected.emit(id)
