#!/bin/sh

set -eu

target=src/http/ngx_http_special_response.c
signature='^[[:space:]]*"<hr><center>"[[:space:]]*NGINX_SERVER[[:space:]]*"</center>"[[:space:]]*CRLF[[:space:]]*$'
tmpdir=$(mktemp -d) || exit 1
cleanup() {
    rm -rf -- "$tmpdir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

sed "\|$signature|d" "$target" > "$tmpdir/special_response.c"

if cmp -s "$target" "$tmpdir/special_response.c"; then
    exit 0
fi

diff -u "$target" "$tmpdir/special_response.c" \
    > "$tmpdir/nginx-hardening.patch" || [ "$?" -eq 1 ]
patch --forward --silent "$target" < "$tmpdir/nginx-hardening.patch"

if grep -q "$signature" "$target"; then
    echo "failed to remove nginx signature from error pages" >&2
    exit 1
fi
