function __leantime_set_status --description 'fzf-pick a status for ticket $argv[1], apply it, print the resolved status name (nothing + failure status on cancel/error)'
    set -l script_dir "$LEANTIME_SCRIPT_DIR"
    test -z "$script_dir"
    and set script_dir ~/.config/fish/leantime

    set -l id $argv[1]
    if test -z "$id"
        __aigit_err "__leantime_set_status: missing ticket id"
        return 1
    end

    set -l prev $PWD
    cd $script_dir

    __aigit_step "Fetching statuses"
    set -l statuses (npx --no-install tsx src/set-status.ts labels 2>/tmp/leantime-set-status.err)
    if test -z "$statuses"
        cd $prev
        __aigit_err "__leantime_set_status: no statuses returned"
        test -s /tmp/leantime-set-status.err; and cat /tmp/leantime-set-status.err >&2
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
        return 1
    end
    set -l status_name (string split \t -- $picked)[2]

    __aigit_step "Updating ticket #$id -> $status_name"
    set -l result (npx --no-install tsx src/set-status.ts $id $status_name 2>/tmp/leantime-set-status.err)
    cd $prev

    if test -z "$result"
        __aigit_err "__leantime_set_status: failed to update ticket #$id"
        test -s /tmp/leantime-set-status.err; and cat /tmp/leantime-set-status.err >&2
        return 1
    end

    printf '%s' "$result"
end
