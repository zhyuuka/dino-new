# T8 — 昼夜循环 + 大气光照

## 目标
加入约 120 秒一轮的昼夜循环，动态改变太阳光强/颜色与天空/环境光，显著提升沉浸感与"有趣度"。

## 方案（scripts/game/Main.gd）
- `@onready var sun_light: DirectionalLight3D = $DirectionalLight3D`
- `@onready var world_env: WorldEnvironment = $WorldEnvironment`
- `var day_t: float = 0.3`；`const DAY_LENGTH: float = 120.0`
- `_process` 内：`day_t = fmod(day_t + delta / DAY_LENGTH, 1.0)`；调用 `_apply_day_night()`。
- `_apply_day_night()`：
  - `h = sin(day_t*TAU)`（-1 午夜 .. 1 正午）；`day = clamp(h,0,1)`；`twilight` 为近地平线辉光。
  - 太阳光强 `lerp(0.15, 1.25, day)`；光色在 夜蓝/白天白/黄昏橙 间插值。
  - 天空（ProceduralSkyMaterial）top/horizon 颜色与 `ambient_light_energy` 随 day 插值；黄昏加橙。
  - 全程空值保护（world_env / sky / sky_material）。

## 效果预期
- 世界随时间从白昼→黄昏→夜晚→黎明循环，光照与天色自然变化。
- 不旋转光源（避免阴影/性能问题），仅调色与光强。
- headless 运行零报错；类型访问均有保护。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误 / 无效类型访问。
- 代码审查：sky_material 为 ProceduralSkyMaterial 时修改其颜色；无每帧分配大对象。
