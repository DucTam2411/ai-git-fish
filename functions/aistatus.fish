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

        set -l result (__leantime_set_status $id)
        if test -n "$result"
            __aigit_ok "ticket #$id -> $result"
        end
    end
end
