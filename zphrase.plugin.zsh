
# NLShell - Natural Language Shell

typeset -g NLSHELL_ROOT="${${(%):-%x}:A:h}"
typeset -g NLSHELL_MODEL="${NLSHELL_MODEL:-system}"

# ----------------------------------------
# AI Inference
# ----------------------------------------

_nlshell_infer() {
    local task="$1"
    local request="$2"
    local instructions
    local prompt_file

    case "$task" in
        translate|explain|repair) ;;
        *) return 1 ;;
    esac

    prompt_file="$NLSHELL_ROOT/prompts/$task.txt"

    [[ -r "$prompt_file" ]] || return 1

    instructions=$(<"$prompt_file")

    local -a args

    args=(
        respond
        --model "$NLSHELL_MODEL"
        --no-stream
        --instructions "$instructions"
    )

    if [[ "$task" == translate ]]; then
        args+=(
            --schema
            "$NLSHELL_ROOT/schemas/suggestion.json"
        )
    fi

    command fm "${args[@]}" \
        "Operating system: macOS
Shell: zsh
Working directory: $PWD
Request: $request"
}

# ----------------------------------------
# ZLE Integration
# ----------------------------------------

_nlshell_accept_line() {
    local request response suggestion explanation

    # Native shell fast path
    if [[ "$CONTEXT" != start ||
          "$BUFFER" != '>'* ]]; then
        zle accept-line
        return
    fi

    request="${BUFFER#>}"

    if [[ "$request" != *[![:space:]]* ]]; then
        zle -M "NLShell: Please enter a request."
        return
    fi

    if ! command -v jq >/dev/null 2>&1; then
        zle -M "NLShell: jq is required."
        return
    fi

    zle -M "NLShell: Generating command..."

    response=$(_nlshell_infer translate "$request") || {
        zle -M "NLShell: Inference failed."
        return
    }

    # Validate and extract JSON fields
    suggestion=$(printf '%s' "$response" | jq -er '
        .command |
        select(type == "string") |
        select(test("[[:cntrl:]]") | not)
    ') || {
        zle -M "NLShell: Invalid response."
        return
    }

    explanation=$(printf '%s' "$response" | jq -r '
        .explanation |
        if type == "string"
        then gsub("[[:cntrl:]]"; " ")
        else ""
        end
    ')

    # Validate command
    if [[ "$suggestion" != *[![:space:]]* ||
          "$suggestion" == *[[:cntrl:]]* ||
          "$suggestion" == *'```'* ||
          "$suggestion" == '>'* ]]; then
        zle -M "NLShell: Invalid command."
        return
    fi

    # Preview, never execute automatically
    BUFFER="$suggestion"
    CURSOR=${#BUFFER}

    zle -M "$explanation | Enter: Execute | Ctrl+C: Cancel"
}

# ----------------------------------------
# Register Plugin
# ----------------------------------------

zle -N _nlshell_accept_line

bindkey '^M' _nlshell_accept_line
bindkey '^J' _nlshell_accept_line
