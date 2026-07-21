class_name AICorpse
extends StaticBody3D
## AI / 玩家恐龙尸体：肉食者（玩家或 AI）可走到附近咬食回饥饿
## - 一段时间后自动消失
## - 可吃若干口，吃完立即消失
## - 躺在地上、按死亡物种上色后变暗
## 物理层 layer 3 (AI)，被玩家 / AI 的咬击与寻食检测（group "corpse"）

const LIFETIME: float = 20.0
const MAX_BITES: int = 3
const FADE_DURATION: float = 0.4

# 由 Main 在生成时按死亡物种设置
var species_id: String = ""
var species_colors: Array = []

@onready var dino_visual: DinoVisual = $DinoVisual

var bites_remaining: int = MAX_BITES
var lifetime_timer: float = LIFETIME
var is_being_destroyed: bool = false


func _ready() -> void:
	add_to_group("corpse")
	var b: Color = Color(0.5, 0.4, 0.3)
	var d: Color = Color(0.3, 0.25, 0.15)
	if species_colors.size() >= 2 and species_colors[0] is Color:
		b = species_colors[0]
		d = species_colors[1]
	if species_id == "":
		species_id = "raptor"
	# 加载模型并放倒、变暗（尸体表现由 DinoVisual 处理）
	dino_visual.setup(species_id, b, d, {"corpse": true})


func _process(delta: float) -> void:
	if is_being_destroyed:
		return
	lifetime_timer -= delta
	if lifetime_timer <= 0.0:
		_fade_out_and_free()


## 尝试吃尸体一口。成功返回 true
func try_eat() -> bool:
	if is_being_destroyed or bites_remaining <= 0:
		return false
	bites_remaining -= 1
	dino_visual.pulse_damage()
	if bites_remaining <= 0:
		_fade_out_and_free()
	return true


func _fade_out_and_free() -> void:
	if is_being_destroyed:
		return
	is_being_destroyed = true
	dino_visual.fade_out(queue_free)
