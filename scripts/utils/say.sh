#!/usr/bin/env bash
# TTS helper for loom-works.
# Source this file, then call: say_it / say_it_en / say_auto / say_id
# All functions degrade silently if say-it binary or piper model is missing.

_LOOM_SAY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_LOOM_SAY_BIN="${_LOOM_SAY_ROOT}/scripts/say-it"

_say_core() {
    local model="$1" text="$2"
    [[ -x "$_LOOM_SAY_BIN" ]] || return 0
    [[ -f "$model" ]] || return 0
    SAY_IT_MODEL="$model" "$_LOOM_SAY_BIN" "$text" 2>/dev/null || true
}

say_it() {
    local model="${SAY_IT_MODEL:-$HOME/.local/share/piper-voices/it_IT-paola-medium.onnx}"
    _say_core "$model" "$1"
}

say_it_en() {
    # Override model via SAY_IT_MODEL_EN env var (e.g. en_US-amy-medium.onnx).
    # Degrades silently if model file is absent — no EN fallback to IT.
    local model="${SAY_IT_MODEL_EN:-$HOME/.local/share/piper-voices/en_US-amy-medium.onnx}"
    _say_core "$model" "$1"
}

# Dispatches to say_it or say_it_en based on heuristic:
# if at least 3 words end with a vowel → Italian, otherwise → English.
say_auto() {
    local text="$1"
    local word vowel_end=0
    for word in $text; do
        [[ "$word" =~ [aeiouAEIOU]$ ]] && vowel_end=$((vowel_end + 1))
    done
    if [[ $vowel_end -ge 3 ]]; then
        say_it "$text"
    else
        say_it_en "$text"
    fi
}

# Trims leading zeros from task ID for TTS readability: T05 → T5.
say_id() {
    echo "$1" | sed -E 's/^(T)0+([0-9])/\1\2/'
}
