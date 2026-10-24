extends Node
## 帧预算监控（autoload "FrameProfiler"）：采集最近 300 帧的关键性能指标，
## 每 60 帧计算 p50/p95，供 DebugOverlay 显示与画质建议。
## 只在 debug build 采集：release 下 _ready 即 set_process(false)，零每帧开销。
## 只做"建议"，绝不自动改渲染设置（避免玩家体验突变）。

## 单帧预算（毫秒）：60 FPS 对应 16.6ms
const BUDGET_MS: float = 16.6
## 环形缓冲帧数
const BUFFER_SIZE: int = 300
## 每隔多少帧重算一次分位数
const STATS_INTERVAL: int = 60
## 参与 p50/p95 统计的指标（其余指标只展示当前值）
const STATS_KEYS: Array[String] = [
	"process_ms", "physics_ms", "frame_ms", "fps", "draw_calls",
]

## release 下为 false：不分配缓冲、不注册 _process
var _enabled: bool = false
## 预分配的 300 个样本字典（原地复用，避免每帧分配）
var _samples: Array[Dictionary] = []
## 下一个写入位置
var _write_index: int = 0
## 已填充样本数（上限 BUFFER_SIZE）
var _filled: int = 0
## 距上次统计的帧数
var _frame_counter: int = 0
var _p50: Dictionary = {}
var _p95: Dictionary = {}


func _ready() -> void:
	_enabled = OS.is_debug_build()
	if not _enabled:
		set_process(false)
		return
	for i in BUFFER_SIZE:
		_samples.append({
			"process_ms": 0.0,
			"physics_ms": 0.0,
			"frame_ms": 0.0,
			"fps": 0.0,
			"draw_calls": 0.0,
			"primitives": 0.0,
			"nodes": 0.0,
			"vram_mb": 0.0,
		})


func _process(_delta: float) -> void:
	if not _enabled:
		return
	# TIME_PROCESS / TIME_PHYSICS_PROCESS 单位是秒，统一换成毫秒
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var vram_bytes: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	# 环形缓冲：预分配字典原地写入，不产生每帧新对象
	var sample: Dictionary = _samples[_write_index]
	sample["process_ms"] = process_ms
	sample["physics_ms"] = physics_ms
	sample["frame_ms"] = process_ms + physics_ms
	sample["fps"] = Performance.get_monitor(Performance.TIME_FPS)
	sample["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	sample["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	sample["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	sample["vram_mb"] = vram_bytes / (1024.0 * 1024.0)

	_write_index = (_write_index + 1) % BUFFER_SIZE
	_filled = mini(_filled + 1, BUFFER_SIZE)
	_frame_counter += 1
	if _frame_counter >= STATS_INTERVAL:
		_frame_counter = 0
		_compute_stats()


## 供 UI 读取的只读快照：当前值 + p50/p95 + 建议画质
func get_snapshot() -> Dictionary:
	if not _enabled or _filled == 0:
		return {
			"enabled": false,
			"sample_count": 0,
			"fps": 0.0,
			"process_ms": 0.0,
			"physics_ms": 0.0,
			"frame_ms": 0.0,
			"draw_calls": 0,
			"primitives": 0,
			"nodes": 0,
			"vram_mb": 0.0,
			"p50": {},
			"p95": {},
			"suggest": 0,
			"budget_ms": BUDGET_MS,
		}
	# 最近一帧即写入位置的前一格（环形）
	var last: Dictionary = _samples[(_write_index - 1 + BUFFER_SIZE) % BUFFER_SIZE]
	return {
		"enabled": true,
		"sample_count": _filled,
		"fps": float(last["fps"]),
		"process_ms": float(last["process_ms"]),
		"physics_ms": float(last["physics_ms"]),
		"frame_ms": float(last["frame_ms"]),
		"draw_calls": int(last["draw_calls"]),
		"primitives": int(last["primitives"]),
		"nodes": int(last["nodes"]),
		"vram_mb": float(last["vram_mb"]),
		"p50": _p50.duplicate(),
		"p95": _p95.duplicate(),
		"suggest": suggest_quality(),
		"budget_ms": BUDGET_MS,
	}


## 按 p95 单帧 CPU 耗时给出画质建议：0=高 1=中 2=低。
## 仅返回建议值，调用方（UI）展示即可；本函数不修改任何渲染设置。
func suggest_quality() -> int:
	if not _enabled or _p95.is_empty():
		return 0
	var frame_p95: float = float(_p95.get("frame_ms", 0.0))
	if frame_p95 <= BUDGET_MS * 0.9:
		return 0
	if frame_p95 <= BUDGET_MS * 1.25:
		return 1
	return 2


## 重算 p50/p95：只统计已填充的样本（环形未满时按 0.._filled-1）
func _compute_stats() -> void:
	for key in STATS_KEYS:
		var values := PackedFloat32Array()
		values.resize(_filled)
		for i in _filled:
			values[i] = float(_samples[i][key])
		values.sort()
		_p50[key] = _percentile(values, 0.50)
		_p95[key] = _percentile(values, 0.95)


## 最近秩分位数（输入必须已升序排序）
func _percentile(sorted_values: PackedFloat32Array, p: float) -> float:
	var n: int = sorted_values.size()
	if n == 0:
		return 0.0
	var idx: int = int(round(float(n - 1) * p))
	return sorted_values[clampi(idx, 0, n - 1)]
