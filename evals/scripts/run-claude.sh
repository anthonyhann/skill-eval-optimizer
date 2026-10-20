#!/bin/bash
# skill-up custom engine wrapper — 通过 claude 兼容 CLI（默认 claude）调用大模型，
# 规避两类已知问题。
#
# 用法（由 eval.yaml engine.custom.local 驱动）：
#   run-claude.sh <input_file>
# 输入：SessionInput JSON（messages 为完整对话历史）
# 输出：最终回复文本输出到 stdout（response_format: text）
#
# ─── CLI 通道选择 ──────────────────────────────────────────────────────────
# 默认: claude —— Claude Code CLI，需 OAuth 登录（交互终端执行 claude /login）。
# 覆盖: SKILLUP_CLAUDE_CMD 环境变量，可切到任何 claude 兼容 CLI，
#       如 SKILLUP_CLAUDE_CMD="claude"（默认值）或你的内部代理 CLI。
#
# ─── 已规避的问题 ──────────────────────────────────────────────────────────
# 1) --session-id 400：内置 claude_code 引擎固定传 --session-id，某些 API 网关
#    对该参数间歇性返回 400；本 wrapper 不带该参数，
#    并对「API Error: 400」做最多 8 次退避重试。
# 2) 认证失效伪装成 FAIL：认证失效时 CLI 以 exit 0 返回合成
#    消息 "Not logged in · Please run /login"（stream-json 中
#    error=authentication_failed），若不拦截会被 judge 当作模型回复判成 case
#    FAIL，把环境故障伪装成能力缺陷，污染 pass_rate。防护：
#    - 启动预检：跑 case 前轻量探测（结果缓存 5 分钟），失效 fail-fast
#    - 中途拦截：每次运行后检测认证失败签名，命中即非零退出 → skill-up 记
#      ERROR（环境故障，不进 pass_rate）而非 FAIL（能力缺陷）
#
# 输出聚合：--output-format stream-json 捕获**全部** assistant 文本消息并按序
# 拼接（jq select(.type=="assistant") 只提取 assistant 行，CLI 的版本检查噪音
# 等非 JSON 输出自动被过滤）。
#
# 修复指引（认证/通道故障，环境层 layer=env）：
#   - 交互终端执行 claude /login（或你所用 CLI 的登录命令）
#   - 登录/修复前如需记录评分，维度 8 按 references/skill-up.md 降级 dry_run，
#     note 记 blocked_by=claude_auth_expired
#
# 限制：单轮用例（当前加载 case 均为单轮）；多轮 turns 用例会把历史拼接为单轮。
#
# ─── 被测 skill 确定性注入 ─────────────────────────────────────────────────
# 问题：skill-up 只把被测 skill staging 到 workspace 根目录（SKILL.md +
# references/），但 agent 不会自动加载项目根目录的裸 SKILL.md；
# 模型是否加载 skill 全凭其自发调用全局 skills 目录里的副本——
# ① 非确定性（同批次 case 有的真正加载，有的声明"无可调用的 Skill 工具"后
#   自由发挥伪 FAIL）；② 版本偏斜（命中时测的是全局安装副本，非 workspace
#   里被测版本）；③ 全局其他 skill 会竞争触发词导致劫持。
# 修复：从 SessionInput 读 .workspace，定位根目录 SKILL.md，经
# --append-system-prompt-file 确定性注入（probe 与 run 同参，保证探测与
# 真实调用环境一致）。找不到 SKILL.md 时行为不变（向后兼容）。
set -uo pipefail

IN="$1"
[[ "$IN" != /* ]] && IN="$PWD/$IN"   # 相对路径基于 workspace（skill-up 以 cwd=${workspace} 执行）

# 定位被测 skill：优先 SessionInput 的 workspace 字段，fallback 当前目录
WORKSPACE_DIR=$(jq -r '.workspace // empty' "$IN" 2>/dev/null)
SKILL_MD=""
for _c in "${WORKSPACE_DIR:-}/SKILL.md" "$PWD/SKILL.md"; do
  [[ -n "$_c" && -f "$_c" ]] && { SKILL_MD="$_c"; break; }
done

PROMPT=$(jq -r '
  .messages
  | map(select(.role == "user"))
  | map(.content | if type == "array" then (map(.text // "") | join("")) else . end)
  | join("\n\n")
' "$IN")

# 被测 skill 注入：把 staging 的 SKILL.md 追加到 system prompt（确定性加载，
# 测的就是 workspace 里这份，消除全局副本版本偏斜与加载方差）
SYSPROMPT_FILE=""
SYSPROMPT_FLAGS=()
if [[ -n "$SKILL_MD" ]]; then
  SYSPROMPT_FILE="${TMPDIR:-/tmp}/skill-up-sysprompt.$UID.$$.md"
  {
    echo "你正在参与 skill 评测。下面是本次任务的唯一权威工作流定义（被测 skill 的完整 SKILL.md，位于当前工作目录）。"
    echo "无论该 skill 是否出现在你的 Skill 工具列表中，你都必须严格按其路由、步骤、约束与输出要求执行；"
    echo "不要转用其他 skill 或自由发挥。需要读 references/ 下的分册时，基于当前工作目录相对路径读取。"
    echo "若任务属于该 skill 声明的 NOT for 边界，则按其分流指示明确拒单/转交。"
    echo ""
    cat "$SKILL_MD"
  } > "$SYSPROMPT_FILE"
  SYSPROMPT_FLAGS=(--append-system-prompt-file "$SYSPROMPT_FILE")
fi
trap '[[ -n "$SYSPROMPT_FILE" ]] && rm -f "$SYSPROMPT_FILE" 2>/dev/null' EXIT

# CLI 通道（默认 claude；SKILLUP_CLAUDE_CMD 可覆盖为任何 claude 兼容 CLI）
read -r -a CLI <<< "${SKILLUP_CLAUDE_CMD:-claude}"

# 评测纯净模式：默认 --strict-mcp-config + 空 mcpServers，不加载用户全局 MCP/
# 插件服务（实测禁用后单次调用从 20-30s+ 降到 ~7s；全局 MCP pending 会拖慢甚至
# 撑爆 case 超时，且引入与被测 skill 无关的变量）。被测 skill 只依赖
# Read/Bash 等内建工具；若某评测确实要 MCP，设 SKILLUP_KEEP_MCP=1 跳过禁用
MCP_FLAGS=(--strict-mcp-config --mcp-config '{"mcpServers":{}}')
if [[ "${SKILLUP_KEEP_MCP:-0}" == "1" ]]; then
  MCP_FLAGS=()
fi

# 评测通道基址保护：全局 ~/.claude/settings.json 可能被其他工具改写
# ANTHROPIC_BASE_URL 后不可用（403 Request not allowed 伪认证故障）。
# 如需会话级锁定基址，设 SKILLUP_ANTHROPIC_BASE_URL（如内部代理网关）；
# 不设置则跟随用户全局/默认配置，本 wrapper 不动用户全局文件。
SETTINGS_JSON='{"disableAllHooks":true}'
if [[ -n "${SKILLUP_ANTHROPIC_BASE_URL:-}" ]]; then
  SETTINGS_JSON="{\"disableAllHooks\":true,\"env\":{\"ANTHROPIC_BASE_URL\":\"${SKILLUP_ANTHROPIC_BASE_URL}\"}}"
fi

run_once() {
  "${CLI[@]}" --settings "$SETTINGS_JSON" ${MCP_FLAGS[@]+"${MCP_FLAGS[@]}"} ${SYSPROMPT_FLAGS[@]+"${SYSPROMPT_FLAGS[@]}"} \
    -p --permission-mode=bypassPermissions \
    --output-format stream-json --verbose "$PROMPT" 2>&1
}

# 拼接全部 assistant 文本块；无 assistant 文本时输出为空。
# 用 -R fromjson? 逐行安全解析：CLI 首行可能输出版本检查噪音（非 JSON），
# 普通 jq 遇到会 parse error 立即退出并丢弃后续合法行（曾致 case
# 整批伪 FAIL/ERROR）；fromjson? 对非法行返回 empty 静默跳过
extract() {
  jq -R -r 'fromjson? | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null
}

# ─── 认证/通道失效检测 ──────────────────────────────────────────────────────
# 签名（按可靠性排序）：
#   1. stream-json 事件里的 "error":"authentication_failed"
#   2. 合成回复同时含 "Not logged in" 与 "Please run /login"
#   3. 通道不可用：CLI 未安装 / 代理连接被拒（connection refused）
# （单看自然语言签名可能与 prompt/回复内容误撞，故要求双签名或 JSON 级签名）
is_auth_failure() {
  local raw="$1"
  if printf '%s' "$raw" | grep -q '"error":"authentication_failed"'; then
    return 0
  fi
  if printf '%s' "$raw" | grep -q 'Not logged in' && printf '%s' "$raw" | grep -q 'Please run /login'; then
    return 0
  fi
  # 4. 认证被拒：网关 403 Request not allowed（如 BASE_URL 被改到无授权路由）
  if printf '%s' "$raw" | grep -q 'Failed to authenticate'; then
    return 0
  fi
  # 5. 上游账号会话过期/额度耗尽：401 登录未授权 / 402 Credit 已耗尽（环境层）
  if printf '%s' "$raw" | grep -qE '登录未授权|请先登录|Credit已耗尽|Credit 已耗尽'; then
    return 0
  fi
  return 1
}

auth_fail_msg() {
  cat >&2 <<MSG
错误: 评测 CLI 通道认证失效（Not logged in / authentication_failed / 通道不可用）。
当前通道: ${CLI[*]}（可用 SKILLUP_CLAUDE_CMD 覆盖）
这是环境层(layer=env)故障，不是被测 skill 的能力缺陷：
  - 交互终端执行 claude /login（或你所用 CLI 的登录/修复命令）
  修复后重跑: skill-up run <eval.yaml>
  修复前如需记录评分，维度 8 降级 dry_run，note 记 blocked_by=claude_auth_expired
MSG
}

# ─── 启动预检（结果缓存 5 分钟）─────────────────────────────────────────────
# 预检价值：通道已失效时 fail-fast，避免烧完 N 个 case 才发现全是伪 FAIL；
# 缓存价值：一次评测通常跑多个 case（每次都调本 wrapper），并行评测也会并发调用，
# 5 分钟缓存把探测开销收敛到每个评测批次约 1 次。
# 时效判断：把探测时间戳写进缓存文件**内容**（不用 stat 查 mtime——macOS BSD
# stat 与 GNU stat 的 -f 语义冲突，非数字输出进入算术展开会被当变量名解引用，
# set -u 下报 "unbound variable" 致预检崩溃，case 批量空输出伪 FAIL）
# 注意：预检通过不代表中途不会失效（认证可能中途过期/代理中途挂掉），中途拦截兜底。
AUTH_CACHE="${TMPDIR:-/tmp}/skill-up-claude-auth.$UID"

auth_probe() {
  local now cached
  now=$(date +%s)
  if [[ -f "$AUTH_CACHE" ]]; then
    cached=$(cat "$AUTH_CACHE" 2>/dev/null)
    if [[ "$cached" =~ ^[0-9]+$ ]] && (( now - cached < 300 )); then
      return 0
    fi
  fi
  # 通道一：CLI 本身不存在 → 直接失败
  if ! command -v "${CLI[0]}" >/dev/null; then
    echo "错误: 未找到 CLI '${CLI[0]}'（默认通道需安装 Claude Code CLI，或用 SKILLUP_CLAUDE_CMD 指定你的兼容 CLI）" >&2
    exit 1
  fi
  # 通道二：轻量真实探测（认证签名检测；同纯净模式参数，保证探测与真实调用环境一致）
  local probe_out
  probe_out="$("${CLI[@]}" --settings "$SETTINGS_JSON" ${MCP_FLAGS[@]+"${MCP_FLAGS[@]}"} ${SYSPROMPT_FLAGS[@]+"${SYSPROMPT_FLAGS[@]}"} -p --permission-mode=bypassPermissions 'ping' 2>&1)"
  if is_auth_failure "$probe_out"; then
    auth_fail_msg
    exit 1
  fi
  # 探测通过：刷新缓存（时间戳写入文件内容；探测输出非认证失败即视为可继续，
  # 空输出等异常由后续真实调用兜底）
  echo "$now" > "$AUTH_CACHE" 2>/dev/null
}

auth_probe

# ─── 主循环 ────────────────────────────────────────────────────────────────
# 重试两类瞬时故障（各最多 8 次退避）：
#   1) 网关 400：grep "API Error:"；此时流里可能已含部分 assistant 消息，不能
#      据此判成功，必须整次重试
#   2) 模型侧 api_error：流尾部 terminal_reason":"api_error / is_error":true
#      （注意正常流的 "api_error_status":null，匹配必须精确，勿用裸 "api_error"）
# 另对无错误签名的空输出也退避重试，避免瞬时异常直接判失败
LAST_ERR=""
# 网关 400 为瞬时高频故障（单次运行内 CLI 也会内部重试多次），
# 重试预算 8 次；退避 attempt*3s 封顶 12s，控制在 case 600s 超时内
for attempt in 1 2 3 4 5 6 7 8; do
  RAW="$(run_once)"
  # 中途认证/通道失效：立即致命退出（重试无意义），并作废预检缓存，
  # 避免下次评测带着过期的"通道正常"结论启动
  if is_auth_failure "$RAW"; then
    rm -f "$AUTH_CACHE" 2>/dev/null
    auth_fail_msg
    exit 1
  fi
  OUT="$(printf '%s\n' "$RAW" | extract)"
  if printf '%s' "$RAW" | grep -qE 'API Error:|terminal_reason":"api_error|"is_error":true'; then
    LAST_ERR="$RAW"
    sleep $(( attempt * 3 > 12 ? 12 : attempt * 3 ))
    continue
  fi
  # 429 TPM/QPS 限流（如 "429 Too Many Requests: ..."）：瞬时故障，
  # 整次重试；若不拦截会以限流文案为"响应"被 judge 误判 FAIL
  if printf '%s' "$RAW" | grep -qE '429 Too Many Requests|Too Many Requests|tpm超过限制'; then
    LAST_ERR="$RAW"
    sleep $(( attempt * 5 > 30 ? 30 : attempt * 5 ))
    continue
  fi
  if [[ -n "${OUT//[[:space:]]/}" ]]; then
    printf '%s\n' "$OUT"
    exit 0
  fi
  LAST_ERR="$RAW"
  sleep $(( attempt * 2 ))
done
printf '%s\n' "$LAST_ERR" >&2
exit 1
