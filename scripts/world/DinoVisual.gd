class_name DinoVisual
extends Node3D
## 统一恐龙模型加载器：从 res://assets/models/<species_id>.glb 实例化模型，
## 自动归一化缩放、按成长放大、播放骨骼动画（若模型自带）、尸体变暗放倒。
## PlayerDino / AIDino / AICorpse 三个脚本都通过它显示模型，不再依赖 CSG 占位几何体。
##
## 模型来源（均为 CC0 免费可商用）：
##   raptor=迅猛龙 / trike=三角龙 / trex=霸王龙 / anky=剑龙（代理）/
##   carno=装甲异特龙（代理） / galli=鸵鸟（似鸡龙代理）
## 其中 raptor/trike/trex/anky 为 Quaternius 带动画模型，carno/galli 为静态模型。

const MODELS_DIR := "res://assets/models/"
const TARGET_LEN := 2.2   # 归一化参考长度（米）：current_size=1.0 时模型水平长度约 2.2

var _model: Node = null
var _anim: AnimationPlayer = null
var _meshes: Array = []
var _base_scale: float = 1.0
var _size_mult: float = 1.0
var _corpse: bool = false
var _clips: Dictionary = {}
var _bob_t: float = 0.0


func setup(species_id: String, body_color: Color, dark_color: Color, opts: Dictionary = {}) -> void:
	_corpse = opts.get("corpse", false)
	var path := MODELS_DIR + species_id + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("DinoVisual: 缺少模型 %s" % path)
		return
	var sc: PackedScene = load(path)
	if sc == null:
		return
	_model = sc.instantiate()
	_model.name = "Model"
	add_child(_model)

	_meshes = _model.find_children("*", "MeshInstance3D", true)
	var anims := _model.find_children("*", "AnimationPlayer", true)
	if anims.size() > 0 and anims[0] is AnimationPlayer:
		_anim = anims[0]
		_collect_clips()

	# 归一化缩放：依据 AABB 水平长度
	var ab := _safe_aabb(_model)
	var horiz := maxf(absf(ab.size.x), absf(ab.size.z))
	if horiz < 0.001:
		horiz = 1.0
	_base_scale = TARGET_LEN / horiz
	_apply_scale()

	# 着色
	if _corpse:
		_tint(Color(0.16, 0.14, 0.12))
		_model.rotation.x = PI * 0.5   # 放倒成尸体
	else:
		# 保留模型原生外观（各模型已有合理配色）；如需按物种染色可在此扩展
		pass


func _safe_aabb(n: Node) -> AABB:
	if n.has_method("get_aabb"):
		var a: AABB = n.get_aabb()
		if a.size.length() > 0.0001:
			return a
	var total := AABB()
	var found := false
	for c in n.get_children():
		var ca := _safe_aabb(c)
		if ca.size.length() > 0.0001:
			if not found:
				total = ca
				found = true
			else:
				total = total.merge(ca)
	if found:
		return total
	return AABB(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))


func _collect_clips() -> void:
	_clips.clear()
	for name in _anim.get_animation_list():
		var s := name.to_lower()
		if "idle" in s:
			_clips["idle"] = name
		elif "walk" in s:
			_clips["walk"] = name
		elif "run" in s:
			_clips["run"] = name
		elif "attack" in s or "bite" in s or "eat" in s:
			_clips["attack"] = name


func _tint(col: Color) -> void:
	for mi in _meshes:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.85
		(mi as MeshInstance3D).material_override = mat


func set_size(mult: float) -> void:
	_size_mult = mult
	_apply_scale()


func _apply_scale() -> void:
	scale = Vector3.ONE * _base_scale * _size_mult


## 由父节点每帧调用：moving=是否在移动，speed_ratio=当前速度/最大速度(0~1)
func play_locomotion(moving: bool, speed_ratio: float) -> void:
	if _anim != null:
		var name := "idle"
		if moving:
			name = "run" if speed_ratio > 0.6 else "walk"
		if not _clips.has(name):
			name = "idle"
		var clip: String = _clips[name]
		if _anim.current_animation != clip:
			_anim.play(clip, 0.15)
		return
	# 无骨骼动画的静态模型：不在此处处理（见 _process 的轻微呼吸）


func play_attack() -> void:
	if _anim != null and _clips.has("attack"):
		_anim.play(_clips["attack"], 0.05)
		return
	if _model != null:
		var t := create_tween()
		t.tween_property(_model, "position:z", 0.25, 0.08)
		t.tween_property(_model, "position:z", 0.0, 0.18)


## 受击时快速缩放脉冲（在 _model 上，独立于成长缩放）
func pulse_damage() -> void:
	if _model == null:
		return
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 1.12, 0.05)
	t.tween_property(_model, "scale", Vector3.ONE, 0.12)


## 玩家死亡：模型缩没
func shrink_death() -> void:
	if _model == null:
		return
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.5)


## 成长闪光（短暂自发光后恢复原生外观）
func glow() -> void:
	for mi in _meshes:
		var m := mi as MeshInstance3D
		var base = m.material_override if m.material_override != null else m.get_active_material(0)
		if base == null:
			continue
		var mat := base.duplicate() as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.2)
		mat.emission_energy_multiplier = 2.5
		m.material_override = mat
	if _corpse:
		return
	await get_tree().create_timer(1.0).timeout
	for mi in _meshes:
		(mi as MeshInstance3D).material_override = null


## 尸体淡出后回调
func fade_out(on_done: Callable) -> void:
	if _model == null or _meshes.is_empty():
		on_done.call()
		return
	for mi in _meshes:
		var m := mi as MeshInstance3D
		var base = m.material_override if m.material_override != null else m.get_active_material(0)
		if base == null:
			continue
		var mat := base.duplicate() as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.material_override = mat
	var t := create_tween()
	for mi in _meshes:
		var m := mi as MeshInstance3D
		if m.material_override is StandardMaterial3D:
			t.parallel().tween_property(m.material_override, "albedo_color:a", 0.0, 0.4)
	t.chain().tween_callback(on_done)


func _process(delta: float) -> void:
	# 仅对无骨骼动画的静态模型做轻微生命感处理
	if _anim != null or _corpse or _model == null:
		return
	_bob_t += delta
	_model.position.y = sin(_bob_t * 2.0) * 0.03
	_model.rotation.z = sin(_bob_t * 1.3) * 0.02
