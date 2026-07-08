function __aireport_pick_date --description 'fzf day picker, last 60 days, today pre-selected at top'
    set -l today (date +%Y-%m-%d)
    set -l lines
    for i in (seq 0 59)
        set -l d (date -v-{$i}d +%Y-%m-%d 2>/dev/null; or date -d "-$i day" +%Y-%m-%d)
        set -l wd (date -v-{$i}d +%a 2>/dev/null; or date -d "-$i day" +%a)
        set -l label "$d  $wd"
        test "$d" = "$today"; and set label "$label  ← today"
        set -a lines $label
    end
    set -l picked (printf '%s\n' $lines | fzf --prompt='date> ' \
        --header='pick a day for the report (top = today)' \
        --height=22 --reverse --no-multi)
    test -z "$picked"; and return 1
    string match -rg '^\S+' -- "$picked"
end

function aireport --description 'aireport <hours> [YYYY-MM-DD] — AI daily report from your real git/PR activity'
    for dep in git gh curl jq
        if not type -q $dep
            __aigit_err "aireport: $dep not found"
            return 1
        end
    end
    if test -z "$DEEPSEEK_API_KEY"
        __aigit_err "aireport: DEEPSEEK_API_KEY not set (run 'aigit config')"
        return 1
    end
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        __aigit_err "aireport: not a git repo"
        return 1
    end
    if not gh auth status >/dev/null 2>&1
        __aigit_err "aireport: gh not authenticated (run 'gh auth login')"
        return 1
    end

    # --- args: hours (accepts '12' or '12h'), optional date (default: today, fzf calendar to pick another) ---
    set -l hours (string replace -r 'h$' '' -- "$argv[1]")
    if test -z "$hours"
        __aigit_err "aireport: usage: aireport <hours> [YYYY-MM-DD]"
        return 1
    end
    set -l day $argv[2]
    if test -z "$day"
        if type -q fzf
            set day (__aireport_pick_date)
            or return 1
        else
            set day (date +%Y-%m-%d)
        end
    end

    set -l gh_login (gh api user -q '.login' 2>/dev/null)
    if test -z "$gh_login"
        __aigit_err "aireport: could not resolve gh user"
        return 1
    end
    # commit-level author name may differ from the gh login (e.g. "Duc Tam" vs "DucTam2411")
    set -l git_name (git config user.name)

    __aigit_step "Scanning $day for merges by $gh_login…"

    # merge commits authored (as PR opener) by $gh_login on $day
    set -l merges (git log --all --merges --author="$gh_login" \
        --since="$day 00:00" --until="$day 23:59" \
        --pretty=format:'%H %s' 2>/dev/null)

    if test -z "$merges"
        __aigit_warn "no merged PRs found for $gh_login on $day"
    end

    set -l own_block ""
    set -l reviewed_block ""

    for line in $merges
        set -l hash (string split -m1 ' ' -- $line)[1]
        set -l subject (string split -m1 ' ' -- $line)[2]
        set -l pr_num (string match -rg 'pull request #(\d+)' -- $subject)
        test -z "$pr_num"; and continue

        # who actually authored the commits inside this merge?
        set -l authors (git log --pretty=format:'%an' "$hash^1..$hash^2" 2>/dev/null | sort -u)
        set -l is_mine 0
        for a in $authors
            test "$a" = "$git_name"; and set is_mine 1
        end

        if test $is_mine -eq 1
            __aigit_info "own work: PR #$pr_num — $subject"
            set -l pr_json (gh pr view $pr_num --json title,body 2>/dev/null)
            set -l title (echo $pr_json | jq -r '.title // empty')
            set -l body (echo $pr_json | jq -r '.body // empty')
            set own_block "$own_block

### PR #$pr_num: $title
$body"
        else
            __aigit_info "reviewed/merged only: PR #$pr_num — $subject (by $authors)"
            set reviewed_block "$reviewed_block
- PR #$pr_num: $subject (author: $authors)"
        end
    end

    if test -z "$own_block"; and test -z "$reviewed_block"
        __aigit_err "aireport: nothing to report for $day"
        return 1
    end

    # --- ask DeepSeek to read everything and write a plain-language, non-technical report ---
    set -l sys "You are writing a daily standup report for a non-technical audience (PM/manager). Input is real PR data for one day: PRs the person authored (full title+body, may be very technical) and PRs they only reviewed/merged (title only, authored by someone else).

OUTPUT FORMAT (markdown, match exactly this style):

**Daily Report – <name> – <date DD/MM/YYYY>**

🚧 **What I'm working on:**

- <task line>: <est>h → <remaining>h
  - <plain-language sub-bullet if the task has multiple notable changes>

🛠️ **Blockers/Issues:**

<None, or list>

⏭️ **Next plan:**

- <forward-looking bullet>

RULES:
- Total of all <est>h values in 'What I'm working on' MUST sum to exactly $hours hours (the user-given total for the day). Distribute realistically based on how much each PR actually contains (bigger PR body / more changes = more hours).
- Every task is finished today unless told otherwise, so <remaining>h is always 0h.
- Group all PRs for the SAME underlying feature/ticket into ONE task line with sub-bullets, even if they came from separate PRs — read every PR body fully to extract the real user-facing outcome.
- Rewrite technical PR content in plain language a non-engineer understands: say what changed for the user/product, not implementation details (no file names, function names, library names, component names).
- PRs the person only reviewed/merged (not authored) go into ONE separate line: 'Review & merge PR: <short list>' — do not describe their internals in depth, just name what each was about and (author) credit.
- Do not invent work that isn't in the input.
- Keep it concise — this is a daily report, not documentation."

    set -l user "Name: $git_name
Date: $day
Total hours for the day: $hours

=== PRs authored by $git_name (real work — read fully) ===
$own_block

=== PRs merged/reviewed only (not authored by $git_name) ===
$reviewed_block"

    set -l payload (jq -n --arg sys "$sys" --arg user "$user" \
        '{model:"deepseek-chat", stream:false, temperature:0.3,
          messages:[{role:"system",content:$sys},{role:"user",content:$user}]}')

    __aigit_step "Asking DeepSeek to draft the report…"
    set -l resp (curl -sS https://api.deepseek.com/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
        -d "$payload")
    set -l err (echo $resp | jq -r '.error.message // empty')
    if test -n "$err"
        __aigit_err "API error: $err"
        return 1
    end
    set -l out (printf '%s' $resp | jq -r '.choices[0].message.content // empty' | string collect)
    if test -z "$out"
        __aigit_err "empty response from DeepSeek"
        return 1
    end
    set out (printf '%s' $out | string replace -r '^```[a-z]*\n?' '' | string replace -r '\n?```$' '' | string collect)

    echo ""
    printf '%s\n' $out
end
