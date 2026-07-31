function aistatus --description 'Dashboard loop: fzf-pick a Leantime ticket, set its status, repeat'
    set -l script_dir "$LEANTIME_SCRIPT_DIR"
    test -z "$script_dir"
    and set script_dir ~/.config/fish/leantime

    if not type -q fzf
        __aigit_err "aistatus: fzf not found (brew install fzf)"
        return 1
    end
    if not type -q npx
        __aigit_err "aistatus: npx not found (install Node.js)"
        return 1
    end
    if not test -d "$script_dir"
        __aigit_err "aistatus: script dir not found: $script_dir"
        return 1
    end

    # First loop turn only: an explicit id skips the ticket picker. Every turn
    # after that re-opens the picker (fresh fetch -> shows the status you just set).
    set -l next_id $argv[1]

    while true
        set -l id $next_id
        set -e next_id
        if test -z "$id"
            set id (__leantime_pick)
            or return 0
        end

        set -l prev $PWD
        cd $script_dir

        __aigit_step "Fetching statuses"
        set -l statuses (npx --no-install tsx src/set-status.ts labels 2>/tmp/aistatus.err)
        if test -z "$statuses"
            cd $prev
            __aigit_err "aistatus: no statuses returned"
            test -s /tmp/aistatus.err; and cat /tmp/aistatus.err >&2
            return 1
        end

        set -l picked (printf '%s\n' $statuses | fzf \
            --delimiter '\t' --with-nth '2..' \
            --prompt 'status> ' --height '85%' --reverse --border \
            --header "Set status for ticket #$id" \
            --preview "cat /tmp/leantime-pick/$id.txt" \
            --preview-window 'right,55%,wrap')
        if test -z "$picked"
            cd $prev
            continue
        end
        set -l status_name (string split \t -- $picked)[2]

        __aigit_step "Updating ticket #$id -> $status_name"
        set -l result (npx --no-install tsx src/set-status.ts $id $status_name 2>/tmp/aistatus.err)
        cd $prev

        if test -z "$result"
            __aigit_err "aistatus: failed to update ticket #$id"
            test -s /tmp/aistatus.err; and cat /tmp/aistatus.err >&2
            continue
        end

        __aigit_ok "ticket #$id -> $result"
    end
end
