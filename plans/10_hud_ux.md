# T10 — HUD / UX 打磨

## 目标
- 技能按钮：仅拥有「冲锋」主动技能的物种显示；其余物种隐藏，避免无效操作。
- 技能冷却可视化：按钮上显示剩余秒数并降低不透明度，让玩家感知可用时机。
- 首次游玩引导：开局弹出图文图例（移动/视角/攻击/技能/喝水/目标/小地图含义），点按关闭。

## 方案
1. **PlayerDino.gd**：新增 `has_charge_ability() -> bool`，返回 `species.active == DinoSpecies.ActiveAbility.CHARGE`。
2. **TouchControls.gd**：
   - `set_ability_visible(v: bool)` → 控制 `ability_button.visible`。
   - `set_ability_cooldown(remaining: float, total: float)` → 冷却中显示 `%.1f` 秒并 `modulate.a=0.55`，就绪时显示「技能」并 `modulate.a=1.0`；按钮隐藏时直接返回。
3. **Main.gd**：
   - `_spawn_touch_controls()` 末尾：若 `player` 已就绪则 `touch_controls.set_ability_visible(player.has_charge_ability())`（player 在 controls 之前已生成，安全）。
   - `_process()` 内（is_over 外）：若玩家有冲锋能力，每帧 `touch_controls.set_ability_cooldown(player.charge_cooldown_timer, PlayerDino.CHARGE_COOLDOWN)`。
   - `_start_game()` 末尾：调用 `hud.show_help()`（玩家与 HUD 已生成）。
4. **HUD.gd**：新增 `show_help()` / `hide_help()`，操作 HelpPanel（半透明遮罩 + RichTextLabel 图例 + 「开始狩猎」按钮）。
5. **HUD.tscn**：新增 `HelpPanel` 节点（ColorRect 半透明 + RichTextLabel + Button），脚本连接按钮到 `hide_help`。

## 效果预期
- 选 raptor/carno/trex（冲锋）时右下出现「技能」按钮并正确冷却；选 galli/trike/anky（无冲锋）时按钮消失。
- 开局出现引导面板，点「开始狩猎」后关闭，不阻挡操作。
- 零 SCRIPT ERROR / Animation not found；APK 可正常进入游戏。

## 验证
- 无头运行 14s，过滤错误（忽略 is_inside_tree 良性警告）。
- 检查 scene 引用一致（HelpPanel 子节点路径正确）。
