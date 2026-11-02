# Zero Floating Objects at Round Start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a pile is built, no object rests on nothing, on all four difficulties, without touching the generator, round flow or soak tests' guarantees.

**Architecture:** `PileLayout.build()` ends with one `settle_all()` pass that lowers every active object (lowest first) to its highest touching supporter or the floor, reusing the same "plan-view segment" support rule as `remove_and_settle()`. The pass runs inside `build()`, which `RoundManager.start_round()` already calls one pile per frame behind the "Preparing your order..." overlay, so no flow change is needed. A shared test helper holds the independent floating rule so the new test and the soak use one definition.

**Tech Stack:** Godot 4.7 (`godot` on PATH), GDScript, headless `SceneTree` tests.

**Spec:** `CLAUDE.md` ("Design rules", "Code rules") and the user's task brief (zero floating objects at round start; lower piles acceptable; report average pile height and width per difficulty; keep generator, flow and soak tests green; plain commit message, no attribution).

## Global Constraints

- Static typing in all GDScript.
- Pile objects stay in `MultiMeshInstance3D`s; this change touches `PileLayout` data only.
- Tunables live in exported vars or a Resource, never hardcoded in logic (the new pass adds none; it reuses the existing `PileLayout` constants).
- Generator guarantees (exactly one match, target reachable by digging) stay true.
- Commit after each working step, short plain message, never any Co-Authored-By or Claude/Anthropic attribution.
- Test commands: `godot --headless --path . -s tests/<name>.gd` or `godot --headless --path . tests/<name>.tscn`.

## Review Focus

- Chains: an object resting on an object that itself floats must end up supported (settle order lowest-first). Pinned by the zero-floating assertion over all 200 seeded rounds of every difficulty.
- Idempotence: a second `settle_all()` on a built layout moves nothing. Pinned by an assertion in the new test.
- Determinism: the same seed gives the same layout twice (the pass must not consume the RNG). Pinned by a seed-1 double build in the new test.
- Never raises or sinks through the floor: every final `y >= half_vert - 0.001`. Pinned in the new test.
- Expert frame stall: `build()` per pile gets slower; the new test prints average ms per pile so a regression on Expert (5 piles of 2000) is visible against the pre-change number.

---

### Task 1: Share the floating rule with the soak

**Files:**
- Create: `tests/floating_check.gd`
- Modify: `tests/soak_test.gd` (remove `SUPPORT_TOL`, `FLOOR_TOL`, `_floating_flags`, `_segment`, `_segment_distance`; call the helper)

**Interfaces:**
- Produces: `tests/floating_check.gd` (no `class_name`; consumers use `const FloatingCheck = preload("res://tests/floating_check.gd")`):
  - `const SUPPORT_TOL: float = 0.02`, `const FLOOR_TOL: float = 0.01`
  - `static func flags(l: PileLayout) -> PackedByteArray` — 1 per active object that is not on the floor and has no lower touching object within `SUPPORT_TOL` vertical gap; same body as the soak's current `_floating_flags(pile)` with `pile.layout` as `l` and `pile.object_count()` as `l.ids.size()`.

- [ ] **Step 1: Create `tests/floating_check.gd`** by moving the three functions and two constants out of `tests/soak_test.gd` unchanged (static, taking a `PileLayout`).
- [ ] **Step 2: In `tests/soak_test.gd`**, add the preload const and replace the two `_floating_flags(pile)` calls with `FloatingCheck.flags(pile.layout)`; delete the moved code.
- [ ] **Step 3: Verify the soak still passes:** `godot --headless --path . tests/soak_test.tscn -- rounds=8 seed=1`. Expected: `TOTAL FAILURES: 0` (or the soak's equivalent pass line).
- [ ] **Step 4: Commit** `git add tests && git commit -m "Share the floating-object rule between tests"`.

### Task 2: Failing test, then `settle_all()`

**Files:**
- Create: `tests/zero_floating_test.gd`
- Modify: `scripts/procedural/pile_layout.gd` (`build()` end, `remove_and_settle()`, new `settle_all()`, new `_drop_to_support()`)

**Interfaces:**
- Consumes: `FloatingCheck.flags(l: PileLayout) -> PackedByteArray` (Task 1).
- Produces in `PileLayout`:
  - `func settle_all() -> int` — lowers every active object, lowest `y` first, returns how many moved; called once at the end of `build()` after `grid.setup(...)`.
  - `func _drop_to_support(k: int) -> bool` — computes `new_y` exactly as the inner loop of `remove_and_settle()` does today (floor `half_vert[k]`, raised by every lower touching supporter's `y + half_vert[m] + half_vert[k]`), moves `k` via `grid.move` when `new_y < y - 0.003`, returns true if it moved. `remove_and_settle()` calls it instead of its inline copy (it still does the queueing and `moved`/`moved_from_y` bookkeeping around it).

- [ ] **Step 1: Write the failing test** `tests/zero_floating_test.gd` (`extends SceneTree`, header comment `Run: godot --headless --path . -s tests/zero_floating_test.gd [-- rounds=200]`). For each of `easy medium hard expert` and each seed `1..rounds`: `rng.seed = seed`, `ChallengeGenerator.new(cfg).generate(rng)`, build every pile with `PileLayout.new().build(data, k, rng)`, then assert:
  - `FloatingCheck.flags(layout)` sums to 0 (fail message names difficulty, seed, pile, count);
  - `layout.settle_all() == 0` (idempotent);
  - every `grid.positions[j].y >= half_vert[j] - 0.001`;
  - seed 1 built twice gives identical `grid.positions`.
  Accumulate per difficulty: average pile height (max over objects of `y + half_vert`), average pile width (`2 * max(Vector2(x, z).length() + foot[j])`), average build ms per pile, total floating objects. Print one summary line per difficulty and `TOTAL FAILURES: n`; `quit(1 if failures > 0 else 0)`. Cap printed failures at 10 like `pile_layout_test.gd`.
- [ ] **Step 2: Run it and confirm it fails:** `godot --headless --path . -s tests/zero_floating_test.gd -- rounds=20`. Expected: floating-object failures on every difficulty (and a compile error for `settle_all` on the idempotence assertion is acceptable as the first red). Save the summary lines: they are the BEFORE numbers (run the idempotence check behind `layout.has_method("settle_all")` for this run if needed so the height/width/ms baseline prints).
- [ ] **Step 3: Implement** `_drop_to_support`, refactor `remove_and_settle()` to use it, add `settle_all()` (sort all indices by `grid.positions[j].y`, ascending; ties are harmless because a supporter must be strictly lower), call it at the end of `build()`.
- [ ] **Step 4: Run the new test at full size:** `godot --headless --path . -s tests/zero_floating_test.gd`. Expected: `TOTAL FAILURES: 0`; record the AFTER numbers.
- [ ] **Step 5: Run the other tests:** `pile_layout_test.gd`, `challenge_generator_test.gd`, `round_flow_test.tscn`, `picker_stress_test.tscn`. Expected: all pass.
- [ ] **Step 6: Commit** `git add -A tests scripts && git commit -m "Settle each pile once after placement so nothing floats at round start"`.

### Task 3: Tighten the soak, update the report

**Files:**
- Modify: `tests/soak_test.gd` (`MAX_UNSUPPORTED_SHARE` from `0.15` to `0.0`; wording of the fail message so it reads "rests on nothing (limit 0)")
- Modify: `REPORT.md` (known limitation 4 becomes resolved; before/after pile height and width per difficulty)

- [ ] **Step 1: Set `MAX_UNSUPPORTED_SHARE = 0.0`** and check the comparison fails on any unsupported object (`share > MAX` already does).
- [ ] **Step 2: Run the full soak:** `godot --headless --path . tests/soak_test.tscn -- rounds=50 seed=1`. Expected: 0 failures.
- [ ] **Step 3: Update `REPORT.md`** with the before/after table from Task 2 and mark limitation 4 fixed.
- [ ] **Step 4: Commit** `git add -A && git commit -m "Soak requires zero floating objects at round start; report pile size change"`.

---

## Self-review

- Spec coverage: failing test first (Task 2 step 1-2), 200 seeded rounds per difficulty (Task 2), settle once after placement behind the overlay (Task 2 step 3, no flow change needed because `start_round` already builds behind it), lower piles reported (Task 2 steps 2 and 4, Task 3 step 3), generator/flow/soak green (Task 2 step 5, Task 3 step 2), plain commits (all tasks).
- Types: `FloatingCheck.flags`, `settle_all`, `_drop_to_support` are named identically wherever used.
- Proportion: one small production change; plan is mostly test and verification steps.
