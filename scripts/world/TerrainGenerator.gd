class_name TerrainGenerator
extends Node3D
## 程序化/高度图地形：生成带顶点着色的高度网格 + 三角网格碰撞，并提供 get_height() 供放置万物。
## 模式 0：FastNoiseLite 分形噪声；模式 1：采样下载的灰度高度图 PNG。

const SEGMENTS: int = 128
const CELL: float = 2.0
var half_extent: float = SEGMENTS * CELL * 0.5   # 128

var _def: Maps.MapDef
var _heights: PackedFloat32Array = []


func setup(def: Maps.MapDef) -> void:
	_def = def
	_heights.resize((SEGMENTS + 1) * (SEGMENTS + 1))
	_generate_heights()
	_carve_water_basins()
	_build_mesh()
	_build_collision()


func _idx(i: int, j: int) -> int:
	return j * (SEGMENTS + 1) + i


func _get(i: int, j: int) -> float:
	return _heights[_idx(i, j)]


func _set(i: int, j: int, v: float) -> void:
	_heights[_idx(i, j)] = v


func _generate_heights() -> void:
	if _def.mode == 1 and ResourceLoader.exists("res://" + _def.heightmap_path):
		var img := Image.new()
		if img.load_from_file("res://" + _def.heightmap_path) == OK:
			var w := img.get_width(); var h := img.get_height()
			for j in SEGMENTS + 1:
				for i in SEGMENTS + 1:
					var u := float(i) / SEGMENTS
					var v := float(j) / SEGMENTS
					var px := clampi(int(u * (w - 1)), 0, w - 1)
					var py := clampi(int(v * (h - 1)), 0, h - 1)
					var hgt := img.get_pixel(px, py).r
					# 高度图偏暗，提升对比以露出峡谷
					hgt = pow(hgt, 1.4)
					_set(i, j, hgt * _def.max_height)
			return
	# 回退用噪声
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = _def.noise_freq if _def.noise_freq > 0.0 else 0.012
	n.fractal_octaves = 5
	n.fractal_lacunarity = 2.3
	n.fractal_gain = 0.45
	n.seed = _def.noise_seed
	for j in SEGMENTS + 1:
		for i in SEGMENTS + 1:
			var x := (i - SEGMENTS * 0.5) * CELL
			var z := (j - SEGMENTS * 0.5) * CELL
			var h := n.get_noise_2d(x, z) * 0.5 + 0.5   # 0..1
			h = pow(h, 1.3)
			_set(i, j, h * _def.max_height)


## 在每个水源周围下挖盆地，使湖面自然下沉
func _carve_water_basins() -> void:
	for wp in _def.water_points:
		var ci := int(wp.x / CELL + SEGMENTS * 0.5)
		var cj := int(wp.z / CELL + SEGMENTS * 0.5)
		var r := int(18.0 / CELL)
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				var i := ci + di; var j := cj + dj
				if i < 0 or i > SEGMENTS or j < 0 or j > SEGMENTS:
					continue
				var d := sqrt(di * di + dj * dj)
				if d > r:
					continue
				var t := 1.0 - d / float(r)
				var target := _def.water_level - 0.6
				var v := lerpf(_get(i, j), target, t * 0.92)
				_set(i, j, v)


func _color_for_height(y: float) -> Color:
	var t := clampf(y / _def.max_height, 0.0, 1.0)
	var grass := Color(0.26, 0.43, 0.18)
	var rock := Color(0.42, 0.37, 0.32)
	var snow := Color(0.93, 0.95, 0.98)
	var c := grass.lerp(rock, smoothstep(0.22, 0.55, t))
	c = c.lerp(snow, smoothstep(_def.snow_line, _def.snow_line + 0.12, t))
	return c


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in SEGMENTS + 1:
		for i in SEGMENTS + 1:
			var x := (i - SEGMENTS * 0.5) * CELL
			var z := (j - SEGMENTS * 0.5) * CELL
			var y := _get(i, j)
			st.set_color(_color_for_height(y))
			st.add_vertex(Vector3(x, y, z))
	for j in SEGMENTS:
		for i in SEGMENTS:
			var a := j * (SEGMENTS + 1) + i
			var b := j * (SEGMENTS + 1) + i + 1
			var c := (j + 1) * (SEGMENTS + 1) + i
			var d := (j + 1) * (SEGMENTS + 1) + i + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_colors_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = false
	mi.receive_shadow = true
	add_child(mi)
	mi.create_trimesh_collision()


## 双线性插值查询任意世界坐标的地形高度
func get_height(x: float, z: float) -> float:
	var fi := x / CELL + SEGMENTS * 0.5
	var fj := z / CELL + SEGMENTS * 0.5
	fi = clampf(fi, 0.0, float(SEGMENTS))
	fj = clampf(fj, 0.0, float(SEGMENTS))
	var i0 := int(fi); var j0 := int(fj)
	var i1 := mini(i0 + 1, SEGMENTS); var j1 := mini(j0 + 1, SEGMENTS)
	var tx := fi - i0; var tz := fj - j0
	var h0 := lerpf(_get(i0, j0), _get(i1, j0), tx)
	var h1 := lerpf(_get(i0, j1), _get(i1, j1), tx)
	return lerpf(h0, h1, tz)


## 该点是否低于水面（用于避免在水里种树）
func is_under_water(x: float, z: float) -> bool:
	return get_height(x, z) < _def.water_level + 0.4
