# Audit decisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Carry out the owner's decisions on the audit: delete dead shop/magnet code, ignore `.mcp.json`, land tossed objects with no snap, make `DifficultyConfig.problem()` cover every generator crash (with a fuzz test), then run the full suite.

**Spec:** The owner's decision list (this conversation) and `CLAUDE.md`.

## Global Constraints

- Static typing; tunables are exported vars, never hardcoded in logic.
- Tests first (red), then code. A fresh subagent reviews all changes before the commits. Commits are separate, short, plain, no attribution.
- Item 3 (no money penalty for wrong guesses, time penalty only) is already how `RoundManager` works: no code change. The soak already asserts money is unchanged after a wrong submit.
- Item 4 (worker thread): skipped.

## Review Focus

- Deleted code left a dangling reference (scene, input action, signal, `.uid`). Pinned by a headless boot of the main scene plus the whole suite.
- The landing blend must end exactly at the committed rest height (no snap). Pinned by a pure-function test of the blend.
- `problem()` rejecting configs that used to generate fine (the four shipped configs). Pinned in the fuzz test and generator test.
- A fuzz generator that never produces accepted configs would pass vacuously. Pinned by asserting a minimum share of accepted and rejected configs.

---

### Task 1: Config fuzz test, then `problem()` covers every crash

**Files:** Create `tests/config_fuzz_test.gd`, `tests/error_catcher.gd` (the Logger that was inlined in `tests/soak_test.gd`, now shared). Modify `tests/soak_test.gd`, `scripts/procedural/difficulty_config.gd`.

- [ ] Extract `ErrorCatcher` (`extends Logger`, `var errors: Array[String]`, same `_log_error` body) to `tests/error_catcher.gd`; soak uses `preload`.
- [ ] Write `tests/config_fuzz_test.gd`: 3000 seeded random plus edge-case `DifficultyConfig`s (out-of-range and duplicate `spec_props`, empty and out-of-range `target_types`, `object_count` and `pile_count` in -3..60, negative and inverted `target_cover_*`, `near_miss_ratio` outside 0..1). For each: if `problem() == ""`, run `ChallengeGenerator.new(cfg).generate(rng)` under the error catcher; assert zero engine errors, `count` objects, exactly one object matching the order, every object in exactly one pile. Assert at least 5% of configs accepted and at least 5% rejected. Every accepted config also builds all its piles (`PileLayout.build`, finite positions, no engine error), with the layout fields (`grid_cell_size`, `units_per_mm`, `pile_slope`, `pile_packing`, `pile_spread`) fuzzed too. Dropped on purpose: probing rejected configs to see if they would have survived (the error flood from broken configs made it take minutes).
- [ ] Run it red against the current `problem()`.
- [ ] Extend `problem()` until green: every `spec_props` value a valid `ObjDefs.Prop`; every `target_types` value a valid `ObjDefs.Type`; for every target type some listed property has more than one value; cover range valid (`0 <= min <= max`); the layout fields above 0 (`grid_cell_size = 0` made the pile build loop forever; found by the first review, then reproduced by the fuzz); not both `LENGTH_CLASS` and `LENGTH_MM` (found by the fuzz: the class jitter changes the target's length too, so an exact-length order matched nothing). Keep the four shipped configs passing.

### Task 2: Toss lands with no snap

**Files:** Create `scripts/collection/landing_blend.gd`. Modify `scripts/procedural/pile_layout.gd` (public `rest_height`), `scripts/collection/hand_controller.gd`, `tests/toss_landing_test.gd`.

- [ ] Test first: `LandingBlend.y(planned, rest, t, start)` is `planned` for `t <= start`, exactly `rest` at `t == 1.0`, monotone and never overshooting in between. Run red.
- [ ] Implement it as a pure static function in its own script (not in `HandController`: that script names the `EventBus` autoload, which a `-s` test cannot compile; found when the first attempt failed to load). Rename `_rest_height` to public `rest_height`; `_apply_flight` blends with a new `@export_range(0, 0.95) toss_settle_start: float = 0.6` (1.0 would never blend: `_apply_flight` never runs at t = 1).

### Task 3: Delete dead shop and magnet code

**Delete:** `scripts/economy/shop_terminal.gd`, `scripts/ui/shop_menu.gd`, `scripts/procedural/magnet_mesh_factory.gd`, `scenes/ui/shop_menu.tscn`, `scenes/equipment/shop_terminal.tscn` and their `.uid` files.
**Modify:** `scripts/event_bus.gd` (3 shop signals), `scripts/economy/economy.gd` (`try_spend`, `money_spent`), `scripts/ui/money_counter.gd` (the `money_spent` line), `project.godot` (`open_shop`), `REPORT.md` (the two lines that say it still ships).

- [ ] Delete and edit; headless-boot `scenes/main/main.tscn` for a few frames and confirm no errors; full quick suite.

### Task 4: `.gitignore`

- [ ] Add `.mcp.json`; `git rm --cached .mcp.json` (the file stays on disk), because ignoring a tracked file does nothing.

### Task 5: Review, commits, full suite

- [ ] Fresh subagent reviews the whole uncommitted change; fix findings.
- [ ] Commits: fuzz test + `problem()`; toss blend; delete shop/magnet; gitignore.
- [ ] `tests/run_all.sh` (full). It already includes the 200-round zero-floating test and the 50-round soak; report each result.
