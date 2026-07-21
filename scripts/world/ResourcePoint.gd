class_name ResourcePoint
extends Node3D
## 探索资源点：巢穴(休整回血回体力) / 矿物盐(限时伤害+速度增益)
## 由 Main 在地图散布；玩家靠近时触发效果（仅在范围内生效，离开即停）。

enum Type { NEST, LICK }

const NEST_RADIUS: float = 6.0
const LICK_RADIUS: float = 5.0
const LICK_DURATION: float = 30.0
const LICK_SPEED: float = 1.25
const LICK_DMG: float = 1.4
const NEST_HEAL_RATE: float = 7.0     # 每秒回血
const NEST_STAMINA_RATE: float = 16.0 # 每秒回体力

@export var point_type: Type = Type.NEST

var _nest_heal_acc: float = 0.0
var _nest_stam_acc: float = 0.0
var _lick_hinted: bool = false


func _ready() -> void:
	_build_visual()


func _build_visual() -> void:
	match point_type:
		Type.NEST:
			# 褐色环（巢） + 柔光地面
			var ring := CSGTorus3D.new()
			ring.inner_radius = 3.0
			ring.outer_radius = 4.2
			ring.height = 0.6
			ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			ring.position = Vector3(0, 0.3, 0)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.45, 0.32, 0.2)
			m.roughness = 1.0
			ring.material = m
			add_child(ring)
			var glow := CSGCylinder3D.new()
			glow.radius = 4.0
			glow.height = 0.1
			glow.position = Vector3(0, 0.06, 0)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.3, 0.7, 0.4)
			gm.emission_enabled = true
			gm.emission = Color(0.25, 0.6, 0.35)
			gm.emission_energy_multiplier = 0.6
			gm.roughness = 1.0
			glow.material = gm
			add_child(glow)
		Type.LICK:
			# 彩色矿物盐盘 + 微光
			var disc := CSGCylinder3D.new()
			disc.radius = 4.0
			disc.height = 0.15
			disc.position = Vector3(0, 0.08, 0)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.85, 0.7, 0.25)
			m.emission_enabled = true
			m.emission = Color(0.9, 0.75, 0.2)
			m.emission_energy_multiplier = 0.5
			m.roughness = 0.7
			disc.material = m
			add_child(disc)
			var spark := CSGCylinder3D.new()
			spark.radius = 1.6
			spark.height = 0.25
			spark.position = Vector3(0, 0.2, 0)
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.95, 0.9, 0.6)
			sm.emission_enabled = true
			sm.emission = Color(1.0, 0.85, 0.3)
			sm.emission_energy_multiplier = 0.9
			spark.material = sm
			add_child(spark)


func _process(delta: float) -> void:
	var p: PlayerDino = _player()
	if p == null or p.is_dead:
		return
	var d: float = Vector2(global_position.x - p.global_position.x, global_position.z - p.global_position.z).length()
	match point_type:
		Type.NEST:
			if d <= NEST_RADIUS:
				_nest_heal_acc += NEST_HEAL_RATE * delta
				_nest_stam_acc += NEST_STAMINA_RATE * delta
				if _nest_heal_acc >= 1.0:
					var h: int = int(_nest_heal_acc)
					p.heal(h)
					_nest_heal_acc -= h
				if _nest_stam_acc >= 1.0:
					var s: int = int(_nest_stam_acc)
					p.restore_stamina(s)
					_nest_stam_acc -= s
			else:
				_nest_heal_acc = 0.0
				_nest_stam_acc = 0.0
		Type.LICK:
			if d <= LICK_RADIUS:
				p.apply_buff(LICK_DURATION, LICK_SPEED, LICK_DMG)
				if not _lick_hinted:
					p.banner.emit("矿物盐强化！伤害与速度提升")
					_lick_hinted = true
			else:
				_lick_hinted = false


func _player() -> PlayerDino:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		return null
	return arr[0] as PlayerDino
