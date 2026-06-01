function aipr --description 'Create or update a GitHub PR with an AI summary + linked Leantime ticket'
    # --- deps ---
    for dep in git gh curl jq
        if not type -q $dep
            echo "aipr: $dep not found" >&2
            return 1
        end
    end
    if test -z "$DEEPSEEK_API_KEY"
        echo "aipr: DEEPSEEK_API_KEY not set" >&2
        return 1
    end
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "aipr: not a git repo" >&2
        return 1
    end
    if not gh auth status >/dev/null 2>&1
        echo "aipr: gh not authenticated (run 'gh auth login')" >&2
        return 1
    end

    # --- branch + base ---
    set -l branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    set -l base (gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)
    test -z "$base"; and set base main
    if test "$branch" = "$base"
        echo "aipr: on default branch '$base' — checkout a feature branch first" >&2
        return 1
    end

    # --- make sure the branch is on the remote (gh needs it pushed) ---
    if not git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1
        echo "aipr: pushing '$branch' to origin..." >&2
        if not git push -u origin HEAD
            echo "aipr: push failed" >&2
            return 1
        end
    else
        echo "aipr: syncing '$branch' to origin..." >&2
        git push >/dev/null 2>&1
    end

    # --- author hint (all args) ---
    set -l hint (string join ' ' -- $argv)

    # --- ticket id: branch (\d{3,}) -> AIPR_TICKET env -> #id in hint -> fzf pick ---
    set -l ticket (string match -rg '(\d{3,})' -- $branch)
    test -n "$AIPR_TICKET"; and set ticket "$AIPR_TICKET"
    if test -z "$ticket"; and test -n "$hint"
        set -l from_hint (string match -rg '#?(\d{3,})' -- $hint)
        test -n "$from_hint"; and set ticket "$from_hint"
    end
    if test -z "$ticket"; and type -q fzf; and type -q npx
        read -l -P "No ticket id in branch '$branch'. Pick from Leantime? [y/N] " pick
        if test "$pick" = y -o "$pick" = Y
            set ticket (__leantime_pick)
        end
    end

    # --- leantime: LLM context + a pretty GitHub block to embed ---
    set -l script_dir "$LEANTIME_SCRIPT_DIR"
    test -z "$script_dir"; and set script_dir ~/.config/fish/leantime
    set -l ticket_ctx ""
    set -l ticket_md ""
    if test -n "$ticket"; and type -q npx; and test -d "$script_dir"
        echo "aipr: fetching ticket #$ticket..." >&2
        set -l prev $PWD
        cd $script_dir
        set ticket_ctx (npx --no-install tsx src/pick-ticket.ts context $ticket 2>/dev/null | string collect)
        set ticket_md (npx --no-install tsx src/pick-ticket.ts markdown $ticket 2>/dev/null | string collect)
        cd $prev
    end

    # --- what changed vs base: commit messages (subject + body) + diffstat.
    #     Commit messages are the source of truth — aicommit already wrote rich bodies,
    #     so we summarize those instead of the noisy/oversized code diff. ---
    set -l commits (git log --no-color --pretty=format:'### %s%n%b' "origin/$base..HEAD" 2>/dev/null | string collect)
    test -z "$commits"; and set commits (git log --no-color --pretty=format:'### %s%n%b' "$base..HEAD" 2>/dev/null | string collect)
    set -l stat (git diff --no-color --stat "origin/$base...HEAD" 2>/dev/null | string collect)
    test -z "$stat"; and set stat (git diff --no-color --stat "$base...HEAD" 2>/dev/null | string collect)

    if test -z "$commits"
        echo "aipr: no commits between '$base' and '$branch' — nothing to PR" >&2
        return 1
    end

    # --- system prompt: produce PR title + markdown body ---
    set -l sys "You are a GitHub pull-request writer. Given the commits and diffstat (and optional ticket context), output a PR title and body.

OUTPUT FORMAT (exactly):
<title on the first line>
<blank line>
<markdown body>

RULES:
- First line = ONLY the PR title: imperative mood, <= 72 chars, no trailing period, no 'PR:'/'#'/'-' prefix. Then ONE blank line, then the body.
- Body uses GitHub markdown. ALWAYS put a blank line before and after every heading and before every bullet list, or GitHub renders it as one paragraph.
- Start with '## 📝 Summary': 2-4 sentences on WHAT changed and WHY.
- Then '## 🔧 Changes': a bullet list grouping the meaningful changes (derive from the commit messages + diffstat). One bullet per logical change.
- The COMMIT MESSAGES are the source of truth for what was done; diffstat shows file coverage. Ticket context is background scope only — do not claim work the commits don't show.
- Do NOT invent a testing section unless the changes clearly include tests.
- Do NOT add a Leantime/ticket section yourself — it is appended automatically.
- Output ONLY the raw title + body. No code fences, no preamble."

    set -l user "Branch: $branch  ->  base: $base

Commits:
$commits

Diffstat:
$stat"
    if test -n "$ticket_ctx"
        set user "Ticket context (background only):
$ticket_ctx

$user"
    end
    if test -n "$hint"
        set user "$user

Author hint (prioritize this intent): $hint"
    end

    set -l payload (jq -n --arg sys "$sys" --arg user "$user" \
        '{model:"deepseek-chat", stream:false, temperature:0.3,
          messages:[{role:"system",content:$sys},{role:"user",content:$user}]}')

    echo "aipr: asking DeepSeek..." >&2
    set -l resp (curl -sS https://api.deepseek.com/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
        -d "$payload")
    set -l err (echo $resp | jq -r '.error.message // empty')
    if test -n "$err"
        echo "aipr: API error: $err" >&2
        return 1
    end
    set -l out (printf '%s' $resp | jq -r '.choices[0].message.content // empty' | string collect)
    if test -z "$out"
        echo "aipr: empty response from DeepSeek" >&2
        return 1
    end
    # strip stray code fences
    set out (printf '%s' $out | string replace -r '^```[a-z]*\n?' '' | string replace -r '\n?```$' '' | string collect)

    # --- split title (first non-empty line) from body (the rest) ---
    set -l lines (printf '%s\n' $out | string split \n)
    set -l ti 1
    while test $ti -le (count $lines); and test -z (string trim -- "$lines[$ti]")
        set ti (math $ti + 1)
    end
    # strip any leading markdown heading/list markers the model may have added to the title
    set -l title (string trim -- "$lines[$ti]" | string replace -r '^#+\s*' '' | string replace -r '^[-*]\s*' '')
    set -l body ""
    if test $ti -lt (count $lines)
        # string collect keeps the multi-line body as ONE value so newlines survive quoting
        set body (string join \n -- $lines[(math $ti + 1)..-1] | string trim | string collect)
    end

    # prefix [#id] to the title if not already there
    if test -n "$ticket"; and not string match -q "*#$ticket*" -- $title
        set title "[#$ticket] $title"
    end

    # --- assemble final body: AI summary + linked ticket block ---
    set -l full_body $body
    if test -n "$ticket_md"
        set full_body "$body

---

$ticket_md"
    end

    # --- existing PR for this branch? ---
    set -l pr_url (gh pr view --json url -q '.url' 2>/dev/null)

    echo ""
    echo "  ───────────────────────────────────────────────"
    echo "  $branch  →  $base"
    if test -n "$pr_url"
        echo "  PR exists: $pr_url  (will UPDATE)"
    else
        echo "  No PR yet  (will CREATE)"
    end
    echo "  ───────────────────────────────────────────────"
    echo ""
    echo "  📌 $title"
    echo ""
    printf '%s\n' $full_body | sed 's/^/  │ /'
    echo ""

    read -l -P "Proceed? [y/N/e=edit body] " answer
    set -l tmp (mktemp)
    printf '%s\n' $full_body > $tmp
    switch $answer
        case e E
            set -l editor $EDITOR
            test -z "$editor"; and set editor vi
            $editor $tmp
            set full_body (cat $tmp | string collect)
        case y Y yes
            # keep body as-is
        case '*'
            echo "aipr: aborted" >&2
            rm -f $tmp
            return 1
    end

    # --- create or update ---
    if test -n "$pr_url"
        gh pr edit --title "$title" --body-file $tmp
        and echo "aipr: updated $pr_url"
    else
        gh pr create --base $base --head $branch --title "$title" --body-file $tmp
    end
    set -l rc $status
    rm -f $tmp
    return $rc
end
