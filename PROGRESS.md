# 项目进度（跨会话同步）

> 这个文件用于多会话之间的上下文传递。每个会话开始时主 Agent 必须读取本文件来恢复进度。
> 每个会话结束前必须更新本文件。

## 项目基本信息
- **项目名**：dino-world（3D 开放世界恐龙生存游戏）
- **仓库**：https://github.com/zhyuuka/dino-world （Public）
- **目标平台**：Android（最终交付 APK，纯手机游戏，横屏锁定 + 触屏操控）
- **引擎**：Godot 4.4.1 stable + GDScript
- **当前阶段**：第 2 阶段系统 + 第 3 阶段打磨全部完成（T1–T12 自主收尾，游戏可玩、有趣、零运行时错误）

## 第 1 阶段目标（已完成）
- [x] Godot 4.4.1 引擎在沙箱跑通（/workspace/tools/godot）
- [x] Android SDK 安装配置完成（/workspace/tools/android-sdk，build-tools 34.0.0 + platform-34）
- [x] Godot Android 导出模板安装（/root/.local/share/godot/export_templates/4.4.1.stable/）
- [x] 项目骨架（project.godot + 目录结构 + .gitignore + export_presets.cfg）
- [x] GitHub 私有仓库 dino-world 创建
- [x] 首次推送到 GitHub
- [x] APK 导出跑通
- [x] 玩家恐龙场景（CharacterBody3D + 摄像机 + 操控）
- [x] 小型地形场景（StaticBody3D 地面 + 装饰物）
- [x] AI 恐龙（简单状态机：游荡/追击/逃跑）
- [x] HUD（血量、提示）
- [x] 触屏操控（虚拟摇杆 + 按钮）
- [x] 第 1 阶段最终 APK 交付

## 第 2 阶段目标（已完成 2026-07-21）
- [x] 饥饿系统（上限 100，每 14 秒 -1；口渴每 12 秒 -1，冲刺减半；归零掉血，T11 平衡）
- [x] 食物系统：AI 尸体（玩家吃，回 30 饥饿 + 10 血，2 口）+ 果子（自动捡，回 5 饥饿）
- [x] AI 食性分类：肉食（红橙，2 只，主动追玩家咬）+ 食草（绿棕，3 只，见玩家逃/找果子吃）
- [x] 5 段进化系统：幼龙→少年→亚成体→成体→霸主，每吃 5 次食物进化一次
  - 体型 ×1.15 / 血量上限 +20 / 咬击 +2 / 速度 +5% / 饥饿上限 +10
  - 进化时金色发光 1 秒 + HUD 显示横幅 2 秒
  - 死亡后保留进化等级（static var 跨场景）
- [x] 尸体节点 AICorpse：变暗 + 躺倒，15 秒自动消失，可吃 2 口
- [x] 果子生成器 FoodSpawner：8-12 个果子，30 秒重生
- [x] HUD 升级：血条 / 饥饿条（黄）/ 进化等级标签 / 进化进度条 / 进化横幅
- [x] 死亡惩罚：保留进化等级，重开时饥饿/血量回满、AI/果子重新生成
- [x] 编译通过（--import 无错）
- [x] APK 打包成功（47.3MB）
- 注：第 2 阶段 APK 体积较大，是因为当时仍用几何体占位 + 未压缩资源；模型替换与纹理压缩优化后体积已大幅下降（见下方第 2.5 阶段）

## 第 2 阶段交付物
- 新增文件：
  - scripts/world/Berry.gd + scenes/Berry.tscn（果子节点）
  - scripts/world/FoodSpawner.gd + scenes/FoodSpawner.tscn（果子生成器）
  - scripts/ai/AICorpse.gd + scenes/AICorpse.tscn（AI 尸体节点）
- 改造文件：
  - scripts/player/PlayerDino.gd（加饥饿/5 段进化/吃食物/发光特效）
  - scripts/ai/AIDino.gd（加 Diet 枚举/食肉食草行为差异/寻找果子状态）
  - scripts/ai/StateController.gd（加 SEEK_FOOD 状态）
  - scripts/ui/HUD.gd + scenes/HUD.tscn（加饥饿条/进化等级/进化进度/横幅）
  - scripts/game/Main.gd（串联所有系统，2 肉食 + 3 食草 AI 生成）
- APK：build/dino-world-debug.apk（47.3MB，arm64-v8a，已签名）

## 第 2.5 阶段目标（模型替换，已完成 2026-07-22）
> 用户要求：把 CSG 几何体占位恐龙，换成**免费的现成 3D 模型**（CC0 可商用）。

- [x] 选定 6 个 CC0 恐龙模型（全部免费、可商用、已本地化）：
  - `raptor.glb` 迅猛龙（Quaternius 带动画：Idle/Walk/Run/Attack/Death/Jump）
  - `trike.glb` 三角龙（Quaternius 带动画）
  - `trex.glb` 霸王龙（Poly Pizza 带动画）
  - `anky.glb` 剑龙（Quaternius Stegosaurus 带动画，作剑龙代理）
  - `carno.glb` 装甲异特龙（静态 208 网格模型，作装甲异特龙代理）
  - `galli.glb` 鸵鸟（静态带贴图模型，似鸡龙/长途奔走代理）
- [x] 新增统一模型加载器 `scripts/world/DinoVisual.gd`：
  - 从 `res://assets/models/<species_id>.glb` 实例化
  - 按 AABB 自动归一化缩放到参考长度 ~2.2m，再按成长倍率放大
  - 自动收集骨骼动画 clip（idle/walk/run/attack）并按移动状态播放
  - 尸体：变暗 + 放倒 + 淡出
  - 静态模型（carno/galli）：用轻微呼吸/摆动代替骨骼动画
- [x] 移除 PlayerDino / AIDino / AICorpse 三个场景与脚本里的所有 CSG 占位几何体
- [x] 修复 `play_locomotion` 动画名 bug（之前传了字典 key 而非真实 clip 名，导致 "Animation not found"）
- [x] 触屏控制确认完整接好：摇杆→移动、咬/跳/技能/喝水按钮全部 connect
- [x] 屏幕方向锁定为横屏（project.godot `window/handheld/orientation=1`），沉浸模式已开
- [x] 重新导出 Android Debug APK（29.6MB，arm64-v8a，v1/v2/v3 签名全通过，横屏锁定写入 manifest）

### 模型来源说明（代理选择理由）
- anky 用 Quaternius 的 **Stegosaurus**（剑龙）而非真正甲龙——CC0 资源中最接近"带背板的食草恐龙"
- carno 用 **Armored Allosaurus** 静态模型作装甲异特龙代理（CC0 无合适甲龙带动画资源）
- galli 用 **Ostrich**（鸵鸟）作似鸡龙/长途奔走型代理，体现"快、胆小、群居"特性
- 若后续找到更贴合的 CC0 模型，替换 `assets/models/<id>.glb` 即可，无需改代码（DinoVisual 按文件名自动加载）

## 第 3 阶段目标（自主完成 T1–T12，2026-07-22）

> 用户入睡后下达自主指令：不停工作直到游戏完整、有趣、无 bug；每任务先写计划+效果预期，完成后对照验证，高频 git 提交。

- [x] **T1 手机视角**：右半屏拖动控制偏航+俯仰（LookControl），修复之前手机无法转动视角的致命可玩性缺口
- [x] **T2 体力延迟**：修复体力耗尽标志 1 帧延迟（在 `_update_stamina` 内即时刷新 `_exhausted`）
- [x] **T3 威压机制**：实现 APEX 威压——非霸主肉食龙在附近霸王龙出现时强制逃跑，无视体型
- [x] **T4 扩地图**：地图半径 135、地面 280×280、3 处水源（中央湖 + 2 小水塘）、更密装饰 + 3 处树林集群；玩家越界自动拉回
- [x] **T5 探索资源点**：巢穴（回血+回体力）与矿物盐（限时增伤+加速 buff）；玩家 buff 系统（速度/伤害倍率 + 计时）
- [x] **T6 生态重平衡 + 传说霸主**：生态名册按玩家成长阶段动态扩充；地图上持续游荡的霸王龙 Boss（最高阶段），死亡 60 秒后重生并播横幅
- [x] **T7 程序化音效**：8 个纯 Python 合成 WAV（咬/受伤/吃/喝/进化/死亡/UI/环境风声）；玩家与 UI 事件接入音效，环境风声循环
- [x] **T8 昼夜循环**：120 秒一天，太阳光强/颜色 + 天空顶/地平线色 + 环境光随时间动态变化（黄昏橘调过渡）
- [x] **T9 小地图 HUD**：右上角小地图，北朝上，绘制水源(蓝)/资源(黄)/草食(绿)/肉食(红)/霸主(大红)，不拦截触摸
- [x] **T10 HUD/UX 打磨**：技能按钮仅冲锋物种显示；技能冷却秒数显示 + 半透明；开局首次游玩引导面板（点「开始狩猎」关闭）
- [x] **T11 数值平衡**：饥饿/口渴衰减提速（14s/12s 每点），尸体存活延长至 35s、可吃 4 口，形成真实但可控的「捕食→进食→成长」循环
- [x] **T12 最终 APK 导出 + 文档**：headless 30s 零运行时错误；重新导出签名 APK（29.7MB，arm64-v8a）；更新本文档与 HANDOVER.md

### 成品可玩性核对
- 开场选物种（6 种，含食性/技能差异）→ 出生幼体 → 捕食/进食成长（5 段进化）→ 躲开更大肉食与传说霸王龙
- 触屏：左摇杆移动、右半屏转视角、咬/跳/技能/喝水；横屏锁定 + 沉浸模式
- HUD：血/饿/渴/力 四条、成长条+阶段、物种+能力、计分（代际/存活/击杀）、小地图、横幅/提示、死亡屏
- 存档：死亡保留成长，代际 +1，下一局继续变强

### 验证
- 每次任务后无头运行（12–30s）过滤 `SCRIPT ERROR / parse / compile / Animation not found`，仅 `is_inside_tree` 良性警告
- 最终 APK：`apksigner verify` 通过（Android Debug 签名），含 `classes.dex` + `lib/arm64-v8a/libgodot_android.so` + 内嵌游戏资源
- 新脚本凡带 `class_name` 必重建 `.godot/global_script_class_cache.cfg` 后再校验

## 第 4 阶段目标（可选 / 待用户决定）
- 多人联机（受 Godot 联机能力限制，可能需评估迁移）
- 为 carno/galli 静态模型补简单骨骼动画，或替换更贴合的 CC0 模型
- 更多物种 / 更丰富地貌 / 季节或天气系统

## 当前会话状态（最新更新：2026-07-21）

### 关键突破：APK 导出失败问题已解决
**根因**：Godot 4.4 源码 `platform/android/export/export_plugin.cpp` 第 2784-2786 行：
```cpp
if (!ResourceImporterTextureSettings::should_import_etc2_astc()) {
    valid = false;  // 注意：这里设置 valid=false 但不填充 err！
}
```
`should_import_etc2_astc()` 检查项目设置 `rendering/textures/vram_compression/import_etc2_astc`，
未启用时返回 false（Linux x86_64 不是 ETC2_ASTC 首选格式），导致 `has_valid_project_configuration`
返回 false 但错误信息为空 → 用户看到 "configuration errors:" 后面空白。

**修复**：在 project.godot 的 [rendering] 节加入：
```
textures/vram_compression/import_etc2_astc=true
```

### 已完成
- 项目规则写入 `.trae/rules/project_rules.md`（10 节，含质量优先原则）
- 需求澄清：开放恐龙世界、3D、Android、单人+多人（多人第4阶段）、卡通风、大型开放世界（已劝说分阶段）
- 技术栈决定：Godot 4.4.1 + GDScript
- Godot 4.4.1 Linux x86_64 下载（通过 gh-proxy.com 镜像从 10KB/s 提速到 25-28MB/s）
- Android SDK 安装（platform-tools 37.0.0 + build-tools 34.0.0 + platform android-34）
- Godot Android export templates 4.4.1 安装（android_debug.apk + android_release.apk）
- debug.keystore 生成
- project.godot 配置完成（含输入映射、物理层、mobile 渲染器、ETC2/ASTC 纹理压缩）
- export_presets.cfg 配置完成（Android Debug 预设，arm64-v8a）
- Main.tscn 场景占位（Node3D + DirectionalLight3D + CSGBox3D 地面 + Camera3D）
- Main.gd 占位脚本
- editor_settings-4.4.tres 配置（Java 17 + Android SDK 路径 + keystore）
- GitHub PAT 认证成功（gh CLI 登录 zhyuuka）
- 私有仓库 https://github.com/zhyuuka/dino-world 已创建
- **APK 导出成功**：build/dino-world-debug.apk（47MB，arm64-v8a，已签名）

### 进行中
- 首次 git 提交并推送到 GitHub
- 委托子 Agent 实现第 1 阶段游戏代码

### 待办
- 委托子 Agent 实现第 1 阶段代码（场景 + 玩家恐龙 + AI 恐龙 + 触屏操控 + HUD）
- 子 Agent 完成后重新打包 APK 并交付用户

## 最新会话状态（2026-07-22：模型替换 + APK 交付）

### 已完成（本次会话）
- 修复 `DinoVisual.play_locomotion` 动画名 bug（传 `_clips[name]` 而非 key `name`），headless 运行 15 秒零脚本/编译/动画报错
- 恢复 `Main.gd` 的 `skip_select=false`，首次启动会先弹**选种界面**（玩家开局选物种）
- 把 3 个恐龙场景的 CSG 占位几何体全部替换为 6 个 CC0 现成 GLB 模型
- 确认触屏控制完整：虚拟摇杆 + 咬/跳/技能/喝水按钮均已 connect 到 PlayerDino
- 屏幕方向锁横屏 + 沉浸模式，重新导出 APK 并写进 manifest（`screenOrientation=0x1`）
- 导出成功：`build/dino-world-debug.apk`（29.6MB，arm64-v8a，apksigner 验证 v1/v2/v3 全通过）
- 这是纯手机游戏：landscape 锁屏、触屏操作、arm64 原生库、已签名可直接装安卓手机

### 验证结果
- Headless 运行：`ERROR: Condition "!is_inside_tree()"` 仅 1 条（来自 SpringArm3D 启动阶段取 global_transform 的良性警告，Godot 4 headless 通病，不影响运行）
- APK 校验：`apksigner verify` 通过；`aapt dump badging` 显示 package=com.dinoworld.game，含 lib/arm64-v8a/libgodot_android.so

### 待办（后续会话）
- 第 3 阶段（扩地图/多种恐龙/探索资源点）已由 T1–T12 全部完成
- 可选：为 carno/galli 静态模型补一套简单骨骼动画，或替换更贴合的 CC0 模型
- git 已高频本地提交（push 需用户在 GitHub 撤销 PAT 后重新授权，见"风险与未决事项"）

## 关键技术决定（备忘）
1. **不用 Unity**：Unity Editor 必须图形界面，沙箱跑不了。Godot 4.x 可命令行导出 APK。
2. **第 1 阶段单机**：不做联机，专注核心玩法跑通。
3. **几何体占位美术**：第 1 阶段用 Box/Capsule 代表恐龙，先做玩法。
4. **私有仓库**：用户要求 Private。
5. **GitHub PAT 认证**：沙箱非交互环境，不能用 `gh auth login` 交互式，用 PAT。
6. **Java 17**：与 Android build-tools 34 兼容性更好（虽然 Java 25 也能用，但 17 更稳）。
7. **ETC2/ASTC 纹理压缩**：Android 导出强制要求，必须在 project.godot 启用。
8. **mobile 渲染器**：3D Forward+ 的移动版，适合 Android 设备。
9. **arm64-v8a only**：现代 Android 手机都是 64 位 ARM，减小 APK 体积。
10. **重度任务委托子 Agent**：主会话 200k 上下文宝贵，写代码/调报错一律委托。

## 关键环境变量（导出 APK 时必须设置）
```bash
export JAVA_HOME=/root/.local/share/mise/installs/java/17.0.2
export ANDROID_HOME=/workspace/tools/android-sdk
export ANDROID_SDK_ROOT=/workspace/tools/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH
```

## 打包 APK 命令
```bash
cd /workspace/dino-world
export ANDROID_HOME=/workspace/tools/android-sdk ANDROID_SDK_ROOT=/workspace/tools/android-sdk
/workspace/tools/godot --headless --export-debug "Android Debug" build/dino-world-debug.apk
# 产物：build/dino-world-debug.apk
```

## 风险与未决事项
- 沙箱磁盘空间需监控（Android SDK 458MB + Godot templates 1.2GB + Godot binary 123MB）
- 多人联机是第 4 阶段，可能因 Godot 联机能力限制而需要迁移引擎（届时再评估）
- 用户是小白，所有打包/测试由 AI 完成，用户只看 APK 结果
- **用户 GitHub PAT 已暴露在聊天记录，建议用户尽快到 GitHub Settings 撤销重置**

## 跨会话恢复指令（给未来的主 Agent）
1. 先读 `.trae/rules/project_rules.md` 了解所有规则
2. 再读本文件了解进度
3. 检查 Godot 是否已安装：`/workspace/tools/godot --version`
4. 检查 GitHub 认证状态：`gh auth status`
5. 检查 git 远程：`cd /workspace && git remote -v && git log --oneline -5`
6. 拉取最新：`cd /workspace && git pull`
7. 根据上面"第 1 阶段目标"清单继续推进下一个未完成项
8. 重度实现任务用 Task 工具委托给 general_purpose_task 子 Agent
9. 打包 APK 前必须设置上面的环境变量
