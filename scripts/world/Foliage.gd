class_name Foliage
extends Node3D
## 植物（灌木/蕨类）：草食者（玩家或 AI）碰到即自动进食并回饥饿。
## 被吃掉后发出 eaten 信号，由 FoliageSpawner 负责在别处重生。
## 加入 group "plant"。
##
## 视觉方案 A：本节点只保留"逻辑本体 + Area3D"，不再实例化 gltf 网格；
## 视觉由 FoliageSpawner 的 MultiMesh 池按 slug 批量绘制。
## 落点在入树前注入、_ready 内先落位再注册视觉槽位，
## 保证 MultiMesh 实例与 Area3D 用同一个 global_position（判定与视觉不脱节）。

signal eaten(node: Foliage)
## 入树落位完成后发出：FoliageSpawner 据此分配 MultiMesh 视觉槽位。
## 用信号而不是持有 Spawner 引用，避免两个 class_name 互相引用形成循环依赖。
signal visual_attach_requested(node: Foliage)

## 视觉等比缩放（与旧版逐实例一致）
const VISUAL_SCALE: float = 0.6

## 由 FoliageSpawner 注入：生成落点（入树前赋值，_ready 内落位后再注册视觉）
var spawn_position: Vector3 = Vector3.ZERO
## 由 FoliageSpawner 注入：要渲染的自然模型 slug（空则不渲染）
var visual_slug: String = ""
## 在当前 slug 的 MultiMesh 中占用的实例号（-1 = 未占用：被吃、或超出可见距离被剔除）
var visual_index: int = -1
## 视觉参数：每株随机偏航 + 固定等比缩放
var visual_yaw: float = 0.0
var visual_scale: float = VISUAL_SCALE

@onready var plant_area: Area3D = $PlantArea


func _ready() -> void:
	add_to_group(Groups.PLANT)
	# 先落位：视觉实例与 Area3D 共用同一个 global_position
	global_position = spawn_position
	visual_yaw = randf() * TAU
	# 向 Spawner 注册视觉实例（由 Spawner 写入 MultiMesh 变换，本节点不创建任何网格）
	visual_attach_requested.emit(self)
	if plant_area != null:
		plant_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if is_queued_for_deletion():
		return
	var is_herbivore: bool = false
	if body is PlayerDino and not (body as PlayerDino).is_carnivore():
		is_herbivore = true
	elif body is AIDino and (body as AIDino).species.diet == DinoSpecies.Diet.HERBIVORE:
		is_herbivore = true
	if is_herbivore:
		if body.has_method("on_eat_plant"):
			body.on_eat_plant()
		# 携带自身节点发出信号，便于生成器精确定位被吃的植物；必须在 queue_free 之前发
		eaten.emit(self)
		queue_free()
