class_name HUD
extends CanvasLayer
## HUD 层：左上血量/饥饿/口渴/体力四条；中上成长条；右上物种+计分；居中横幅/死亡屏；底部提示。
## 另含：顶部居中常驻目标条（新手引导用，TutorialGuide 调用 set_objective/clear_objective）、
## 成就解锁横幅（连接 Achievements.achievement_unlocked）。

signal menu_pressed

@onready var health_bar: ProgressBar = $Control/HealthBar
@onready var health_label: Label = $Control/HealthBar/HealthLabel
@onready var hunger_bar: ProgressBar = $Control/HungerBar
@onready var hunger_label: Label = $Control/HungerBar/HungerLabel
@onready var thirst_bar: ProgressBar = $Control/ThirstBar
@onready var thirst_label: Label = $Control/ThirstBar/ThirstLabel
@onready var stamina_bar: ProgressBar = $Control/StaminaBar
@onready var stamina_label: Label = $Control/StaminaBar/StaminaLabel
@onready var growth_bar: ProgressBar = $Control/GrowthBar
@onready var growth_label: Label = $Control/GrowthLabel
@onready var stage_label: Label = $Control/GrowthBar/StageLabel
@onready var species_label: Label = $Control/SpeciesLabel
@onready var score_label: Label = $Control/ScoreLabel
@onready var banner: Label = $Control/Banner
@onready var hint_label: Label = $Control/HintLabel
@onready var death_panel: ColorRect = $Control/DeathPanel
@onready var death_label: Label = $Control/DeathPanel/DeathLabel
@onready var menu_button: Button = $Control/MenuButton
@onready var help_panel: Control = $Control/HelpPanel
@onready var help_label: RichTextLabel = $Control/HelpPanel/HelpLabel
@onready var help_button: Button = $Control/HelpPanel/HelpButton

var _hint_tween: Tween = null
var _last_hint: String = ""
var _pause_menu: PauseMenu
var _is_dead: bool = false

# 常驻目标条（代码动态构建，见 _build_objective_bar）
var _objective_panel: PanelContainer
var _objective_label: Label
var _objective_tween: Tween = null
var _objective_text: String = ""


func _ready() -> void:
	_color_bar(health_bar, Color(0.85, 0.2, 0.2))
	_color_bar(hunger_bar, Color(0.9, 0.6, 0.15))
	_color_bar(thirst_bar, Color(0.2, 0.6, 0.9))
	_color_bar(stamina_bar, Color(0.3, 0.8, 0.35))
	_color_bar(growth_bar, Color(0.7, 0.4, 0.9))
	banner.modulate.a = 0.0
	banner.visible = false
	hint_label.modulate.a = 0.0
	death_panel.visible = false
	death_label.visible = false
	# 加入 HUD 组（Groups.HUD）：供 TutorialGuide 动态发现
	add_to_group(Groups.HUD)
	# 新手引导目标条（顶部居中，代码动态构建）
	_build_objective_bar()
	# 成就解锁横幅：Achievements autoload 在本节点 _ready 前已就绪，直接连接；
	# 死亡重开重建 HUD 时旧实例随旧 HUD 释放，连接自动断开，不会重复
	Achievements.achievement_unlocked.connect(_on_achievement_unlocked)
	# 暂停菜单：HUD 持有并实例化；其回主菜单请求转发给既有的 menu_pressed（Main 侧零改动）
	_pause_menu = PauseMenu.new()
	_pause_menu.exit_to_menu.connect(func(): menu_pressed.emit())
	add_child(_pause_menu)
	menu_button.pressed.connect(_on_menu_button)
	help_panel.visible = false
	help_button.pressed.connect(func(): hide_help())


## 用主题样式覆盖进度条填充色（Godot 4 的正确上色方式）
func _color_bar(bar: ProgressBar, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	bar.add_theme_stylebox_override("fill", sb)


## 菜单按钮：存活时打开暂停菜单；死亡屏期间保持原行为直接回主菜单（玩家已死不该有暂停）
func _on_menu_button() -> void:
	if _is_dead:
		menu_pressed.emit()
	else:
		_pause_menu.open()


func set_health(c: int, m: int) -> void:
	health_bar.max_value = m
	health_bar.value = c
	health_label.text = "血 %d/%d" % [c, m]

func set_hunger(c: int, m: int) -> void:
	hunger_bar.max_value = m
	hunger_bar.value = c
	hunger_label.text = "饿 %d/%d" % [c, m]

func set_thirst(c: int, m: int) -> void:
	thirst_bar.max_value = m
	thirst_bar.value = c
	thirst_label.text = "渴 %d/%d" % [c, m]

func set_stamina(c: int, m: int) -> void:
	stamina_bar.max_value = m
	stamina_bar.value = c
	stamina_label.text = "力 %d/%d" % [c, m]

func set_growth(stage: int, name: String, progress: float) -> void:
	growth_bar.max_value = 100
	growth_bar.value = int(progress * 100.0)
	growth_label.text = "成长"
	stage_label.text = name

func set_species(name: String, diet: String, stage: String) -> void:
	species_label.text = "%s（%s·%s）" % [name, diet, stage]

func set_score(time_sec: int, kills: int, generation: int) -> void:
	score_label.text = "第%d代  存活%d秒  击杀%d" % [generation, time_sec, kills]


func show_banner(text: String) -> void:
	banner.text = text
	banner.visible = true
	banner.modulate.a = 1.0
	var t: Tween = create_tween()
	t.tween_interval(1.8)
	t.tween_property(banner, "modulate:a", 0.0, 0.6)
	t.tween_callback(func(): banner.visible = false)


func show_hint(text: String) -> void:
	if text == _last_hint and hint_label.visible:
		return
	_last_hint = text
	hint_label.text = text
	hint_label.visible = true
	hint_label.modulate.a = 1.0
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(5.0)
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 1.0)
	_hint_tween.tween_callback(func(): hint_label.visible = false)


func hide_hint() -> void:
	_last_hint = ""
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	hint_label.visible = false
	hint_label.modulate.a = 0.0


func show_death(text: String) -> void:
	_is_dead = true
	death_label.text = text
	death_panel.visible = true
	death_label.visible = true
	death_label.modulate.a = 1.0


## 首次游玩引导：图文图例，点「开始狩猎」关闭
func show_help() -> void:
	help_panel.visible = true


func hide_help() -> void:
	help_panel.visible = false


# ================= 常驻目标条（新手引导） =================
## 构建顶部居中目标条：PanelContainer 半透明深色底 + 居中暖色文字，
## 位于成长条（y 12~28）下方，初始隐藏（set_objective 显示 / clear_objective 隐藏）
func _build_objective_bar() -> void:
	_objective_panel = PanelContainer.new()
	_objective_panel.visible = false
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顶边中点锚定，成长条下方不遮挡（右上菜单按钮在 y 70 起、横向不重叠）
	_objective_panel.anchor_left = 0.5
	_objective_panel.anchor_right = 0.5
	_objective_panel.anchor_top = 0.0
	_objective_panel.anchor_bottom = 0.0
	_objective_panel.offset_left = -260.0
	_objective_panel.offset_right = 260.0
	_objective_panel.offset_top = 36.0
	_objective_panel.offset_bottom = 66.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, 0.72)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	_objective_panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_objective_panel.add_child(lbl)
	_objective_label = lbl
	$Control.add_child(_objective_panel)


## 显示/更新常驻目标条（文案未变且已显示时幂等返回，供 TutorialGuide 周期重连调用）
func set_objective(text: String) -> void:
	if text == _objective_text and _objective_panel.visible:
		return
	_objective_text = text
	_objective_label.text = "目标：%s" % text
	_objective_panel.visible = true
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_panel.modulate.a = 1.0
	_objective_tween = create_tween()
	_objective_tween.tween_property(_objective_panel, "modulate:a", 1.0, 0.25).from(0.0)


## 隐藏目标条（淡出；引导结束自毁前调用）
func clear_objective() -> void:
	_objective_text = ""
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_tween = create_tween()
	_objective_tween.tween_property(_objective_panel, "modulate:a", 0.0, 0.4)
	_objective_tween.tween_callback(func(): _objective_panel.visible = false)


# ================= 成就横幅 =================
## 成就解锁横幅（Achievements autoload 首次解锁时发出）
func _on_achievement_unlocked(_id: String, title: String) -> void:
	show_banner("成就解锁：%s" % title)
