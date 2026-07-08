function aitask --description 'Create a Leantime task: fzf-pick project + sprint, create ticket'
    set -l script_dir "$LEANTIME_SCRIPT_DIR"
    test -z "$script_dir"
    and set script_dir ~/.config/fish/leantime

    if not type -q fzf
        __aigit_err "aitask: fzf not found (brew install fzf)"
        return 1
    end
    if not type -q npx
        __aigit_err "aitask: npx not found (install Node.js)"
        return 1
    end
    if not test -d "$script_dir"
        __aigit_err "aitask: script dir not found: $script_dir"
        return 1
    end

    # --- headline: arg (joined) or interactive prompt ---
    set -l headline "$argv"
    if test -z "$headline"
        read -l -P (__aigit_col -o cyan)'? '(__aigit_col normal)'Task headline: ' headline
    end
    if test -z "$headline"
        __aigit_err "aitask: empty headline"
        return 1
    end

    set -l prev $PWD
    cd $script_dir

    # --- pick project ---
    __aigit_step "Fetching Leantime projects"
    set -l projects (npx --no-install tsx src/add-task.ts projects 2>/tmp/aitask.err)
    if test -z "$projects"
        cd $prev
        __aigit_err "aitask: no projects returned"
        test -s /tmp/aitask.err; and cat /tmp/aitask.err >&2
        return 1
    end
    set -l picked_project (printf '%s\n' $projects | fzf \
        --delimiter '\t' --with-nth '2..' \
        --prompt 'project> ' --height '60%' --reverse --border --header 'Pick a project')
    if test -z "$picked_project"
        cd $prev
        return 1
    end
    set -l project_id (string split \t -- $picked_project)[1]

    # --- pick sprint ---
    __aigit_step "Fetching sprints"
    set -l sprints (npx --no-install tsx src/add-task.ts sprints $project_id 2>/tmp/aitask.err)
    if test -z "$sprints"
        cd $prev
        __aigit_err "aitask: no sprints returned"
        test -s /tmp/aitask.err; and cat /tmp/aitask.err >&2
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
    __aigit_step "Creating task"
    set -l result (npx --no-install tsx src/add-task.ts create $project_id $sprint_id $headline 2>/tmp/aitask.err)
    cd $prev

    if test -z "$result"
        __aigit_err "aitask: create failed"
        test -s /tmp/aitask.err; and cat /tmp/aitask.err >&2
        return 1
    end

    set -l parts (string split \t -- $result)
    __aigit_ok "task #$parts[1] created — $parts[2]"
end
