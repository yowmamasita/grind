# grind

Iterative AI coding loop — one agent works, another reviews, repeat until clean.

## How it works

1. **Doer** works on the task
2. **Reviewer** reviews the changes
3. If issues found → feed review back to doer, repeat
4. If `ALL_GOOD` → stop

Loop runs until the reviewer has no more issues.

## Install

```bash
# Add to your shell
echo 'source ~/grind.zsh' >> ~/.zshrc
source ~/grind.zsh
```

## Usage

```bash
grind "Add input validation to the signup form"
grind "Fix the race condition" "Focus only on performance and thread safety."
```

Second argument overrides the review prompt (the termination instruction is always appended automatically).

## Supported agents

| Agent | GRIND_DOER / GRIND_REVIEWER value |
|-------|-----------------------------------|
| Claude | `claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p` |
| Codex | `codex -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -p` |
| OpenCode | `opencode -p` |
| Gemini | `gemini -m gemini-2.5-pro --approval-mode=yolo -p` |
| Crush | `crush --yolo run -q -m anthropic/claude-sonnet-4 --` |
| Oh My Pi | `omp --slow -p` |
| Pi | `pi --model anthropic/claude-sonnet-4 --thinking high -p` |
| Trae | `trae-cli run` |
| Cursor | `cursor-agent --yolo --model claude-sonnet-4-6 --print` |
| Cline | `cline --yolo` |
| Qoder | `qodercli -p` |
| Droid | `droid exec --auto high --model gpt-5.5` |
| Kilocode | `kilo run --auto --model anthropic/claude-sonnet-4-6` |
| Goose | `goose run --text` |

## Configuration

Override agents via environment variables:

```bash
# Defaults
GRIND_DOER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p"
GRIND_REVIEWER="codex -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -p"
GRIND_REVIEW_PROMPT="Review the code changes in this repository. Ensure there are no bugs and the solution is elegant and simple."
```

### Inline override

```bash
GRIND_DOER="gemini -m gemini-2.5-pro --approval-mode=yolo -p" \
GRIND_REVIEWER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort high -p" \
grind "Fix the race condition in the worker pool"
```

### Session override

```bash
export GRIND_DOER="goose run --text"
export GRIND_REVIEWER="codex -m o3 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -p"
grind "Implement retry logic for the HTTP client"
```
