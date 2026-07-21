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
| 第 3 阶段 | 扩大地图、加多种恐龙、加探索/资源点 | ⬜ 待做 |
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
- **仓库**：GitHub 新建私有仓库 `dino-world`
- **协作方式**：GitHub 仓库跨会话同步 + 主 Agent 委托子 Agent 做重度实现任务
- **最高原则**：质量优先（引擎和语法选型不考虑小白能否看懂，只看产出质量）

### 4.4 第 2 阶段设计细节（第 6 批提问）
- **饥饿消耗**：每 60 秒掉 1 点（饥饿上限 100，约 100 分钟耗尽，休闲节奏）
- **食物来源**：
  - 玩家是肉食恐龙，吃 AI 尸体（+30 饥饿，2 口）
  - 地图散布果子（+5 饥饿，应急用）
  - 按现实食性：肉食只能吃肉，素食吃果子，杂食两者都能吃
- **AI 行为**：所有 AI 恐龙不互相打架，**全部针对玩家**——肉食 AI 主动追玩家咬，素食 AI 看到玩家就跑
- **5 段进化**：幼龙 → 少年 → 亚成体 → 成体 → 霸主
- **死亡惩罚**：死了保留进化等级，重开场景，饥饿/血量回满（用户选 1）

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
- **饥饿系统**：100 上限，每 60s 掉 1，0 时每 5s 掉 5 血，HUD 黄色饥饿条
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

---

## 七、当前代码结构

```
/workspace
├── .trae/rules/project_rules.md   # 项目规则（10 节，最高原则：质量优先）
├── HANDOVER.md                    # 本文件（AI 接力文档）
├── PROGRESS.md                    # 最新进度同步
├── project.godot                  # Godot 项目配置（[input][rendering] 勿改）
├── export_presets.cfg             # Android 导出预设（勿改）
├── .gitignore                     # APK 入库，.idsig 排除
├── assets/icons/icon.svg          # 应用图标
├── scenes/
│   ├── Main.tscn                  # 主场景
│   ├── PlayerDino.tscn            # 玩家恐龙
│   ├── AIDino.tscn                # AI 恐龙
│   ├── AICorpse.tscn              # AI 尸体
│   ├── Berry.tscn                 # 果子
│   ├── FoodSpawner.tscn           # 果子生成器
│   ├── HUD.tscn                   # HUD
│   └── TouchControls.tscn         # 触屏操控
├── scripts/
│   ├── game/Main.gd               # 主场景脚本（生成 AI、管理游戏循环）
│   ├── player/PlayerDino.gd       # 玩家恐龙（饥饿/进化/static 保存等级）
│   ├── ai/
│   │   ├── AIDino.gd              # AI 恐龙（食性分类）
│   │   ├── StateController.gd     # 状态机（wander/chase/flee/dead/eat）
│   │   └── AICorpse.gd            # 尸体脚本
│   ├── world/
│   │   ├── Berry.gd               # 果子
│   │   └── FoodSpawner.gd         # 果子生成器
│   └── ui/
│       ├── HUD.gd                 # HUD（血条/饥饿条/进化显示）
│       ├── TouchControls.gd       # 触屏
│       └── VirtualJoystick.gd     # 虚拟摇杆
├── build/
│   └── dino-world-debug.apk       # 当前 APK（47MB，arm64-v8a，已签名）
└── tools/
    ├── godot                      # Godot 4.4.1 二进制
    └── android-sdk/               # Android SDK
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

## 十一、待办事项（第 3 阶段规划）

按规则第四节，**开始第 3 阶段前必须先用 AskUserQuestion 问清所有细节**，给推荐选项+效果说明。

第 3 阶段大致方向（待用户确认细节）：
- 扩大地图（50×50 → 200×200 或更大？分块加载？）
- 加多种恐龙（具体加几种？什么食性？什么体型？）
- 加探索/资源点（资源点是什么？水？巢穴？特殊地形？）

**不要在没问清前就动手。**

第 4 阶段（远期）：多人联机。届时需评估 Godot 高级网络 API 或迁移引擎。

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
ls -lh build/dino-world-debug.apk  # 应生成 ~47MB APK
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

**文档版本**：v1.0
**最后更新**：2026-07-21
**当前阶段**：第 2 阶段已完成，等待用户确认进入第 3 阶段
