# ai-git-fish — bootstrap the Leantime node backend that fisher can't copy.
#
# Fisher only installs functions/ completions/ conf.d/. The aibranch/aipr/aicommit
# ticket integration needs the TypeScript picker in ./leantime, so we fetch it from
# GitHub on install/update and run `npm i`. Override the target with LEANTIME_SCRIPT_DIR.

set -q AI_GIT_FISH_REPO; or set -g AI_GIT_FISH_REPO DucTam2411/ai-git-fish
set -q AI_GIT_FISH_BRANCH; or set -g AI_GIT_FISH_BRANCH main

function __ai_git_fish_dir
    set -l d "$LEANTIME_SCRIPT_DIR"
    test -z "$d"; and set d ~/.config/fish/leantime
    echo $d
end

function __ai_git_fish_bootstrap --description 'Download + install the Leantime backend'
    set -l dir (__ai_git_fish_dir)
    for dep in tar npm
        if not type -q $dep
            echo "ai-git-fish: '$dep' not found — install it, then run __ai_git_fish_bootstrap" >&2
            return 1
        end
    end

    echo "ai-git-fish: fetching Leantime backend into $dir ..." >&2
    set -l tmp (mktemp -d)
    # Prefer authenticated `gh` so this works on PRIVATE repos; fall back to public curl.
    if type -q gh; and gh auth status >/dev/null 2>&1
        gh api "repos/$AI_GIT_FISH_REPO/tarball/$AI_GIT_FISH_BRANCH" 2>/dev/null | tar -xz -C $tmp 2>/dev/null
    else if type -q curl
        set -l url "https://codeload.github.com/$AI_GIT_FISH_REPO/tar.gz/refs/heads/$AI_GIT_FISH_BRANCH"
        curl -sSL "$url" | tar -xz -C $tmp 2>/dev/null
    else
        echo "ai-git-fish: need 'gh' (private repo) or 'curl' (public) to fetch backend" >&2
        rm -rf $tmp
        return 1
    end
    set -l extracted (path filter -d $tmp/*/leantime)[1]
    if test -z "$extracted"
        echo "ai-git-fish: download/extract failed for $AI_GIT_FISH_REPO@$AI_GIT_FISH_BRANCH" >&2
        rm -rf $tmp
        return 1
    end

    mkdir -p $dir/src
    # copy code only — never clobber an existing .env
    cp $extracted/src/*.ts $dir/src/
    cp $extracted/package.json $dir/
    test -f $extracted/package-lock.json; and cp $extracted/package-lock.json $dir/
    if not test -f $dir/.env
        cp $extracted/.env.example $dir/.env
        echo "ai-git-fish: wrote $dir/.env — fill in LEANTIME_BASE_URL / LEANTIME_API_KEY / LEANTIME_USER_ID" >&2
    end
    rm -rf $tmp

    echo "ai-git-fish: installing node deps (tsx, dotenv)..." >&2
    set -l prev $PWD
    cd $dir
    npm install --no-audit --no-fund >/dev/null 2>&1
    set -l rc $status
    cd $prev
    if test $rc -ne 0
        echo "ai-git-fish: 'npm install' failed in $dir" >&2
        return 1
    end
    echo "ai-git-fish: backend ready. Set DEEPSEEK_API_KEY and edit $dir/.env to finish." >&2
end

function __ai_git_fish_install --on-event ai-git-fish_install
    __ai_git_fish_bootstrap
end

function __ai_git_fish_update --on-event ai-git-fish_update
    __ai_git_fish_bootstrap
end

function __ai_git_fish_uninstall --on-event ai-git-fish_uninstall
    functions -e __ai_git_fish_dir __ai_git_fish_bootstrap
    set -e AI_GIT_FISH_REPO AI_GIT_FISH_BRANCH
    echo "ai-git-fish: left "(__ai_git_fish_dir)" in place (holds your .env). Remove it manually if you want." >&2
end
