#!/usr/bin/env bash
# UserPromptSubmit hook: TTS ping on specific built-in slash commands.
# Fires only for /goal, /review, /security-review — no other prompts.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$(dirname "$HOOK_DIR")")"
SAY_SH="${PLUGIN_ROOT}/scripts/utils/say.sh"

prompt="$(jq -r '.prompt // empty' 2>/dev/null)"
[[ -z "$prompt" ]] && exit 0

[[ -f "$SAY_SH" ]] || exit 0
# shellcheck source=/dev/null
source "$SAY_SH" 2>/dev/null || exit 0

case "$prompt" in
    /goal*)             say_it "goal: ${prompt#/goal}" 2>/dev/null || true ;;
    /review*)           say_it "review in corso" 2>/dev/null || true ;;
    /security-review*)  say_it "security review in corso" 2>/dev/null || true ;;
esac

exit 0
