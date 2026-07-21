class_name WaterSource
extends Node3D
## 水源（湖泊）：玩家与恐龙可进入饮水。
## 进入范围（radius）内即视为“在水中”，玩家按住饮水键回口渴，AI 自动饮水。
## 被加入 group "water"，供 PlayerDino / AIDino 查询。

@export var radius: float = 18.0

@onready var water_mesh: CSGBox3D = $Water


func _ready() -> void:
	add_to_group("water")
	if water_mesh != null:
		water_mesh.size = Vector3(radius * 2.0, 0.25, radius * 2.0)
