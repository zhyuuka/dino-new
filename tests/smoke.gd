extends SceneTree
## 标准冒烟脚本（长期资产：禁止改成用完即删的临时脚本，所有验证轮次都必须走这里）
##
## 用法：
##   godot --headless --path /workspace/dino-new -s res://tests/smoke.gd
##
## 环境变量：
##   SMOKE_SECONDS  进入世界后的观察秒数（默认 40）
##   SMOKE_MAP      地图 id（默认 forest）
##   SMOKE_SPECIES  物种 id（默认 raptor）
##
## 流程：加载 Main.tscn → 0.5s 后走完选图/选种（等价玩家点击）→ 观察指定秒数 → 输出单行 SMOKE_JSON
##
## 判定（ok）：
##   player == 1 且 pos_y 在 (-50, 200) 之间（未掉穿地形）且节点数 > 100
##
## 说明：script_errors 固定写 -1。脚本内部读不到引擎 stderr，
##       真实脚本错误数由 scripts/verify.sh 从进程完整输出统计后写入验证记录。

const MENU_SETTLE_SEC: float = 0.5
const DEFAULT_SECONDS: float = 40.0
const DEFAULT_MAP: String = "forest"
const DEFAULT_SPECIES: String = "raptor"

const NODE_MIN: int = 100
const POS_Y_MIN: float = -50.0
const POS_Y_MAX: float = 200.0


func _initialize() -> void:
	# _initialize 里启动协程：await 的续行由 SceneTree 的正常帧循环驱动
	_run()


func _run() -> void:
	var seconds: float = _env_float("SMOKE_SECONDS", DEFAULT_SECONDS)
	var map_id: String = _env_string("SMOKE_MAP", DEFAULT_MAP)
	var species_id: String = _env_string("SMOKE_SPECIES", DEFAULT_SPECIES)
	print("SMOKE_START map=%s species=%s seconds=%.1f" % [map_id, species_id, seconds])

	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if packed == null:
		_finish(seconds, null, "加载 Main.tscn 失败")
		return
	var main: Node = packed.instantiate()
	if main == null:
		_finish(seconds, null, "实例化 Main.tscn 失败")
		return
	root.add_child(main)

	# 等选图界面完成 _ready，再模拟玩家的两次点击
	await create_timer(MENU_SETTLE_SEC).timeout
	main.call("_on_map_selected", map_id)
	main.call("_on_species_selected", species_id, false)

	# 观察窗口从选种之后开始计（含加载世界的时间）
	var started_msec: int = Time.get_ticks_msec()
	await create_timer(seconds).timeout
	var elapsed: float = float(Time.get_ticks_msec() - started_msec) / 1000.0

	_finish(elapsed, main, "")


## 采样并输出单行 JSON；fatal 非空表示流程未跑起来（同样输出 JSON，ok=false）
func _finish(elapsed: float, main: Node, fatal: String) -> void:
	if not fatal.is_empty():
		print("SMOKE_FATAL: " + fatal)

	var player: Node = null
	if main != null and is_instance_valid(main):
		var value: Variant = main.get("player")
		if value != null and is_instance_valid(value):
			player = value as Node

	var pos_y: float = -9999.0
	if player != null:
		var pos_value: Variant = player.get("global_position")
		if pos_value != null:
			pos_y = (pos_value as Vector3).y

	var players: int = get_nodes_in_group(Groups.PLAYER).size()
	var ai: int = get_nodes_in_group(Groups.AI).size()
	var plants: int = get_nodes_in_group(Groups.PLANT).size()
	var eggs: int = get_nodes_in_group(Groups.EGG).size()
	var corpses: int = get_nodes_in_group(Groups.CORPSE).size()

	# 节点数与 MultiMeshInstance3D 数都按 Main 子树统计（未加载成功时退回整棵树）
	var scope: Node = main if (main != null and is_instance_valid(main)) else root
	var nodes: int = _count_nodes(scope)
	var mmi: int = _count_mmi(scope)

	var hunger: int = _int_prop(player, "current_hunger")
	var thirst: int = _int_prop(player, "current_thirst")
	var hp: int = _int_prop(player, "current_health")

	var ok: bool = (
			fatal.is_empty()
			and players == 1
			and pos_y > POS_Y_MIN and pos_y < POS_Y_MAX
			and nodes > NODE_MIN
	)

	var result: Dictionary = {
		"ok": ok,
		"seconds": snappedf(elapsed, 0.01),
		"player": players,
		"ai": ai,
		"plants": plants,
		"eggs": eggs,
		"corpses": corpses,
		"nodes": nodes,
		"hunger": hunger,
		"thirst": thirst,
		"hp": hp,
		"pos_y": snappedf(pos_y, 0.001),
		"mmi": mmi,
		# 引擎 stderr 只能在外部进程统计；此处固定 -1 由 scripts/verify.sh 覆盖
		"script_errors": -1,
	}
	print("SMOKE_JSON:" + JSON.stringify(result))
	quit(0 if ok else 1)


func _env_string(name: String, fallback: String) -> String:
	var raw: String = OS.get_environment(name).strip_edges()
	return raw if not raw.is_empty() else fallback


func _env_float(name: String, fallback: float) -> float:
	var raw: String = OS.get_environment(name).strip_edges()
	if raw.is_empty():
		return fallback
	var value: float = raw.to_float()
	return value if value > 0.0 else fallback


func _int_prop(obj: Object, prop: String) -> int:
	if obj == null:
		return 0
	var value: Variant = obj.get(prop)
	return 0 if value == null else int(value)


func _count_nodes(node: Node) -> int:
	var total: int = 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


## mmi = 子树内 MultiMeshInstance3D 数量（自然物/植物合批是否正常生成的量化指标）
func _count_mmi(node: Node) -> int:
	var total: int = 1 if node is MultiMeshInstance3D else 0
	for child in node.get_children():
		total += _count_mmi(child)
	return total
