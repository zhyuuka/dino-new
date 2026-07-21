class_name HUD
extends CanvasLayer
## HUD 层：左上血量/饥饿/口渴/体力四条；中上成长条；右上物种+计分；居中横幅/死亡屏；底部提示。

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
	menu_button.pressed.connect(func(): menu_pressed.emit())
	help_panel.visible = false
	help_button.pressed.connect(func(): hide_help())


## 用主题样式覆盖进度条填充色（Godot 4 的正确上色方式）
func _color_bar(bar: ProgressBar, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	bar.add_theme_stylebox_override("fill", sb)


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
	death_label.text = text
	death_panel.visible = true
	death_label.visible = true
	death_label.modulate.a = 1.0


## 首次游玩引导：图文图例，点「开始狩猎」关闭
func show_help() -> void:
	help_panel.visible = true


func hide_help() -> void:
	help_panel.visible = false
