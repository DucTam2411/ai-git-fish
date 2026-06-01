# ai-git-fish — shared pretty logging. All output to stderr so it never pollutes
# captured stdout (commit messages, PR bodies). Colors auto-disable when stderr
# isn't a tty or NO_COLOR is set.

function __aigit_col # __aigit_col <set_color args...> -> escape codes (or nothing)
    if isatty stderr; and not set -q NO_COLOR
        set_color $argv
    end
end

function __aigit_banner # __aigit_banner [subtitle]
    set -l sub "aicommit · aibranch · aipr"
    test -n "$argv[1]"; and set sub "$argv[1]"
    set -l c (__aigit_col -o brmagenta); set -l d (__aigit_col brblack); set -l n (__aigit_col normal)
    echo "" >&2
    echo "$c  ╭─ ✨ ai-git-fish ───────────────────────────╮$n" >&2
    printf '%s  │  %s%-42s%s│%s\n' "$c" "$d" "$sub" "$c" "$n" >&2
    echo "$c  ╰────────────────────────────────────────────╯$n" >&2
end

function __aigit_step # cyan ❯  — a stage starting
    echo "$(__aigit_col -o cyan)❯$(__aigit_col normal) $argv" >&2
end
function __aigit_ok # green ✓
    echo "  $(__aigit_col green)✓$(__aigit_col normal) $argv" >&2
end
function __aigit_warn # yellow ▲
    echo "  $(__aigit_col -o yellow)▲$(__aigit_col normal) $argv" >&2
end
function __aigit_err # red ✗
    echo "  $(__aigit_col -o red)✗$(__aigit_col normal) $argv" >&2
end
function __aigit_info # dim ·
    echo "  $(__aigit_col brblack)·$(__aigit_col normal) $argv" >&2
end

function __aigit_confirm # __aigit_confirm "question" [yes] -> status 0 if yes
    set -l suffix "[y/N]"; test "$argv[2]" = yes; and set suffix "[Y/n]"
    read -l -P "  $(__aigit_col -o cyan)?$(__aigit_col normal) $argv[1] $suffix " r
    test -z "$r"; and set r $argv[2]
    string match -qi 'y*' -- $r
end
