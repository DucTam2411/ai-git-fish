function aidone --description 'fzf-pick a Leantime ticket and mark it Done'
    set -l script_dir "$LEANTIME_SCRIPT_DIR"
    test -z "$script_dir"
    and set script_dir ~/.config/fish/leantime

    if not type -q npx
        __aigit_err "aidone: npx not found (install Node.js)"
        return 1
    end
    if not test -d "$script_dir"
        __aigit_err "aidone: script dir not found: $script_dir"
        return 1
    end

    set -l id $argv[1]
    if test -z "$id"; and git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set id (string match -rg '(\d{3,})' -- (git rev-parse --abbrev-ref HEAD 2>/dev/null))
    end
    if test -z "$id"
        set id (__leantime_pick)
        or return 1
    end

    __aigit_step "Marking ticket #$id Done"
    set -l prev $PWD
    cd $script_dir
    set -l result (npx --no-install tsx src/set-status.ts $id Done 2>/tmp/aidone.err)
    cd $prev

    if test -z "$result"
        __aigit_err "aidone: failed to update ticket #$id"
        test -s /tmp/aidone.err; and cat /tmp/aidone.err >&2
        return 1
    end

    __aigit_ok "ticket #$id -> $result"
end
