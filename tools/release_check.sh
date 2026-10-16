#!/bin/sh
# Checks that HEAD is ready to release as TAG, such as v0.1.0.
# Usage: sh tools/release_check.sh TAG
# The release Action runs it on the pushed tag. Run it before tagging, too.

tag=${1:?usage: sh tools/release_check.sh TAG}
fail() { printf 'FAILED: %s\n' "$1" >&2; exit 1; }

version=${tag#v}
printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || fail "tag $tag is not vX.Y.Z"

grep -q "^## $version " CHANGELOG.md || fail "CHANGELOG.md has no '## $version (date)' section"

minor_of() { sed -n 's/^local MAJOR, MINOR = "Polymorph-1.0", \([0-9]*\).*/\1/p'; }
minor=$(minor_of < Polymorph.lua)
[ -n "$minor" ] || fail "no MINOR in Polymorph.lua"

# Every commit before v0.1.0 had MINOR 1, so a copy embedded from one of them
# must lose to the first release too.
previous=$(git tag --list 'v*' --merged HEAD --sort=-v:refname | grep -vx "$tag" | head -n 1)
if [ -n "$previous" ]; then
    before=$(git show "$previous:Polymorph.lua" | minor_of)
else
    previous="commits before v0.1.0" before=1
fi
[ "$minor" -gt "$before" ] || fail "MINOR is $minor, and must be above $before from $previous"

printf 'release %s: MINOR %s, above %s from %s\n' "$tag" "$minor" "$before" "$previous"
