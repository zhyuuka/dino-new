# T7 — 程序化音效 + 环境音

## 目标
为游戏加入合成音效（无外部依赖，纯 Python 生成 WAV），显著提升手感与"有趣度"：
玩家咬击/受击/进食/喝水/进化/死亡 有对应音；场景有循环风声环境音；按钮有点击音。

## 资源（已生成于 assets/audio/，已 import）
bite / hurt / eat / drink / evolve / death / ui / ambient(循环风声)

## 方案
### scripts/player/PlayerDino.gd
- `const SFX_*` 预载 6 个音；`var sfx: AudioStreamPlayer`（_ready 内 new 并 add_child，volume_db=-4）。
- 辅助 `_sfx(s)`：sfx 有效且 s 非空则切流播放。
- 触发点：try_bite→bite；take_damage→hurt；_eat_meal→eat；drink 起→drink（边沿检测 _was_drinking）；_add_growth_meal→evolve；_die→death。

### scripts/game/Main.gd
- `const SFX_AMBIENT`；_ready 末尾 new AudioStreamPlayer(loop, stream=ambient, volume_db=-14) 并 play()。

### scripts/ui/TouchControls.gd
- `const SFX_UI`；new AudioStreamPlayer；各按钮按下时播放 ui 点击音。

## 效果预期
- 关键事件有音反馈；环境风声增强沉浸；按钮有反馈音。
- 音量适中（不刺耳）；不影响玩法与性能。
- headless 运行零报错（AudioStreamPlayer 在 headless 下静默，不报错）；导出 APK 含音频。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误（preload 路径正确）。
- 代码审查：sfx 节点在 _ready 创建，调用前有效；死亡音在 is_dead 后仍可播（sfx 节点未被释放）。
