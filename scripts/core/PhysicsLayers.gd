class_name PhysicsLayers
## 物理层位与派生碰撞掩码的唯一事实来源。
## 位序对应 project.godot [layer_names] 3d_physics 的 layer_1..layer_6：
##   World / PlayerBody / AIBody / PropBody / Interact / Trigger
## 场景（.tscn）无法引用 GDScript 常量，必须写十进制数字，各场景文件内已注释映射；
## 任何层位调整必须同时改本文件、project.godot 层名与各场景数字，三者保持一致。
## 十进制：位 n（从 0 起）对应 1 << n，即 1/2/4/8/16/32。

## 位 0 = 1：地形、边界墙、静态世界几何
const WORLD: int = 1 << 0
## 位 1 = 2：玩家角色本体（CharacterBody3D）
const PLAYER_BODY: int = 1 << 1
## 位 2 = 4：AI 恐龙本体（CharacterBody3D）
const AI_BODY: int = 1 << 2
## 位 3 = 8：可交互静态道具（尸体等 StaticBody3D，与 AI 本体区分）
const PROP_BODY: int = 1 << 3
## 位 4 = 16：交互检测（预留，当前未使用）
const INTERACT: int = 1 << 4
## 位 5 = 32：触发区（预留，当前未使用）
const TRIGGER: int = 1 << 5

## 玩家碰撞掩码 = WORLD | AI_BODY | PROP_BODY = 1 | 4 | 8 = 13
## 等价性：旧 mask=5（World 1 + AI 层 4，旧尸体也在 AI 层）→ 新增 PROP_BODY 承接尸体，仍能碰撞尸体
const PLAYER_MASK: int = WORLD | AI_BODY | PROP_BODY
## AI 碰撞掩码 = WORLD | PLAYER_BODY = 1 | 2 = 3（与旧行为严格等价：不被尸体阻挡）
const AI_MASK: int = WORLD | PLAYER_BODY
## 道具碰撞掩码 = WORLD = 1
const PROP_MASK: int = WORLD
## 植被 Area3D 检测掩码 = PLAYER_BODY | AI_BODY = 2 | 4 = 6（与旧值 6 完全一致）
const FOLIAGE_AREA_MASK: int = PLAYER_BODY | AI_BODY
## 相机避让掩码 = WORLD | PROP_BODY = 1 | 8 = 9（当前 SpringArm 仍用 WORLD=1 保持原行为）
const CAMERA_MASK: int = WORLD | PROP_BODY
