class_name FoliageSpawner
extends Node3D
## 植物生成器：在地图随机散布草食植物（自然模型），被吃掉后在随机位置重生。
## 维持固定数量，保证草食龙有稳定食物来源（构成食物链底层）。
##
## 视觉方案 A（MultiMesh 池）：Foliage 节点只保留逻辑本体 + Area3D，不再各自实例化 gltf；
## 本节点按 slug 建一组 MultiMeshInstance3D（模板有几个子网格就有几个 MMI），
## 实例容量固定 = plant_count，可见实例紧凑排在 [0, visible_instance_count)：
##   · 被吃 / 超出可见距离 → 与末尾实例交换 + visible_instance_count--（swap-remove）
##   · 重生 / 进入可见距离 → 追加到末尾，等价于复用最小编号空闲槽
## 因此绘制批次只随"本地图用到的模板子网格数"增长，与植物数量无关。

const FoliageScene: PackedScene = preload("res://scenes/Foliage.tscn")

const BASE_RESPAWN_INTERVAL: float = 12.0  # 默认重生间隔（丰饶期临时 ÷4，结束恢复）

# 可见距离（米）：超出 VIEW_DISTANCE 从 MultiMesh 剔除，回到 VIEW_DISTANCE 内才恢复；
# VIEW_MARGIN 是迟滞带宽（28~34m 之间保持原状态），避免边界来回抖动；fade 关闭省透明开销。
const VIEW_DISTANCE: float = 28.0
const VIEW_MARGIN: float = 6.0

const CULL_INTERVAL: float = 0.25  # 距离巡检周期（秒）：30 株 × 每 0.25s 一次，开销可忽略
const MODEL_PATH: String = "res://assets/models/nature/%s/%s_1k.gltf"
const AABB_PAD: float = 1.0  # 可见包围盒余量（米）


## 单个模板子网格：网格资源 + 相对 gltf 场景根的变换（实例变换 = 落点变换 × 本变换）
class Proto:
	extends RefCounted
	var mesh: Mesh = null
	var xf: Transform3D = Transform3D.IDENTITY


## 单个 slug 的视觉批次：一组 MMI（对应模板各子网格，实例号含义完全一致）+ 可见实例表
class Batch:
	extends RefCounted
	var slug: String = ""
	var mmis: Array[MultiMeshInstance3D] = []
	var protos: Array[Proto] = []
	## 可见实例表：下标即 MultiMesh 实例号，长度即 visible_instance_count
	var plants: Array[Foliage] = []
	var pad: float = 1.0  # 单株视觉包围半径（米），用于 custom_aabb

## slug -> Array[Proto]，进程内常驻（与 NatureBatch 同理：模板只解析一次，跨局复用）
static var _proto_cache: Dictionary = {}

# 由 Main 注入：地形引用 + 本地图的植物模型与数量
var terrain: TerrainGenerator
var plant_slugs: Array = []
var plant_count: int = 30

var foliage: Array[Foliage] = []
var respawn_timers: Array[float] = []
## 被吃后的重生等待秒数（丰饶期由 set_abundant 临时缩短）
var respawn_interval: float = BASE_RESPAWN_INTERVAL

# slug -> Batch（MultiMesh 池本体）
var _batches: Dictionary = {}
var _cull_elapsed: float = 0.0
var _camera_seen: bool = false


func _ready() -> void:
	_build_batches()
	for i in plant_count:
		_spawn_foliage(_random_position())


func _process(delta: float) -> void:
	# 重生计时
	var done: Array[int] = []
	for i in range(respawn_timers.size()):
		respawn_timers[i] -= delta
		if respawn_timers[i] <= 0.0:
			_spawn_foliage(_random_position())
			done.append(i)
	done.reverse()
	for i in done:
		respawn_timers.remove_at(i)

	# 相机首次出现（玩家生成）时立刻巡检一次：加载期没有相机，全部实例是可见的，
	# 整张地图尺度的包围盒可能被节点级可见距离整批剔除，需在同一帧收敛到正确集合。
	var cam: Camera3D = _camera()
	if cam != null and not _camera_seen:
		_camera_seen = true
		_cull_elapsed = CULL_INTERVAL
	# 可见距离巡检（节流）
	_cull_elapsed += delta
	if _cull_elapsed >= CULL_INTERVAL:
		_cull_elapsed = 0.0
		_update_visibility()


## 丰饶期开关（随机事件调用）：生效期重生间隔 ÷4，触发瞬间补生 5 株。
## 槽位制下存活总数恒 ≤ plant_count：这里只会占用空闲槽位，没有空闲槽时自然无操作
## （旧实现会净增节点，越挂越多）。
func set_abundant(on: bool) -> void:
	respawn_interval = BASE_RESPAWN_INTERVAL / 4.0 if on else BASE_RESPAWN_INTERVAL
	if on:
		for i in 5:
			_spawn_foliage(_random_position())


func _spawn_foliage(pos: Vector3) -> void:
	# 硬上限：存活总数与 MultiMesh 实例容量都钉在 plant_count
	if foliage.size() >= plant_count:
		return
	var f: Foliage = FoliageScene.instantiate() as Foliage
	if not plant_slugs.is_empty():
		f.visual_slug = str(plant_slugs[randi() % plant_slugs.size()])
	f.spawn_position = pos
	# 先连接信号再入树：_ready 内的落位/注册、以及入树首帧被吃都不会漏接
	f.visual_attach_requested.connect(attach_visual)
	f.eaten.connect(_on_foliage_eaten)
	# _ready 内：落位 → 注册 MultiMesh 槽位（Area3D 与视觉同一 global_position）
	add_child(f)
	foliage.append(f)


func _on_foliage_eaten(f: Foliage) -> void:
	# 先释放视觉实例槽（swap-remove），再移除逻辑实例并排入重生计时
	var batch: Batch = _batches.get(f.visual_slug) as Batch
	if batch != null and f.visual_index >= 0:
		_hide_visual(batch, f)
		_sync_batch(batch)
	foliage.erase(f)
	respawn_timers.append(respawn_interval)


# ================= 视觉池：槽位分配 / 写变换 =================
## Foliage._ready 内调用（此时 global_position 已落位）：占用一个 MultiMesh 实例槽。
## 超出可见距离时先不占槽，等巡检回到距离内再追加（省一次无谓的变换写入）。
func attach_visual(f: Foliage) -> void:
	var batch: Batch = _batches.get(f.visual_slug) as Batch
	if batch == null:
		f.visual_index = -1
		return
	var cam: Camera3D = _camera()
	if cam != null and cam.global_position.distance_to(f.global_position) > VIEW_DISTANCE:
		f.visual_index = -1
		return
	_show_visual(batch, f)
	_sync_batch(batch)


## 占用 batch 的最小编号空闲槽（可见实例表是稠密的，空闲槽即 [size, capacity) 区间）
func _show_visual(batch: Batch, f: Foliage) -> void:
	if f.visual_index >= 0:
		return
	var idx: int = batch.plants.size()
	if idx >= plant_count:  # 容量保护（存活总数 ≤ plant_count，理论上到不了）
		f.visual_index = -1
		return
	batch.plants.append(f)
	f.visual_index = idx
	_write_instance(batch, idx, f)


## 释放槽位：把末尾那株搬到空出的槽（swap-remove），再缩短可见实例数
func _hide_visual(batch: Batch, f: Foliage) -> void:
	var idx: int = f.visual_index
	f.visual_index = -1
	if idx < 0 or idx >= batch.plants.size():
		return
	var last: int = batch.plants.size() - 1
	if idx != last:
		var moved: Foliage = batch.plants[last]
		batch.plants[idx] = moved
		moved.visual_index = idx
		_write_instance(batch, idx, moved)
	batch.plants.remove_at(last)


## 写入第 idx 号实例的全部子网格变换。
## 位置统一取 Foliage.global_position（与 Area3D 同源），转到本节点局部空间后
## 再乘模板子网格相对根的变换，与 NatureBatch 的烘焙规则一致。
func _write_instance(batch: Batch, idx: int, f: Foliage) -> void:
	var xf := Transform3D(
		Basis(Vector3.UP, f.visual_yaw).scaled(Vector3.ONE * f.visual_scale),
		to_local(f.global_position)
	)
	for i in batch.mmis.size():
		var mm: MultiMesh = batch.mmis[i].multimesh
		if mm != null:
			mm.set_instance_transform(idx, xf * batch.protos[i].xf)


## 同步可见实例数 + custom_aabb（后者只覆盖当前可见实例，
## 免得隐藏槽位的旧坐标把包围盒撑到整张地图，导致视锥/可见距离判断失真）
func _sync_batch(batch: Batch) -> void:
	var count: int = batch.plants.size()
	var box: AABB = _visible_aabb(batch)
	for mmi in batch.mmis:
		var mm: MultiMesh = mmi.multimesh
		if mm != null:
			mm.visible_instance_count = count
		mmi.custom_aabb = box


func _visible_aabb(batch: Batch) -> AABB:
	var pad: Vector3 = Vector3.ONE * batch.pad
	var box := AABB()
	var first: bool = true
	for f in batch.plants:
		if not is_instance_valid(f):
			continue
		var b := AABB(to_local(f.global_position) - pad, pad * 2.0)
		box = b if first else box.merge(b)
		first = false
	if first:
		# 无可见实例：给一个极小包围盒，批次直接被剔除，不产生无谓提交
		return AABB(Vector3(-0.01, -0.01, -0.01), Vector3(0.02, 0.02, 0.02))
	return box.grow(AABB_PAD)


# ================= 可见距离巡检 =================
func _update_visibility() -> void:
	var cam: Camera3D = _camera()
	if cam == null:
		return  # 加载期无相机：保持全部可见，由相机出现后的首次巡检收敛
	var cam_pos: Vector3 = cam.global_position
	var dirty: Dictionary = {}
	for f in foliage:
		if not is_instance_valid(f):
			continue
		var batch: Batch = _batches.get(f.visual_slug) as Batch
		if batch == null:
			continue
		var dist: float = cam_pos.distance_to(f.global_position)
		if f.visual_index >= 0:
			if dist > VIEW_DISTANCE + VIEW_MARGIN:  # 迟滞：进来 28m 内、出去 34m 外才切换
				_hide_visual(batch, f)
				dirty[batch] = true
		elif dist <= VIEW_DISTANCE:
			_show_visual(batch, f)
			dirty[batch] = true
	for batch_key in dirty.keys():
		_sync_batch(batch_key as Batch)


func _camera() -> Camera3D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()


# ================= MultiMesh 池构建 =================
func _build_batches() -> void:
	for slug_value in plant_slugs:
		var slug: String = str(slug_value)
		if slug.is_empty() or _batches.has(slug):
			continue
		var protos: Array = _get_protos(slug)
		if protos.is_empty():
			continue  # 模板缺失：该 slug 不渲染，判定玩法不受影响
		var batch := Batch.new()
		batch.slug = slug
		batch.pad = _proto_pad(protos)
		for proto_value in protos:
			var proto: Proto = proto_value as Proto
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = false
			mm.use_custom_data = false
			mm.mesh = proto.mesh
			mm.instance_count = plant_count  # 容量固定 = 最大植物数，运行期永不重分配
			mm.visible_instance_count = 0
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "PlantBatch_%s_%d" % [slug, batch.mmis.size()]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# 节点级可见距离作为兜底（逐株剔除由 _update_visibility 负责：
			# Godot 的 visibility_range 按"实例 AABB 中心"判定，整张地图一个 AABB 无法逐株生效）。
			# 因为 custom_aabb 只覆盖当前可见实例，其中心必在 28m 附近，兜底阈值不会抢先误剔。
			mmi.visibility_range_end = VIEW_DISTANCE
			mmi.visibility_range_end_margin = VIEW_MARGIN
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mmi.custom_aabb = AABB(Vector3(-0.01, -0.01, -0.01), Vector3(0.02, 0.02, 0.02))
			add_child(mmi)
			batch.mmis.append(mmi)
			batch.protos.append(proto)
		_batches[slug] = batch


## 单株视觉包围半径：各模板子网格经模板变换后的 AABB 对角线一半 × 缩放（取最大值）
func _proto_pad(protos: Array) -> float:
	var half: float = 0.0
	for proto_value in protos:
		var proto: Proto = proto_value as Proto
		if proto.mesh == null:
			continue
		var box: AABB = _transformed_aabb(proto.mesh.get_aabb(), proto.xf)
		half = maxf(half, box.size.length() * 0.5 * Foliage.VISUAL_SCALE)
	return maxf(half, 0.5)


## 取模板（首次调用时 load + instantiate 并快照成 Proto；之后零加载开销）
static func _get_protos(slug: String) -> Array:
	if _proto_cache.has(slug):
		return _proto_cache[slug] as Array
	var protos: Array = []
	var path: String = MODEL_PATH % [slug, slug]
	if ResourceLoader.exists(path):
		var scn := load(path) as PackedScene
		if scn != null:
			var root: Node = scn.instantiate()
			if root != null:
				# 只快照 网格 + 相对根的变换，随后整体释放模板节点（Mesh 资源由引用保持存活）
				_collect_protos(root, Transform3D.IDENTITY, protos)
				root.free()
	_proto_cache[slug] = protos
	return protos


## 递归收集可渲染网格，把父链变换累积进各自的相对变换
static func _collect_protos(node: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var proto := Proto.new()
			proto.mesh = mi.mesh
			proto.xf = xf
			out.append(proto)
	for child in node.get_children():
		_collect_protos(child, xf, out)


## 把 mesh 的局部 AABB 经变换后求轴对齐包围盒（8 角点，兼容旋转/缩放）
static func _transformed_aabb(local_box: AABB, xf: Transform3D) -> AABB:
	var p: Vector3 = local_box.position
	var s: Vector3 = local_box.size
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


## 随机位置：有地形时按地形高度取 xz 并避水，否则回退到旧的圆内随机
func _random_position() -> Vector3:
	if terrain != null:
		var half := terrain.half_extent - 6.0
		for attempt in 30:
			var x: float = randf_range(-half, half)
			var z: float = randf_range(-half, half)
			if terrain.is_under_water(x, z):
				continue
			return Vector3(x, terrain.get_height(x, z), z)
		return Vector3(0.0, 0.0, 0.0)
	var angle: float = randf() * TAU
	var dist: float = randf() * 130.0
	return Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
