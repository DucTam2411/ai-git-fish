function __leantime_pick --description 'fzf-pick a Leantime ticket assigned to me, echo its id'
    # Standalone picker dir (override with LEANTIME_SCRIPT_DIR). Self-contained: survives repo removal.
    set -l script_dir "$LEANTIME_SCRIPT_DIR"
    test -z "$script_dir"
    and set script_dir ~/.config/fish/leantime

    if not type -q fzf
        echo "__leantime_pick: fzf not found (brew install fzf)" >&2
        return 1
    end
    if not type -q npx
        echo "__leantime_pick: npx not found (install Node.js)" >&2
        return 1
    end
    if not test -d "$script_dir"
        echo "__leantime_pick: script dir not found: $script_dir" >&2
        return 1
    end

    echo "__leantime_pick: fetching your newest Leantime tickets..." >&2
    # NOTE: fish command substitution shares the shell's cwd (no subshell), so any `cd`
    # inside (...) leaks to the caller. Save + restore pwd around the fetch.
    set -l prev $PWD
    cd $script_dir
    set -l list (npx --no-install tsx src/pick-ticket.ts 2>/tmp/leantime-pick.err)
    cd $prev
    if test -z "$list"
        echo "__leantime_pick: no tickets returned (check LEANTIME_* env in $script_dir/.env)" >&2
        test -s /tmp/leantime-pick.err; and cat /tmp/leantime-pick.err >&2
        return 1
    end

    # Field 1 = id, field 2 = headline. Preview reads pre-rendered cache file.
    set -l picked (printf '%s\n' $list | fzf \
        --delimiter '\t' --with-nth '2..' \
        --prompt 'ticket> ' --height '85%' --reverse --border \
        --preview 'cat /tmp/leantime-pick/{1}.txt' \
        --preview-window 'right,55%,wrap')

    test -z "$picked"
    and return 1

    printf '%s' (string split \t -- $picked)[1]
end
