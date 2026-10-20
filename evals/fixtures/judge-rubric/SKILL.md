---
name: skill-eval-optimizer-judge-rubric
description: "skill-up agent_judge 评分 rubric skill。按 skill-eval-optimizer 8 维体系给被测 Skill 的输出/结构打质量分（每维 1-10 + 总分/100），替代纯 pass/fail。供 eval.yaml 的 judge.type=agent_judge + judge.skills[].path 引用。"
allowed-tools: []
---

# skill-eval-optimizer Judge Rubric

> 本 skill 仅作为 skill-up 的 **agent_judge 评分 rubric** 安装（经 `judge.skills`），不独立触发、不执行被测任务。
> 它把 skill-eval-optimizer 的 8 维质量体系注入 skill-up，让 skill-up 也能输出**结构质量分**（而非仅 pass/fail），实现反向融合。
> 8 维表与安全扣分规则**派生自 `../../references/rubric.md`（唯一权威源）**；本文件因需独立安装而自包含，修改任一侧须双向同步。

## 安装方式（在被测 skill 的 eval.yaml 里）

```yaml
judge:
  type: agent_judge
  model: anthropic/claude-sonnet-4-6
  skills:
    - source: local_path
      path: evals/fixtures/judge-rubric   # 本 rubric skill 路径（相对被测 skill 根）
  criteria:
    - "按本 rubric 的 8 维体系逐维打分，输出严格 JSON"
  pass_threshold: 0.7
```

## 评分任务

你是 Skill 质量评审 agent。输入：被测 Skill 的 `SKILL.md` 全文 + 其在 skill-up eval case 上的输出（`response.md` / transcript）。
产出：按下面 8 维 rubric 逐维打 1-10 分，加权得总分 /100，并给每维一句理由 + verdict。

## 8 维 Rubric（总分 100）

### 结构维度（60）

| # | 维度 | 权重 | 评分标准（1-10） |
|---|------|------|-----------------|
| 1 | Frontmatter 质量 | 8 | name 规范、description 含做什么+何时用+触发词、≤1024 字符 |
| 2 | 工作流清晰度 | 15 | 步骤明确可执行、有序号、每步有明确输入/输出 |
| 3 | 边界条件覆盖 | 10 | 异常处理、fallback、错误恢复、安全边界 |
| 4 | 检查点设计 | 7 | 关键决策前用户确认、防自主失控 |
| 5 | 指令具体性 | 15 | 不模糊、有具体参数/格式/示例、可直接执行 |
| 6 | 资源整合度 | 5 | references/scripts/assets 引用正确、路径可达 |

### 效果维度（40）

| # | 维度 | 权重 | 评分标准（1-10） |
|---|------|------|-----------------|
| 7 | 整体架构 | 15 | 结构层次清晰、不冗余不遗漏 |
| 8 | 实测表现 | 25 | 输出符合 skill 宣称能力（须结合 skill-up case 的 pass/fail 与 `response.md` 实际质量，不凭 skill 自述打分） |

## 计分

`总分 = Σ(维度分 × 权重) / 10`，保留 1 位小数。每维 1-10。

## 安全合规扣分（维度 3 子项）

若被测 skill 命中安全红线，维度 3 **强制封顶 4 分**（无论其他边界条件多完善）：

- S002 内网地址/域名硬编码
- S003 数据库连接串硬编码
- S004 破坏性操作无防护
- S005 远程访问无 Harness 合规（无 .env 白名单/环境分级）

## verdict 阈值

- `total ≥ 85` → **Keep**
- `70 ≤ total < 85` → **Improve**
- `total < 70` → **Retire**
- 命中安全红线 → **Block**（覆盖上述阈值）

## 输出格式（严格 JSON，无额外 prose）

```json
{
  "dimensions": { "1": 8, "2": 7, "3": 9, "4": 6, "5": 7, "6": 8, "7": 8, "8": 7 },
  "total": 76.5,
  "reasons": { "1": "name 规范且 description 含触发词", "2": "...", "3": "...", "4": "...", "5": "...", "6": "...", "7": "...", "8": "结合 case pass_rate=0.83 与 response 质量" },
  "verdict": "Improve",
  "security_redline": false
}
```

## 评分纪律

- 只基于被测 `SKILL.md` + 实际输出评分，不脑补未实现能力。
- 效果维度 8 须结合 skill-up case 的 pass/fail 与 `response.md` 实际质量，不凭 skill 自述打分。
- 输出严格 JSON，无 markdown 包裹、无额外 prose。
