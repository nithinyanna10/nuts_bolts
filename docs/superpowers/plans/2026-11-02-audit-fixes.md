# Audit fixes (items 1, 5, 6)

> Written alongside the work, not before it: CLAUDE.md's "plan first" rule changed after coding had started. Tests were still written red first.

**Goal:** fix the three clear findings from the repo audit. Not done on purpose: 2 (delete shop code), 3 (wrong-guess cost), 4 (worker thread), 7 (.mcp.json).

1. **Tossed landing re-checks support** — `tests/toss_landing_test.gd` (supporter picked up mid-flight; two flights to one spot) fails first. Then `PileLayout._rest_height()` is shared by `plan_landing()` and `commit_landing()`, which now works the height out again at landing.
2. **Bad config reported, not crashed** — `challenge_generator_test.gd` first asserts `DifficultyConfig.problem()` flags empty `spec_props` / `target_types` and zero `object_count` / `pile_count`; `RoundManager.start_round` refuses such configs.
3. **One test runner** — `tests/run_all.sh [quick]`.

Verify: `tests/run_all.sh` all PASS. Then a fresh subagent reviews before the commit.
