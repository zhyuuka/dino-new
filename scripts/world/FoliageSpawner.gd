class_name FoliageSpawner
extends Node3D
## 植物生成器：在地图随机散布草食植物（自然模型），被吃掉后在随机位置重生。
## 维持固定数量，保证草食龙有稳定食物来源（构成食物链底层）。

const FoliageScene: PackedScene = preload("res://scenes/Foliage.tscn")

const RESPAWN_INTERVAL: float = 12.0

# 由 Main 注入：地形引用 + 本地图的植物模型与数量
var terrain: TerrainGenerator
var plant_slugs: Array = []
var plant_count: int = 30

var foliage: Array[Foliage] = []
var respawn_timers: Array[float] = []


func _ready() -> void:
	for i in plant_count:
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
	if not plant_slugs.is_empty():
		f.visual_slug = plant_slugs[randi() % plant_slugs.size()]
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


## 随机位置：有地形时按地形高度取 xz 并避水，否则回退到旧的圆内随机
func _random_position() -> Vector3:
	if terrain != null:
		var half := terrain.half_extent - 6.0
		for attempt in 30:
			var x: float = randf_range(-half, half)
			var z: float = randf_range(-half, half)
			if terrain.is_under_water(x, z):
				continue
			return Vector3(x, terrain.get_height(x, z), z)
		return Vector3(0.0, 0.0, 0.0)
	var angle: float = randf() * TAU
	var dist: float = randf() * 130.0
	return Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
