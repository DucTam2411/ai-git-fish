function aibpm --description 'BPM (Anymateme Web platform) sprint board; pass a headline to fast-create instead of browsing'
    set -l script_dir "$LEANTIME_SCRIPT_DIR"
    test -z "$script_dir"
    and set script_dir ~/.config/fish/leantime

    if not type -q fzf
        __aigit_err "aibpm: fzf not found (brew install fzf)"
        return 1
    end
    if not type -q npx
        __aigit_err "aibpm: npx not found (install Node.js)"
        return 1
    end
    if not test -d "$script_dir"
        __aigit_err "aibpm: script dir not found: $script_dir"
        return 1
    end

    # BPM is the one Leantime project (nicknamed "bpm" by the team) — no project
    # picker needed. Override with $AIBPM_PROJECT_ID if that id ever changes.
    set -l project_id "$AIBPM_PROJECT_ID"
    test -z "$project_id"
    and set project_id 2

    # No headline given (bare `aibpm`, or explicit `aibpm board`) -> browse, don't
    # force a create flow. Pass a headline to skip straight to fast-create instead.
    if test -z "$argv"; or test "$argv[1]" = board
        __aibpm_board $script_dir $project_id
        return
    end

    # --- pick sprint ---
    __aigit_step "Fetching sprints"
    set -l prev $PWD
    cd $script_dir
    set -l sprints (npx --no-install tsx src/add-task.ts sprints $project_id 2>/tmp/aibpm.err)
    cd $prev
    if test -z "$sprints"
        __aigit_err "aibpm: no sprints returned"
        test -s /tmp/aibpm.err; and cat /tmp/aibpm.err >&2
        return 1
    end
    set -l picked_sprint (printf '%s\n' $sprints | fzf \
        --delimiter '\t' --with-nth '2..' \
        --prompt 'sprint> ' --height '60%' --reverse --border --header 'Pick a sprint')
    if test -z "$picked_sprint"
        return 1
    end
    set -l sprint_id (string split \t -- $picked_sprint)[1]

    __aibpm_create $script_dir $project_id $sprint_id $argv
end

# Shared by aibpm's top-level create and the board's "new task" row: fzf-pick an
# assignee, prompt for a headline unless $argv[4..] already supplies one (the top-level
# caller forwards its own headline arg; the board calls with just the 3 named args).
function __aibpm_create --argument-names script_dir project_id sprint_id
    set -l headline $argv[4..]

    set -l prev $PWD
    cd $script_dir

    __aigit_step "Fetching members"
    set -l users (npx --no-install tsx src/pick-ticket.ts users 2>/tmp/aibpm.err)
    if test -z "$users"
        cd $prev
        __aigit_err "aibpm: no members returned"
        test -s /tmp/aibpm.err; and cat /tmp/aibpm.err >&2
        return 1
    end
    set -l picked_user (printf '%s\n' $users | fzf \
        --delimiter '\t' --with-nth '2..' \
        --prompt 'assignee> ' --height '60%' --reverse --border --header 'Pick an assignee')
    if test -z "$picked_user"
        cd $prev
        return 1
    end
    set -l editor_id (string split \t -- $picked_user)[1]
    set -l editor_label (string split \t -- $picked_user)[2]

    if test -z "$headline"
        read -P "$(__aigit_col -o cyan)? $(__aigit_col normal)Task headline: " headline
    end
    if test -z "$headline"
        cd $prev
        __aigit_err "aibpm: empty headline"
        return 1
    end

    __aigit_step "Creating task for $editor_label"
    set -l result (npx --no-install tsx src/add-task.ts createFor $project_id $sprint_id $editor_id $headline 2>/tmp/aibpm.err)
    cd $prev

    if test -z "$result"
        __aigit_err "aibpm: create failed"
        test -s /tmp/aibpm.err; and cat /tmp/aibpm.err >&2
        return 1
    end

    set -l parts (string split \t -- $result)
    __aigit_ok "task #$parts[1] created for $editor_label — $parts[2]"
end

# `aibpm board`: pick a sprint, then loop a board of its tasks grouped by assignee.
# Selecting a task sets its status (via __leantime_set_status); selecting the "new
# task" row creates one in the same sprint (via __aibpm_create). Both loop back to a
# refreshed board until you exit the sprint picker or the board picker itself.
function __aibpm_board --argument-names script_dir project_id
    set -l prev $PWD
    cd $script_dir
    __aigit_step "Fetching sprints"
    set -l sprints (npx --no-install tsx src/add-task.ts sprints $project_id 2>/tmp/aibpm.err)
    cd $prev
    if test -z "$sprints"
        __aigit_err "aibpm: no sprints returned"
        test -s /tmp/aibpm.err; and cat /tmp/aibpm.err >&2
        return 1
    end

    set -l picked_sprint (printf '%s\n' $sprints | fzf \
        --delimiter '\t' --with-nth '2..' \
        --prompt 'sprint> ' --height '60%' --reverse --border --header 'Pick a sprint to view')
    if test -z "$picked_sprint"
        return 0
    end
    set -l sprint_id (string split \t -- $picked_sprint)[1]
    set -l sprint_label (string split \t -- $picked_sprint)[2]

    while true
        cd $script_dir
        __aigit_step "Fetching board"
        set -l board (npx --no-install tsx src/pick-ticket.ts board $project_id $sprint_id 2>/tmp/aibpm.err)
        if test -z "$board"
            cd $prev
            __aigit_err "aibpm: no board data for this sprint"
            test -s /tmp/aibpm.err; and cat /tmp/aibpm.err >&2
            return 1
        end

        # </>: cycle that row's status one step (wraps), redrawn from local state
        # instantly — no network wait in the hot path (updates fire in the
        # background; see cycle-status in pick-ticket.ts). ctrl-r: full re-fetch,
        # for when you want the real, reconciled state (e.g. someone else edited
        # it). Both run with cwd = $script_dir so their relative `src/...` paths
        # resolve; that's why the fzf call stays inside the cd/cd-back pair below.
        set -l picked (printf '%s\n' $board | fzf \
            --delimiter '\t' --with-nth '2..' \
            --prompt 'task> ' --height '90%' --reverse --border \
            --header "$sprint_label   [</> cycle status]  [ctrl-r refresh]  [enter: full status picker / add task]" \
            --preview 'cat /tmp/leantime-pick/{1}.txt 2>/dev/null' \
            --preview-window 'right,55%,wrap' \
            --bind '<:execute-silent(npx --no-install tsx src/pick-ticket.ts cycle-status {1} prev)+reload(npx --no-install tsx src/pick-ticket.ts render-state)' \
            --bind '>:execute-silent(npx --no-install tsx src/pick-ticket.ts cycle-status {1} next)+reload(npx --no-install tsx src/pick-ticket.ts render-state)' \
            --bind "ctrl-r:reload(npx --no-install tsx src/pick-ticket.ts board $project_id $sprint_id)")
        cd $prev
        if test -z "$picked"
            return 0
        end
        set -l id (string split \t -- $picked)[1]

        switch $id
            case 0
                continue
            case new
                __aibpm_create $script_dir $project_id $sprint_id
            case '*'
                set -l result (__leantime_set_status $id)
                if test -n "$result"
                    __aigit_ok "ticket #$id -> $result"
                end
        end
    end
end
