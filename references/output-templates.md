# 输出模板（各 Phase 展示格式，唯一权威定义）

> `{xxx}` 为占位符。所有 Phase 的用户可见输出均按本文件模板渲染，SKILL.md 工作流不再内嵌模板。

## Phase 0：Inventory

```
## Inventory ({total} skills)
| # | Skill | Path | mtime | Description |
|---|-------|------|-------|-------------|
| 1 | {name} | {short_path} | {mtime} | {desc_50} |
```

## Phase 0.5：Triage

```
## Triage: {skill_name}
- Overlap: {与X重叠/无}
- Rule overlap: {与CLAUDE.md重叠/无}
- Timeliness: {工具名验证: 正常/过时}
- Usage: {use_7d}/{use_30d}
- Security: {S002/S003/S004/S005 检查结果: 通过/违规项}
- Harness: {涉及远程访问→合规/缺失.env/缺失环境分级/缺失操作级别声明 | 不涉及→N/A}
**Verdict**: {Improve/Keep/Retire/Merge/Block}
**Reason**: {具体缺陷+改进方向}
```

## Phase 1：Evaluation 评分卡

> 维度行必须保留 `D{n}` 维度标记（列表或表格形式均可，如 `D1 Frontmatter` 或表列含 `D1`），总分以 `/100` 呈现。

```
## Evaluation: {skill_name}
### 结构维度
- D1 Frontmatter: {x}/10 — {理由}
- D2 工作流清晰度: {x}/10 — {理由}
- D3 边界条件: {x}/10 — {理由}
- D4 检查点: {x}/10 — {理由}
- D5 指令具体性: {x}/10 — {理由}
- D6 资源整合度: {x}/10 — {理由}
### 效果维度
- D7 整体架构: {x}/10 — {理由}
- D8 实测表现: {x}/10 — {eval_mode}
### 总分
**Score**: {weighted}/100
### 短板分析
- 结构短板: {最低维度}
- 效果短板: {测试prompt}/{baseline表现}
```

基线批量汇总评分卡：

```
| Skill | Score | 结构短板 | 效果短板 |
|-------|-------|---------|----------|
| proofreading | 78 | 边界条件 | 测试prompt2 |
| slides-gen | 72 | 指令具体性 | baseline持平 |
| **平均** | **75** | | |
```

## Phase 2：Round 卡

```
## Round {N}: {skill_name}
### 诊断
- 目标维度: D{dim} — {维度名}
- 具体问题: {段落+问题描述}
- 改进方案: {改什么+如何改}
- 预期加分: {old} → {new}（{理由}）
### 编辑操作
- 文件: {SKILL.md 路径}
- 改动: {行号范围 + 摘要}
- Commit: {commit_hash}
### 重评结果
- New Score: {new_score}
- D{dim}变化: {old_dim} → {new_dim}
- Verdict: **{keep|revert}**
- 评估模式: {full_test|dry_run}
```

## Phase 3：优化报告

```
## 优化报告

### 总览
- 优化skills数：N
- 总实验次数：M
- 保留改进：X（Y%）
- 回滚次数：Z
- 实测验证：A次完整测试 / B次干跑

### 分数变化
| Skill | Before | After | Δ |
|-------|--------|-------|---|
| proofreading | 78 | 87 | +9 |
| slides-gen | 72 | 83 | +11 |
| **平均** | **75** | **85** | **+10** |

### 主要改进
1. [skill-A] 补充了边界条件处理，测试输出质量提升明显
2. [skill-B] 重组了workflow结构，baseline对比优势增大
```

## 健康面板

见 `health-panel.md`（三段格式：成功率趋势 / 失败模式聚类 / 版本历史摘要）。

