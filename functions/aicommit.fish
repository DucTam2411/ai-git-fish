function aicommit --description 'Generate conventional commit msg from staged diff via DeepSeek'
    # --- deps ---
    if not type -q curl
        echo "aicommit: curl not found" >&2
        return 1
    end
    if not type -q jq
        echo "aicommit: jq not found (brew install jq)" >&2
        return 1
    end
    if test -z "$DEEPSEEK_API_KEY"
        echo "aicommit: DEEPSEEK_API_KEY not set" >&2
        return 1
    end

    # --- must be in git repo ---
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "aicommit: not a git repo" >&2
        return 1
    end

    # --- staged diff, code only (exclude binaries/assets/lockfiles) ---
    set -l excludes \
        ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.jpeg' ':(exclude)*.gif' \
        ':(exclude)*.webp' ':(exclude)*.ico' ':(exclude)*.svg' ':(exclude)*.pdf' \
        ':(exclude)*.mp4' ':(exclude)*.mov' ':(exclude)*.webm' ':(exclude)*.zip' \
        ':(exclude)*.gz' ':(exclude)*.tar' ':(exclude)*.woff' ':(exclude)*.woff2' \
        ':(exclude)*.ttf' ':(exclude)*.otf' ':(exclude)*.eot' ':(exclude)*.mp3' \
        ':(exclude)*.wav' ':(exclude)*.lock' ':(exclude)pnpm-lock.yaml' \
        ':(exclude)package-lock.json' ':(exclude)yarn.lock'

    set -l diff (git diff --cached --no-color -- . $excludes | string collect)

    if test -z "$diff"
        echo "aicommit: no staged code changes (stage with 'git add' first)" >&2
        return 1
    end

    # --- secret scan before anything leaves the machine ---
    if type -q gitleaks
        echo "aicommit: scanning staged changes with gitleaks..." >&2
        if not gitleaks protect --staged --no-banner --redact >/dev/null 2>&1
            echo "aicommit: gitleaks found potential secrets in staged changes. Aborting (not sending to API)." >&2
            echo "          run 'gitleaks protect --staged --verbose' to inspect." >&2
            return 1
        end
    else
        echo "aicommit: gitleaks not installed — skipping secret scan" >&2
    end

    # --- truncate oversized diff to keep token use sane ---
    set -l max_lines 4000
    set -l n_lines (count (string split \n -- $diff))
    if test $n_lines -gt $max_lines
        echo "aicommit: diff has $n_lines lines, truncating to $max_lines for the API" >&2
        set diff (string split \n -- $diff)[1..$max_lines] (printf '\n... [diff truncated: %d of %d lines sent]' $max_lines $n_lines)
        set diff (string join \n -- $diff)
    end

    # --- list of staged code files for context ---
    set -l files (git diff --cached --name-only -- . $excludes | string collect)

    # --- optional user hint (everything passed as args) ---
    set -l hint (string join ' ' -- $argv)

    # --- ticket id: from branch (\d{3,}), else offer fzf pick. resolved BEFORE the LLM call
    #     so the ticket goal can steer the message. no id -> diff-only fallback. ---
    set -l branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    set -l ticket (string match -rg '(\d{3,})' -- $branch)
    # env override wins (AICOMMIT_TICKET=1234 aicommit ...)
    test -n "$AICOMMIT_TICKET"; and set ticket "$AICOMMIT_TICKET"
    # else try to grab a #1234 / 1234 from the author hint
    if test -z "$ticket"; and test -n "$hint"
        set -l from_hint (string match -rg '#?(\d{3,})' -- $hint)
        test -n "$from_hint"; and set ticket "$from_hint"
    end
    if test -z "$ticket"; and type -q fzf; and type -q npx
        echo "aicommit: no ticket in branch '$branch' — pick one to switch onto a ticket branch" >&2
        set ticket (__leantime_pick)
        # Move the staged changes onto a proper ticket branch, then commit there.
        # git switch carries the staged index over (aborts cleanly on conflict).
        if test -n "$ticket"; and functions -q aibranch
            if aibranch feat $ticket
                set branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
            else
                echo "aicommit: branch switch failed — committing on '$branch', labeling [#$ticket]" >&2
            end
        end
    end

    # --- fetch ticket content (headline + description) to focus the LLM ---
    set -l ticket_ctx ""
    if test -n "$ticket"; and type -q npx
        set -l script_dir "$LEANTIME_SCRIPT_DIR"
        test -z "$script_dir"
        and set script_dir ~/.config/fish/leantime
        if test -d "$script_dir"
            echo "aicommit: fetching ticket #$ticket for context..." >&2
            # fish command-sub shares cwd (no subshell) -> save + restore pwd around the cd.
            set -l prev $PWD
            cd $script_dir
            set ticket_ctx (npx --no-install tsx src/pick-ticket.ts context $ticket 2>/dev/null | string collect)
            cd $prev
        end
    end

    # --- system prompt ---
    set -l sys "You are a commit message generator. Read the git diff and output ONE conventional commit message.

FORMAT (exactly):
<type>(<scope>): <summary>
<blank line>
- <detailed bullet>
- <detailed bullet>
...

RULES:
- type is one of: feat|fix|docs|style|refactor|perf|test|build|ci|chore
- subject line <= 72 chars, imperative mood, lower-case summary, no trailing period
- scope = the main area changed (e.g. e2e, frontend, infra)
- After a blank line, write a DETAILED body as bullet points starting with '- '.
- Be thorough: one bullet per distinct change. Explain WHAT changed and WHY/the effect, not just file names.
- Group related changes; prefer more detail over less. Cover every meaningful change in the diff.
- THE DIFF IS THE SINGLE SOURCE OF TRUTH. Describe ONLY what the diff actually changes. NEVER claim work the diff does not contain.
- Ticket context is background scope ONLY. Use it for wording/scope, NOT to invent changes. If the diff does not match the ticket goal, describe the DIFF (e.g. 'remove console.log') and add one bullet noting the diff does not cover the ticket goal.
- Output ONLY the raw commit message. No markdown fences, no preamble, no explanation, no quotes around it."

    set -l user "Files changed:
$files

Diff:
$diff"

    if test -n "$ticket_ctx"
        set user "Ticket context (BACKGROUND ONLY — do NOT describe this unless the diff actually shows it):
$ticket_ctx

$user"
    end

    if test -n "$hint"
        set user "$user

Author hint (prioritize this intent and weave it into the message): $hint"
    end

    # --- build payload safely ---
    set -l payload (jq -n \
        --arg sys "$sys" \
        --arg user "$user" \
        '{model:"deepseek-chat", stream:false, temperature:0.3,
          messages:[{role:"system",content:$sys},{role:"user",content:$user}]}')

    echo "aicommit: asking DeepSeek..." >&2

    set -l resp (curl -sS https://api.deepseek.com/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
        -d "$payload")

    if test $status -ne 0
        echo "aicommit: request failed" >&2
        return 1
    end

    # --- API error? ---
    set -l err (echo $resp | jq -r '.error.message // empty')
    if test -n "$err"
        echo "aicommit: API error: $err" >&2
        return 1
    end

    # string collect keeps the multi-line message as ONE string (newlines intact)
    set -l msg (printf '%s' $resp | jq -r '.choices[0].message.content // empty' | string collect)
    if test -z "$msg"
        echo "aicommit: empty response from DeepSeek" >&2
        echo $resp >&2
        return 1
    end

    # --- strip stray code fences if model added them ---
    set msg (printf '%s' $msg | string replace -r '^```[a-z]*\n?' '' | string replace -r '\n?```$' '' | string collect)

    # inject [#id] right after "type(scope): " in the subject line (skip if already present)
    # ($ticket already resolved before the LLM call above)
    if test -n "$ticket"
        set -l lines (printf '%s\n' $msg | string split \n)
        if not string match -q "*#$ticket*" -- $lines[1]
            # insert after "type(scope): " if present...
            set -l newline (string replace -r '^(\w+(\([^)]*\))?:\s*)' '$1'"[#$ticket] " -- $lines[1])
            # ...otherwise the model dropped the conventional prefix -> just prepend so the id is never lost
            if test "$newline" = "$lines[1]"
                set newline "[#$ticket] $lines[1]"
            end
            set lines[1] $newline
        end
        set msg (string join \n -- $lines)
    end

    # --- subject + tasks-done grid ---
    set -l subject (printf '%s\n' $msg | string split \n)[1]
    set -l tasks (printf '%s\n' $msg | string match -r '^\s*[-*]\s+.+' | string replace -r '^\s*[-*]\s+' '')

    echo ""
    echo "  📝 $subject"
    echo ""

    if test (count $tasks) -gt 0
        printf '%s\n' $tasks | python3 (dirname (status filename))/aicommit_grid.py
    end
    echo ""
    read -l -P "Commit with this message? [y/N/e=edit] " answer

    switch $answer
        case e E
            set -l tmp (mktemp)
            printf '%s\n' $msg > $tmp
            git commit -e -F $tmp
            rm -f $tmp
        case y Y yes
            printf '%s\n' $msg | git commit -F -
        case '*'
            echo "aicommit: aborted" >&2
            return 1
    end
end
