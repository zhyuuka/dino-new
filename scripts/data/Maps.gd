class_name Maps
extends RefCounted
## 地图预设：地形来源（程序化噪声 / 下载高度图）+ 资源散布 + 天空/雾 基调。
## 所有自然模型均来自 Poly Haven（CC0 / 公有领域），高度图来自 3DTexel 社区库（CC0）。

class MapDef:
	var id: String = ""
	var name: String = ""
	var blurb: String = ""
	var mode: int = 0                 # 0=噪声程序化, 1=下载高度图
	var noise_seed: int = 0
	var noise_freq: float = 0.014
	var max_height: float = 22.0
	var snow_line: float = 0.75       # max_height 的比例：超过此高度开始积雪
	var water_level: float = 1.2      # 水面绝对高度（地形会被下挖成盆地）
	var water_points: Array = []
	var tree_models: Array = []
	var tree_count: int = 60
	var rock_models: Array = []
	var rock_count: int = 30
	var plant_models: Array = []
	var plant_count: int = 30
	var sky_top: Color = Color(0.35, 0.6, 0.85)
	var sky_horizon: Color = Color(0.7, 0.82, 0.9)
	var ambient: float = 0.55
	var fog_color: Color = Color(0.8, 0.85, 0.8)
	var fog_density: float = 0.006
	var sun_color: Color = Color(1.0, 0.98, 0.9)
	var heightmap_path: String = ""


static var _db: Array = []


static func _build() -> void:
	if not _db.is_empty():
		return
	_db.append(_forest())
	_db.append(_snow())
	_db.append(_waste())
	_db.append(_canyon())


static func all() -> Array:
	_build()
	return _db


static func by_id(id: String) -> MapDef:
	_build()
	for d in _db:
		if d.id == id:
			return d
	return _db[0]


# 1) 森林谷地：起伏丘陵 + 茂密针叶林 + 三处湖泊
static func _forest() -> MapDef:
	var d := MapDef.new()
	d.id = "forest"; d.name = "森林谷地"; d.blurb = "起伏丘陵，茂密针叶林，三处湖泊，最适合新手。"
	d.mode = 0; d.noise_seed = 7; d.noise_freq = 0.014; d.max_height = 22.0; d.snow_line = 0.8; d.water_level = 1.2
	d.water_points = [Vector3(-45, 0, 45), Vector3(70, 0, -55), Vector3(-80, 0, -70)]
	d.tree_models = ["fir_tree_01", "fir_sapling_medium", "island_tree_01", "island_tree_02", "dead_tree_trunk"]
	d.tree_count = 110
	d.rock_models = ["boulder_01", "coast_land_rocks_02", "coast_land_rocks_03", "namaqualand_boulder_02"]
	d.rock_count = 40
	d.plant_models = ["fern_02", "flower_heliophila", "grass_bermuda_01", "grass_medium_01"]
	d.plant_count = 48
	d.sky_top = Color(0.35, 0.6, 0.85); d.sky_horizon = Color(0.72, 0.83, 0.92)
	d.ambient = 0.55; d.fog_color = Color(0.8, 0.85, 0.82); d.fog_density = 0.006
	d.sun_color = Color(1.0, 0.98, 0.9)
	return d


# 2) 高山雪岭：陡峭雪峰，植被稀疏
static func _snow() -> MapDef:
	var d := MapDef.new()
	d.id = "snow"; d.name = "高山雪岭"; d.blurb = "陡峭雪峰，寒雾弥漫，只有耐寒的松树与裸岩。"
	d.mode = 0; d.noise_seed = 21; d.noise_freq = 0.01; d.max_height = 46.0; d.snow_line = 0.45; d.water_level = 2.0
	d.water_points = [Vector3(60, 0, 60), Vector3(-70, 0, -60)]
	d.tree_models = ["fir_tree_01", "fir_sapling_medium", "dead_tree_trunk"]
	d.tree_count = 50
	d.rock_models = ["boulder_01", "coast_land_rocks_02", "coast_land_rocks_04", "moon_rock_01"]
	d.rock_count = 60
	d.plant_models = ["fern_02", "grass_medium_02"]
	d.plant_count = 16
	d.sky_top = Color(0.45, 0.6, 0.85); d.sky_horizon = Color(0.86, 0.9, 0.95)
	d.ambient = 0.7; d.fog_color = Color(0.9, 0.93, 0.97); d.fog_density = 0.011
	d.sun_color = Color(0.95, 0.97, 1.0)
	return d


# 3) 荒原丘陵：低矮红岩，干燥暖雾
static func _waste() -> MapDef:
	var d := MapDef.new()
	d.id = "waste"; d.name = "荒原丘陵"; d.blurb = "低矮红岩丘陵，稀疏灌木，干燥暖雾，资源稀缺。"
	d.mode = 0; d.noise_seed = 99; d.noise_freq = 0.02; d.max_height = 13.0; d.snow_line = 0.9; d.water_level = 0.6
	d.water_points = [Vector3(0, 0, -60), Vector3(-60, 0, 60)]
	d.tree_models = ["dead_tree_trunk", "dead_tree_trunk_02", "island_tree_01"]
	d.tree_count = 22
	d.rock_models = ["coast_land_rocks_02", "coast_land_rocks_03", "coast_land_rocks_04", "boulder_01", "namaqualand_boulder_02"]
	d.rock_count = 70
	d.plant_models = ["flower_heliophila", "grass_medium_01", "grass_bermuda_01"]
	d.plant_count = 30
	d.sky_top = Color(0.6, 0.55, 0.5); d.sky_horizon = Color(0.85, 0.7, 0.55)
	d.ambient = 0.6; d.fog_color = Color(0.82, 0.66, 0.5); d.fog_density = 0.013
	d.sun_color = Color(1.0, 0.9, 0.75)
	return d


# 4) 峡谷群峰：基于下载高度图的崎岖峡谷
static func _canyon() -> MapDef:
	var d := MapDef.new()
	d.id = "canyon"; d.name = "峡谷群峰"; d.blurb = "由下载的真实高度图生成的崎岖峡谷地貌，落差极大。"
	d.mode = 1; d.noise_seed = 0; d.noise_freq = 0.0; d.max_height = 40.0; d.snow_line = 0.5; d.water_level = 3.0
	d.water_points = [Vector3(0, 0, 0)]
	d.tree_models = ["fir_tree_01", "dead_tree_trunk", "island_tree_02"]
	d.tree_count = 36
	d.rock_models = ["boulder_01", "coast_land_rocks_02", "coast_land_rocks_03", "coast_land_rocks_04"]
	d.rock_count = 48
	d.plant_models = ["fern_02", "flower_heliophila", "grass_medium_02"]
	d.plant_count = 26
	d.sky_top = Color(0.4, 0.55, 0.8); d.sky_horizon = Color(0.8, 0.82, 0.85)
	d.ambient = 0.6; d.fog_color = Color(0.85, 0.85, 0.88); d.fog_density = 0.009
	d.sun_color = Color(1.0, 0.96, 0.88)
	d.heightmap_path = "assets/terrain/heightmap_community.png"
	return d
