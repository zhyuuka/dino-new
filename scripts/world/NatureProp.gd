class_name NatureProp
extends Node3D
## 静态自然物：加载 assets/models/nature/<slug>/<slug>_1k.gltf（Poly Haven CC0）。
## 由散布逻辑实例化，按地形高度放置。多个实例共享同一份几何体/纹理（Godot 资源缓存）。

const BASE: String = "res://assets/models/nature/%s/%s_1k.gltf"

var slug: String = ""
var _scale: float = 1.0
var _yoff: float = 0.0
var _view_end: float = 75.0
var _view_margin: float = 10.0


## 工厂：生成已配置好的自然物节点（_ready 时加载模型）
## view_end / view_margin：可见距离与淡出过渡带（米），由 WorldBuilder 按树/岩石分别传入。
static func create(slug: String, scale: float = 1.0, y_off: float = 0.0, view_end: float = 75.0, view_margin: float = 10.0) -> NatureProp:
	var p := NatureProp.new()
	p.slug = slug
	p._scale = scale
	p._yoff = y_off
	p._view_end = view_end
	p._view_margin = view_margin
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
			# 可见距离剔除（Godot 4 里 visibility_range_* 属于 GeometryInstance3D，
			# 不属于 Node3D），逐个网格实例设置；超出后引擎不提交绘制，省顶点/像素开销。
			# SELF 淡出避免远景硬闪。取值依据：地图 128m 见方（half_extent≈64）、
			# 各图雾密度 0.006～0.013，75m 外树石已与雾色融为一体，无需继续渲染。
			_apply_view_distance(inst)
	rotation = Vector3(0.0, randf() * TAU, 0.0)


## 递归给子树的每个可渲染实例套用可见距离（树 75m/岩石 65m，含淡出过渡带）
func _apply_view_distance(node: Node) -> void:
	var gi := node as GeometryInstance3D
	if gi != null:
		gi.visibility_range_end = _view_end
		gi.visibility_range_end_margin = _view_margin
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child in node.get_children():
		_apply_view_distance(child)
