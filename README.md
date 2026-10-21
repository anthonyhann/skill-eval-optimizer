<div align="center">

# Skill Eval Optimizer 🧬

### Train your agent skills like a model: measure, hill-climb, keep what works.

An agent skill that scores your other skills on **8 dimensions (/100)**, rewrites the weakest one, and only keeps a change when the score actually goes up — git ratchet included.

[![license](https://img.shields.io/badge/license-MIT-orange?style=flat-square)](LICENSE)
[![stars](https://img.shields.io/github/stars/anthonyhann/skill-eval-optimizer?style=flat-square)](https://github.com/anthonyhann/skill-eval-optimizer/stargazers)
[![agent skill](https://img.shields.io/badge/agent%20skill-Claude%20Code-blue?style=flat-square)](SKILL.md)
[![rubric](https://img.shields.io/badge/dimensions-8%20%C3%97%201--10-green?style=flat-square)](references/rubric.md)

[Quickstart](#-quickstart) · [How it works](#-how-it-works) · [Demo](#-demo) · [Docs](SKILL.md) · [Evals](evals/) · **[中文 README](README_zh.md)**

</div>

## 📸 Demo

![A real result card: knowledge-wiki went from 80.8 to 90.3 (+9.5), 404→216 lines, token footprint -39%](templates/card-knowledge-wiki.png)
> A real card this skill generated: **knowledge-wiki 80.8 → 90.3 (+9.5)**, while shrinking 404 → 216 lines and cutting token footprint by 39%.

## 📈 Track record

Six months of production receipts (**2026-04 → 2026-10**), every record scored by this skill itself:

- **49 agent skills** under management, **342 scored optimization records**
- Of **44 skills** with full baselines: **40 improved, average +9.9 / 100** — the loop keeps a change only when the score actually goes up
- Biggest comeback: a code-review skill **61.2 → 93.1** over 19 rounds → [agentic-code-review](https://github.com/anthonyhann/agentic-code-review); a knowledge skill **67.8 → 90.3** while *shrinking 39% of its tokens* → [knowledge-wiki](https://github.com/anthonyhann/knowledge-wiki)
- Its own baseline: **90.7 / 100** — yes, the optimizer optimizes itself

## 😅 Sound familiar?

- You tweaked a skill prompt three times last week. Did it actually get better? **Nobody knows — there's no score.**
- Your skills folder keeps growing: two skills overlap, one references a dead CLI, one still hardcodes a database password.
- You asked an LLM "is this skill good?" and it said *"looks great!"* — then the next edit quietly broke the trigger words.

This skill replaces vibes with a loop: **scan → triage → score → hill-climb → verify → keep-or-revert**.

## 🔄 How it works

```
Phase 0    Inventory      scan ~/.claude/skills + ./.claude/skills → JSON list
Phase 0.5  Triage         5 checks (overlap / rule-overlap / staleness / usage / security red-lines)
                          → verdict: Keep · Improve · Update · Retire · Merge · 🔴 Block
Phase 0.7  Test prompts   2-3 real prompts per skill → materialized as skill-up eval cases
Phase 1    Baseline       8-dimension rubric, 6 structural (60) + 2 effectiveness (40) → /100
Phase 2    Hill-climb     attack the weakest dimension each round (default ≤3 rounds);
                          score up → keep & commit · score down → git revert, never reset --hard
Phase 3    Report + Card  before/after table, keep/revert stats, visual result card (PNG, 2x)
```

Human-in-the-loop by design: a **round gate** shows the exact paragraph, the planned edit, and the expected delta before every change. Security red-lines (hardcoded intranet addresses, DB connection strings, unguarded destructive ops, non-compliant remote access) force **verdict=Block** and cap the boundary dimension at 4/10.

Dimension 8 (real-world performance) isn't a judge's opinion — it runs your test prompts through [skill-up](https://github.com/alibaba/skill-up) and maps `pass_rate × 10`, so the same input gives the same score, in CI too.

## 🚀 Quickstart

**Prerequisites:** `bash` + `jq` (`brew install jq`). Cards need Node + Playwright (optional). Dimension 8 auto-installs skill-up on first run.

**1. Install** (any agent that reads `SKILL.md`):

```bash
git clone https://github.com/anthonyhann/skill-eval-optimizer ~/.claude/skills/skill-eval-optimizer
```

**2. Say the word:**

```
/skill-eval-optimizer        # full run: inventory → triage → score
```

or naturally: *"optimize my code-review skill"* · *"score all my skills"* · *"skill health status"*

**For AI agents** — paste this to yours:

> Install the skill from https://github.com/anthonyhann/skill-eval-optimizer into my skills directory (e.g. `~/.claude/skills/skill-eval-optimizer`), make sure `jq` is installed, then run `/skill-eval-optimizer`.

That's it. 2 commands, 1 sentence.

## 📁 What's inside

```
skill-eval-optimizer/
├── SKILL.md                     # the skill itself: workflow, phases, round gates, guardrails
├── references/
│   ├── rubric.md                # 8-dimension rubric + security red-line rules (S002–S005)
│   ├── skill-up.md              # deterministic scoring via skill-up, regression lock, CI fields
│   ├── output-templates.md      # per-phase output formats
│   └── health-panel.md          # keep-rate trends / failure clustering / version history
├── scripts/
│   ├── scan.sh                  # skill inventory + frontmatter + mtime + 7d/30d usage
│   ├── quick-diff.sh            # what changed since last evaluation
│   ├── save-results.sh          # shallow-merge results.json (UTC timestamps)
│   └── screenshot.mjs           # 2x PNG result cards via Playwright
├── templates/
│   ├── result-card.html         # 3-theme card template (swiss / terminal / newspaper)
│   └── card-knowledge-wiki.png  # a real generated card (see above)
└── evals/                       # this skill's own 3 eval cases — it eats its own dog food
```

Two runtime files stay local and git-ignored: `results.json` (snapshot / quick-scan baseline) and `results.tsv` (append-only experiment log).

## ⚠️ When NOT to use it

- **As a substitute for unit/integration tests.** It evaluates and improves *skill prompt files*, not code correctness.
- **On anything that isn't an agent skill.** It reads `SKILL.md`-style files with frontmatter; give it a random markdown doc and it will (correctly) refuse.
- **If you want a fire-and-forget batch rewriter.** Every optimization round waits for your confirmation — that's a guardrail, not a bug.
- **On Windows**, dimension 8 falls back to `dry_run` (skill-up's installer is macOS/Linux only). Structural dimensions 1–7 are unaffected.

## License

MIT © [anthonyhann](https://github.com/anthonyhann) — if this saved your skills from prompt rot, a ⭐ tells you when new rubric dimensions land.
