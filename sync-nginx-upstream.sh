#!/bin/sh

set -eu

remote=upstream
url=https://github.com/nginx/nginx.git
marker=.nginx-upstream

root=$(git rev-parse --show-toplevel)
cd "$root"

if [ -n "$(git status --porcelain)" ]; then
    echo "error: commit or stash local changes first" >&2
    exit 1
fi

if current_url=$(git remote get-url "$remote" 2>/dev/null); then
    case "$current_url" in
        https://github.com/nginx/nginx|https://github.com/nginx/nginx.git|git@github.com:nginx/nginx.git) ;;
        *)
            echo "error: $remote points to $current_url, expected $url" >&2
            exit 1
            ;;
    esac
else
    git remote add "$remote" "$url"
fi

git fetch --tags "$remote" master

read -r base < "$marker"
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || {
    echo "error: invalid commit in $marker: $base" >&2
    exit 1
}

target=$(git rev-parse "$remote/master")
git merge-base --is-ancestor "$base" "$target" || {
    echo "error: $base is not an ancestor of $remote/master" >&2
    exit 1
}

if [ "$base" = "$target" ]; then
    echo "Already up to date: $target"
    exit 0
fi

patch=$(mktemp)
index=$(mktemp)
cleanup() {
    rm -f -- "$patch" "$index"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

git diff --binary --full-index "$base" "$target" > "$patch"
cp "$(git rev-parse --git-path index)" "$index"
GIT_INDEX_FILE=$index git apply --check --3way "$patch"
cp "$(git rev-parse --git-path index)" "$index"
GIT_INDEX_FILE=$index git apply --3way "$patch"
printf '%s\n' "$target" > "$marker"

echo "Applied upstream changes: $base..$target"
echo "Review and commit the unstaged changes."
