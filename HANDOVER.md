# AI 接手开发文档

> **你只需要读这份文档。读完即可从断点继续开发。其他所有 md 已被删除。**

## 一、这是什么项目

**3D 恐龙生存游戏（Android APK）**，参考《诅咒之岛》。玩家是一条恐龙，出生后捕食/觅食、成长进化、躲开更大的恐龙。终局目标：活下来、变强。

- **引擎**：Godot 4.4.1 stable，GDScript（强类型）
- **Godot 可执行文件**：`/workspace/tools/godot`
- **项目目录**：`/workspace/dino-world`
- **目标平台**：Android（arm64-v8a），横屏锁定（`project.godot` 已设 `window/handheld/orientation=1`）
- **仓库**：GitHub 公开仓库 `https://github.com/zhyuuka/dino-new`（本地 remote 名 `private`，token 已从 remote URL 清除，push 时需重新嵌入或走 gh 凭证）

## 二、当前已完成的功能

| 模块 | 状态 |
|------|------|
| 玩家恐龙（移动/跳跃/咬/喝水/触屏控制） | ✅ 完整 |
| 6 个 CC0 恐龙模型（raptor/trike/trex/anky/carno/galli）+ 统一 DinoVisual 加载器 | ✅ |
| AI 恐龙（食物链生态/状态机/威压机制/传说霸王龙 Boss 重生） | ✅ |
| 生存系统（饥饿/口渴/体力/5 段成长进化）+ 数值平衡 | ✅ |
| HUD（血/饿/渴/力条/成长/物种/计分/小地图/引导面板/死亡屏） | ✅ |
| 资源点（巢穴回血体力 + 矿物盐临时 buff） | ✅ |
| 触屏操控（虚拟摇杆 + 右半屏转视角 + 咬/跳/技能/喝水按钮） | ✅ |
| 三种相机模式（第一人称/越肩/第三人称）+ 切换按钮 + 提示 | ✅ |
| 8 个程序化音效（咬/受伤/吃/喝/进化/死亡/UI/环境风声） | ✅ |
| 120s 昼夜循环（太阳光/天空色/环境光动态变化） | ✅ |
| 存档（保留成长+代际，死亡续关） | ✅ |
| 开始游戏引导面板（"开始狩猎"按钮可正常关闭） | ✅ |
| APK 已导出存档（29.7MB，arm64-v8a，已签名） | ✅ |

---

## 三、当前在做什么——地图/地形重构（未完成）

上一轮重构的目标：
1. ✅ 下载了 **19 个 Poly Haven CC0 免费自然模型**（松树/枯树/阔叶树/岩石/蕨类/草丛），放在 `assets/models/nature/<slug>/`（.gltf + .jpg 纹理，共 58MB）。
2. ✅ 下载了 **1 张 CC0 高度图** `assets/terrain/heightmap_community.png`（1024×1024 灰度 PNG，来自 3DTexel 社区库）。
3. ✅ 写了 `scripts/data/Maps.gd`（定义 4 个地图预设：森林谷地/高山雪岭/荒原丘陵/峡谷群峰，含地形参数 + 散布密度 + 天空/雾色调）。
4. ✅ 写了 `scripts/world/TerrainGenerator.gd`（用 FastNoiseLite 分形噪声或高度图生成地形网格 + 顶点着色 + 三角碰撞 + get_height 查询）。
5. ✅ 写了 `scripts/world/NatureProp.gd`（按 slug 加载 gltf 3D 模型为静态自然物，带缩放/偏航旋转）。
6. ✅ 改写了 `scenes/Main.tscn`：移除了旧的 CSG 地面（Floor/DryPatch），围墙挪到 ±132 位置并加高到 30。
7. ❌ **Main.gd 尚未接线**：旧代码仍然用 CSG `_make_tree`/`_make_rock`，不调用 `TerrainGenerator`，所有物件仍按 y=0 放置（但地面已被移除 → 当前场景运行会掉穿）。
8. ❌ **Foliage.tscn/FoliageSpawner.gd 未更新**：植物仍是 CSG 球体，不是下载的自然模型。
9. ❌ **地图选择界面（MapSelect）未创建**。
10. ❌ **SaveManager 未加 map_id**。
11. ❌ **天空/雾未接地图预设**。

**当前 WIP commit**：`742a65b`。

---

## 四、你需要完成的（按顺序，每步做完验证一次）

### 第 1 步：运行编辑器导入，让 Godot 识别 19 个新模型

```bash
cd /workspace/dino-world
timeout 90 /workspace/tools/godot --headless --editor --quit 2>&1 | tail -10
```
这会把所有 `.gltf`/`.jpg` 导入为 Godot 资源，生成 `.import` 缓存文件。确认无 `SCRIPT ERROR`。忽略 `is_inside_tree` 警告（Godot 4 headless 良性通病）和 `resources still in use at exit`（退出时资源清理提示）。

### 第 2 步：创建 `scenes/MapSelect.tscn` + `scripts/ui/MapSelect.gd`

地图选择界面。**结构类似于现有的 SpeciesSelect（`scenes/SpeciesSelect.tscn` 和 `scripts/ui/SpeciesSelect.gd`）**，但展示的是 4 个地图选项。

**MapSelect.gd 逻辑**：
- `extends CanvasLayer`
- `signal selected(map_id: String)`
- `_ready`：遍历 `Maps.all()`（来自 `Maps.gd`），为每个地图创建一个 `Button` 子节点，按钮 `text = def.name`，点击时 `selected.emit(def.id)`。
- 按钮按上下排列，铺在 `ColorRect` 背景上。
- 设 `mouse_filter = Control.MOUSE_FILTER_IGNORE` 于根 `Control`，由按钮自身捕获。
- 布局建议：全屏半透明深色背景 + 中央标题"选择地图" + 4 个垂直排列的按钮（每个宽 400 / 高 80 / 间距 20）。每个按钮文本两行：第一行地图名（20px 粗体），第二行简介（14px 灰色）。

**MapSelect.tscn 结构**（建议手写 .tscn，或按 SpeciesSelect.tscn 模板改）：
```
CanvasLayer (script=MapSelect)
 └ Control (anchors_preset=15, mouse_filter=0)
    └ ColorRect 背景 (anchors_preset=15, color=Color(0.07,0.09,0.12,0.92))
    └ Label "选择地图" (anchors_preset=8, offset_left=-300, offset_top=20, offset_right=300, offset_bottom=60)
    （按钮由脚本动态创建）
```

### 第 3 步：更新 `scripts/data/SaveManager.gd` 加 `map_id`

在 `load_save` 返回的字典里，默认增加 `map_id = "forest"`：
```gdscript
# 读档时补充默认值
if not d.has("map_id"):
    d["map_id"] = "forest"
```

在 `write_save` 不用改（字典直接写）。

在 `_start_game` 里 `SaveManager.write_save(d)` 时确保 `d["map_id"]` 被写入。

### 第 4 步：改 `scripts/game/Main.gd`（核心重构，最多改动）

这是最主要的工作量。以下是所有需要改的地方：

#### 4.1 增加变量与常量
在 `extends Node3D` 后、const 区域前添加：

```gdscript
# 地形生成器（替代旧的 CSG 地板）
var terrain: TerrainGenerator
var _map_def: Maps.MapDef
```

修改 `MAP_RADIUS` 和 `WATER_POINTS`：删除旧的 `const MAP_RADIUS = 135.0` 和 `const WATER_POINTS`（这些现在由地毯预设 `_map_def` 提供）。**Maps.gd 的每个 MapDef 有 `water_points`、`water_level`、`max_height` 等，TerrainGenerator.half_extent 用于边界夹取。**

用 terraind 动态值替代：
- `MAP_RADIUS` → `terrain.half_extent - 6.0`（仅在有 terrain 时使用）
- `WATER_POINTS` → `_map_def.water_points`
- `LAKE_RADIUS` → 保留，或按 def 改。

**建议**：把 `MAP_RADIUS` 改成 `func _map_radius() -> float: return terrain.half_extent - 6.0 if terrain else 135.0`。所有引用 `MAP_RADIUS` 的地方换成 `_map_radius()`。

#### 4.2 删除 CSG 装饰相关
删除整个：
- `func _make_tree(pos)`
- `func _make_rock(pos)`
- `func _spawn_decor()`
- `var mat_trunk / mat_foliage / mat_rock`（在 `_ready` 中的初始化也删掉）
- `func _too_close_to_water`
- `func _random_ground_pos`

#### 4.3 新增 `func _spawn_terrain(def: Maps.MapDef)`
在 `_start_game` 最前面调用，生成地形并存入 `terrain` 变量：

```gdscript
func _spawn_terrain(def: Maps.MapDef) -> void:
    terrain = TerrainGenerator.new()
    terrain.setup(def)
    terrain.name = "Terrain"
    dynamic.add_child(terrain)
    # 应用地图的天空/雾/环境光基调
    _apply_map_atmosphere(def)
```

`_apply_map_atmosphere(def)` 用 `def` 中的 `sky_top/horizon/ambient/fog_color/density/sun_color` 去设 `world_env.environment` 的雾和天空。由于 `_apply_day_night` 每帧覆写天空色，需要在 `_apply_day_night` 中引入 `_def` 作为日间基色（见下）。

#### 4.4 新增 `func _spawn_nature()`
取代旧的 `_spawn_decor`。根据 `_map_def` 的 `tree_models/tree_count/rock_models/rock_count` 在地形上随机撒自然模型：

```gdscript
func _spawn_nature() -> void:
    var half := terrain.half_extent - 8.0
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    # 树木
    for i in _map_def.tree_count:
        var x: float = rng.randf_range(-half, half)
        var z: float = rng.randf_range(-half, half)
        if terrain.is_under_water(x, z):
            continue
        var slug: String = _map_def.tree_models[rng.randi() % _map_def.tree_models.size()]
        var s: float = rng.randf_range(0.8, 1.3)
        var p := NatureProp.create(slug, s, 0.0)
        p.global_position = Vector3(x, terrain.get_height(x, z), z)
        dynamic.add_child(p)
    # 岩石（同上，用 rock_models/rock_count；缩放 0.6~1.8）
    # 略——参照上面写，改 slug 源和 scale 范围
```

#### 4.5 改 `_spawn_water()`
水源的 y 从 `_map_def.water_level` 取；水源位置从 `_map_def.water_points` 取。**保留 LAKE_RADIUS 和半径数组，用于 WaterSource.radius。** 地形已经下挖了盆地。

```gdscript
func _spawn_water() -> void:
    var radii := [18.0, 12.0, 10.0]
    for i in _map_def.water_points.size():
        var wp := _map_def.water_points[i]
        var w := WaterScene.instantiate() as WaterSource
        w.global_position = Vector3(wp.x, _map_def.water_level, wp.z)
        w.radius = radii[i] if i < radii.size() else 10.0
        dynamic.add_child(w)
```

#### 4.6 改 `_spawn_player`
y 从地形高度取：

```gdscript
player.global_position = Vector3(PLAYER_SPAWN.x, terrain.get_height(PLAYER_SPAWN.x, PLAYER_SPAWN.z) + 0.2, PLAYER_SPAWN.z)
```
同时设 `player.map_radius = terrain.half_extent - 6.0`。

#### 4.7 改 `_spawn_ai`
y 从地形取（代替原来的 `Vector3(pos.x, 1.5, pos.z)`）：

```gdscript
ai.global_position = Vector3(pos.x, terrain.get_height(pos.x, pos.z) + 0.2, pos.z)
```
`ai.map_radius` 也跟地形走。

#### 4.8 改 `_spawn_boss`
同 AI：boss 出生点的 y 取 `terrain.get_height`。

#### 4.9 改 `_spawn_resource_points`
巢穴/矿物盐的 y 取 `terrain.get_height`，避开水（`is_under_water`）。

#### 4.10 改 `_random_ground_pos`（如果保留）
给 y 加地形高度即可（部分调用处如重刷 AI 需要）。

#### 4.11 改 `_spawn_foliage()`
需要把 `terrain` 引用传给 `FoliageSpawner`：
```gdscript
var fs := FoliageSpawnerScene.instantiate() as FoliageSpawner
fs.terrain = terrain
dynamic.add_child(fs)
```
（FoliageSpawner 需加 `var terrain: TerrainGenerator`，见第 5 步。）

#### 4.12 改 `_apply_day_night` 融合地图基调
当前 `_apply_day_night` 用硬编码 `Color(0.35,0.6,0.85)` 等做天空色。改为用 `_map_def` 里的 `sky_top/sky_horizon/ambient/fog_color/sun_color` 作为日间基色：

```gdscript
# 在 _apply_day_night 中，把原有的 day_col/night_col 替换为从 _map_def 取的值：
var day_top := _map_def.sky_top
var day_horizon := _map_def.sky_horizon
# sky_top = night.lerp(day_top, day); sky_horizon = night.lerp(day_horizon, day)
# sun_color = _map_def.sun_color.lerp(night_col, 1.0-day)

# 雾：在 _ready 中设 env.fog_enabled=true, env.fog_mode=1 (depth), env.fog_density=_map_def.fog_density
# fog_color = _map_def.fog_color 与 day 稍作混合
```

但 `_apply_day_night` 在 `_process` 每帧跑，而 `_map_def` 在 `_start_game` 才赋值。需要在 `_start_game` 中把 `_map_def` 存到实例变量 `_map_def`。然后在 `_apply_day_night` 中判 `if _map_def != null`。

#### 4.13 改地图选择流程
`Main.gd` 的 `_ready` 中 `if not skip_select:` → 先调 `_show_map_select()`。

```gdscript
func _show_map_select() -> void:
    var ms := MapSelectScene.instantiate()
    dynamic.add_child(ms)
    ms.selected.connect(_on_map_selected)

func _on_map_selected(map_id: String) -> void:
    _map_def = Maps.by_id(map_id)
    _show_species_select()
```

需要在 Main.gd 顶部加 `const MapSelectScene := preload("res://scenes/MapSelect.tscn")`。

`_continue_game` 中：从存档读 `map_id`（默认 "forest"），设 `_map_def`，再 `_start_game(...)`。

`_start_game` 签名改为接受 `map_def` 或用成员变量 `_map_def`。建议：
- `_start_game(species_id, is_continue)` → 不改签名，统一用 `self._map_def`（在 `_on_map_selected` 和 `_continue_game` 中已赋值）。

#### 4.14 改 `_clamp_to_map`
PlayerDino 里的 `_clamp_to_map` 当前用 `map_radius` 对 xz 做 clamp。在 `_spawn_player` 中设 `player.map_radius = terrain.half_extent - 6.0` 即可，不扰代码。

---

### 第 5 步：改 `scripts/world/FoliageSpawner.gd` + `scenes/Foliage.tscn`

#### FoliageSpawner.gd
- 加 `var terrain: TerrainGenerator`。
- `_random_position()` 当前返回 `Vector3(sin(angle)*dist, 0, cos(angle)*dist)`。改为：从 `terrain.half_extent` 随机取 x,z，`y = terrain.get_height(x, z)`；避水（`terrain.is_under_water`）。
- `_spawn_foliage(pos)` 中 `f.global_position = pos` 不变。
- 删除 `const SPAWN_RADIUS`，改用 `terrain.half_extent - 6.0`。
- 用 `_map_def.plant_models` 和 `_map_def.plant_count` 来决定种什么植物模型。**把 plant_models 传给 FoliageSpawner**（`var plant_slugs: Array = []`）。

#### Foliage.tscn
替换 CSG 球体为自然模型：
- 删除 `[node name="Bush" type="CSGSphere3D"]` 节点。
- 改为脚本自身在 `_ready` 加载一个随机植物 gltf（从 `plant_slugs` 数组抽），用 `NatureProp.create` 或直接加载 gltf。
- 或者在 Foliage.gd 中加载 `assets/models/nature/<slug>/<slug>_1k.gltf` 作为视觉。**推荐**：Foliage.gd 加 `var visual_slug: String = ""`，`_ready` 中实例化 gltf。

**Foliage.gd 改动**：
```gdscript
var visual_slug: String = ""
func _ready() -> void:
    add_to_group("plant")
    if visual_slug != "":
        var path := "res://assets/models/nature/%s/%s_1k.gltf" % [visual_slug, visual_slug]
        if ResourceLoader.exists(path):
            var scn := load(path) as PackedScene
            if scn != null:
                var inst := scn.instantiate()
                inst.scale = Vector3(0.6, 0.6, 0.6)
                inst.rotation = Vector3(0, randf()*TAU, 0)
                add_child(inst)
    if plant_area != null:
        plant_area.body_entered.connect(_on_body_entered)
```

FoliageSpawner 在 `_spawn_foliage` 时：
```gdscript
func _spawn_foliage(pos: Vector3) -> void:
    var f: Foliage = FoliageScene.instantiate() as Foliage
    f.visual_slug = plant_slugs[randi() % plant_slugs.size()]
    add_child(f)
    f.global_position = pos
    f.eaten.connect(_on_foliage_eaten)
    foliage.append(f)
```

`FoliageSpawner` 也需要知道 `_map_def.plant_count`（设 `var plant_count: int = 30`），在 `_ready` 中用 `plant_count` 取代硬编码的 `FOLIAGE_COUNT`。

### 第 6 步：Headless 验证

每做完一步都跑一次：
```bash
cd /workspace/dino-world
timeout 60 /workspace/tools/godot --headless --quit-after 16 2>&1 | grep -iE "SCRIPT ERROR|parse error|compile error|Can't find type|Could not find|Animation not found|Invalid get|Null instance" | grep -viE "is_inside_tree"
```
**如果无输出 = 通过。** 注意：凡新增了 `class_name` 的脚本（如 MapSelect），必须在验证前重建类缓存：
```bash
rm -f .godot/global_script_class_cache.cfg
/workspace/tools/godot --headless --editor --quit
```
然后再跑验证。

### 第 7 步：导出 APK

```bash
cd /workspace/dino-world
export ANDROID_HOME=/workspace/tools/android-sdk ANDROID_SDK_ROOT=/workspace/tools/android-sdk
timeout 540 /workspace/tools/godot --headless --export-debug "Android Debug" build/dino-world-debug.apk 2>&1 | tail -15
```
确认输出中看到 `Signed`。然后验证：
```bash
ls -lh build/dino-world-debug.apk
/workspace/tools/android-sdk/build-tools/34.0.0/apksigner verify build/dino-world-debug.apk
```
预期 APK 体积 **远大于 29.7MB**（因为新增了 58MB 自然模型纹理，即使用 ASTC 压缩也会有明显膨胀）。

### 第 8 步：Git 提交并推送

```bash
cd /workspace/dino-world
git add -A
git commit -m "B阶段: 完成地形/多地图/自然模型散布全流程 + APK 导出"
# 推送需要 token（嵌入 URL 再清掉）
git remote set-url private "https://ghp_你的TOKEN@github.com/zhyuuka/dino-new.git"
git push private main
git remote set-url private "https://github.com/zhyuuka/dino-new.git"
```

---

## 五、文件清单（当前仓库中有什么）

```
/workspace/dino-world/
├── HANDOVER.md                      # ← 你就读这一份
├── project.godot                    # Godot 配置（横屏/渲染/输入映射，勿改）
├── export_presets.cfg               # Android 导出预设（勿改）
├── .gitignore                       # 排除 .godot/、tools/、.idsig、keystore
├── scenes/
│   ├── Main.tscn                    # 主场景（CSG 地面已移除，围墙已挪到 ±132 × 高 30）
│   ├── PlayerDino.tscn              # 玩家恐龙
│   ├── AIDino.tscn                  # AI 恐龙
│   ├── AICorpse.tscn                # 尸体
│   ├── SpeciesSelect.tscn           # 选物种界面（参考它写 MapSelect）
│   ├── HUD.tscn                     # HUD（含小地图/引导面板）
│   ├── TouchControls.tscn           # 触屏（含 LookZone/视角按钮）
│   ├── WaterSource.tscn             # 水源（CSGBox3D 水面，脚本文本不变）
│   ├── ResourcePoint.tscn           # 巢穴/矿物盐
│   ├── Foliage.tscn                 # 可食植物（需改为自然模型）
│   └── FoliageSpawner.tscn          # 植物生成器
├── scripts/
│   ├── game/Main.gd                 # ★ 核心需要改的文件
│   ├── player/PlayerDino.gd         # 玩家（移动/进食/进化/相机三模式）
│   ├── ai/
│   │   ├── AIDino.gd                # AI 恐龙（食物链/威压）
│   │   ├── StateController.gd       # 状态机
│   │   └── AICorpse.gd              # 尸体（MAX_BITES=4, LIFETIME=35s）
│   ├── data/
│   │   ├── DinoSpecies.gd           # 物种数据库（6 种，属性/食性/技能/成长倍率）
│   │   ├── SaveManager.gd           # 存档（需加 map_id）
│   │   └── Maps.gd                  # ★ 地图预设（4 张：森林/雪岭/荒原/峡谷）
│   ├── world/
│   │   ├── TerrainGenerator.gd      # ★ 地形生成（噪声/高度图 + 顶点着色 + 碰撞 + get_height）
│   │   ├── NatureProp.gd            # ★ 自然物工厂（加载 gltf，随机缩放/偏航）
│   │   ├── DinoVisual.gd            # 恐龙 GLB 加载+动画
│   │   ├── WaterSource.gd           # 水源
│   │   ├── ResourcePoint.gd         # 资源点
│   │   ├── Foliage.gd               # 可食植物（需改为自然模型）
│   │   └── FoliageSpawner.gd        # 植物生成器（需连 terrain）
│   └── ui/
���       ├── HUD.gd                   # HUD
│       ├── Minimap.gd               # 小地图
│       ├── TouchControls.gd         # 触屏
│       ├── LookControl.gd           # 右半屏视角拖动
│       ├── VirtualJoystick.gd       # 虚拟摇杆
│       └── SpeciesSelect.gd         # 选物种（参考）
├── assets/
│   ├── models/                      # 6 个 CC0 恐龙 GLB（raptor/trike/trex/anky/carno/galli）
│   ├── models/nature/               # ★ 19 个 Poly Haven 自然模型（gltf+jpg，共 58MB）
│   ├── terrain/heightmap_community.png  # ★ CC0 高度图（1024×1024 灰度）
│   ├── audio/                       # 8 个程序化合成 WAV
│   └── icons/icon.svg               # 应用图标
├── build/
│   └── dino-world-debug.apk         # 最终 APK（导出后更新）
├── plans/13_round2.md               # 本轮需求与计划概要（可选读）
└── tools/
    ├── download_polyhaven.py         # Poly Haven 模型下载器（已完成使命）
    └── gen_audio.py                  # 音频合成器（已完成使命）
```

---

## 六、关键环境信息

### Godot
- 二进制：`/workspace/tools/godot`
- 版本：4.4.1 stable
- 导出模板：`/root/.local/share/godot/export_templates/4.4.1.stable/`

### Android
- SDK：`/workspace/tools/android-sdk`（build-tools 34.0.0 + platform android-34）
- Keystore：`/root/.android/debug.keystore`（alias=androiddebugkey, pass=android）
- 导出预设：`build/dino-world-debug.apk`，arm64-v8a only

### Git
- 本地仓库：`/workspace/dino-world`
- 当前远程（private）：`https://github.com/zhyuuka/dino-new.git`（公开仓库，原名 dino-world-private 已改名）
- 旧远程（origin）：`https://github.com/zhyuuka/dino-world.git`
- 当前分支：`main`，最新提交 `48d766e`（HANDOVER.md）

---

## 七、已知陷阱

1. **class_name 缓存**：任何新 `.gd` 加了 `class_name` 后，必须 `rm -f .godot/global_script_class_cache.cfg && godot --headless --editor --quit` 重建缓存，否则依赖它的脚本会报 "Could not find type X in current scope"。

2. **GDScript 缩进是 tab**：编辑时确认 indented block 用的是 `\t` 制表符，不是空格。误改缩进会导致 parse error。

3. **`mouse_filter=0`（pass）让帮助按钮可点击**：已修复。TouchControls 根 Control 的 mouse_filter 从 2 改成了 0。这里面的逻辑：TouchControls（CanvasLayer）画在 HUD 之上，根 Control 全屏覆盖。若 mouse_filter=2（stop），HUD 里的"开始狩猎"按钮永远收不到点击。改成 0 后穿透。

4. **横屏已锁定**：`project.godot` 设了 `window/handheld/orientation=1`（landscape），APK manifest 也写了 screenOrientation=0x1。**不要改**。

5. **headless 16s 验证**：运行 `godot --headless --quit-after 16` 会真正 spawn 世界并跑几十帧（AI 生成/生态维护/小地图/昼夜），足以触发绝大多数运行时错误。

6. **APK 体积**：导入的 19 个自然模型在 APK 中经 ASTC 纹理压缩后体积会缩小（jpg→astc），但加上顶点数据、gltf 网格，APK 会比之前的 29.7MB 明显大很多，目标 80MB+。正常现象。

7. **新增场景引用**：新增 MapSelect.tscn 后，Main.gd 需要 `preload("res://scenes/MapSelect.tscn")` 常量。`MapSelect.gd` 如果是 `class_name MapSelect`，则 Main.gd 可以用类型标注（`var ms: MapSelect = ...`），但必须重建类缓存。

---

## 八、推荐开发节奏

```
Step 1（导入）         → 跑一次 godot --editor --quit，完成 → 验证无错
Step 2（MapSelect）    → 写 scene+script → 验证 → 小提交
Step 3（SaveManager）  → 改 map_id → 验证 → 提交
Step 4（Main.gd）      → 这是大头，可以分次提交：
  4a（删CSG装饰+引地形）→ 验证
  4b（改水/玩家/AI/资源点放置用 terrain）→ 验证
  4c（改地图选择流程 + 天空/雾融合）→ 验证
  4d（改 _spawn_nature 散布下载模型）→ 验证
Step 5（Foliage 自然化）→ 改 Foliage.gd + FoliageSpawner.gd → 验证
Step 6（最终导出）      → APK 构建 → 签名校验 → 提交 + push
```

**每做完一步都要跑 headless 16s 验证**（命令见第六节），确保零错误。遇到报错不要重试同一操作——先诊断再改。

---

## 零、其他说明

- 所有 Poly Haven 模型为 CC0（公有领域），可商用。高度图来自 3DTexel 社区库（CC0）。
- 地图选择界面不需要花哨——4 个按钮够用。
- 不要重写架构或引入新的设计模式。当前架构足够。
- 如果某一步出现 Godot 崩溃或 `ERR_FILE`，优先检查资源路径是否正确（尤其是 gltf 的 `textures/` 相对子目录在导入时是否正确 resolve——已验证过，Poly Haven 的 gltf 引用 `textures/xxx.jpg`，下载时保留了该目录结构，导入正常）。
