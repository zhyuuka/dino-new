class_name DinoEgg
extends Node3D
## 恐龙蛋：代际机制的具象化
## - AI 蛋：45s 自动孵化 → 广播 hatched → Main 调 EcosystemDirector.hatch_ai 落地幼体；
##   成功由 Main 销毁蛋壳，生态满员由 Main 回调 notify_hatch_failed 延时重试
## - 玩家蛋：不自动孵化，是死亡后的重生锚点（Main._restart_run 消费，跨代资产）
## - 可被掠食者咬破（take_damage，血量 2 口），破掉即消失
## 蛋壳色随物种 body_color 变化（_ready 内按 species_id 现建材质）

signal hatched(species_id: String, pos: Vector3)

const HATCH_TIME_AI: float = 45.0    # AI 蛋自动孵化计时（秒）
const RETRY_DELAY: float = 20.0      # 孵化被拒后的重试间隔（秒）
const MAX_EGGS_ON_FIELD: int = 10    # 同屏 AI 蛋数守卫：孵化瞬间自查，超限延后重试（玩家蛋不占名额）
const MAX_HP: int = 2                # 被咬 2 口破坏

# 由产蛋方在挂树前赋值
var species_id: String = DinoSpecies.ID_RAPTOR
var owner_player: bool = false       # true = 玩家的蛋（不自动孵化，死亡后从蛋重生）
var growth_stage_snapshot: int = 0   # 玩家蛋：产蛋瞬间玩家的成长阶段快照
var from_generation: int = 1         # 玩家蛋：所属代际（AI 蛋无意义）；重生时取代际最大者为最新锚点

var hatch_timer: float = HATCH_TIME_AI
var hp: int = MAX_HP

# 孵化请求已广播（等待 Main 回传成败），防止计时归零后重复广播
var _hatch_requested: bool = false

@onready var mesh: MeshInstance3D = $EggMesh


func _ready() -> void:
	add_to_group(Groups.EGG)
	if owner_player:
		# 玩家蛋不自动孵化：作为跨代重生锚点，由 Main 在死亡重开时消费
		hatch_timer = -1.0
	_apply_shell_color()


func _process(delta: float) -> void:
	if owner_player or hp <= 0 or _hatch_requested:
		return
	hatch_timer -= delta
	if hatch_timer <= 0.0:
		_try_hatch()


## 孵化守卫：只统计 AI 蛋（玩家蛋是跨代重生锚点，不占孵化名额）。
## 同屏 AI 蛋超限（>10）则延后重试、不广播；
## 否则广播 hatched，成败由 Main 回传决定（满员 → notify_hatch_failed；成功 → Main 销毁蛋）
func _try_hatch() -> void:
	var ai_egg_count: int = 0
	for n in get_tree().get_nodes_in_group(Groups.EGG):
		var e := n as DinoEgg
		if e != null and not e.owner_player:
			ai_egg_count += 1
	if ai_egg_count > MAX_EGGS_ON_FIELD:
		hatch_timer = RETRY_DELAY
		return
	_hatch_requested = true
	hatched.emit(species_id, global_position)


## Main 回传孵化失败（生态满员）：延时 RETRY_DELAY 秒重试
func notify_hatch_failed() -> void:
	_hatch_requested = false
	hatch_timer = RETRY_DELAY


## 被咬（掠食者偷蛋）：血量 2 口，破掉即消失
## （AI 蛋被吃掉不孵化；玩家蛋被偷走则失去重生锚点——护巢有理）
func take_damage(amount: int, attacker: Node = null) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()


## 蛋壳色：物种 body_color 混入蛋壳白，附微光便于玩家在草丛里注意到蛋
func _apply_shell_color() -> void:
	var base := Color(0.93, 0.9, 0.8)
	var def := DinoSpecies.by_id(species_id)
	if def != null:
		base = def.body_color.lerp(Color(0.95, 0.93, 0.85), 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = 0.55
	mat.emission_enabled = true
	mat.emission = base
	mat.emission_energy_multiplier = 0.08
	mesh.material_override = mat
