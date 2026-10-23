class_name NatureBatch
extends RefCounted
## 自然物批处理（静态工具类，无运行时实例）：
## 把同类自然物（同 slug）按 32m 分块合并为 MultiMesh：大幅减少节点数，
## 并让同块内同模型的重复实例共用一次绘制（每块 × 每模板网格 = 一个 MultiMesh）。
## 模板缓存：每个 gltf 只 load + instantiate 一次；网格节点的 transform 按"相对场景根"
## 烘焙后挂到不入树的占位宿主上，供所有实例复用（模板节点不入树，也不参与渲染）。

const BASE: String = "res://assets/models/nature/%s/%s_1k.gltf"

## 分块：地图 half_extent=128（-128..128），64m 一块 → 4×4 块，只创建有内容的块。
## 取 64m 而非 32m：32m 时同块同 slug 平均不足 1 个实例，MultiMesh 合并收益有限；
## 64m 在 draw call 与可见距离剔除粒度之间折中（树 75m/石 65m 可见，块角最远约 90m，仍在雾中）。
const CHUNK_SIZE: float = 64.0
const CHUNK_MIN: float = -128.0
const CHUNK_COUNT: int = 4

## MultiMesh 无逐实例剔除：custom_aabb 覆盖整块范围，再留 1m 余量防止边缘提前剔除。
const AABB_PAD: float = 1.0

## slug -> Array[MeshInstance3D]（模板网格；transform 已是相对场景根的 bake 结果）
static var _templates: Dictionary = {}
## slug -> Node（模板网格的宿主：不入树，仅为保持 MeshInstance3D 存活，进程内常驻不泄漏增长）
static var _holders: Dictionary = {}


## 一条待批量实例：slugs / 落点 / 缩放 / 偏航 / 可见距离
class Item:
	extends RefCounted
	var slug: String = ""
	var position: Vector3 = Vector3.ZERO
	var scale: float = 1.0
	var yaw: float = 0.0
	var view_end: float = 75.0
	var view_margin: float = 10.0


## 世界坐标 -> 分块整型坐标（越界钳制到 8×8 范围）
static func chunk_of(pos: Vector3) -> Vector2i:
	var ix := int(floor((pos.x - CHUNK_MIN) / CHUNK_SIZE))
	var iz := int(floor((pos.z - CHUNK_MIN) / CHUNK_SIZE))
	return Vector2i(clampi(ix, 0, CHUNK_COUNT - 1), clampi(iz, 0, CHUNK_COUNT - 1))


## 分块中心（y 取 0，实例高度直接用世界 y，方便 AABB 计算）
static func chunk_center(chunk: Vector2i) -> Vector3:
	return Vector3(
		CHUNK_MIN + (float(chunk.x) + 0.5) * CHUNK_SIZE,
		0.0,
		CHUNK_MIN + (float(chunk.y) + 0.5) * CHUNK_SIZE
	)


## 把一条落点归入 groups：groups[chunk][slug] -> Array[Item]
static func add(groups: Dictionary, item: Item) -> void:
	var chunk := chunk_of(item.position)
	var by_slug: Dictionary
	if groups.has(chunk):
		by_slug = groups[chunk] as Dictionary
	else:
		by_slug = {}
		groups[chunk] = by_slug
	var list: Array
	if by_slug.has(item.slug):
		list = by_slug[item.slug] as Array
	else:
		list = []
		by_slug[item.slug] = list
	list.append(item)


## 烘焙全部组：groups[chunk][slug] -> Array[Item]，产物挂在 parent 下
static func bake(groups: Dictionary, parent: Node3D) -> void:
	if parent == null or groups.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "NatureBatches"
	parent.add_child(holder)
	for chunk_key in groups.keys():
		var chunk: Vector2i = chunk_key
		var by_slug: Dictionary = groups[chunk_key] as Dictionary
		var center := chunk_center(chunk)
		for slug_key in by_slug.keys():
			var items: Array = by_slug[slug_key] as Array
			_bake_group(holder, center, chunk, str(slug_key), items)


## 单块单 slug：每个模板网格子节点建一个 MultiMeshInstance3D
static func _bake_group(parent: Node3D, center: Vector3, chunk: Vector2i, slug: String, items: Array) -> void:
	if items.is_empty():
		return
	# 模板缺失（模型文件不存在）时静默跳过，与旧 NatureProp 行为一致
	var template := _get_template(slug)
	if template.is_empty():
		return
	var first := items[0] as Item
	for t in template.size():
		var proto: MeshInstance3D = template[t]
		if proto.mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.use_custom_data = false
		mm.mesh = proto.mesh
		mm.instance_count = items.size()
		var bounds := AABB()
		var first_box := true
		for i in items.size():
			var it := items[i] as Item
			# 实例变换 = (偏航 + 等比缩放 + 块内局部位置) × 模板网格相对根的变换
			var local_pos := it.position - center
			var xf := Transform3D(Basis(Vector3.UP, it.yaw).scaled(Vector3.ONE * it.scale), local_pos)
			xf = xf * proto.transform
			mm.set_instance_transform(i, xf)
			var box := _transformed_aabb(proto.mesh.get_aabb(), xf)
			if first_box:
				bounds = box
				first_box = false
			else:
				bounds = bounds.merge(box)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_c%d_%d_m%d" % [slug, chunk.x, chunk.y, t]
		mmi.multimesh = mm
		# custom_aabb：水平覆盖整块 32m，竖直取块内实例实际高度范围，再留余量
		var chunk_box := AABB(
			Vector3(-CHUNK_SIZE * 0.5, bounds.position.y, -CHUNK_SIZE * 0.5),
			Vector3(CHUNK_SIZE, bounds.size.y, CHUNK_SIZE)
		)
		mmi.custom_aabb = chunk_box.merge(bounds).grow(AABB_PAD)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 可见距离与旧逐实例设置完全一致（树 75/10，岩石 65/8，SELF 淡出）
		mmi.visibility_range_end = first.view_end
		mmi.visibility_range_end_margin = first.view_margin
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)


## 取模板（首次调用时 load + instantiate 并缓存，之后零加载开销）
static func _get_template(slug: String) -> Array:
	if _templates.has(slug):
		return _templates[slug] as Array
	var result: Array[MeshInstance3D] = []
	var path := BASE % [slug, slug]
	if ResourceLoader.exists(path):
		var scn := load(path) as PackedScene
		if scn != null:
			var root := scn.instantiate() as Node3D
			if root != null:
				# MeshInstance3D 节点的 transform 先蒸成"相对场景根"，随后脱离场景根
				_collect_meshes(root, Transform3D.IDENTITY, result)
				var holder := Node.new()
				holder.name = "NatureTemplate_" + slug
				for mi in result:
					var old_parent := mi.get_parent()
					if old_parent != null:
						old_parent.remove_child(mi)
					holder.add_child(mi)
				# 根节点本身若是 MeshInstance3D 已被收集复用，不能释放；否则释放这个空壳根
				if not (root is MeshInstance3D):
					root.free()
				_holders[slug] = holder
	_templates[slug] = result
	return result


## 递归收集 MeshInstance3D，并把父链变换累积进节点自身 transform（相对传入根）
static func _collect_meshes(node: Node, parent_xf: Transform3D, out: Array[MeshInstance3D]) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.transform = xf
		out.append(mi)
	for child in node.get_children():
		_collect_meshes(child, xf, out)


## 把 mesh 的局部 AABB 经实例变换后求轴对齐包围盒（8 角点，兼容旋转/缩放）
static func _transformed_aabb(local_box: AABB, xf: Transform3D) -> AABB:
	var p := local_box.position
	var s := local_box.size
	var corners: Array[Vector3] = [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]
	var out := AABB(xf * corners[0], Vector3.ZERO)
	for i in range(1, corners.size()):
		out = out.expand(xf * corners[i])
	return out
