class_name Maps
extends RefCounted
## 地图预设：地形来源（程序化噪声 / 下载高度图）+ 资源散布 + 天空/雾 基调。
## 所有自然模型均来自 Poly Haven（CC0 / 公有领域），高度图来自 3DTexel 社区库（CC0）。
##
## 移动端显存约束（2026-10 选种卡死修复）：
## - 单图自然模型总体积（去重后的模型目录体积之和）必须 < 180MB；禁用 > 100MB 的高模。
## - fir_tree_01（≈465MB）与 jacaranda_tree（≈205MB）已从全部地图剔除，任何 MapDef 不得再引用。
## - 数量上限：tree_count ≤ 45、rock_count ≤ 30、plant_count ≤ 30（手机内存与可玩密度折中）。
## - fir_sapling_medium（≈75MB）仅允许在 1 张图使用且实例数 ≤ 15（当前仅雪岭，tree_count=15）。
## - 选型优先小体积：dead_tree_trunk(4.7MB) / island_tree_02(45MB) / island_tree_01(64MB) /
##   boulder_01(5.6MB) / coast_land_rocks_04(33MB) 等；所有实例共享同一份模型资源。

## 默认地图 id：存档缺省与选图兜底统一引用此常量，避免业务代码裸写 "forest"
const DEFAULT_MAP_ID := "forest"

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
	## 地图专属加成物种：在基础 11 只花名册之外额外并入的物种 id 列表
	## （由 EcosystemDirector._build_roster 末尾合并，用于强化各图生态基调）
	var extra_roster: Array[String] = []


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
	d.id = DEFAULT_MAP_ID; d.name = "森林谷地"; d.blurb = "起伏丘陵，茂密林地，三处湖泊，最适合新手。"
	d.mode = 0; d.noise_seed = 7; d.noise_freq = 0.014; d.max_height = 22.0; d.snow_line = 0.8; d.water_level = 1.2
	d.water_points = [Vector3(-45, 0, 45), Vector3(70, 0, -55), Vector3(-80, 0, -70)]
	# 树木 45 棵（原 110）：island_tree_01 64MB + island_tree_02 45MB + dead_tree_trunk 4.7MB ≈ 113.7MB
	d.tree_models = ["island_tree_01", "island_tree_02", "dead_tree_trunk"]
	d.tree_count = 45
	# 岩石 26 块（原 40）：boulder_01 5.6MB + coast_land_rocks_04 33MB + namaqualand_boulder_02 5.0MB ≈ 43.6MB
	d.rock_models = ["boulder_01", "coast_land_rocks_04", "namaqualand_boulder_02"]
	d.rock_count = 26
	# 植物 30 株（原 48）：合计 ≈ 9.5MB
	d.plant_models = ["fern_02", "flower_heliophila", "grass_bermuda_01", "grass_medium_01"]
	d.plant_count = 30
	d.sky_top = Color(0.35, 0.6, 0.85); d.sky_horizon = Color(0.72, 0.83, 0.92)
	d.ambient = 0.55; d.fog_color = Color(0.8, 0.85, 0.82); d.fog_density = 0.006
	d.sun_color = Color(1.0, 0.98, 0.9)
	# 水草丰美的谷地：食草族群格外兴旺，食物链底层厚实
	d.extra_roster = [DinoSpecies.ID_GALLI, DinoSpecies.ID_TRIKE]
	return d


# 2) 高山雪岭：陡峭雪峰，植被稀疏
static func _snow() -> MapDef:
	var d := MapDef.new()
	d.id = "snow"; d.name = "高山雪岭"; d.blurb = "陡峭雪峰，寒雾弥漫，只有耐寒的松树与裸岩。"
	d.mode = 0; d.noise_seed = 21; d.noise_freq = 0.01; d.max_height = 46.0; d.snow_line = 0.45; d.water_level = 2.0
	d.water_points = [Vector3(60, 0, 60), Vector3(-70, 0, -60)]
	# 全项目唯一使用 fir_sapling_medium 的图：15 棵全部实例数 ≤ 15（75MB + dead_tree_trunk 4.7MB ≈ 79.7MB）
	d.tree_models = ["fir_sapling_medium", "dead_tree_trunk"]
	d.tree_count = 15
	# 岩石 30 块（原 60）：boulder_01 5.6MB + coast_land_rocks_04 33MB + moon_rock_01 1.7MB ≈ 40.3MB
	d.rock_models = ["boulder_01", "coast_land_rocks_04", "moon_rock_01"]
	d.rock_count = 30
	d.plant_models = ["fern_02", "grass_medium_02"]
	d.plant_count = 16
	d.sky_top = Color(0.45, 0.6, 0.85); d.sky_horizon = Color(0.86, 0.9, 0.95)
	d.ambient = 0.7; d.fog_color = Color(0.9, 0.93, 0.97); d.fog_density = 0.011
	d.sun_color = Color(0.95, 0.97, 1.0)
	# 寒冷雪原：厚甲抗寒的甲龙常驻，耐寒的似鸡龙小群游荡
	d.extra_roster = [DinoSpecies.ID_ANKY, DinoSpecies.ID_GALLI]
	return d


# 3) 荒原丘陵：低矮红岩，干燥暖雾
static func _waste() -> MapDef:
	var d := MapDef.new()
	d.id = "waste"; d.name = "荒原丘陵"; d.blurb = "低矮红岩丘陵，稀疏灌木，干燥暖雾，资源稀缺。"
	d.mode = 0; d.noise_seed = 99; d.noise_freq = 0.02; d.max_height = 13.0; d.snow_line = 0.9; d.water_level = 0.6
	d.water_points = [Vector3(0, 0, -60), Vector3(-60, 0, 60)]
	# 枯树 22 棵：dead_tree_trunk 4.7MB + dead_tree_trunk_02 4.8MB ≈ 9.5MB（该图不放阔叶树，贴合荒原）
	d.tree_models = ["dead_tree_trunk", "dead_tree_trunk_02"]
	d.tree_count = 22
	# 岩石 30 块（原 70）：coast_land_rocks_02 38MB + coast_land_rocks_04 33MB + boulder_01 5.6MB + namaqualand_boulder_02 5.0MB ≈ 81.6MB
	d.rock_models = ["coast_land_rocks_02", "coast_land_rocks_04", "boulder_01", "namaqualand_boulder_02"]
	d.rock_count = 30
	d.plant_models = ["flower_heliophila", "grass_medium_01", "grass_bermuda_01"]
	d.plant_count = 30
	d.sky_top = Color(0.6, 0.55, 0.5); d.sky_horizon = Color(0.85, 0.7, 0.55)
	d.ambient = 0.6; d.fog_color = Color(0.82, 0.66, 0.5); d.fog_density = 0.013
	d.sun_color = Color(1.0, 0.9, 0.75)
	# 开阔荒原：迅猛龙群在稀疏掩体间协同猎杀，疾驰的似鸡龙成群觅食
	d.extra_roster = [DinoSpecies.ID_RAPTOR, DinoSpecies.ID_GALLI]
	return d


# 4) 峡谷群峰：基于下载高度图的崎岖峡谷
static func _canyon() -> MapDef:
	var d := MapDef.new()
	d.id = "canyon"; d.name = "峡谷群峰"; d.blurb = "由下载的真实高度图生成的崎岖峡谷地貌，落差极大。"
	d.mode = 1; d.noise_seed = 0; d.noise_freq = 0.0; d.max_height = 40.0; d.snow_line = 0.5; d.water_level = 3.0
	d.water_points = [Vector3(0, 0, 0)]
	# 树木 34 棵：island_tree_02 45MB + dead_tree_trunk 4.7MB + dead_tree_trunk_02 4.8MB ≈ 54.5MB
	d.tree_models = ["island_tree_02", "dead_tree_trunk", "dead_tree_trunk_02"]
	d.tree_count = 34
	# 岩石 30 块（原 48）：boulder_01 5.6MB + coast_land_rocks_02 38MB + coast_land_rocks_04 33MB ≈ 76.6MB
	d.rock_models = ["boulder_01", "coast_land_rocks_02", "coast_land_rocks_04"]
	d.rock_count = 30
	d.plant_models = ["fern_02", "flower_heliophila", "grass_medium_02"]
	d.plant_count = 26
	d.sky_top = Color(0.4, 0.55, 0.8); d.sky_horizon = Color(0.8, 0.82, 0.85)
	d.ambient = 0.6; d.fog_color = Color(0.85, 0.85, 0.88); d.fog_density = 0.009
	d.sun_color = Color(1.0, 0.96, 0.88)
	d.heightmap_path = "assets/terrain/heightmap_community.png"
	# 险峻峡谷：顶级猎手的领地，食肉牛龙盘踞谷底，霸王龙偶尔巡猎（高难图加压）
	d.extra_roster = [DinoSpecies.ID_CARNO, DinoSpecies.ID_TREX]
	return d
