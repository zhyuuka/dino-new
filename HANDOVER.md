# AI 接力文档（HANDOVER）

> **本文件是新 AI 会话接手项目时的必读文档。**
> 新会话开始时，AI 必须按顺序读取：1) `.trae/rules/project_rules.md`（项目规则）2) 本文件（完整上下文）3) `PROGRESS.md`（最新进度）。
> 三份文件读完即可完全恢复上下文，无需反复问用户。

---

## 〇、给新 AI 的第一句话

**你接手的是一个为完全不懂软件的小白用户做安卓恐龙游戏的云端项目。引擎、语言、配置全部由你决定；用户只看 APK 成品。所有重度实现任务必须委托子 Agent，主会话保留 200k 上下文。遇到问题联网搜索最新文档，不要凭旧知识死磕。所有用户沟通用日常语言，代码注释用中文。**

---

## 一、用户档案

- **GitHub 账号**：zhyuuka
- **邮箱**：3684939695@qq.com
- **技术水平**：完全不懂任何软件知识的小白
- **沟通偏好**：日常语言，不要技术黑话；用户只关心"能玩到什么"，不关心代码
- **当前已知安全问题**：用户曾把 GitHub PAT 明文贴在聊天里（已提醒撤销，未确认是否已撤销）

---

## 二、项目最终目标

做一个**3D 开放世界恐龙生存游戏**，参考《诅咒之岛》。

**核心主题**：弱肉强食的恐龙世界，主角是一只恐龙，其他所有生物也是恐龙。

**最终交付物**：能装到安卓手机上独立运行的 APK 文件。

---

## 三、分阶段开发计划（已确认）

项目分 4 阶段推进，**每阶段都是可玩成品**，做完一阶段再谈下一阶段，禁止跨阶段超前实现。

| 阶段 | 内容 | 状态 |
|------|------|------|
| 第 1 阶段 | 小型 3D 场景 + 1 只玩家恐龙（走/跑/咬/视角）+ 几只 AI 恐龙。**单机** | ✅ 已完成 |
| 第 2 阶段 | 饥饿/血量/食性/5 段成长进化系统 | ✅ 已完成 |
| 第 3 阶段 | 扩大地图、多种恐龙、探索/资源点 + 手机视角/音效/昼夜/小地图/HUD 打磨（T1–T12 自主完成） | ✅ 已完成 |
| 第 4 阶段 | 多人联机（如条件允许） | ⬜ 待做 |

---

## 四、已确认的所有设计决策（用户已拍板）

### 4.1 游戏基本设定（第 1 批提问）
- **类型**：开放恐龙世界（参考诅咒之岛）
- **画面**：3D 立体
- **平台**：Android 手机
- **主题**：弱肉强食的恐龙世界，主角是恐龙，所有生物都是恐龙

### 4.2 玩法与体量（第 2 批提问）
- **体量**：大型开放世界（已劝说分阶段实现，先做小场景验证玩法）
- **模式**：单机 + 多人联机（**联机推迟到第 4 阶段**）
- **玩法**：生存动作（吃/咬/跑）+ 成长进化 + 多恐龙种类 + 地图探索/资源
- **美术**：卡通风（当前用几何体占位，后续再升级美术）

### 4.3 引擎与协作（第 3-5 批提问）
- **引擎**：Godot 4.x（确认 4.4.1 stable）
- **语言**：GDScript（强类型）
- **仓库**：GitHub 公开仓库 `dino-world`（https://github.com/zhyuuka/dino-world，原为私有，2026-07-21 改为 Public）
- **协作方式**：GitHub 仓库跨会话同步 + 主 Agent 委托子 Agent 做重度实现任务
- **最高原则**：质量优先（引擎和语法选型不考虑小白能否看懂，只看产出质量）

### 4.4 第 2 阶段设计细节（第 6 批提问，部分数值已被 T11 调优）
- **饥饿消耗**：饥饿上限 100，每 14 秒掉 1 点；口渴上限 100，每 12 秒掉 1 点（冲刺时口渴间隔减半）。0 时分别每 5s/4s 掉 6/5 血（T11 平衡后更真实但可控）
- **食物来源**：
  - 玩家是肉食恐龙，吃 AI 尸体（+28 饥饿 +8 血，每具 4 口，尸体存活 35s）
  - 玩家是草食恐龙，吃植物（Foliage，+10 饥饿 +4 口渴 +4 血，被吃后别处重生）
  - 按现实食性：肉食只能吃肉，草食只能吃植物（杂食无）
- **AI 行为**：真实**食物链**生态——肉食 AI 追猎草食与玩家，草食 AI 见威胁逃跑并觅食；霸王龙具 APEX 威压，附近非霸主肉食龙强制逃跑（T3）；存在持续游荡的传说霸王龙 Boss（死亡 60s 重生，T6）
- **5 段进化**：幼龙 → 少年 → 亚成体 → 成体 → 霸主（每阶段体型/血量/咬击/速度按倍率缩放）
- **死亡惩罚**：死了保留成长等级与代际（+1），重开场景，饥饿/血量回满（用户选 1）

---

## 五、技术栈与配置（已固定，勿改）

### 5.1 引擎与工具
| 项目 | 版本/路径 | 备注 |
|------|----------|------|
| Godot | 4.4.1 stable | 二进制 `/workspace/tools/godot` |
| Android SDK | platform-tools 37.0.0 + build-tools 34.0.0 + platform android-34 | 路径 `/workspace/tools/android-sdk` |
| Godot Android 导出模板 | 4.4.1 stable | `/root/.local/share/godot/export_templates/4.4.1.stable/` |
| Java | 17.0.2（mise 管理） | `/root/.local/share/mise/installs/java/17.0.2` |
| debug.keystore | alias=androiddebugkey, pass=android | `/root/.android/debug.keystore` |
| gh CLI | 已认证 zhyuuka | PAT 方式登录 |

### 5.2 渲染配置（project.godot，**勿改 [rendering] 节**）
- 渲染器：mobile（3D Forward+ 移动版）
- ETC2/ASTC 纹理压缩：**必须启用** `textures/vram_compression/import_etc2_astc=true`
  - 不启用会导致 Android 导出报 "configuration errors:" 但错误信息空白（Godot 源码 bug）
- MSAA 3D：2

### 5.3 输入映射（project.godot，**勿改 [input] 节**）
- `move_forward/backward/left/right`：WASD + 方向键
- `jump`：Space
- `bite`：J + 鼠标左键
- `sprint`：Shift
- `cam_left/right`：Q/E
- `toggle_camera`：C
- `ui_touch` / `ui_drag`：触摸事件
- 触摸模拟：`pointing/emulate_touch_from_mouse=true` + `pointing/emulate_mouse_from_touch=true`

### 5.4 物理层（project.godot）
- Layer 1: World
- Layer 2: Player
- Layer 3: AI
- Layer 4: Trigger

### 5.5 导出预设（export_presets.cfg，**勿改**）
- Android Debug 预设
- `architectures/arm64-v8a=true`（其他 false，减小 APK 体积）
- `script_export_mode=0`
- `screen/immersive_mode=true`
- 所有 permissions=false

### 5.6 关键环境变量（打包 APK 前必须设置）
```bash
export JAVA_HOME=/root/.local/share/mise/installs/java/17.0.2
export ANDROID_HOME=/workspace/tools/android-sdk
export ANDROID_SDK_ROOT=/workspace/tools/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH
```

### 5.7 打包 APK 命令
```bash
cd /workspace
./tools/godot --headless --export-debug "Android Debug"
# 产物：build/dino-world-debug.apk
```

---

## 六、当前已完成的功能（第 1+2 阶段）

### 6.1 第 1 阶段（基础玩法）
- 玩家恐龙：CharacterBody3D + CSG 几何体身体（绿色），第三人称 SpringArm3D 摄像机
- 移动：WASD/方向键走，Shift 加速跑，Space 跳，J/鼠标左键咬（0.3s 冷却）
- 平滑朝向旋转，重力 19.6
- 小型地形：50×50 地面 + 5 棵树 + 5 块石头 + 四面边界墙 + 天空盒
- 4 只 AI 恐龙：状态机 wander/chase/flee/dead
- HUD：血条 + 击杀数 + 游戏结束/胜利画面
- 触屏操控：左下虚拟摇杆 + 右下咬/跳按钮
- 游戏循环：死亡 3s 重开 / 全杀胜利 3s 重开

### 6.2 第 2 阶段（生存+进化）
- **饥饿系统**：100 上限，每 14s 掉 1，0 时每 5s 掉 6 血；口渴每 12s 掉 1（冲刺减半），0 时每 4s 掉 5 血；HUD 黄/蓝色条
- **食性系统**：
  - 玩家肉食，吃 AI 尸体（+30 饥饿 +10 血，2 口）+ 果子（+5 饥饿）
  - AI 死后变尸体（变暗+躺倒 90 度，15s 消失）
  - 地图随机生成 8-12 个红色果子（浮动+旋转），被吃 30s 重生
- **AI 食性分类**：
  - 肉食 AI（红橙，2 只）：8 血，咬击 3，主动追玩家
  - 食草 AI（绿棕，3 只）：5 血，见玩家逃跑，自己找果子吃
- **5 段进化**：幼龙→少年→亚成体→成体→霸主
  - 每吃 5 次食物进化一次
  - 每级：体型 ×1.15、血量上限 +20、咬击 +2、速度 +5%、饥饿上限 +10
  - 进化时金色发光 1s + 屏幕中央横幅"进化为【XX】！"
  - 满级后继续吃仍回饥饿/血量但不进化
- **死亡惩罚**：保留进化等级（static var `PlayerDino.saved_evolution_level`），3s 重开
- **HUD 升级**：血条→饥饿条→进化等级标签；右上击杀数+进化进度条；进化横幅

### 6.3 第 2.5–3 阶段（模型替换 + 打磨 T1–T12）
- **模型替换（第 2.5 阶段）**：6 个 CC0 恐龙 GLB（raptor/trike/trex/anky/carno/galli）+ 统一 `DinoVisual` 加载器（按文件名自动加载、AABB 归一化缩放、自动收集骨骼动画、尸体放倒淡出；carno/galli 静态模型用呼吸/摆动代替骨骼动画）
- **T1 手机视角**：右半屏拖动控制偏航+俯仰（LookControl + TouchControls 接入）
- **T2 体力**：修复体力耗尽标志 1 帧延迟
- **T3 威压**：APEX 霸王龙令附近非霸主肉食龙强制逃跑
- **T4 扩地图**：半径 135、地面 280×280、3 处水源、更密装饰+树林；越界拉回
- **T5 资源点**：巢穴（回血+回体力）与矿物盐（限时增伤+加速 buff）；玩家 buff 系统
- **T6 生态 + 传说霸主**：动态生态名册 + 游荡霸王龙 Boss（60s 重生）
- **T7 音效**：8 个纯 Python 合成 WAV（咬/受伤/吃/喝/进化/死亡/UI/环境风声）
- **T8 昼夜**：120s 一天，太阳光/天空/环境光动态变化
- **T9 小地图**：右上角北朝上小地图（水源/资源/草食/肉食/霸主）
- **T10 HUD/UX**：技能按钮仅冲锋物种显示 + 冷却秒数；开局引导面板
- **T11 平衡**：饥饿/口渴衰减提速 + 尸体延长（见 4.4）
- **T12 最终 APK**：29.7MB arm64-v8a 已签名，`apksigner verify` 通过

---

## 七、当前代码结构

```
/workspace
├── .trae/rules/project_rules.md   # 项目规则（10 节，最高原则：质量优先）
├── HANDOVER.md                    # 本文件（AI 接力文档）
├── PROGRESS.md                    # 最新进度同步
├── plans/                         # 每个任务 T1–T12 的计划+效果预期文档
├── project.godot                  # Godot 项目配置（[input][rendering] 勿改）
├── export_presets.cfg             # Android 导出预设（勿改）
├── .gitignore                     # APK 入库，.idsig 排除
├── assets/
│   ├── models/                    # 6 个 CC0 恐龙 GLB（raptor/trike/trex/anky/carno/galli）
│   ├── audio/                     # 8 个程序化合成 WAV + .import
│   └── icons/icon.svg             # 应用图标
├── scenes/
│   ├── Main.tscn                  # 主场景
│   ├── PlayerDino.tscn            # 玩家恐龙
│   ├── AIDino.tscn                # AI 恐龙
│   ├── AICorpse.tscn              # AI 尸体
│   ├── SpeciesSelect.tscn         # 开局选物种界面
│   ├── HUD.tscn                   # HUD（含小地图/引导面板）
│   ├── TouchControls.tscn         # 触屏操控（含 LookZone）
│   ├── WaterSource.tscn           # 水源
│   ├── ResourcePoint.tscn         # 巢穴/矿物盐
│   ├── Foliage.tscn               # 可食植物
│   └── FoliageSpawner.tscn        # 植物生成器
├── scripts/
│   ├── game/Main.gd               # 主场景（生成世界/生态/昼夜/HUD/触屏，管理游戏循环）
│   ├── player/PlayerDino.gd       # 玩家恐龙（移动/视角/进食/进化/buff/技能）
│   ├── ai/
│   │   ├── AIDino.gd              # AI 恐龙（食物链行为/威压）
│   │   ├── StateController.gd      # 状态机（wander/chase/flee/dead/eat）
│   │   └── AICorpse.gd            # 尸体脚本
│   ├── data/
│   │   ├── DinoSpecies.gd         # 物种数据库（属性/食性/技能/成长倍率）
│   │   └── SaveManager.gd         # 存档（成长/代际/最佳）
│   ├── world/
│   │   ├── DinoVisual.gd          # 统一 GLB 模型加载器（动画/尸体）
│   │   ├── WaterSource.gd         # 水源
│   │   ├── ResourcePoint.gd       # 巢穴/矿物盐
│   │   ├── Foliage.gd             # 可食植物
│   │   └── FoliageSpawner.gd      # 植物生成器
│   └── ui/
│       ├── HUD.gd                 # HUD（血/饿/渴/力/成长/物种/计分/小地图/引导）
│       ├── Minimap.gd             # 小地图绘制
│       ├── TouchControls.gd       # 触屏
│       ├── LookControl.gd         # 右半屏视角拖动
│       ├── VirtualJoystick.gd     # 虚拟摇杆
│       └── SpeciesSelect.gd       # 选物种
├── build/
│   └── dino-world-debug.apk       # 当前 APK（29.7MB，arm64-v8a，已签名）
├── tools/
│   ├── gen_audio.py               # 纯 Python WAV 合成（生成 assets/audio）
│   ├── godot                      # Godot 4.4.1 二进制
│   └── android-sdk/               # Android SDK
```

---

## 八、项目规则核心（详见 .trae/rules/project_rules.md）

1. **最高原则：质量优先**。引擎/语言/库选型只看产出质量，不看小白能否看懂。
2. **面向用户约定**：解释用日常语言，用户只看 APK 成品。
3. **原生游戏硬约束**：必须 APK/.exe/.app，**严禁 HTML 网页游戏**。
4. **配置责任在 AI**：引擎、构建、依赖全由 AI 自行决定。
5. **开发前必问清需求**：用 AskUserQuestion，单次最多 4 题。
6. **技术选项必须给推荐+效果说明**：推荐项放第一位标"（推荐）"。
7. **遇问题必须 WebSearch 联网**：不靠旧知识库死磕，搜索用 2026 年。
8. **GitHub 私有仓库跨会话同步**：会话开始 `git pull`，结束 `git commit && git push`。
9. **重度任务委托子 Agent**：主会话只做需求对接/决策/汇报/调度。
10. **PROGRESS.md 跨会话同步**：会话开始必读，结束必更新。

---

## 九、工作流程规范（新 AI 必须遵守）

### 9.1 会话开始流程
1. `cd /workspace && git pull` 拉最新代码
2. 读 `.trae/rules/project_rules.md`
3. 读 `HANDOVER.md`（本文件）
4. 读 `PROGRESS.md`
5. 检查环境：`./tools/godot --version`、`gh auth status`、`git log --oneline -5`
6. 用 TodoWrite 规划本会话任务

### 9.2 实现任务流程
1. **重度实现任务一律委托 `Task` 工具的 `general_purpose_task` 子 Agent**（写代码、搭场景、调报错）
2. 主会话只做：需求对接、决策、子 Agent 调度、向用户汇报
3. 给子 Agent 的任务描述必须**极其详细**：项目背景、现有代码结构、需求清单、实现要求、验证步骤、约束条件
4. 子 Agent 完成后主会话验证 APK 打包、git 提交推送

### 9.3 遇到报错的流程
1. **必须先 WebSearch**（用 2026 年关键词），不要凭训练知识死磕
2. 必要时直接看 Godot 源码（用 `gh api -H "Accept: application/vnd.github.raw+json" "/repos/godotengine/godot/contents/<path>?ref=4.4-stable"`）
3. 搜索仍无解再向用户说明并请求决策，不得无限重试同一失败操作

### 9.4 会话结束流程
1. 子 Agent 任务全部验证通过
2. 打包 APK 并确认产物存在
3. `git add -A && git commit -m "..." && git push origin main`
4. 更新 `PROGRESS.md`（最新进度、未决事项、跨会话恢复指令）
5. 向用户汇报（日常语言，说"能玩到什么"，不说代码细节）

---

## 十、已知坑与解决方案（避免新 AI 重复踩）

### 10.1 Godot Android 导出报"configuration errors:"但错误信息空白
**根因**：Godot 4.4 源码 `platform/android/export/export_plugin.cpp` 第 2784-2786 行，`ResourceImporterTextureSettings::should_import_etc2_astc()` 返回 false 时设 `valid=false` 但**不填充 err**。
**修复**：project.godot 的 `[rendering]` 节加 `textures/vram_compression/import_etc2_astc=true`。**已修复，勿动。**

### 10.2 GitHub 下载速度慢
**问题**：沙箱直连 GitHub 资产 10KB/s。
**解决**：用 `gh-proxy.com` 镜像（25-28MB/s）。

### 10.3 沙箱非交互环境 gh auth 不能用交互登录
**解决**：用 PAT：`echo "<token>" | gh auth login --with-token`，然后 `gh auth setup-git` 配置 git 凭证。

### 10.4 Godot 4 API 误用
- `Vector2.clamp_length` **不存在**，正确是 `limit_length(max)`
- 其他不熟悉的 API 必须先 WebSearch 确认

### 10.5 headless 模式 `--check-only` 会卡住不退出
**现象**：无错时不退出。
**解决**：用 `--import` 替代验证（退出码 0 即编译通过），或 `--quit-after N` 跑 N 帧后退出。

### 10.6 Write 工具不能写 /workspace 外的文件
**问题**：PathScopeExceed 错误。
**解决**：用 `RunCommand` 的 `cat > file <<'EOF' ... EOF` heredoc 方式写 /root/ 下的文件（如 editor_settings）。

### 10.7 editor_settings 在 headless/CI 模式不被读取
**问题**：godot-ci issue #151，CI 环境 editor_settings 配置不生效。
**解决**：依赖环境变量 `JAVA_HOME` 和 `ANDROID_HOME`（Godot 源码 platform/android/export/export.cpp 第 52 行读 OS env）。

---

## 十一、待办事项（第 3 阶段已完成，第 4 阶段待定）

第 3 阶段已在用户入睡后的自主指令下由 T1–T12 全部完成（扩地图/多种恐龙/探索资源点 + 手机视角/音效/昼夜/小地图/HUD 打磨 + 数值平衡 + 最终 APK）。

第 4 阶段（远期，待用户确认）：多人联机。届时需评估 Godot 高级网络 API 或迁移引擎。

**注意**：自主阶段是按"最优解"直接推进的，未再走 AskUserQuestion 需求澄清流程（用户已明确授权"不向我报告、按最优解不停工作"）。若用户后续对玩法有具体偏好，应在第 4 阶段开始前用 AskUserQuestion 问清细节。

---

## 十二、跨会话恢复检查清单

新 AI 接手时跑一遍这个清单确认环境就绪：

```bash
# 1. 拉最新代码
cd /workspace && git pull

# 2. 验证 Godot
./tools/godot --version  # 应输出 4.4.1.stable.official

# 3. 验证 GitHub 认证
gh auth status  # 应显示 Logged in to github.com account zhyuuka

# 4. 验证 git 远程
git remote -v  # 应有 origin https://github.com/zhyuuka/dino-world.git

# 5. 查看最新提交
git log --oneline -5

# 6. 验证 Android SDK
ls /workspace/tools/android-sdk/build-tools/  # 应有 34.0.0

# 7. 验证导出模板
ls /root/.local/share/godot/export_templates/4.4.1.stable/  # 应有 android_debug.apk + android_release.apk

# 8. 验证 Java
/root/.local/share/mise/installs/java/17.0.2/bin/java -version  # 应是 17.0.2

# 9. 验证 keystore
ls /root/.android/debug.keystore  # 应存在

# 10. 测试打包
export JAVA_HOME=/root/.local/share/mise/installs/java/17.0.2
export ANDROID_HOME=/workspace/tools/android-sdk
export ANDROID_SDK_ROOT=/workspace/tools/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH
cd /workspace
./tools/godot --headless --export-debug "Android Debug" 2>&1 | tail -10
ls -lh build/dino-world-debug.apk  # 应生成 ~29.7MB APK
```

全部通过即可开始本会话工作。

---

## 十三、给新 AI 的最后提醒

1. **用户是小白**，所有面向用户的回复用日常语言，不抛代码细节。
2. **质量优先**，引擎/语言选型不考虑小白能否看懂。
3. **重度任务委托子 Agent**，主会话保 200k 上下文。
4. **遇问题先 WebSearch**（2026 年关键词），不靠旧知识死磕。
5. **每会话必读三文件**：project_rules.md + HANDOVER.md（本文件）+ PROGRESS.md。
6. **每会话结束必更新**：PROGRESS.md + git push。
7. **APK 必须入库**（用户从 GitHub 直接下载），`.idsig` 排除。
8. **不要修改** project.godot 的 `[input]` 和 `[rendering]` 节，不要改 export_presets.cfg。
9. **新阶段开始前必须 AskUserQuestion 问清细节**，给推荐选项+效果说明。
10. **诚实告知不切实际的需求**，给出分阶段方案。

---

**文档版本**：v2.0
**最后更新**：2026-07-22
**当前阶段**：第 1+2+3 阶段全部完成；游戏可玩、有趣、零运行时错误；APK 已导出（29.7MB）。等待用户确认是否进入第 4 阶段（联机）或追加打磨。
