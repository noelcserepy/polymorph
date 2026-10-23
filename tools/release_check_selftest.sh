#!/bin/sh
# Proves tools/release_check.sh tells good releases from bad ones.
# Usage: sh tools/release_check_selftest.sh [CHECKER]
# CHECKER defaults to tools/release_check.sh. Pass another copy to prove a
# broken checker fails here.
# Each case builds a throwaway git repo and names what the checker must print:
# "release" to pass it, or the failure message of the one check it breaks.

script=${1:-$(dirname "$0")/release_check.sh}
script=$(cd "$(dirname "$script")" && pwd)/$(basename "$script")
root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
failures=0 count=0

# repo DIR MINOR HEADING [TAGGED_MINOR]: a repo whose HEAD has MINOR and a
# changelog with HEADING. With TAGGED_MINOR, an earlier commit tagged v0.1.0 has it.
repo() {
    dir=$root/$1
    git init -q "$dir"
    if [ -n "${4:-}" ]; then
        write "$dir" "$4" '## 0.1.0 (2026-10-16)'
        commit "$dir" && git -C "$dir" tag v0.1.0
    fi
    write "$dir" "$2" "$3"
    commit "$dir"
}
write() {
    printf 'local MAJOR, MINOR = "Polymorph-1.0", %s\n' "$2" > "$1/Polymorph.lua"
    printf '# Changelog\n\n%s\n\n- A change.\n' "$3" > "$1/CHANGELOG.md"
}
commit() {
    git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm fixture
}

# check NAME TAG WANT MINOR HEADING [TAGGED_MINOR [pushed]]
# "pushed" tags HEAD with TAG first, as the release Action sees it.
# A WANT that starts with "FAILED:" must exit 1, and any other must exit 0.
check() {
    count=$((count + 1))
    repo "$count" "$4" "$5" "${6:-}"
    [ "${7:-}" = pushed ] && git -C "$root/$count" tag "$2"
    out=$(cd "$root/$count" && sh "$script" "$2" 2>&1)
    status=$?
    case $3 in FAILED:*) want_status=1 ;; *) want_status=0 ;; esac
    case $out in
        "$3"*) [ "$status" -eq "$want_status" ] ;;
        *) false ;;
    esac || {
        failures=$((failures + 1))
        printf 'FAILED: %s: want exit %s and "%s", got exit %s and "%s"\n' "$1" "$want_status" "$3" "$status" "$out" >&2
    }
}

no_section="FAILED: CHANGELOG.md has no"
check "first release" v0.1.0 "release v0.1.0" 2 '## 0.1.0 (2026-10-16)'
check "first release, pushed" v0.1.0 "release v0.1.0: MINOR 2, above 1 from commits before v0.1.0" 2 '## 0.1.0 (2026-10-16)' '' pushed
check "tag without v" 0.1.0 "FAILED: tag 0.1.0 is not vX.Y.Z" 2 '## 0.1.0 (2026-10-16)'
check "tag with two parts" v0.1 "FAILED: tag v0.1 is not vX.Y.Z" 2 '## 0.1 (2026-10-16)'
check "heading without date" v0.1.0 "$no_section" 2 '## 0.1.0 Unreleased'
check "heading with x for dots" v0.1.0 "$no_section" 2 '## 0x1x0 (2026-10-16)'
check "heading with trailing text" v0.1.0 "$no_section" 2 '## 0.1.0 (2026-10-16) extra'
check "heading for a longer version" v0.1.0 "$no_section" 2 '## 0.1.00 (2026-10-16)'
check "first release, MINOR unchanged" v0.1.0 "FAILED: MINOR is 1, and must be above 1" 1 '## 0.1.0 (2026-10-16)'
check "first release, MINOR decreased" v0.1.0 "FAILED: MINOR is 0, and must be above 1" 0 '## 0.1.0 (2026-10-16)'
check "second release" v0.2.0 "release v0.2.0: MINOR 3, above 2 from v0.1.0" 3 '## 0.2.0 (2026-11-01)' 2
check "second release, pushed" v0.2.0 "release v0.2.0: MINOR 3, above 2 from v0.1.0" 3 '## 0.2.0 (2026-11-01)' 2 pushed
check "second release, MINOR unchanged" v0.2.0 "FAILED: MINOR is 2, and must be above 2 from v0.1.0" 2 '## 0.2.0 (2026-11-01)' 2
check "second release, MINOR decreased" v0.2.0 "FAILED: MINOR is 1, and must be above 2 from v0.1.0" 1 '## 0.2.0 (2026-11-01)' 2

[ "$failures" -eq 0 ] || { printf 'FAILED: %s of %s release_check cases\n' "$failures" "$count" >&2; exit 1; }
printf 'release_check_selftest: %s cases passed\n' "$count"
