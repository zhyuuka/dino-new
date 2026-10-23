class_name WorldBuilder
extends Node
## 世界构建子系统（纯构建工具，不持运行时状态）：按地图预设生成
## 地形网格、湖泊水源、植被撒布器、树石自然模型与巢穴 / 矿物盐资源点。
## 全部为参数化实例方法：传入动态容器 parent 与地图预设 def（及所需引用），
## 关键产物（TerrainGenerator / FoliageSpawner）通过返回值交回 Main。

const WaterScene: PackedScene = preload("res://scenes/WaterSource.tscn")
const FoliageSpawnerScene: PackedScene = preload("res://scenes/FoliageSpawner.tscn")
const ResourcePointScene: PackedScene = preload("res://scenes/ResourcePoint.tscn")

const LAKE_RADIUS: float = 18.0

# 巢穴与矿物盐的固定散布点（坐标为水平面位置，高度按地形落点计算）
const NEST_POINTS: Array[Vector3] = [
	Vector3(45.0, 0.0, 50.0),
	Vector3(-60.0, 0.0, 30.0),
	Vector3(20.0, 0.0, -70.0),
]
const LICK_POINTS: Array[Vector3] = [
	Vector3(-30.0, 0.0, -40.0),
	Vector3(80.0, 0.0, 20.0),
	Vector3(-90.0, 0.0, -30.0),
]


## 生成地形网格并应用地图的天空/雾基调，返回地形生成器
func spawn_terrain(parent: Node3D, def: Maps.MapDef, world_env: WorldEnvironment) -> TerrainGenerator:
	var terrain := TerrainGenerator.new()
	terrain.setup(def)
	terrain.name = "Terrain"
	parent.add_child(terrain)
	apply_map_atmosphere(def, world_env)
	return terrain


## 用地图预设里的天空/雾/环境光基调初始化 WorldEnvironment
func apply_map_atmosphere(def: Maps.MapDef, world_env: WorldEnvironment) -> void:
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = def.fog_density
	env.fog_light_color = def.fog_color


## 按地图预设的水域点生成湖泊水源（首湖为主湖，半径依次递减，多余湖泊回退默认半径）
func spawn_water(parent: Node3D, def: Maps.MapDef) -> void:
	var radii := [LAKE_RADIUS, 12.0, 10.0]
	for i in def.water_points.size():
		var wp := def.water_points[i] as Vector3
		var w: WaterSource = WaterScene.instantiate() as WaterSource
		w.global_position = Vector3(wp.x, def.water_level, wp.z)
		w.radius = radii[i] if i < radii.size() else 10.0
		parent.add_child(w)


## 生成植被撒布器（按地图预设的植物模型与数量），返回撒布器引用
func spawn_foliage(parent: Node3D, def: Maps.MapDef, terrain: TerrainGenerator) -> FoliageSpawner:
	var fs: FoliageSpawner = FoliageSpawnerScene.instantiate() as FoliageSpawner
	fs.terrain = terrain
	fs.plant_slugs = def.plant_models
	fs.plant_count = def.plant_count
	parent.add_child(fs)
	return fs


## 在地形上随机撒自然模型（树木 + 岩石），替代旧的 CSG 装饰。
## chunk_await > 0 时每处理 chunk_await 个候选点让出一帧（await process_frame），
## 让加载界面能重绘、避免一次性同步 load() 大量模型把主线程堵死（手机端表现为"假死"）。
## on_progress(done, total) 为可选进度回调；调用方必须 await 本函数才能等到全部撒完。
func spawn_nature(parent: Node3D, def: Maps.MapDef, terrain: TerrainGenerator, chunk_await: int = 0, on_progress: Callable = Callable()) -> void:
	if terrain == null:
		return
	var half := terrain.half_extent - 8.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total: int = def.tree_count + def.rock_count
	var done: int = 0
	# 树木
	for i in def.tree_count:
		# 分帧点：每 chunk_await 个让出一帧（NatureProp._ready 里是同步 load，必须在实例之间断开）
		if chunk_await > 0 and done > 0 and done % chunk_await == 0:
			if on_progress.is_valid():
				on_progress.call(done, total)
			await get_tree().process_frame
		done += 1
		var x: float = rng.randf_range(-half, half)
		var z: float = rng.randf_range(-half, half)
		if terrain.is_under_water(x, z):
			continue
		if abs(x) < 12.0 and abs(z) < 12.0:
			continue  # 出生点附近留空
		var slug: String = def.tree_models[rng.randi() % def.tree_models.size()]
		var s: float = rng.randf_range(0.8, 1.3)
		var p := NatureProp.create(slug, s, 0.0)
		p.global_position = Vector3(x, terrain.get_height(x, z), z)
		parent.add_child(p)
	# 岩石
	for i in def.rock_count:
		if chunk_await > 0 and done > 0 and done % chunk_await == 0:
			if on_progress.is_valid():
				on_progress.call(done, total)
			await get_tree().process_frame
		done += 1
		var x: float = rng.randf_range(-half, half)
		var z: float = rng.randf_range(-half, half)
		if terrain.is_under_water(x, z):
			continue
		if abs(x) < 10.0 and abs(z) < 10.0:
			continue
		var slug: String = def.rock_models[rng.randi() % def.rock_models.size()]
		var s: float = rng.randf_range(0.6, 1.8)
		var p := NatureProp.create(slug, s, 0.0)
		p.global_position = Vector3(x, terrain.get_height(x, z), z)
		parent.add_child(p)
	if on_progress.is_valid():
		on_progress.call(total, total)


## 巢穴与矿物盐散布在地图各处（避开水下点位，按地形高度放置）
func spawn_resource_points(parent: Node3D, terrain: TerrainGenerator) -> void:
	for pos in NEST_POINTS:
		if terrain != null and terrain.is_under_water(pos.x, pos.z):
			continue
		var rp: ResourcePoint = ResourcePointScene.instantiate() as ResourcePoint
		rp.point_type = ResourcePoint.Type.NEST
		var y: float = terrain.get_height(pos.x, pos.z) if terrain != null else 0.0
		rp.global_position = Vector3(pos.x, y, pos.z)
		parent.add_child(rp)
	for pos in LICK_POINTS:
		if terrain != null and terrain.is_under_water(pos.x, pos.z):
			continue
		var rp: ResourcePoint = ResourcePointScene.instantiate() as ResourcePoint
		rp.point_type = ResourcePoint.Type.LICK
		var y: float = terrain.get_height(pos.x, pos.z) if terrain != null else 0.0
		rp.global_position = Vector3(pos.x, y, pos.z)
		parent.add_child(rp)
