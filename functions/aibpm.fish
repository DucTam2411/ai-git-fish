function aibpm --description 'Create a BPM (Anymateme Web platform) Leantime task: fzf-pick assignee + sprint, create ticket'
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

    # --- headline: arg (joined) or interactive prompt ---
    set -l headline "$argv"
    if test -z "$headline"
        read -P "$(__aigit_col -o cyan)? $(__aigit_col normal)Task headline: " headline
    end
    if test -z "$headline"
        __aigit_err "aibpm: empty headline"
        return 1
    end

    set -l prev $PWD
    cd $script_dir

    # --- pick assignee ---
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

    # --- pick sprint ---
    __aigit_step "Fetching sprints"
    set -l sprints (npx --no-install tsx src/add-task.ts sprints $project_id 2>/tmp/aibpm.err)
    if test -z "$sprints"
        cd $prev
        __aigit_err "aibpm: no sprints returned"
        test -s /tmp/aibpm.err; and cat /tmp/aibpm.err >&2
        return 1
    end
    set -l picked_sprint (printf '%s\n' $sprints | fzf \
        --delimiter '\t' --with-nth '2..' \
        --prompt 'sprint> ' --height '60%' --reverse --border --header 'Pick a sprint')
    if test -z "$picked_sprint"
        cd $prev
        return 1
    end
    set -l sprint_id (string split \t -- $picked_sprint)[1]

    # --- create ---
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
