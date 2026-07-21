class_name NatureProp
extends Node3D
## 静态自然物：加载 assets/models/nature/<slug>/<slug>_1k.gltf（Poly Haven CC0）。
## 由散布逻辑实例化，按地形高度放置。多个实例共享同一份几何体/纹理（Godot 资源缓存）。

const BASE: String = "res://assets/models/nature/%s/%s_1k.gltf"

var slug: String = ""
var _scale: float = 1.0
var _yoff: float = 0.0


## 工厂：生成已配置好的自然物节点（_ready 时加载模型）
static func create(slug: String, scale: float = 1.0, y_off: float = 0.0) -> NatureProp:
	var p := NatureProp.new()
	p.slug = slug
	p._scale = scale
	p._yoff = y_off
	return p


func _ready() -> void:
	var path := BASE % [slug, slug]
	if ResourceLoader.exists(path):
		var scn := load(path) as PackedScene
		if scn != null:
			var inst := scn.instantiate()
			inst.scale = Vector3(_scale, _scale, _scale)
			inst.position = Vector3(0.0, _yoff, 0.0)
			add_child(inst)
	rotation = Vector3(0.0, randf() * TAU, 0.0)
