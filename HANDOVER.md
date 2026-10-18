# AI 接手开发文档

> **你只需要读这份文档。读完即可从断点继续开发。其他所有 md 已被删除。**

## 一、这是什么项目

**3D 恐龙生存游戏（Android APK）**，参考《诅咒之岛》。玩家是一条恐龙，出生后捕食/觅食、成长进化、躲开更大的恐龙。终局目标：活下来、变强。

- **引擎**：Godot 4.4.1 stable，GDScript（强类型）
- **Godot 可执行文件**：`/workspace/tools/godot`
- **项目目录**：`/workspace/dino-world`
- **目标平台**：Android（arm64-v8a），横屏锁定（`project.godot` 设 `window/handheld/orientation=0`；Android manifest `screenOrientation=0`=横屏）
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

4. **横屏已锁定**：`project.godot` 设了 `window/handheld/orientation=0`（= Android manifest `screenOrientation="0"` = `SCREEN_ORIENTATION_LANDSCAPE` 横屏）。**不要改**。
   ⚠️ 注意 Godot 4 把 `window/handheld/orientation` 的枚举值**原样写进** Android manifest；而 Android 的 `screenOrientation` 编号里 `0`=横屏、`1`=竖屏（与 Godot 3 的 `1`=横屏相反）。所以这里用 `0` 才是横屏——曾误写成 `1` 导致游戏被锁成竖屏、触屏 UI 因横向裁切而点不到（相机切换"没生效"即此症状）。

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

---

## 九、P0/P1 修复记录（2026-10-18）

> 终验子会话追加。

1. **植物被吃后永不重生（P0）**：`Foliage.eaten` 信号改为携带节点自身 `eaten(node: Foliage)`（emit 仍在 `queue_free` 之前），`FoliageSpawner._on_foliage_eaten` 改为 `foliage.erase(f)` + 重生计时——旧的按下标扫描逻辑在实例仍 valid 时永远匹配不上，植物被吃后无法重生。涉及 `scripts/world/Foliage.gd`、`scripts/world/FoliageSpawner.gd`。
2. **组名常量化（P1）**：新建 `scripts/core/Groups.gd`（`class_name Groups`），player/ai/corpse/plant/water/resource 六个组名全项目统一引用常量，消除裸字符串拼写风险；`.tscn` 中无组与信号连接残留。涉及 `scripts/core/Groups.gd` 及 PlayerDino/AIDino/AICorpse/Foliage/ResourcePoint/WaterSource/Minimap/Main 等引用文件。
3. **存档安全（P0/P1）**：`SaveManager` 新增 `SAVE_VERSION` 读取侧校验（`int()` 包裹，防 JSON 数字解析为浮点导致版本比较失效）、原子写（先写 `.tmp` 再 `DirAccess.rename_absolute` 覆盖，失败时清理 tmp；官方支持 `user://` 路径）、默认 `map_id` 统一走 `Maps.DEFAULT_MAP_ID`。涉及 `scripts/data/SaveManager.gd`、`scripts/data/Maps.gd`。
4. **高度图导出后静默失效（P0）**：`TerrainGenerator._generate_heights` 改用 `load() as Texture2D` 取像素（`Image.load_from_file` 在导出包内读不到未打包的原始 png，导致峡谷地图静默回退噪声地形），`is_compressed()` 短路后 `decompress()`。涉及 `scripts/world/TerrainGenerator.gd`。
5. **死亡重开移动端卡顿（P1）**：`Main._on_player_died` 由整场景 `reload_current_scene()` 改为 `_restart_run()`——仅释放并重建玩家/AI/HUD/触屏/尸体/选图选种残留等运行期节点，保留地形/水源/植被/资源点等世界资产，成长从存档续代；`_on_menu` 与 `static skip_select` 语义不变。涉及 `scripts/game/Main.gd`。
6. **AI 感知与小地图性能（P1）**：`AIDino` 的 GRAZE/DRINK 最近目标改为 0.25s 决策周期内缓存、执行层只消费缓存（消除每帧全组 O(n) 距离扫描），目标失效时优雅退回漫游等下轮决策刷新；`Minimap` 重绘降为 8Hz（delta 累积器触发后归零），`MAP_SCALE=122` 对齐 `terrain.half_extent(128)-6`。涉及 `scripts/ai/AIDino.gd`、`scripts/ui/Minimap.gd`。

**未执行事项**：
- P1 资源瘦身（APK 体积）：需要 Godot 编辑器环境做纹理压缩（ASTC）与模型精简，本次未执行。
- `HeightMapShape3D` 因 Godot 4.4 不支持自定义格距（格距固定 1 米，与 2 米格距地形对不上）而保留 trimesh 碰撞，待引擎升级后迁移。

**终验补充修复（本次交叉验证新发现）**：
- `Main._process` 计分刷新处 `hud.set_score` 增加 `hud != null` 防护——选图/选种界面期间 hud 尚未生成，原代码每 0.5 秒会刷一次 null instance 运行时错误。涉及 `scripts/game/Main.gd`。

---

## 十、P2 工程化记录（2026-10-18）

> P2 终验子会话追加。四块改动均已完成交叉终验（逐句对照原 Main.gd 529 行版本），见下方"终验修复"。

**四块改动**：

1. **Autoload 架构**：新增全局设置中心与音频总线两个 autoload 单例——GameState 负责 user://settings.json 的加载校验（逐键类型+范围，损坏/越界一律回退默认）与原子写；AudioManager 负责幂等创建 SFX/Ambient 总线（send 到 Master）并按设置应用音量（linear≤0.0001 压到 -80dB，避免 linear_to_db(0) 产生 -inf）。注册顺序 GameState 在前，AudioManager._ready 依赖此顺序读 `GameState.settings`。
   新文件：`scripts/core/GameState.gd`、`scripts/core/AudioManager.gd`；改动：`project.godot`（末尾 [autoload] 区段，`*` 单例前缀）。
2. **Main 拆分**：Main.gd 529→316 行，瘦身为纯编排器（流程/信号接线/存档），按职责拆出四个子系统——DayNightCycle（昼夜循环，day_t 跨死亡重开连续）、ScoreKeeper（计分与 0.5s 刷分节奏）、WorldBuilder（世界资产构建，纯参数化工具）、EcosystemDirector（AI 花名册/种群补员/Boss 重生，经 ai_died/boss_spawned 信号回报 Main 生成尸体与横幅）。调用时序与 reset/reset_all 使用场景（_start_game 用 reset 保留原"不清刷分计时"怪癖；_restart_run 用 reset_all + clear_all）与原逻辑逐句等价。
   新文件：`scripts/game/DayNightCycle.gd`、`scripts/game/ScoreKeeper.gd`、`scripts/game/WorldBuilder.gd`、`scripts/game/EcosystemDirector.gd`。
3. **暂停+设置**：HUD 内嵌 PauseMenu（CanvasLayer，process_mode WHEN_PAUSED，layer 10 高于 HUD），打开时暂停整棵树、关闭恢复；菜单按钮存活时开暂停、死亡屏期间保持原"直接回主菜单"行为（HUD._is_dead 分支）；回主菜单先 unpause 再 reload；死亡重开重建 HUD 时旧 PauseMenu 随旧 HUD 释放，无悬挂连接。SettingsPanel 提供主音量/音效/环境音/视角灵敏度四滑条，变化即经 GameState 落盘并经 AudioManager.apply_settings 实时生效；PlayerDino 的 sfx 挂 SFX 总线、触屏视角增量乘以灵敏度（LookControl/TouchControls 的 look 增量统一走 add_look_delta，覆盖 Android 全部视角来源）。
   新文件：`scripts/ui/PauseMenu.gd`、`scripts/ui/SettingsPanel.gd`；改动：`scripts/ui/HUD.gd`、`scripts/player/PlayerDino.gd`。
4. **测试与 CI**：tests/run_tests.gd（extends SceneTree，入口 `_initialize()`——已查证 4.4 源码 `SceneTree::initialize()`→`MainLoop::initialize()`→`GDVIRTUAL_CALL(_initialize)` 成立；47 断言覆盖 Groups/Maps/DinoSpecies/SaveManager 纯数据层，失败 `quit(1)`）+ GitHub Actions headless 工作流（下载 4.4.1-stable Linux 二进制并缓存，`--editor --quit` 生成全局类缓存后跑 `-s` 测试）。
   新文件：`tests/run_tests.gd`、`.github/workflows/ci.yml`。
   ⚠️ **测试与 CI 未经本地运行验证，首次 push 后以 GitHub Actions 首跑结果为准**（import 步骤已设 continue-on-error + timeout 600 兜底 LFS 缺失的导入报错）。

**终验修复（本次交叉验证新发现，均已修复）**：
- `Main._ready` 中三个 Node 型子系统（day_night/world_builder/director）原先只 `.new()` 不 `add_child`——`reload_current_scene()` 释放 Main 时它们成为孤儿节点泄漏（Node 非引用计数）。现挂到 Main 下随场景释放（均无自带回调，零副作用）。涉及 `scripts/game/Main.gd`。
- `Main._ready` 环境音总线由裸字符串 `"Ambient"` 改为 `AudioManager.BUS_AMBIENT` 常量，与 PlayerDino 的 `AudioManager.BUS_SFX` 用法统一。涉及 `scripts/game/Main.gd`。
- `tests/run_tests.gd` 头注释"-s 模式不加载 autoload"失实（Godot 4.4 `main.cpp` 中 `-s` 且主循环为 SceneTree 的 game 运行仍会加载 autoload），已修正；被测类均为 class_name 静态类，不受影响。
- `ci.yml` 注释"约 1GB 美术资产走 Git LFS"失实——`.gitattributes` 仅 `*.bin` 走 LFS，已修正；Godot 4.4.1-stable 的 `Godot_v4.4.1-stable_linux.x86_64.zip` 下载 URL 已实际请求验证（302→200）。

**终验通过项备忘**：Main 拆分全链路（_start_game/_continue_game/_restart_run/_on_player_died/_on_menu）、director 调用时序（setup(null)→set_terrain→spawn_roster→maintain_population→handle_ai_death→clear_all）、Callable `_map_radius` 0 参签名、day_t 连续性、暂停链路（WHEN_PAUSED 经 CanvasLayer→Control 子树继承生效、unpause 先于 reload）、`_restart_run` 无悬挂连接、AudioServer API 用法（add_bus/set_bus_name/set_bus_send/linear_to_db）、测试删除 user://save.json 仅发生在测试环境（CI 全新环境无真机存档风险；本地跑测试会覆盖本机存档，属已知设计）均逐项核对通过。

---

## 十一、P3/P4 快速项记录（2026-10-18）

> P3/P4 三路改动（A 路代理 AI 仇恨/攻击表现、B 路代理 地图物种+随机事件、C 路代理 版本/图标）已完成全量交叉终验，逐项核对 take_damage 全部 9 处调用点、事件状态机、风暴回滚链路、图标配置与代码风格。两处终验新发现已修复（见末尾）。

**改动内容**：

1. **AI 受击仇恨与反击（A 路）**：`AIDino` 新增 `_aggro_target/_aggro_timer`（受击 6 秒报复窗口）与 `_decide` 仇恨最优先分支——按体型规则（攻击者体型 ≤ 自己×0.9 参考 `_find_prey` 阈值风格）决定反击（转 HUNT 锁定攻击者）或逃跑（转 FLEE），超时/目标失效/死亡即 `_clear_aggro` 掉回常规决策；`take_damage` 加第三参 `attacker: Node = null`（玩家咬击/冲锋、AI 互咬均传 self，环境饥饿掉血不设仇恨）；`PlayerDino.take_damage` 加第二参 `attacker: Node = null`。
2. **攻击表现与择食修正（A 路）**：AI 命中即播撕咬/前扑动画 `_play_attack_anim`（同一目标 1s 内不重复 `ATTACK_ANIM_THROTTLE`，切换目标立即触发）；猎食尸体 `try_eat()` 失败（已空/淡出中）放弃猎物回 WANDER，不再原地空咬；`_has_ally_near`/`_herd_center` 补 `is_dead` 过滤——死亡个体不再计入 PACK 伤害加成与兽群聚群中心。
3. **地图专属物种（B 路）**：`Maps.MapDef` 新增 `extra_roster: Array[String]`（森林+似鸡龙/三角龙、雪岭+甲龙/似鸡龙、荒原+迅猛龙/似鸡龙、峡谷+食肉牛龙/霸王龙高难加压），`EcosystemDirector` 经 `set_map_def` 注入、`_build_roster` 末尾并入基础 11+X 花名册；无效 species_id 有 `AIDino._ready` 回退迅猛龙兜底（四图实际全部使用 `DinoSpecies.ID_*` 常量，不会触发）。
4. **随机事件系统（B 路）**：新建 `scripts/game/RandomEvents.gd`——90~150 秒冷却抽一事件、持续 25~40 秒，IDLE/ACTIVE 状态机保证不重入；三事件数据驱动目录（兽群迁徙→`EcosystemDirector.spawn_herd` 边缘锚点 ±8m 聚簇落位、避水重试、避玩家出生点 20m，结束不回收由 TARGET_POP 调控；风暴→`DayNightCycle.set_storm` 雾密度 ×3/太阳能量 ×0.6；丰饶期→`FoliageSpawner.set_abundant` 重生间隔 ÷4 + 立即补生 5 株）；开始/结束横幅经 `event_started/event_ended` 接 `HUD.show_banner`；`_exit_tree` 仅在 ACTIVE 时回滚未结束的风暴/丰饶——`Main._restart_run` 旧实例 queue_free（帧末执行）+ 同帧新建实例（90s+ 后才可能触发），回滚恰好作用于延续的 DayNightCycle/FoliageSpawner，无跨局误伤路径；`Main` 接线 `_spawn_random_events` 并入 `_start_game/_restart_run`。
5. **受击震动（A 路）**：`PlayerDino.take_damage` 落血反馈 `Input.vibrate_handheld(40)`（仅 Android feature；is_dead 早退保证死后不触发）。
6. **版本与自适应图标（C 路）**：`project.godot` 仅 `config/version` 一行 0.1.0→0.2.0；`export_presets.cfg` Android preset 三键填入 `assets/icons/icon_432.png`（主图标+自适应前景）与 `icon_bg_432.png`（自适应背景，均为 432×432）；`PauseMenu` 主层底部新增 v0.2.0 小字版本标签（`ProjectSettings.get_setting` 带默认值，随主层显隐）。

**终验修复（本次交叉验证新发现，均已修复）**：
- `export_presets.cfg` 的 `permissions/vibrate=false` 与新加的 `Input.vibrate_handheld(40)` 不配套——Android 真机上无 VIBRATE 权限震动会静默无效，已改 `permissions/vibrate=true`。涉及 `export_presets.cfg`。
- `DayNightCycle.set_storm(false)` 原实现无条件恢复雾密度——若在"从未开过风暴"时被误调，会把荒原图的 0.013 等非默认密度错误写成初始 0.006（当前调用路径：`_end_storm` 仅在风暴 ACTIVE 收尾、`_exit_tree` 仅在 ACTIVE 回滚，均满足"开过风暴"，故为隐患而非现行 bug）。已加 was_on 转换沿守卫：仅"开 → 关"时恢复。涉及 `scripts/game/DayNightCycle.gd`。

**终验通过项备忘**：take_damage 三方签名全 9 处调用点参数个数/顺序逐一无错位（PlayerDino 无 by_player 概念，AI 咬玩家传 `(amount, self)` 两参匹配其新签名）；仇恨分支位于 `_decide` 最前（0.25s 决策粒度消费 6s 窗口）、失效清理三条件完备、反击 `hunt_target` 与 `_hunt` 的 Node3D 类型兼容、`last_by_player` 计分链路（`_die` → `died` → `handle_ai_death` → `ai_died` → `Main._on_ai_died.record_kill`）不受影响；`spawn_herd` 个体经 `_spawn_ai_at` 统一连接 `died` 信号与登记花名册（尸体生成/计分链路完整）；风暴期雾密度每帧由 `_apply_day_night` 末尾重写、结束恢复值取自 `_map_def.fog_density` 非硬编码；三张图专属物种 id 与事件兽群池物种 id 均为已验证常量；新代码全 Tab 缩进/中文注释/无 emoji/强类型。

**需真机/编辑器实测验证**：随机事件三态表现（兽群聚簇落位/风暴雾效与恢复/丰饶补生节奏）与 AI 仇恨反击、逃跑、攻击动画节流均为运行时行为，静态审查无法覆盖，需编辑器运行或真机实测确认手感；两张新图标 PNG 尚无 `.import` 文件，首次在 Godot 编辑器打开项目时自动生成导入配置后，APK 导出才会携带自适应图标。

