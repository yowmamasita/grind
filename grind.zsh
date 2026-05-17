#!/usr/bin/env zsh

# grind — iterative AI coding loop (doer works, reviewer checks, repeat until clean)
#
# Usage:
#   grind "task description" ["review prompt"]
#
# Examples:
#   grind "Add input validation to the signup form"
#   grind "Refactor the database layer" "Focus on thread safety and error handling."
#
# Supported agents (use as GRIND_DOER or GRIND_REVIEWER):
#   Claude:    claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p
#   Codex:     codex -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -p
#   OpenCode:  opencode -p
#   Gemini:    gemini -m gemini-2.5-pro --approval-mode=yolo -p
#   Crush:     crush --yolo run -q -m anthropic/claude-sonnet-4 --
#   Oh My Pi:  omp --slow -p
#   Pi:        pi --model anthropic/claude-sonnet-4 --thinking high -p
#   Trae:      trae-cli run
#   Cursor:    cursor-agent --yolo --model claude-sonnet-4-6 --print
#   Cline:     cline --yolo
#   Qoder:     qodercli -p
#   Droid:     droid exec --auto high --model gpt-5.5
#   Kilocode:  kilo run --auto --model anthropic/claude-sonnet-4-6
#   Goose:     goose run --text
#
# Override for a single run:
#   GRIND_DOER="gemini -m gemini-2.5-pro --approval-mode=yolo -p" \
#   GRIND_REVIEWER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort high -p" \
#   grind "Fix the race condition in the worker pool"
#
# Or export to change defaults for the session:
#   export GRIND_DOER="pi --model anthropic/claude-sonnet-4 --thinking high -p"
#   export GRIND_REVIEWER="codex -m o3 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -p"
#   grind "Implement retry logic for the HTTP client"

# Configuration — override these before calling grind()
GRIND_DOER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p"
GRIND_REVIEWER="codex -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -p"
GRIND_REVIEW_PROMPT="Review the code changes in this repository. Ensure there are no bugs and the solution is elegant and simple."

grind() {
  local task="$1"
  local review_prompt="${2:-$GRIND_REVIEW_PROMPT}"
  local iteration=0
  local review_output=""

  if [[ -z "$task" ]]; then
    echo "Usage: grind \"task description\" [\"review prompt\"]"
    echo ""
    echo "Configure agents via:"
    echo "  GRIND_DOER=\"claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p\""
    echo "  GRIND_REVIEWER=\"codex -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -p\""
    return 1
  fi

  echo "═══ grind: starting ═══"
  echo "Task: $task"
  echo "Doer: $GRIND_DOER"
  echo "Reviewer: $GRIND_REVIEWER"
  echo ""

  while true; do
    (( iteration++ ))
    echo "─── iteration $iteration ───"

    # WORK
    echo "[work] doer..."
    local work_prompt
    if [[ -z "$review_output" ]]; then
      work_prompt="$task"
    else
      work_prompt="Original task: $task

The reviewer found these issues with your previous work:

$review_output

Fix all the issues above."
    fi

    eval "$GRIND_DOER" '"$work_prompt"' 2>/dev/null
    echo "[work] done"

    # REVIEW
    echo "[review] reviewer..."
    local full_review_prompt="The task was: $task

$review_prompt

If there are no issues and the code is correct and complete, respond with exactly: ALL_GOOD
Otherwise, list the issues that need to be fixed."
    review_output=$(eval "$GRIND_REVIEWER" '"$full_review_prompt"' 2>/dev/null)
    echo "[review] done"

    # GATE
    if echo "$review_output" | grep -q "ALL_GOOD"; then
      echo ""
      echo "═══ grind: DONE after $iteration iteration(s) ═══"
      return 0
    fi

    echo "[gate] issues found, iterating..."
    echo ""
  done
}
