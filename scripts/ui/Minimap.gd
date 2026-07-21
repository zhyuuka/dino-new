extends Control
## 小地图（北朝上，玩家居中）：水源(蓝)/资源点(黄)/草食(绿)/肉食(红)/霸主(大红)
## 纯绘制，不拦截触摸；通过 group 查询世界对象位置。

const MAP_SCALE: float = 135.0   # 与 Main.MAP_RADIUS 对应

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var player: Node3D = _player()
	if player == null:
		return
	var r: float = size.x * 0.5
	var sc: float = r / MAP_SCALE
	var c := Vector2(r, r)
	draw_circle(c, r, Color(0.0, 0.0, 0.0, 0.4))
	draw_arc(c, r, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.25), 2.0)
	for w in get_tree().get_nodes_in_group("water"):
		_plot(w, player, sc, c, Color(0.25, 0.55, 1.0), 4.0)
	for rp in get_tree().get_nodes_in_group("resource"):
		_plot(rp, player, sc, c, Color(1.0, 0.85, 0.2), 3.0)
	for n in get_tree().get_nodes_in_group("ai"):
		var col := Color(0.6, 0.85, 0.4)
		var rad := 3.0
		if n.species.diet == DinoSpecies.Diet.CARNIVORE:
			col = Color(0.95, 0.25, 0.2)
		if n.species.id == "trex":
			col = Color(1.0, 0.1, 0.1)
			rad = 5.0
		_plot(n, player, sc, c, col, rad)
	draw_circle(c, 4.0, Color(1.0, 1.0, 1.0, 1.0))
	draw_circle(c, 2.0, Color(0.2, 0.8, 1.0, 1.0))


func _plot(node: Node3D, player: Node3D, sc: float, c: Vector2, col: Color, rad: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var dx: float = node.global_position.x - player.global_position.x
	var dz: float = node.global_position.z - player.global_position.z
	var p := c + Vector2(dx, dz) * sc
	if (p - c).length() > size.x * 0.5:
		return
	draw_circle(p, rad, col)


func _player() -> Node3D:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		return null
	return arr[0] as Node3D
