class_name ScoreKeeper
extends RefCounted
## 计分子系统：存活时长、击杀数与 HUD 刷分节奏。
## 存档读写（含 best_time / best_kills）仍由 Main 编排器负责，此处只管运行期数值。

const SCORE_INTERVAL: float = 0.5

var survival_time: float = 0.0
var kill_count: int = 0
var score_timer: float = 0.0


## 每帧累计存活时长与刷分计时；每 SCORE_INTERVAL 秒返回一次 true 表示该刷新 HUD 分数
func tick(delta: float) -> bool:
	survival_time += delta
	score_timer += delta
	if score_timer >= SCORE_INTERVAL:
		score_timer = 0.0
		return true
	return false


## 玩家击杀 +1
func record_kill() -> void:
	kill_count += 1


## 新开一局：清空成绩（不清刷分计时，与原 _start_game 语义一致）
func reset() -> void:
	kill_count = 0
	survival_time = 0.0


## 完全重置（含刷分计时，供死亡重开 _restart_run 使用）
func reset_all() -> void:
	reset()
	score_timer = 0.0
