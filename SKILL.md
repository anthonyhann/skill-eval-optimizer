---
name: skill-eval-optimizer
description: "Skill 评估与自动优化工具（自主 skill 优化器，借鉴 Karpathy autoresearch 实验循环）：清单扫描 → verdict 分流 → 8 维度评分（结构+效果）→ hill-climbing + git 棘轮迭代优化 → 测试 prompt 实测验证 → 生成可视化成果卡片。触发词：优化skill、skill评分、自动优化、auto optimize、skill质量检查、skill-eval-optimizer、帮我改改skill、skill怎么样、提升skill质量、skill review、skill打分、skill健康状态。明确指令：/skill-eval-optimizer（直接触发本 skill，进入 Skill 评估流程）。NOT for: 评估非 skill 文件或替代单元测试/集成测试等工程质量保障手段。"
allowed-tools:
  - Read
  - Write
  - Edit
  - run_terminal_cmd
---

# Skill Eval Optimizer

> 核心流程：**清单 → 分流 → 评估 → 改进 → 实测验证 → 人类确认 → 保留或回滚 → 成果卡片**

## 设计哲学

1. **单一资产** — 每次只改一个目标 `SKILL.md`
2. **双重评估** — 结构评分 + 效果验证（不只规范审查，更看运行效果）
3. **棘轮** — 只保留改进，自动用 `git revert` 回滚退步，不用 `reset --hard`
4. **客观评分** — 效果分走 skill-up 确定性通道（pass_rate），结构分主 agent 按 Rubric 逐维打分
5. **人在回路** — 每步用户确认，不自主失控
6. **verdict 分流** — 先 verdict（Improve/Keep/Retire/Merge），再对 Improve 做 8 维量化评分与 hill-climbing；Retire/Merge 只记录归档，不进入优化循环

## 快速使用

| 场景 | 指令 | 行为 |
|------|------|------|
| 全量 | "评估所有 skills 的质量" | Full：Phase 0→0.5→1（不进入优化） |
| 单 skill 优化 | "优化 xxx skill" | 直接 Phase 0.7→1→2 |
| Quick Scan | "看看哪些 skill 变了" | 检测 results.json → 增量重评 |
| 只评估不改 | "给 skills 打分" | Phase 0.5→1 后结束 |
| 看历史 | "看看优化历史" | 读取 results.tsv 展示 |
| 健康诊断 | "skill 健康状态" / "skill 趋势" / "哪些 skill 在下降" | 只读健康面板，见 `references/health-panel.md` |

> 单 skill 优化同样受 git 棘轮保护：进入 Phase 2 前若未建分支，先初始化 `auto-optimize/YYYYMMDD-HHMM`（同 Phase 0）。

## 环境与路径

- **SKILL_ROOT**：本 `SKILL.md` 所在目录
- **结果快照**：`SKILL_ROOT/results.json`（.gitignore 忽略，仅本地），Quick Scan 基准
- **实验日志**：`SKILL_ROOT/results.tsv`，append-only 优化记录（项目仓库内提交共享，安装副本仅本地）
- **扫描范围**：`scripts/scan.sh` 合并 `~/.claude/skills` + `$PWD/.claude/skills`
- **依赖**：`bash` + `jq`（必须）；成果卡片需 Node + Playwright（可选）；维度 8 依赖 skill-up（preflight 与降级规则见 `references/skill-up.md`，维度 8 通道规则仅在该文件定义）

### Skill 名称解析（5 级）

用户用简称引用 skill（如"优化 ccg"）时按序解析到 `{dir}/SKILL.md`：

1. **目录名精确匹配**（大小写不敏感）
2. **frontmatter name 包含**：扫描 `name:` 字段
3. **description 关键词**：扫描 `description:` 字段
4. **路径前缀匹配**
5. **fallback**：列出候选让用户确认

### Resume（中断恢复）

若 `results.json` 的 `batch_progress.status` 为 `"in_progress"`，下次启动从**第一个尚未写入最终 verdict/score 的 skill** 继续中断的 Phase。完成后设为 `"completed"` 并再次调用 `save-results.sh`。

## 工作流

### Phase 0：Inventory

**输入** → scan.sh JSON（skills 列表）｜**处理** → 解析、初始化分支与日志｜**输出** → 分支 `auto-optimize/YYYYMMDD-HHMM` + results.tsv 表头

1. 执行 `bash SKILL_ROOT/scripts/scan.sh` 或只列出用户指定的 skill
2. 展示清单（path、name、use_7d、use_30d、mtime、description 摘要，模板见 `references/output-templates.md`）
3. 初始化分支与 results.tsv（不存在则写 9 列表头）；读取历史 results.tsv 摘要（如有）

环境变量：`SKILL_EVAL_OPTIMIZER_GLOBAL_DIR`、`SKILL_EVAL_OPTIMIZER_PROJECT_DIR`、`SKILL_EVAL_OPTIMIZER_OBSERVATIONS`（7d/30d 使用计数，缺省 0）。

### Phase 0.5：Triage

**输入** → skills 列表｜**处理** → 读 SKILL.md 做 5 项检查 → verdict｜**输出** → results.json 更新 + verdict 表 + 用户确认

5 项检查：

- [ ] 与其他 skill 内容重叠（步骤、触发语、整段复制）
- [ ] 与 MEMORY.md / CLAUDE.md 重叠（是否可被规则替代）
- [ ] 时效性：CLI 子命令/API/工具名用 WebSearch 验证
- [ ] 使用频率：参考 use_7d / use_30d
- [ ] **安全合规**：按 S002/S003/S004/S005 安全红线清单逐项检查（红线定义与评分标准见 `references/rubric.md`）

| Verdict | 含义 |
|---------|------|
| **Keep** | 质量可接受，不进入后续 |
| **Improve** | 值得保留且需优化 |
| **Update** | 技术引用过时，先改事实再评 |
| **Retire** | 低质/过时，记录后待用户确认删除 |
| **Merge into [X]** | 与另一 skill 重叠，不单独优化 |
| **🔴 Block** | 安全红线违规，禁止发布，必须先修复 |

**Reason/note 守则**（禁止空话）：Retire 须写具体缺陷+哪一文件已覆盖；Merge 须写目标 skill 名+迁入要点；Improve 须写哪节/哪类问题+建议方向；Keep 须说明核心保留价值；Block 须写明违规规则（S002/S003/S004/S005）+修复方向。

**用户确认**：展示 verdict 表（模板见 `references/output-templates.md`）后，用户选择 Improve+Update 子集进入 Phase 0.7。

### Phase 0.7：测试 Prompt 设计

**输入** → Improve verdict 的 skill 列表｜**处理** → 设计 prompt 并物化为 skill-up case｜**输出** → `{skill}/test-prompts.json` + 用户确认

1. 读 SKILL.md 理解用途与边界，设计 2-3 个测试 prompt（happy path + 一个略复杂场景）
2. 写入 `{skill}/test-prompts.json`（schema 见 `references/skill-up.md`）；已存在则询问复用/重写/追加
3. 物化为 skill-up eval 配置：把 prompts 转为 `{skill}/evals/cases/*.yaml` + 按「eval.yaml 规格」创建/更新 `{skill}/evals/eval.yaml`，使 Phase 1 维度 8 走确定性通道
4. 用户确认后进入 Phase 1

### Phase 1：基线评估

**输入** → test-prompts.json + SKILL.md｜**处理** → 维度 1-7 结构评分 → 维度 8 效果评分 → 算总分｜**输出** → results.tsv 基线行 + results.json 更新 + 评分卡

1. 读 SKILL.md 全文，按 `references/rubric.md` 逐维打 1-10 分附简短理由
2. 维度 8 按 `references/skill-up.md`「评分通道」执行：优先 skill-up 确定性通道（pass_rate × 10），不可用则 dry_run
3. 计算加权总分（保留 1 位小数），写入 results.tsv；合并到 results.json
4. 展示评分卡（模板见 `references/output-templates.md`），**暂停等用户确认**再进入 Phase 2

### Phase 2：优化循环（Hill-climbing）

**输入** → 基线结果 + test-prompts.json｜**处理** → 诊断 → 改进 → 重评 → 决策，最多 MAX_ROUNDS 轮（默认 3）｜**输出** → results.tsv 追加行 + results.json 更新 + 优化/回滚

```
按基线分数从低到高排序：
for each skill:
  round = 0
  while round < MAX_ROUNDS:
    round += 1
    1. 诊断最低维度：比较各维度分×权重后的加权占比差距，选 gap 最大的维度(权重优先)；若平局选 D5>D3>D8
    2. 方案：指出具体段落+改什么+对应 rubric + 预期提分
    3. 用 Read 读目标段落，Edit 精准替换模糊描述，每改后检查 Markdown 渲染连续，git add + commit
    4. 重评：维度 1-7 主 agent 逐维重打；维度 8 按 references/skill-up.md 评分通道执行
    5. if 新总分 > 旧总分 → keep, 更新基线
       else → git revert HEAD, 记录 revert, break
    6. results.tsv 追加行; results.json 更新
  每 skill 结束：展示 diff + 分数变化 → 用户确认

  ★ 回归锁：每 skill 优化保留后，按 references/skill-up.md「回归锁」规则生成 skill-up 回归 case 防回退
```

#### Round Gate（每轮确认）

每轮开始前展示：skill、最低维度、拟改段落（行号+原文+改后预览）、预期加分（旧分→新分+理由）。用户三选一：**继续本轮 / 跳过该 skill / 结束 Phase 2**。连续 2 次未响应默认暂停。涉及结构重排须再确认。Round 卡模板见 `references/output-templates.md`。

### Phase 2.5：探索性重写

当连续 2 个 skill 在 round 1 break 时，提议一次「整篇重组」：git stash 保存最优版 → 从头重写 SKILL.md（重组结构，非微调）→ 重评 → 重写版 > stash 版则采用，否则 `git stash pop` 恢复。**须用户明确同意后才执行。**

### Phase 3：汇总报告

输出：优化 skill 数、实验次数、保留/回滚次数、实测 vs 干跑次数；Before/After 表；主要改进点（模板见 `references/output-templates.md`）。为完成优化的 skill 生成成果卡片 PNG（见下节）。

## 检查点总览

| 阶段过渡 | 确认事项 | 形式 |
|---------|---------|------|
| Phase 0.5 → 0.7 | 用户选择 Improve 子集 | verdict 表 + 多选 |
| Phase 0.7 → 1 | 测试 prompt 是否合适 | 不存在则创建后确认；已存在则复用/重写/追加 |
| Phase 1 → 2 | 是否进入优化 | 评分卡 + 确认/拒绝 |
| Phase 2 每轮前 | Round Gate | 继续/跳过/结束 三选一 |
| Phase 2 每 skill 后 | 展示 diff + 分数 | 确认 OK / 回滚 |
| Phase 2.5 触发 | 是否执行重写 | 用户明确同意 |

## 优化策略库

按优先级，每轮只攻一项。

### P0：安全红线（最高优先级）

- 内网地址暴露（S002）→ 移除或替换为环境变量。*before: `ssh user@<内网IP>` → after: `ssh ${JUMP_HOST}`*
- 数据库连接串暴露（S003）→ 封装为 CLI 工具。*before: `mysql -h <内网域名> -P <端口>` → after: `doris-cli`*
- 破坏性操作无防护（S004）→ 补充安全声明。*before: "执行 DELETE FROM" → after: "❗ 禁止执行 DELETE/DROP/TRUNCATE"*
- 远程访问 Harness 违规（S005）→ 创建 `.env.example` + 添加环境分级 + 引用 Harness 规则。*before: "自动发现本机 SSH 配置获取主机" → after: "从 .env 读取 SSH_HOST，禁止自动发现本地 SSH 配置"*
- 缺少操作级别声明（W008）→ 添加安全约束章节 + 操作级别表。*before: 直接 `ssh $host` 无声明 → after: "## 安全约束" + L1/L2/L3 操作级别表 + 确认机制*（⚠️ 仅适用于实际执行远程操作的 skill，知识库/模板/脚手架类跳过，判定见 `references/rubric.md` 排除项）
- 敏感数据无脱敏（W007）→ 补充脱敏规则。*before: "查询手机号" → after: "查询手机号（中间 4 位用 * 替代）"*

### P0.5：效果问题

- 输出偏离意图 → 检查误导性步骤。*before: "处理图片" → after: "用 ImageMagick `convert -resize 800x600`"*
- 带 skill 弱于 baseline → 精简约束。*before: 5 段约束 → after: 保留 2 条核心*
- 格式不符预期 → 补充输出模板

### P1：结构性问题

- Frontmatter 缺触发词 → 补充中英文
- 缺 Phase 结构 → `### Phase N：标题` + 有序列表
- 缺检查点 → 插入 `**等用户确认**`

### P2：具体性与异常

- 模糊动词 → 具体参数和命令
- 缺 I/O 规格 → 补充格式、路径、示例
- 缺「若失败则…」→ 每步补充 fallback

### P3：可读性

- 段落 >15 行 → 拆分表格或列表
- 概念重复 ≥3 次 → 去重
- 缺 TL;DR → 长章节前加摘要

## 异常与边界条件

| 场景 | 触发 | 处理 |
|------|------|------|
| 缺少 jq | 脚本失败 | 提示安装后重试 |
| results.json 损坏 | jq 无法解析 | 备份 `.bak.时间戳` 后重建或 git 恢复 |
| evaluated_at 非法 | quick-diff 报错 | 修成 UTC ISO 或删文件走 Full |
| 不在 git 仓库 | `git rev-parse` 失败 | 建议 git init；否则文件备份手动回滚 |
| results.tsv 缺失/损坏 | — | 建表头或备份后重建 |
| 分支重名 | checkout -b 失败 | 加 `-2`/`-3` |
| git revert 失败 | 冲突/脏工作区 | `git stash` 后重试；否则手动恢复 |
| MAX_ROUNDS 触顶 | round=3 仍短板 | 问加轮 / Phase 2.5 / 结束 |
| 优化后超体积 | > 原 × 1.5 | 拒绝提交，先精简 |
| 无 SKILL.md | 目录存在但缺 | results.tsv 记 error，跳过 |
| Resume | batch_progress=in_progress | 从断点续跑 |
| skill-up 超时/失败 | `skill-up run` 无响应或报错 | 维度 8 降级 dry_run（降级条件与 `blocked_by` 取值见 `references/skill-up.md`） |
| 评测 CLI 通道失效 | 评测输出 "Not logged in" / case 批量 FAIL | 环境层(layer=env)：默认通道 `claude` CLI（需 OAuth 登录，交互终端执行 `claude /login`）；可用 `SKILLUP_CLAUDE_CMD` 切换到其他 claude 兼容 CLI；wrapper（`evals/scripts/run-claude.sh`）已内置预检+中途拦截，命中即 ERROR 不进 pass_rate；修复前维度 8 降级 dry_run，`blocked_by=claude_auth_expired` |

**失败分流顺序**：环境层 → 数据层 → 流程层 → 运行时层 → 评测层。每失败在 note 记 `layer=...`（env/data/flow/runtime/eval）、`cause=...`、`action=...`。

## 约束规则

1. 不改 skill 核心用途
2. 不引入新依赖
3. 每轮只改一个维度
4. 优化后 ≤ 原始 × 1.5
5. 中文为主，简洁为上
6. 用 git revert，不用 reset --hard；评分独立（维度 8 通道与 `dim8_channel` 见设计哲学 4 与 `references/skill-up.md`）

## 数据格式

### results.json 快照

```json
{
  "evaluated_at": "2026-04-27T10:00:00Z",
  "mode": "full",
  "batch_progress": { "total": 40, "evaluated": 40, "status": "completed" },
  "skills": {
    "some-skill": {
      "path": "~/.claude/skills/some-skill/SKILL.md",
      "verdict": "Improve",
      "reason": "工作流清晰但维度5指令偏泛；use_7d=3。",
      "mtime": "2026-04-20T08:30:00Z",
      "score": 78.5,
      "dimensions": { "1": 8, "2": 7, "8": 7 },
      "dim8_channel": "deterministic",
      "pass_rate": 0.83,
      "regression_locked": true
    }
  }
}
```

`dim8_channel`/`pass_rate`/`regression_locked` 语义与 CI 门禁见 `references/skill-up.md`「CI 字段」。

写入用 `bash SKILL_ROOT/scripts/save-results.sh RESULTS_JSON <<< "$EVAL_JSON"`（浅合并每 skill，自动设 UTC `evaluated_at`）。

### results.tsv 实验日志

```tsv
timestamp	commit	skill	old_score	new_score	status	dimension	note	eval_mode
2026-04-27T10:00	baseline	some-skill	-	78.0	baseline	-	初始基线	full_test
2026-04-27T10:05	a1b2c3d	some-skill	78.0	84.0	keep	边界条件	补充fallback	dry_run
```

## 成果卡片生成

每个 skill 优化完成后生成单 skill 卡片（`SKILL_ROOT/templates/card-{skill-name}.png`）；Phase 3 全部完成后生成总览卡片（`card-overview.png`）。

1. 复制 `templates/result-card.html` 到临时工作文件，替换占位数据（data-field 对应 skill 名、分数、8 维 dim-bar 宽度、改进摘要、日期）
2. 随机选择主题：URL hash 设为 `swiss`/`terminal`/`newspaper` 之一
3. 截图：`node SKILL_ROOT/scripts/screenshot.mjs /abs/path/to/card.html /abs/path/to/out.png`（2x 高清，只截 .card 元素，自动 open）
4. 回退：`npx playwright screenshot "file:///path/to/card.html#[theme]" out.png --viewport-size=960,1280 --wait-for-timeout=2000`
5. 提示用户查看 PNG

`PLAYWRIGHT_PATH` 环境变量可指定 playwright-core 安装位置。

## 资源速查

| 路径 | 用途 |
|------|------|
| `references/rubric.md` | 8 维度 Rubric + 安全子项 + Harness 合规 + ES 类特殊处理 |
| `references/skill-up.md` | skill-up 依赖/评分通道/回归锁/test-prompts schema/CI 字段 |
| `references/output-templates.md` | 各 Phase 输出模板 |
| `references/health-panel.md` | 健康面板格式 + 快速诊断入口工作流 |
| `scripts/scan.sh` | 清单 + frontmatter + mtime + 7d/30d 使用估计 |
| `scripts/quick-diff.sh` | 相对 evaluated_at 的变更/新增 md 列表 |
| `scripts/save-results.sh` | 合并 results.json（浅合并 + UTC 时间） |
| `scripts/screenshot.mjs` | 卡片 PNG（可选依赖 Playwright） |
| `templates/result-card.html` | 三主题卡片 HTML |
| `evals/` | skill-up 评测配置与回归 case（规格见 `references/skill-up.md`）；`evals/fixtures/judge-rubric/` 为 agent_judge 评分 fixture（8 维表派生自 `references/rubric.md`，修改须同步） |
| `evals/scripts/run-claude.sh` | 评测引擎 wrapper 权威副本：认证预检（缓存 5min）+ 中途失效拦截（ERROR 而非 FAIL）+ 网关 400 退避；各 skill 的 evals 复制到自身 `evals/scripts/` 使用 |
| `{skill}/test-prompts.json` | 维度 8 测试用 |

## 设计灵感

> "You write the goals and constraints in program.md; let an agent generate and test code deltas indefinitely; keep only what measurably improves the objective."
> — Karpathy, autoresearch
> 映射：本文件 ≈ program.md，`SKILL.md` ≈ train.py，8 维总分 ≈ val，git 棘轮 ≈ keep/revert
