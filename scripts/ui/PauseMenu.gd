class_name PauseMenu
extends CanvasLayer
## 暂停菜单：游戏内暂停界面，提供 继续 / 设置 / 成就 / 回到主菜单 四个入口。
## process_mode 为 WHEN_PAUSED：世界（默认 PAUSABLE 继承链）暂停时本层仍可响应按钮。
## UI 风格与 MapSelect / SpeciesSelect 一致：半透明背景 + 居中标题 + 垂直按钮。
## 成就子页读取 Achievements autoload（代码动态构建，风格同 SettingsPanel）。

## 用户确认回到主菜单时发出（Main 已有 hud.menu_pressed → reload_current_scene 的连接，由 HUD 转发）
signal exit_to_menu

var _settings_panel: SettingsPanel
var _main_root: Control   # 主层容器（标题 + 按钮列表），切到设置页时隐藏
var _ach_button: Button   # 主层"成就 x/8"按钮（打开菜单时刷新计数文案）
var _ach_page: Control    # 成就列表子页（整页容器，切到成就页时显示）
var _ach_list: VBoxContainer  # 成就行容器（每次打开子页时重建以反映最新状态）


func _init() -> void:
	# 实例化即生效：暂停树时本层继续处理按钮；层级高于 HUD；默认隐藏由 open() 显示
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 10
	visible = false


func _ready() -> void:
	_build_ui()


## 打开暂停菜单：暂停整个场景树（世界物理 / AI / 计分全停）并显示本层
func open() -> void:
	_show_main()
	# 成就计数每次打开时刷新（游戏进行中可能刚解锁）
	if _ach_button != null:
		_ach_button.text = _achievements_button_text()
	visible = true
	get_tree().paused = true


## 关闭暂停菜单：恢复场景树运行并隐藏本层
func close() -> void:
	visible = false
	get_tree().paused = false


# ================= UI 构建（代码动态构建，风格同 MapSelect） =================
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# 全屏半透明黑背景（压暗并挡住游戏画面；点击背景不关闭，仅"继续"恢复）
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# 主层：居中标题
	_main_root = Control.new()
	_main_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_main_root)

	var title := Label.new()
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_top = 0.5
	title.anchor_right = 0.5
	title.anchor_bottom = 0.5
	title.offset_left = -300.0
	title.offset_right = 300.0
	title.offset_top = -230.0
	title.offset_bottom = -180.0
	_main_root.add_child(title)

	# 主层：垂直按钮列表
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -200.0
	vbox.offset_right = 200.0
	vbox.offset_top = -140.0
	vbox.offset_bottom = 170.0
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 20)
	_main_root.add_child(vbox)

	vbox.add_child(_make_button("继续", close))
	vbox.add_child(_make_button("设置", _show_settings))
	# 成就入口：文案"成就 x/8"（打开菜单时在 open() 刷新计数）
	_ach_button = _make_button("成就 0/8", _show_achievements)
	vbox.add_child(_ach_button)
	vbox.add_child(_make_button("回到主菜单", _on_exit_pressed))

	# 主层底部：小字版本号（随主层显隐；读取项目设置 application/config/version）
	var version_label := Label.new()
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "dev")
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.anchor_left = 0.0
	version_label.anchor_top = 1.0
	version_label.anchor_right = 1.0
	version_label.anchor_bottom = 1.0
	version_label.offset_top = -40.0
	version_label.offset_bottom = -12.0
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.5))
	_main_root.add_child(version_label)

	# 设置子面板（初始隐藏，返回时切回主层；随本层 WHEN_PAUSED 一同在暂停中可用）
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.back_pressed.connect(_show_main)
	root.add_child(_settings_panel)

	# 成就列表子页（初始隐藏，打开时重建列表；风格同 SettingsPanel）
	_ach_page = _build_achievements_page()
	_ach_page.visible = false
	root.add_child(_ach_page)


## 统一构建按钮（尺寸与对齐同 MapSelect 列表项）
func _make_button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(400, 80)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	return btn


# ================= 层切换 =================
func _show_main() -> void:
	_main_root.visible = true
	if _settings_panel != null:
		_settings_panel.visible = false
	if _ach_page != null:
		_ach_page.visible = false


func _show_settings() -> void:
	_main_root.visible = false
	if _settings_panel != null:
		_settings_panel.visible = true
	if _ach_page != null:
		_ach_page.visible = false


func _show_achievements() -> void:
	_main_root.visible = false
	if _settings_panel != null:
		_settings_panel.visible = false
	if _ach_page != null:
		_refresh_achievements_page()
		_ach_page.visible = true


# ================= 成就子页 =================
## 成就按钮计数文案：已解锁数 / 总数（数据来自 Achievements.all()）
func _achievements_button_text() -> String:
	var got: int = 0
	var data: Dictionary = Achievements.all()
	for v: Dictionary in data.values():
		if bool(v.get("unlocked", false)):
			got += 1
	return "成就 %d/%d" % [got, data.size()]


## 构建成就列表子页骨架：深色背景 + 居中标题 + 滚动列表 + 返回按钮（布局同 SettingsPanel）
func _build_achievements_page() -> Control:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 深色背景（与设置页同色，完整覆盖暂停主层）
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)

	# 居中标题
	var title := Label.new()
	title.text = "成就"
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
	page.add_child(title)

	# 垂直布局：滚动列表占满剩余高度 + 返回按钮
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
	page.add_child(vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 仅纵向滚动，横向铺满列表宽
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_ach_list = VBoxContainer.new()
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_ach_list)

	vbox.add_child(_make_button("返回", _show_main))
	return page


## 重建成就列表（每次打开子页时调用，反映最新解锁状态；旧行立即释放避免残影）
func _refresh_achievements_page() -> void:
	for child in _ach_list.get_children():
		_ach_list.remove_child(child)
		child.free()
	for def: Dictionary in Achievements.all().values():
		_ach_list.add_child(_make_achievement_row(def))


## 单条成就行：已解锁 → 亮色标题 + 描述；未解锁 → 灰色"？？？"
func _make_achievement_row(def: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)
	if bool(def.get("unlocked", false)):
		var title := Label.new()
		title.text = String(def.get("title", ""))
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		row.add_child(title)
		var desc := Label.new()
		desc.text = String(def.get("desc", ""))
		desc.add_theme_font_size_override("font_size", 14)
		desc.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
		row.add_child(desc)
	else:
		var locked := Label.new()
		locked.text = "？？？"
		locked.add_theme_font_size_override("font_size", 18)
		locked.add_theme_color_override("font_color", Color(0.45, 0.48, 0.52))
		row.add_child(locked)
	return row


# ================= 按钮行为 =================
## 回到主菜单：先解除暂停再发信号，保证 Main 侧 reload_current_scene 在非暂停状态执行
func _on_exit_pressed() -> void:
	get_tree().paused = false
	exit_to_menu.emit()
