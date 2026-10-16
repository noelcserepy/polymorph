Rules for the pr-reviewer runs on this repository's pull requests, read from the base branch.

## What you can run

Nothing in this repository touches real state, the network, or the game. Run whatever helps you reproduce a finding.

- Checks: `sh tools/check.sh` finds Lua 5.1 and also runs plain `lua`. Use `sh tools/check.sh LUA...` for specific interpreters. The host's plain `lua` is 5.5, newer than the 5.4 that CI also runs. Treat a failure only it shows as a portability note, and prove real bugs on 5.1.
- Probes: write a script in a temp directory outside the tree and run it from the repository root. Start it with `local wow = dofile("tests/fake_wow.lua")`, which installs the fake client (`CreateFrame`, `wow.combat`, `wow.run`, `wow.fire`), load the library with `loadfile("Polymorph.lua")("Polymorph", { dev = true })`, and drive the calls in question. A probe that shows wrong behavior on 5.1 makes a Finding.
- Mutation checks: break the code a new test claims to cover, rerun the tests on 5.1, and restore the file.

## What you cannot run

World of Warcraft does not run on this host, so no claim about the game client can be checked here. Those claims include what the client blocks in combat, how native animation groups draw, what getters return, and anything measured in frames per second or microseconds. The author measures them in-game with a private harness, and those notes are not in the repository.

- List each such claim the PR relies on under Not verified, and name it.
- `tests/fake_wow.lua` is the one model of the client, loaded by both `tests/core_test.lua` and `tools/skill_check.lua`. Each line in it that models client behavior (an order, a timing, a value, what a getter returns, what the client blocks) cites the in-game job and date that measured it, or says `UNMEASURED`, or `CONTRADICTED` with the evidence. When a change adds or changes such a line, Spec lists every one without a cited measurement, with its line in `tests/fake_wow.lua`, whether or not the PR body calls it an assumption. A modelling line with no citation and no tag is a Spec item too. A fake that only matches the new code proves nothing.
- `AGENTS.md` requires the docs to back performance and game-behavior claims with measurements. A new claim in `README.md` or `docs/api.md` without a measurement in the PR body is a Spec item.
