class_name FoliageSpawner
extends Node3D
## 植物生成器：在地图随机散布草食植物，被吃掉后在随机位置重生。
## 维持固定数量，保证草食龙有稳定食物来源（构成食物链底层）。

const FoliageScene: PackedScene = preload("res://scenes/Foliage.tscn")

const FOLIAGE_COUNT: int = 30
const SPAWN_RADIUS: float = 130.0
const RESPAWN_INTERVAL: float = 12.0

var foliage: Array[Foliage] = []
var respawn_timers: Array[float] = []


func _ready() -> void:
	for i in FOLIAGE_COUNT:
		_spawn_foliage(_random_position())


func _process(delta: float) -> void:
	var done: Array[int] = []
	for i in range(respawn_timers.size()):
		respawn_timers[i] -= delta
		if respawn_timers[i] <= 0.0:
			_spawn_foliage(_random_position())
			done.append(i)
	done.reverse()
	for i in done:
		respawn_timers.remove_at(i)


func _spawn_foliage(pos: Vector3) -> void:
	var f: Foliage = FoliageScene.instantiate() as Foliage
	add_child(f)
	f.global_position = pos
	f.eaten.connect(_on_foliage_eaten)
	foliage.append(f)


func _on_foliage_eaten(pos: Vector3) -> void:
	# 从列表移除并安排重生
	for i in range(foliage.size()):
		if not is_instance_valid(foliage[i]):
			foliage.remove_at(i)
			respawn_timers.append(RESPAWN_INTERVAL)
			break


func _random_position() -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = randf() * SPAWN_RADIUS
	return Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
