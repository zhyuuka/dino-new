# T3 — APEX 威压被动落地 + 被动打磨

## 目标
让霸王龙（APEX 被动）的"威压"真正生效：附近的非 APEX 恐龙会被吓退逃窜，无视体型大小；
集群(PACK)/重甲(DEFENSE) 已实现，本次仅补 APEX 这一缺失逻辑。

## 方案（仅改 scripts/ai/AIDino.gd）
- 新增 `const APEX_RADIUS: float = 24.0`（威压感知半径，略大于普通 FLEE_RADIUS）。
- 新增 `_find_apex_threat() -> Node3D`：在 AI 群体与玩家中寻找带 APEX 被动且存活者，取半径内最近者。
- `_find_threat()` 开头（仅当 `self.passive != APEX` 时）优先返回 `_find_apex_threat()` 结果，
  使非 APEX 恐龙对霸王龙产生强制 flee。APEX 个体自身仍走体型判定（不自我恐吓）。

## 效果预期
- 玩家选霸王龙（或地图出现高阶霸王龙）靠近时，迅猛龙/三角龙等会提前逃窜，形成"食物链顶端"压迫感。
- 不影响既有体型食物链逻辑；不改动数值平衡。
- headless 运行零报错，无回归。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误。
- 代码审查：`_find_apex_threat` 只读取群体与玩家，无副作用；空场景安全返回 null。
