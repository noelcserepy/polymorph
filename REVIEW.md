Rules for the pr-reviewer runs on this repository's pull requests, read from the base branch.

## What you can run

Nothing in this repository touches real state, the network, or the game. Run whatever helps you reproduce a finding.

- Tests on Lua 5.1, the version WoW runs: `~/.local/lua51/bin/lua tests/core_test.lua Polymorph.lua`. Syntax check: `~/.local/lua51/bin/luac -p Polymorph.lua`. The host's plain `lua` is 5.5, newer than the 5.4 that CI also runs. Treat a failure only it shows as a portability note, and prove real bugs on 5.1.
- Probes: write a script in a temp directory outside the tree. Copy the fakes at the top of `tests/core_test.lua` (`CreateFrame`, `InCombatLockdown`, `fakeFrame`, `run`, `fire`), load the library with `loadfile("Polymorph.lua")("Polymorph", { dev = true })`, and drive the calls in question. A probe that shows wrong behavior on 5.1 makes a Finding.
- Mutation checks: break the code a new test claims to cover, rerun the tests on 5.1, and restore the file.

## What you cannot run

World of Warcraft does not run on this host, so no claim about the game client can be checked here. Those claims include what the client blocks in combat, how native animation groups draw, what getters return, and anything measured in frames per second or microseconds. The author measures them in-game with a private harness, and those notes are not in the repository.

- List each such claim the PR relies on under Not verified, and name it.
- The fakes in `tests/core_test.lua` model the client. When a change also changes a fake, check that the PR body says where the modelled behavior was measured. A fake that only matches the new code proves nothing.
- `AGENTS.md` requires the docs to back performance and game-behavior claims with measurements. A new claim in `README.md` or `docs/api.md` without a measurement in the PR body is a Spec item.
