#!/bin/sh

run_step() {
    step=$1
    shift
    printf '%s: %s\n' "$interpreter" "$step"
    "$@" || {
        status=$?
        printf 'FAILED: %s (%s), exit %s\n' "$step" "$interpreter" "$status" >&2
        exit "$status"
    }
}

if [ "$#" -eq 0 ]; then
    lua51=
    for candidate in "${LUA51:-}" lua5.1 .dev/lua51/bin/lua "$HOME/.local/lua51/bin/lua"; do
        [ -n "$candidate" ] || continue
        if "$candidate" -e 'if _VERSION ~= "Lua 5.1" then os.exit(1) end' 2>/dev/null; then
            lua51=$candidate
            break
        fi
    done
    if [ -z "$lua51" ]; then
        printf '%s\n' 'FAILED: no Lua 5.1 found. Set LUA51 or install lua5.1, .dev/lua51/bin/lua, or ~/.local/lua51/bin/lua.' >&2
        exit 1
    fi
    set -- "$lua51" lua
fi

for interpreter do
    run_step version "$interpreter" -e 'print(_VERSION)'
    for file in Polymorph.lua tests/*.lua tools/*.lua; do
        run_step "syntax $file" env CHECK_FILE="$file" "$interpreter" -e 'assert(loadfile(os.getenv("CHECK_FILE")))'
    done
    run_step core_test "$interpreter" tests/core_test.lua Polymorph.lua
    run_step skill_check_selftest "$interpreter" tools/skill_check_selftest.lua Polymorph.lua
done

interpreter=sh
run_step release_check_selftest sh tools/release_check_selftest.sh
