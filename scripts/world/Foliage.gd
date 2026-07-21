class_name Foliage
extends Node3D
## 植物（灌木/蕨类）：草食者（玩家或 AI）碰到即自动进食并回饥饿。
## 被吃掉后发出 eaten 信号，由 FoliageSpawner 负责在别处重生。
## 加入 group "plant"。

signal eaten(pos: Vector3)

@onready var plant_area: Area3D = $PlantArea


func _ready() -> void:
	add_to_group("plant")
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
		eaten.emit(global_position)
		queue_free()
