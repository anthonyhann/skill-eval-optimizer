# skill-up 效果评分与回归锁（唯一权威定义）

> 维度 8（实测表现）的全部评分机制。效果分一律用 skill-up 客观 pass_rate，**替代主观子 agent 对比**（消除 LLM 评分波动与子 agent 成本）。本文是 full_test/dry_run、评分通道、回归锁、CI 字段的唯一定义处。

## 依赖与安装（preflight）

维度 8 客观效果分依赖 skill-up。使用前必须执行 preflight（未装则自动安装，安装失败才降级）：

```bash
# 1. 检查是否已安装
command -v skill-up >/dev/null && skill-up --version || {
  # 2. 未安装则执行官方安装（macOS/Linux）
  curl -fsSL https://raw.githubusercontent.com/alibaba/skill-up/main/install.sh | bash
}
# 3. 安装后再验证一次，确认可用
command -v skill-up >/dev/null && skill-up --version
# 4. 评测 CLI 通道认证预检（引擎依赖 claude 兼容 CLI；通道失效会烧完全部 case 产出伪 FAIL）
#    默认通道: claude（Claude Code CLI，需 OAuth 登录：claude /login）
#    如需切换到其他 claude 兼容 CLI: SKILLUP_CLAUDE_CMD="your-cli"
claude --settings '{"disableAllHooks":true}' -p 'ping' 2>&1 | grep -qE 'Not logged in|authentication_failed' \
  && echo "claude 通道失效：交互终端执行 claude /login" \
  || echo "claude 通道正常"
```

- 官方文档：https://github.com/alibaba/skill-up/blob/main/README.zh.md
- **降级条件（仅当）**：安装执行后仍不可用（安装失败 / 网络不通 / 平台不支持 Windows）时，维度 8 才降级 dry_run（结构维度 1-7 不受影响，但效果分不可复现、无 CI 门禁，记 `blocked_by=skill_up_install_failed`）。未装时**先安装、不直接降级**。
- **评测 CLI 通道失效（`blocked_by=claude_auth_expired`）**：默认通道 `claude` CLI（需 OAuth 登录）；可用 `SKILLUP_CLAUDE_CMD` 切换到其他 claude 兼容 CLI（如内部代理 CLI）。通道故障两类：
  - **claude 通道**（默认）：认证中途失效时，CLI 以 exit 0 返回 "Not logged in" 合成消息——若不防护会被 judge 当作模型回复判成 case FAIL，把环境故障伪装成能力缺陷。处理：交互终端执行 `claude /login`；wrapper（`evals/scripts/run-claude.sh`，各 skill 的 evals 应复制到自己 `evals/scripts/` 下）已内置启动预检（CLI 存在 + 轻量探测，缓存 5 分钟）、中途签名拦截、网关 400/api_error 重试 8 次，以及评测纯净模式（默认不加载用户全局 MCP——全局 MCP pending 会把单次调用拖到 20-30s+ 甚至撑爆 case 超时；`SKILLUP_KEEP_MCP=1` 可保留）
  - **自定义通道**（可选，`SKILLUP_CLAUDE_CMD` 切换）：任何 claude 兼容 CLI，预检/拦截逻辑同上；若走自定义代理网关，可用 `SKILLUP_ANTHROPIC_BASE_URL` 做会话级基址锁定
  - 命中后 wrapper 非零退出 → skill-up 记 **ERROR（环境故障，不进 pass_rate）**而非 FAIL；修复后重跑
  - **判定纪律：环境层故障（通道失效/网关 400 击穿重试/CLI 缺失）导致的 case 结果一律视为 ERROR，不得计入 pass_rate 分母作为 skill 质量信号**；只有模型真实回复不满足断言才是 FAIL

## 评分通道（按优先级取其一）

1. **skill-up 确定性通道（唯一效果分来源）**：前置——skill-up 已安装（见上节 preflight）且 `{skill}/evals/eval.yaml` 存在。执行 `skill-up run {skill}/evals/eval.yaml`，取 `result.json` 的 `pass_rate`（0-1）映射维度 8 分：`round(pass_rate × 10, 1)`。同输入同结果，可复现、CI 友好。记 `dim8_channel=deterministic`、`eval_mode=full_test`。
2. **dry_run（兜底）**：skill-up 安装失败（preflight 后仍不可用）、eval.yaml 不存在（首次评估尚未生成 case）、skill-up 运行超时/失败、或评测 CLI 通道失效（重新登录前无法实测）时：
   - 对 test-prompts.json 每个 prompt 做代码路径可达性分析：skill 中是否包含处理该场景的明确步骤链
   - 完整可执行（step A→B→C 均可达）→ 8-10；部分路径模糊（缺 1-2 步具体指令）→ 5-7；缺处理路径或指引矛盾 → 1-4
   - note 注明 `blocked_by=skill_up_install_failed|no_eval_yaml|skill_up_failed|claude_auth_expired` 和 `dry_run_rationale`。记 `dim8_channel=dry_run`、`eval_mode=dry_run`。

**full_test 条件**：维度 8 走 skill-up 确定性通道（skill-up 已安装 + eval.yaml 存在 + 至少 1 个 case 产出 pass_rate）。否则降级为 `dry_run`。

> 不要因为跑不了 skill-up 就跳过维度 8——哪怕是 dry_run 模拟推演也比完全不看效果好。

## test-prompts.json schema

test-prompts.json 是 skill-up case 的设计源（物化时机与流程由 SKILL.md Phase 0.7/2 定义）：

```json
{
  "skill": "<slug>",
  "prompts": [
    {
      "id": "happy-1",
      "prompt": "单轮 happy path 文本",
      "expect": { "must_contain": ["关键词"], "must_not_contain": ["禁忌词"] },
      "judge": { "type": "rule_based", "contains_any": ["拒绝/路由措辞"] }
    },
    {
      "id": "reject-pivot",
      "turns": [
        { "role": "user", "content": "第1轮强触发词加载 skill", "post_condition": { "must_contain_any": ["场景"], "on_fail": "fail" } },
        { "role": "user", "content": "第2轮 pivot 到越界意图" }
      ],
      "judge": { "type": "rule_based", "turn": 2, "contains_any": ["拒绝措辞"] }
    }
  ]
}
```

- `turns`（可选）：多轮，测"加载后 pivot 越界是否守护栏"等时序行为（route_reject / 意图 pivot 类护栏必用多轮，单轮无法强匹配触发词加载 skill）。
- `expect`（可选）：零成本前置过滤，不过则该 prompt 直接 0 分，避免子 agent 白跑。
- `judge.rule_based`（可选）：确定性关键词判定，优先于 LLM 评审；reject 类用例**优先 success-only**，failure 模式勿取用户原话（拒绝输出会回引被拒意图，造成伪 FAIL）。
- **prompt 纪律**：评测 prompt 须要求「最终回复一次性包含完整输出，不要只给摘要」——judge 只评估最后一条 assistant 消息，明细放中间消息会误判 FAIL。
- **锚点纪律**：judge 锚点勿取单一字面量（如仅 `D1`），用兼容正则覆盖多种合规呈现（`D1` 标记 / `维度 1` / 表格列），防止输出形式重排导致伪 FAIL；fixture 强度须与期望 verdict 区间明确匹配（模糊到 Retire 级的样本不应期望 Improve）。

## eval.yaml 规格（唯一定义）

创建 `{skill}/evals/eval.yaml`：`engine=claude_code, environment=none, skills.path=.`。已存在则把新 case 追加进 `cases.files[]`。

## 回归锁（Phase 2 优化保留后执行）

每 skill 优化保留后，针对本轮所改维度生成 skill-up 回归 case，把改进锁住防回退：

- 改进的是"行为可断言"维度（拒绝护栏 / 路由分流 / 输出格式 / 边界处理）→ 生成 `{skill}/evals/cases/<dim>-<short>.yaml`
- 多轮护栏类（route_reject / 意图 pivot）用 `input.turns` + 按轮 `turn_response_contains`；单轮行为类用 `input.prompt` + `output_contains`
- judge 一律 `rule_based`（确定性），优先 success-only；failure 模式只能取被禁交付物实体，不得取用户原话
- 按「eval.yaml 规格」创建或追加 case 文件
- 置 `regression_locked=true` 写入 results.json；后续 CI 跑 `skill-up run {skill}/evals/eval.yaml`，pass_rate 回退即告警
- 生成前展示 case 草案（prompt + expect + judge）等用户确认，不自动落盘未审 case
- 纯结构维度改进（D1 frontmatter / D5 指令具体性 / D6 资源整合度等，无行为可断言）不生成行为 case，改用 results.json 总分/pass_rate 前后比对做软回归：本轮 new_score 写入后，下次评估总分/pass_rate 回退即告警（无 case 硬锁，仅趋势守护）

## CI 字段（供 CI / 外部工具消费）

- `dim8_channel`：维度 8 取分通道 `deterministic | dry_run`
- `pass_rate`：skill-up pass_rate（0-1），仅确定性通道填写，否则 null
- `regression_locked`：是否已为该 skill 生成 skill-up 回归 case（bool）

> CI 门禁：流水线跑 `skill-up run {skill}/evals/eval.yaml`，取 pass_rate 与 results.json 记录值比对；低于阈值或回退即阻断该 skill 发布。

