class_name SpeciesSelect
extends CanvasLayer
## 开局选种界面：列出所有可玩恐龙（属性 / 食性 / 技能），点击即开始。
## 若已有存档，顶部提供“继续”按钮，保留成长与代际。

signal selected(species_id: String, is_continue: bool)

@onready var title_label: Label = $Control/TitleLabel
@onready var continue_button: Button = $Control/ContinueButton
@onready var list: VBoxContainer = $Control/Scroll/List


func _ready() -> void:
	# 是否有可继续的存档
	var d: Dictionary = SaveManager.load_save()
	if d.has("species_id") and d.has("growth_stage"):
		continue_button.visible = true
		var sp: DinoSpecies.SpeciesDef = DinoSpecies.by_id(d["species_id"])
		var nm: String = sp.name if sp != null else str(d["species_id"])
		continue_button.text = "继续：%s（%s · 第%d代）" % [nm, DinoSpecies.stage_name(d["growth_stage"]), d.get("generation", 1)]
		continue_button.pressed.connect(_on_continue.bind(d["species_id"]))
	else:
		continue_button.visible = false

	# 物种卡片
	for sp in DinoSpecies.all():
		var btn: Button = Button.new()
		btn.text = _card_text(sp)
		btn.custom_minimum_size = Vector2(0, 96)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_card_pressed.bind(sp.id))
		list.add_child(btn)


func _on_card_pressed(id: String) -> void:
	selected.emit(id, false)

func _on_continue(id: String) -> void:
	selected.emit(id, true)

func _card_text(sp: DinoSpecies.SpeciesDef) -> String:
	return "%s   [%s]  %s\n体力 %d   速度 %.0f   咬击 %d\n%s" % [
		sp.name, sp.diet_text(), sp.ability_text(),
		sp.max_health, sp.run_speed, sp.bite_damage, sp.blurb
	]
