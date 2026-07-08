function aigit --description 'Manage ai-git-fish: update | uninstall | config | version | help'
    set -l repo "$AI_GIT_FISH_REPO"; test -z "$repo"; and set repo DucTam2411/ai-git-fish
    set -l dir "$LEANTIME_SCRIPT_DIR"; test -z "$dir"; and set dir ~/.config/fish/leantime

    switch "$argv[1]"
        case update up upgrade
            __aigit_banner "update"
            if not functions -q fisher
                __aigit_err "fisher not found — can't update"
                return 1
            end
            __aigit_step "Updating $repo"
            if fisher update $repo
                __aigit_ok "plugin + backend updated"
            else
                __aigit_err "fisher update failed"
                return 1
            end

        case uninstall remove rm
            __aigit_banner "uninstall"
            if functions -q fisher
                __aigit_step "Removing fisher plugin $repo"
                fisher remove $repo; and __aigit_ok "plugin removed"
            else
                __aigit_warn "fisher not found — skipping plugin removal"
            end
            if test -d "$dir"
                if __aigit_confirm "Delete backend dir $dir (holds your .env secrets)?"
                    rm -rf $dir; and __aigit_ok "deleted $dir"
                else
                    __aigit_info "kept $dir"
                end
            end
            if set -q DEEPSEEK_API_KEY
                if __aigit_confirm "Erase the universal DEEPSEEK_API_KEY variable?"
                    set -e DEEPSEEK_API_KEY; and __aigit_ok "erased DEEPSEEK_API_KEY"
                end
            end
            __aigit_ok "done"

        case config setup reconfigure
            __aigit_configure $dir

        case version v --version
            __aigit_banner "version"
            __aigit_info "repo    : $repo"
            __aigit_info "backend : $dir"(test -d "$dir/src"; and echo ' (installed)'; or echo ' (missing)')
            if functions -q fisher
                set -l line (fisher list 2>/dev/null | string match -e "$repo")
                test -n "$line"; and __aigit_ok "fisher: $line"; or __aigit_warn "not managed by fisher (raw install?)"
            end

        case '' help -h --help
            __aigit_banner
            echo "  Usage: aigit <command>" >&2
            echo "" >&2
            __aigit_info "update      pull the latest plugin + backend (fisher update)"
            __aigit_info "config      re-enter Leantime creds + re-pick your user id"
            __aigit_info "uninstall   remove plugin, optionally backend dir + key"
            __aigit_info "version     show repo / backend / fisher status"
            __aigit_info "help        this message"

        case '*'
            __aigit_err "unknown command: $argv[1]"
            aigit help
            return 1
    end
end

# Re-run the interactive Leantime setup (creds + fzf user pick). Shared by `aigit config`.
function __aigit_configure
    set -l dir $argv[1]
    __aigit_banner "config"
    if not test -d "$dir/src"
        __aigit_err "backend not installed at $dir — run 'aigit update' first"
        return 1
    end

    # DeepSeek key
    if set -q DEEPSEEK_API_KEY; and test -n "$DEEPSEEK_API_KEY"
        __aigit_ok "DEEPSEEK_API_KEY already set"
    else
        read -l -P "  $(__aigit_col -o cyan)?$(__aigit_col normal) DEEPSEEK_API_KEY (blank to skip): " k
        test -n "$k"; and set -Ux DEEPSEEK_API_KEY $k; and __aigit_ok "saved DEEPSEEK_API_KEY"
    end

    # current .env values as defaults
    set -l cur_base ""; set -l cur_key ""; set -l cur_uid ""
    set -l cur_slack_url ""; set -l cur_slack_map ""; set -l cur_slack_reviewers ""
    if test -f "$dir/.env"
        set cur_base (string replace -rf '^LEANTIME_BASE_URL=' '' -- (grep '^LEANTIME_BASE_URL=' $dir/.env))
        set cur_key  (string replace -rf '^LEANTIME_API_KEY='  '' -- (grep '^LEANTIME_API_KEY='  $dir/.env))
        set cur_uid  (string replace -rf '^LEANTIME_USER_ID='  '' -- (grep '^LEANTIME_USER_ID='  $dir/.env))
        set cur_slack_url       (string replace -rf '^SLACK_WEBHOOK_URL='  '' -- (grep '^SLACK_WEBHOOK_URL='  $dir/.env))
        set cur_slack_map       (string replace -rf '^SLACK_USER_MAP='     '' -- (grep '^SLACK_USER_MAP='     $dir/.env))
        set cur_slack_reviewers (string replace -rf '^SLACK_PR_REVIEWERS=' '' -- (grep '^SLACK_PR_REVIEWERS=' $dir/.env))
    end
    read -l -P "  $(__aigit_col -o cyan)?$(__aigit_col normal) LEANTIME_BASE_URL [$cur_base]: " base
    test -z "$base"; and set base $cur_base
    read -l -P "  $(__aigit_col -o cyan)?$(__aigit_col normal) LEANTIME_API_KEY ["(test -n "$cur_key"; and echo '****'; or echo '')"]: " key
    test -z "$key"; and set key $cur_key

    # Slack (optional; used by aipr to notify reviewers) — blank keeps current value
    read -l -P "  $(__aigit_col -o cyan)?$(__aigit_col normal) SLACK_WEBHOOK_URL [$(test -n "$cur_slack_url"; and echo '****'; or echo 'blank to skip')]: " slack_url
    test -z "$slack_url"; and set slack_url $cur_slack_url
    set -l slack_map $cur_slack_map
    set -l slack_reviewers $cur_slack_reviewers
    if test -n "$slack_url"
        read -l -P "  $(__aigit_col -o cyan)?$(__aigit_col normal) SLACK_USER_MAP JSON (name->Slack id) [$(test -n "$cur_slack_map"; and echo 'keep current'; or echo 'blank to skip')]: " m
        test -n "$m"; and set slack_map $m
        read -l -P "  $(__aigit_col -o cyan)?$(__aigit_col normal) SLACK_PR_REVIEWERS (comma-separated names) [$cur_slack_reviewers]: " r
        test -n "$r"; and set slack_reviewers $r
    end

    printf 'LEANTIME_BASE_URL=%s\nLEANTIME_API_KEY=%s\nLEANTIME_USER_ID=%s\nSLACK_WEBHOOK_URL=%s\nSLACK_USER_MAP=%s\nSLACK_PR_REVIEWERS=%s\n' \
        "$base" "$key" "$cur_uid" "$slack_url" "$slack_map" "$slack_reviewers" > $dir/.env

    # fzf-pick the user
    set -l uid $cur_uid
    if test -n "$base" -a -n "$key"
        __aigit_step "Fetching Leantime users"
        set -l prev $PWD; cd $dir
        set -l rows (npx --no-install tsx src/pick-ticket.ts users 2>/dev/null)
        cd $prev
        if test (count $rows) -gt 0
            set -l picked (printf '%s\n' $rows | fzf --delimiter \t --with-nth '2..' \
                --prompt 'your user> ' --height 60% --reverse --border --header 'Pick YOUR account')
            test -n "$picked"; and set uid (string split \t -- $picked)[1]; and __aigit_ok "user id $uid"
        else
            __aigit_warn "could not fetch users — keeping id $uid"
        end
    end
    printf 'LEANTIME_BASE_URL=%s\nLEANTIME_API_KEY=%s\nLEANTIME_USER_ID=%s\nSLACK_WEBHOOK_URL=%s\nSLACK_USER_MAP=%s\nSLACK_PR_REVIEWERS=%s\n' \
        "$base" "$key" "$uid" "$slack_url" "$slack_map" "$slack_reviewers" > $dir/.env
    __aigit_ok "wrote $dir/.env"
end
