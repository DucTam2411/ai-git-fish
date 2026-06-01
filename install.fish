#!/usr/bin/env fish
# ai-git-fish installer.
#   fish (curl -sL https://raw.githubusercontent.com/DucTam2411/ai-git-fish/main/install.fish | psub)
#
# Checks deps (offers to install on macOS/Linux), installs the fisher plugin,
# then walks you through DEEPSEEK_API_KEY + the Leantime .env and fzf-picks
# your LEANTIME_USER_ID. Re-runnable / idempotent.

set -g REPO DucTam2411/ai-git-fish
set -g BRANCH main

function _hd;   set_color -o cyan;   echo ""; echo "❯ $argv"; set_color normal; end
function _ok;   echo "  "(set_color green)"✓"(set_color normal)" $argv"; end
function _warn; echo "  "(set_color -o yellow)"▲"(set_color normal)" $argv" >&2; end
function _err;  echo "  "(set_color -o red)"✗"(set_color normal)" $argv" >&2; end
function _banner
    set -l c (set_color -o brmagenta); set -l d (set_color brblack); set -l n (set_color normal)
    set -l padded (string pad --right --width 42 -- "guided installer")
    echo ""
    echo "$c  ╭─ ✨ ai-git-fish ───────────────────────────╮$n"
    echo "$c  │  $d$padded$c│$n"
    echo "$c  ╰────────────────────────────────────────────╯$n"
end
_banner
function _ask # _ask "prompt" default-yes?
    set -l suffix "[y/N]"; test "$argv[2]" = yes; and set suffix "[Y/n]"
    read -l -P "  $argv[1] $suffix " r
    test -z "$r"; and set r $argv[2]
    string match -qi 'y*' -- $r
end

# ---------------------------------------------------------------- OS + pkg mgr
set -g OS unknown
switch (uname)
    case Darwin; set OS mac
    case Linux;  set OS linux
end

set -g PKG ""        # the install command prefix
set -g PKGMGR ""     # brew|apt|dnf|pacman
if type -q brew
    set PKGMGR brew; set PKG brew install
else if type -q apt-get
    set PKGMGR apt; set PKG sudo apt-get install -y
else if type -q dnf
    set PKGMGR dnf; set PKG sudo dnf install -y
else if type -q pacman
    set PKGMGR pacman; set PKG sudo pacman -S --noconfirm
end

# generic dep name -> package name for the detected manager
function _pkgname # _pkgname <generic>
    switch $argv[1]
        case node
            switch $PKGMGR
                case apt dnf pacman; echo nodejs npm
                case '*'; echo node
            end
        case gh
            switch $PKGMGR
                case pacman; echo github-cli
                case '*'; echo gh
            end
        case '*'; echo $argv[1]
    end
end

function _try_install # _try_install <generic>
    if test -z "$PKG"
        _warn "no supported package manager (brew/apt/dnf/pacman) — install '$argv[1]' yourself"
        return 1
    end
    set -l names (_pkgname $argv[1])
    echo "    installing $names via $PKGMGR ..."
    $PKG $names
end

# ---------------------------------------------------------------- deps
_hd "Checking dependencies"
# required: git curl tar jq fzf node ; gh checked separately (needs auth too)
set -g MISSING
for dep in git curl tar jq fzf node npm gh
    if type -q $dep
        _ok "$dep"
    else
        _warn "$dep missing"
        set -a MISSING $dep
    end
end
# node implies npm; de-dup the pair
if contains node $MISSING; or contains npm $MISSING
    set MISSING (string match -v npm -- $MISSING)
end

if test (count $MISSING) -gt 0
    echo ""
    if test "$OS" = mac -a -z "$PKG"
        _warn "Homebrew not found. Install it first: https://brew.sh"
    end
    if test -n "$PKG"; and _ask "Install missing: $MISSING ?" yes
        for d in $MISSING
            _try_install $d; and _ok "installed $d"; or _err "failed to install $d"
        end
    else
        _warn "skipping auto-install — these must be present for the tools to work"
    end
end

# gitleaks is optional (aicommit secret scan) — mention only
type -q gitleaks; and _ok "gitleaks (optional secret scan)"; or _warn "gitleaks not found (optional) — aicommit will skip the staged-secret scan"

# hard stop if the essentials are still absent
for dep in git curl jq node npm fzf
    if not type -q $dep
        _err "'$dep' still missing — aborting. Install it and re-run."
        return 1
    end
end

# ---------------------------------------------------------------- gh auth
_hd "GitHub CLI auth"
if type -q gh
    if gh auth status >/dev/null 2>&1
        _ok "gh authenticated"
    else
        _warn "gh not authenticated"
        if _ask "Run 'gh auth login' now?" yes
            gh auth login
        else
            _warn "aipr needs gh auth — run 'gh auth login' before using it"
        end
    end
else
    _warn "gh not installed — aipr (PR creation) will not work"
end

# ---------------------------------------------------------------- fisher + plugin
_hd "Installing the fisher plugin"
if not functions -q fisher
    _warn "fisher not found — installing it"
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
    and fisher install jorgebucaran/fisher
end
if functions -q fisher
    fisher install $REPO
    and _ok "plugin installed"
    or begin; _err "fisher install failed"; return 1; end
else
    _err "could not bootstrap fisher — see https://github.com/jorgebucaran/fisher"
    return 1
end

# leantime backend dir (the conf.d hook should have populated it)
set -g LT_DIR "$LEANTIME_SCRIPT_DIR"
test -z "$LT_DIR"; and set LT_DIR ~/.config/fish/leantime
if not test -d "$LT_DIR/src"
    _warn "backend not bootstrapped — fetching it now"
    functions -q __ai_git_fish_bootstrap; and __ai_git_fish_bootstrap
end
if not test -d "$LT_DIR/src"
    _err "Leantime backend missing at $LT_DIR — cannot continue"
    return 1
end

# ---------------------------------------------------------------- DeepSeek key
_hd "DeepSeek API key (for aicommit / aipr)"
if set -q DEEPSEEK_API_KEY; and test -n "$DEEPSEEK_API_KEY"
    _ok "DEEPSEEK_API_KEY already set"
else
    read -l -P "  Enter DEEPSEEK_API_KEY (blank to skip): " dskey
    if test -n "$dskey"
        set -Ux DEEPSEEK_API_KEY $dskey   # universal var: persists, no file editing
        _ok "saved as a universal variable"
    else
        _warn "skipped — set DEEPSEEK_API_KEY later or aicommit/aipr won't run"
    end
end

# ---------------------------------------------------------------- Leantime .env
_hd "Leantime configuration ($LT_DIR/.env)"
set -l cur_base ""; set -l cur_key ""; set -l cur_uid ""
if test -f "$LT_DIR/.env"
    set cur_base (string replace -rf '^LEANTIME_BASE_URL=' '' -- (grep '^LEANTIME_BASE_URL=' $LT_DIR/.env))
    set cur_key  (string replace -rf '^LEANTIME_API_KEY='  '' -- (grep '^LEANTIME_API_KEY='  $LT_DIR/.env))
    set cur_uid  (string replace -rf '^LEANTIME_USER_ID='  '' -- (grep '^LEANTIME_USER_ID='  $LT_DIR/.env))
end

read -l -P "  LEANTIME_BASE_URL [$cur_base]: " base; test -z "$base"; and set base $cur_base
read -l -P "  LEANTIME_API_KEY  ["(test -n "$cur_key"; and echo '****'; or echo '')"]: " key; test -z "$key"; and set key $cur_key

if test -z "$base" -o -z "$key"
    _warn "base url / api key empty — writing what we have; aibranch/ticket linking will be limited"
end

# write base+key first so the users fetch can authenticate
printf 'LEANTIME_BASE_URL=%s\nLEANTIME_API_KEY=%s\nLEANTIME_USER_ID=%s\n' \
    "$base" "$key" "$cur_uid" > $LT_DIR/.env
_ok "wrote base url + api key"

# ---------------------------------------------------------------- pick user id
_hd "Selecting your Leantime user (LEANTIME_USER_ID)"
set -g UID_VAL "$cur_uid"
if test -n "$base" -a -n "$key"
    set -l prev $PWD
    cd $LT_DIR
    set -l rows (npx --no-install tsx src/pick-ticket.ts users 2>/dev/null)
    cd $prev
    if test (count $rows) -gt 0
        set -l picked (printf '%s\n' $rows | fzf \
            --delimiter \t --with-nth '2..' \
            --prompt 'your user> ' --height 60% --reverse --border \
            --header 'Pick YOUR Leantime account')
        if test -n "$picked"
            set UID_VAL (string split \t -- $picked)[1]
            _ok "selected user id $UID_VAL"
        else
            _warn "no selection — keeping LEANTIME_USER_ID=$UID_VAL"
        end
    else
        _warn "could not fetch users (RPC unsupported or bad credentials)"
        read -l -P "  Enter LEANTIME_USER_ID manually (blank to skip): " m
        test -n "$m"; and set UID_VAL $m
    end
else
    _warn "no base/key — skipping user fetch"
end

# rewrite .env with the resolved user id
printf 'LEANTIME_BASE_URL=%s\nLEANTIME_API_KEY=%s\nLEANTIME_USER_ID=%s\n' \
    "$base" "$key" "$UID_VAL" > $LT_DIR/.env
_ok "wrote $LT_DIR/.env"

# ---------------------------------------------------------------- done
_hd "Done"
echo "  Commands: aicommit  aibranch  aipr   (open a new shell if not picked up)"
test -n "$UID_VAL"; and echo "  Leantime user id: $UID_VAL"
set -q DEEPSEEK_API_KEY; and test -n "$DEEPSEEK_API_KEY"; or _warn "remember to set DEEPSEEK_API_KEY"
