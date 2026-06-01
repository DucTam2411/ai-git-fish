function aibranch --description 'Pick a Leantime ticket and create/switch a git branch'
    # Usage: aibranch [type] [ticket_id]   (type defaults to feat: feat|fix|chore|...)
    #        ticket_id given -> skip the picker (aicommit passes an already-picked id).
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo "aibranch: not a git repo" >&2
        return 1
    end

    set -l type feat
    if test (count $argv) -ge 1
        set type $argv[1]
    end

    set -l id $argv[2]
    if test -z "$id"
        set id (__leantime_pick)
        or return 1
    end

    # Slug from cached preview line 1: "#<id>  <headline>" (empty if no cache -> type/id).
    set -l head (sed -n '1p' /tmp/leantime-pick/$id.txt 2>/dev/null | string replace -r '^#\S+\s+' '')
    set -l slug (string lower -- $head \
        | string replace -r -a '[^a-z0-9]+' '-' \
        | string trim -c '-' \
        | string sub -l 40 \
        | string trim -c '-')

    set -l branch "$type/$id-$slug"

    # Already on it? nothing to do.
    if test (git rev-parse --abbrev-ref HEAD 2>/dev/null) = "$branch"
        echo "aibranch: already on $branch" >&2
        return 0
    end

    # Branch exists (any matching ref) → switch to it. Else create.
    if git show-ref --verify --quiet "refs/heads/$branch"
        echo "aibranch: switching to existing branch $branch" >&2
        git switch $branch
    else
        echo "aibranch: creating branch $branch" >&2
        git switch -c $branch
    end
end
