# 存档 Repository 收口与版本迁移链

> 实施日期：2026-10-24（文件名按任务指定为 2026-10-18）
> 代码基线：`/workspace/dino-new`（Godot 4.4.1 stable，Android）
> 依据：`docs/reports/2026-10-18-flow-and-save-research.md` 第 3 节“问题二：存档架构与版本迁移”
> 本次范围：只做存档收口（S0→S2 的等价实现），**不改 GameFlow、不改数值、不改存档字段语义**

---

## 0. 结论

存档从“5 个文件散落读改写”收口为：

```
调用方（Main / PlayerDino / SpeciesSelect）
        │  只认 PlayerProfile（强类型）
        ▼
SaveRepository（唯一 IO：JSON、版本、迁移链、原子写、备份、隔离）
        │  dict ↔ typed
        ▼
PlayerProfile（键名常量唯一来源 + 默认值 + 钳制）

SaveManager：兼容门面，只转发，不含任何 IO 逻辑
```

行为等价的判定口径：无档/完整档/缺字段档/损坏档/未来版本档五条路径的**对外可见结果**（能否续档、续档后的物种/成长/代际/地图/最佳成绩）与改造前一致；唯一有意变化是“损坏/未来版本档现在会留下隔离副本”。

---

## 1. 文件与常量

| 文件 | 角色 | 关键内容 |
|---|---|---|
| `scripts/data/PlayerProfile.gd`（新增） | 内存模型 | 6 个强类型字段；`defaults()` / `from_dict()` / `to_dict()`；`KEY_SPECIES` / `KEY_GROWTH_STAGE` / `KEY_GENERATION` / `KEY_MAP_ID` / `KEY_BEST_TIME` / `KEY_BEST_KILLS` |
| `scripts/data/SaveRepository.gd`（新增） | 唯一 IO 入口（静态类） | `SAVE_VERSION := 2`；`SAVE_PATH` / `BAK_PATH` / `FUTURE_BAK_PATH` / `CORRUPT_BAK_PATH`；`load_profile()` / `save_profile()` / `has_save()` / `has_progress()` |
| `scripts/data/SaveManager.gd`（改） | 兼容门面 | `load_save()` = `load_profile().to_dict()`；`write_save(d)` = `save_profile(from_dict(d))`；`SAVE_VERSION` 转发 Repository |
| `scripts/game/Main.gd`（改） | 唯一业务写入者 | 新开局写、死亡结算写、续关/重开读 |
| `scripts/player/PlayerDino.gd`（改） | 进化写盘（受限） | 只“先读再写” `growth_stage`，不碰 `generation/map_id/best_*` |
| `scripts/ui/SpeciesSelect.gd`（改） | 续档入口 | 直接读 `PlayerProfile` + `has_progress()` |
| `tests/run_tests.gd`（改） | 测试 | 新增 Repository 用例，门面用例改为读原始文件校验版本 |

**键名规则**：除 `PlayerProfile` 的 `KEY_*` 外，只有 `SaveRepository` 额外持有 `save_version` / `profile_version` 两个信封键常量。业务代码里已无裸写存档键。

---

## 2. 版本模型

| 版本 | 特征 | 读法 |
|---|---|---|
| 无 `save_version` | 极早期 `SaveManager` 档，字段键与 v1 相同 | 按 v1 处理 |
| `save_version = 1` | v1：**无 `profile_version`**，6 个字段键相同 | 走 `_migrate_v1_to_v2` |
| `save_version = 2` | 当前：`save_version` + `profile_version` 双标记，字段不变 | 直接读 |
| `> SAVE_VERSION` | 未来版本 | 只隔离，不迁移、不覆盖 |

设计取舍：

- `save_version` 是“仓库信封版本”（能不能读懂这份档）；`profile_version` 是“档案结构版本”（字段形状）。v2 起两者同步，v1 只有前者。分开命名是为了将来 envelope 与 profile 各自演进时不互相绑架。
- 当前两版字段完全相同，`_migrate_v1_to_v2` **只补缺省字段与 `profile_version`，不改任何既有字段语义**；这保证旧档升级是纯加法，回退风险最低。

### 2.1 迁移链

```gdscript
_migrate(d, from_version):
    while version < SAVE_VERSION:
        match version:
            1: out = _migrate_v1_to_v2(out)
            _: 缺少步骤 → 返回 {}（fail closed，按损坏处理）
        version += 1
        out[save_version] = version
        out[profile_version] = version
```

- **逐级单步**：每一步只做 vN→vN+1，可单独单测、失败可定位到具体版本。
- **fail closed**：迁移链缺步骤时返回空字典，由 `load_profile()` 隔离为 `save.corrupt.bak` 并回退默认档，不做猜测性迁移。
- **未知字段保留**：迁移全程 `duplicate(true)`，不认识的顶层键原样带过（测试已覆盖 `legacy_note`）。
- **迁移即落盘**：`from_version < SAVE_VERSION` 且迁移成功后立即以当前版本写回（走同一套原子写 + 备份），避免每次启动重复迁移。写回失败不影响本次读取。
- **未来占位**：`_migrate_v2_to_v3(d)` 已留纯函数占位，注释写明启用时要同时改 `match` 分支与 `SAVE_VERSION`；当前 `SAVE_VERSION=2` 不会走到。

---

## 3. 备份与原子写策略

写入顺序（`_write_dict`）：

1. **写前备份**：若 `save.json` 存在，且内容可解析为字典、`save_version <= SAVE_VERSION`，则复制为 `save.bak`（覆盖旧备份）。条件不满足（损坏/未来版本）→ **跳过备份，保留上一份好备份**。
2. **临时文件**：`save.json.tmp` 写入 `JSON.stringify(d, "\t")`，`flush` 后关闭。
3. **回读校验**：重新读取 tmp 文本，与内存字符串逐字节比较；不一致 → 删除 tmp、返回失败。
4. **原子替换**：`DirAccess.rename_absolute(tmp, save.json)`；失败则删 tmp、返回失败。

| 文件 | 何时产生 | 语义 |
|---|---|---|
| `save.json` | 每次成功写入 | 当前档 |
| `save.bak` | 覆盖写前，且旧档有效 | 上一份有效档（仅一份，不做多代轮换） |
| `save.future.bak` | 读到 `save_version > 2` | 未来版本档副本；**原文件保留**，不删不覆盖（除非后续业务写入主动提交新档） |
| `save.corrupt.bak` | JSON 解析失败 / 非字典 / 迁移失败 | 损坏现场副本；原文件保留 |
| `save.json.tmp` | 写入过程 | 正常不应残留；任何失败路径都会清理 |

失败处理统一为“返回 false / 默认档 + `push_warning`”，不抛错、不阻塞开局、不删除玩家文件。

---

## 4. 写入时机矩阵（改造后）

| 时机 | 触发点 | 写入者 | 写法 | 说明 |
|---|---|---|---|---|
| 新开一局 | `Main._start_game(is_continue=false)` | Main | 整快照 `save_profile` | 保留 `best_*`，重置物种/成长/代际/地图 |
| 续档开局 | `Main._continue_game` / `_start_game(true)` | 无写入 | 只读 | 有进度才续，否则按新局写 |
| 进化 | `PlayerDino._add_growth_meal` → `_save_progress()` | PlayerDino（受限） | 先读 → 只改 `growth_stage` → 整快照写 | 保留 `generation/map_id/best_*`；注释声明 Main 是死亡结算唯一权威 |
| 死亡结算 | `Main._on_player_died` | Main（唯一权威） | 先读 → 改物种/成长/代际+1/`best_*` 取大 → 整快照写 | 3.5s 展示期前完成落盘 |
| 死亡重开 | `Main._restart_run` | 无写入 | 只读 | 从刚写的档读回成长与代际 |
| 回主菜单 | `Main._on_menu` | 无写入 | — | 与改造前一致：依赖进化/死亡已落盘，不做额外写 |

**为什么仍保留 PlayerDino 写入**：进化发生在本局中途，若等死亡才写，玩家在进化后被杀进程会丢成长。改造后的写法是先读再写、只改一个字段，并与 Main 的死亡整快照提交在时序上互不覆盖（死亡时 Main 还会用运行期 `player.growth_stage` 覆盖该字段，天然幂等）。

**双写风险是否消失**：旧代码两边都是“读旧快照 → 改多字段 → 写回”，交错时会用旧 `best_*` 覆盖新值。现在 PlayerDino 的写入范围只剩 `growth_stage`，而 Main 死亡写入会重新读盘并取 `maxi`，即使交错也不会回退最佳成绩；`generation` 只由 Main 写。剩余风险见第 7 节。

---

## 5. 改动清单（逐函数）

| 文件 | 位置 | 改动 |
|---|---|---|
| `PlayerProfile.gd` | 全文新增 | 6 字段 + 键常量 + `defaults/from_dict/to_dict`；物种未知回退迅猛龙、成长钳制 0..MAX_STAGE、代际 ≥1、地图经 `Maps.by_id` 归一、最佳成绩 ≥0 |
| `SaveRepository.gd` | 全文新增 | `SAVE_VERSION=2`；`load_profile`（解析→版本→迁移→快照）；`save_profile`（整快照 + 双版本键）；`_migrate` / `_migrate_v1_to_v2` / `_migrate_v2_to_v3` 占位；`_write_dict` / `_backup` / `_read_json`；`has_save` / `has_progress` |
| `SaveManager.gd` | 全文重写 | 退化为门面：`load_save` / `write_save` / `has_save` / `has_progress` 全部转发；删除本地读写与 `_ensure_defaults` |
| `Main.gd` | `_continue_game` | 改读 `PlayerProfile`，地图取 `profile.map_id` |
| `Main.gd` | `_start_game` | 改读 profile + `has_progress()`；新局整快照提交 |
| `Main.gd` | `_on_player_died` | 改读 profile，死亡字段赋值后整快照提交；最佳成绩文案改读 profile |
| `Main.gd` | `_restart_run` | 改读 profile 的物种/成长/代际 |
| `PlayerDino.gd` | `_save_progress` | 先读 profile，只改 `growth_stage`，整快照写；新增“Main 是唯一权威”注释 |
| `SpeciesSelect.gd` | `_ready` | 改读 profile + `has_progress()`；不再裸用字典键 |
| `run_tests.gd` | 测试区 | 新增 `_test_save_repository()`；门面用例版本断言改为读原始 JSON；新增清档/读文件辅助 |

**全仓检索结果**：`SaveManager.load_save/write_save` 只剩门面内部与测试；`Main` / `PlayerDino` / `SpeciesSelect` 已无字典式存档键读写。

---

## 6. 测试与验收

命令与结果：

```bash
# 导入
XDG_DATA_HOME=/workspace/tools/godotdata XDG_CONFIG_HOME=/workspace/tools/godotconfig \
  /workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --headless --path /workspace/dino-new --import
# SCRIPT ERROR / Parse Error / Compile Error = 0（exit 0）

# 单测
... --headless --path /workspace/dino-new -s res://tests/run_tests.gd
# PASSED: 166 / FAILED: 0（exit 0）

# 冒烟（额外自测）
... --headless --path /workspace/dino-new --quit-after 16
# 过滤 SCRIPT ERROR/Invalid get/Null instance/Can't find type/TypedArray = 0
```

Repository 新增断言覆盖：

| 类别 | 断言要点 |
|---|---|
| 无档 | `has_save=false`、默认物种/成长/代际/地图/成绩、读取不创建文件 |
| 往返 | 6 字段一致、无 tmp 残留、落盘含 `save_version=2` 与 `profile_version=2` |
| 备份 | 第二次写入生成 `save.bak`，内容为上一次（`best_time=99`） |
| v1（无版本键） | 6 字段保留、未知字段保留、迁移后 `save_version/profile_version=2` |
| v1（显式 =1） | 字段保留、缺字段补默认、迁移后以 v2 落盘 |
| 未来版本 | 返回默认档、生成 `save.future.bak`、原文件保留、副本内容正确 |
| 损坏 | 返回默认档、生成 `save.corrupt.bak`、副本保留原始文本 |
| 备份保护 | 坏档存在时仍可写入，但 `save.bak` 不被顶掉 |

`user://` 路径与测试隔离：所有用例在开头 `_clean_save_files()` 清理 `save.json` / `.tmp` / `save.bak` / `save.future.bak` / `save.corrupt.bak`，避免上一条用例的备份把“损坏档应回退默认”变成“从备份恢复”。

---

## 7. 风险与回退

| # | 风险 | 触发信号 | 缓解 | 回退 |
|---|---|---|---|---|
| R1 | **PlayerDino 写盘语义变化**：进化时不再写 `species_id`/`generation` | 极端路径（进化后直接杀进程、且本局开局写盘失败）下物种/代际可能滞后 | 新开局 Main 已写物种；死亡结算 Main 会重写三字段；进化只可能让 `growth_stage` 前进 | 恢复为“发出 `save_requested` 信号由 Main 写”，彻底单写 |
| R2 | 迁移即落盘引入“读操作也写盘” | 启动/续关时多一次小文件写 | 仅在 `from_version<2` 且迁移成功时触发；写失败不影响读取；原子写 + 备份 | 去掉 `_write_dict(migrated)`，改为纯内存迁移 |
| R3 | `load_save()` 现在总是返回全部键 | 旧代码用 `d.has("species_id")` 判断有无进度会永远为真 | 生产调用点已改用 `has_progress()`；门面保留旧形状仅为兼容 | 门面在无进度时只返回 `{map_id}`（与更早行为一致） |
| R4 | 损坏/未来档原文件保留，后续写入会覆盖主文件 | 玩家降级后升级回来发现主档已变 | 已保留 `save.future.bak` / `save.corrupt.bak` 副本；不删除任何现场 | 从隔离副本手工恢复 |
| R5 | `save.bak` 只有一份，不滚动多代 | 连续两次坏写可能丢掉更早的好档 | 写前先回读校验 + tmp 不覆盖主档；坏写概率极低 | 扩为 `.bak.1/.bak.2` 轮换 |
| R6 | JSON 数字统一变 float | `generation` 显示为 `3.0`、下标异常 | `PlayerProfile` 所有读取 `int()` 并钳制；往返测试覆盖 | — |
| R7 | 新增 `class_name` 未重建全局类缓存 | 启动报 “Could not find type PlayerProfile” | 交付前必跑 `--import`；本次已跑且 0 错误 | 重新导入 |

**行为等价说明**：五条存档路径的对外结果不变；唯一“新增”是损坏/未来档会多出隔离副本文件，不改变任何读取结果。`save_version` 由 1 变 2 属于格式升级，旧版本客户端读新档会被旧逻辑当未来版本回退默认（不会崩溃）——因此**降级客户端不可再写盘覆盖**，这是升级的既有代价，已由 `save.future.bak` 兜底。

---

## 8. 后续（不在本轮）

1. `PlayerDino` 彻底去写盘：进化只发 `growth_changed`/`save_requested`，由 `Main` 合并写入（真正单写者）。
2. 写入时机补齐：定时自动存档、Android `NOTIFICATION_APPLICATION_PAUSED` 收尾。
3. `save.bak` 多代轮换与“从 .bak 自动恢复”（当前只隔离不自动恢复，避免把坏档误判成好档）。
4. 多槽位 / 云同步：`SaveRepository` 的路径与版本入口已集中，届时只需参数化路径，不动调用方。
