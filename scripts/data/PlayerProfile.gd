class_name PlayerProfile
extends RefCounted
## 存档的内存模型：强类型、单一形状、默认值集中。
## 职责边界：
## - 只做 dict ↔ 类型化快照的转换与范围钳制，**不碰文件**（磁盘读写由 SaveRepository 负责）
## - 所有存档键名常量集中在本类，其他文件禁止裸写存档键字符串
## - 本类不包含“本局瞬时值”（血量/坐标/世界时间），那些不进存档

## 存档键名常量（唯一来源）
const KEY_SPECIES := "species_id"
const KEY_GROWTH_STAGE := "growth_stage"
const KEY_GENERATION := "generation"
const KEY_MAP_ID := "map_id"
const KEY_BEST_TIME := "best_time"
const KEY_BEST_KILLS := "best_kills"

var species_id: String = DinoSpecies.ID_RAPTOR
var growth_stage: int = 0
var generation: int = 1
var map_id: String = Maps.DEFAULT_MAP_ID
var best_time: int = 0
var best_kills: int = 0


## 默认档：无档 / 损坏档 / 未来版本档的统一回退值
static func defaults() -> PlayerProfile:
	return PlayerProfile.new()


## 从（已迁移到当前版本的）字典构造；字段做类型转换 + 范围钳制，非法值回退默认
static func from_dict(d: Dictionary) -> PlayerProfile:
	var p := PlayerProfile.new()

	var sid: String = str(d.get(KEY_SPECIES, DinoSpecies.ID_RAPTOR))
	# 未知物种回退迅猛龙，避免运行期 by_id() 拿到 null
	p.species_id = sid if DinoSpecies.by_id(sid) != null else DinoSpecies.ID_RAPTOR
	p.growth_stage = clampi(int(d.get(KEY_GROWTH_STAGE, 0)), 0, DinoSpecies.MAX_STAGE)
	p.generation = maxi(int(d.get(KEY_GENERATION, 1)), 1)
	# Maps.by_id() 对未知 id 总回退到第一张图，这里同样收敛成合法 id
	p.map_id = Maps.by_id(str(d.get(KEY_MAP_ID, Maps.DEFAULT_MAP_ID))).id
	p.best_time = maxi(int(d.get(KEY_BEST_TIME, 0)), 0)
	p.best_kills = maxi(int(d.get(KEY_BEST_KILLS, 0)), 0)
	return p


## 转成磁盘字典；save_version / profile_version 由 SaveRepository 统一添加，不在此处写
func to_dict() -> Dictionary:
	return {
		KEY_SPECIES: species_id,
		KEY_GROWTH_STAGE: growth_stage,
		KEY_GENERATION: generation,
		KEY_MAP_ID: map_id,
		KEY_BEST_TIME: best_time,
		KEY_BEST_KILLS: best_kills,
	}
