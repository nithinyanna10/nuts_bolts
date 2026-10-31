# Overnight report

Autonomous work list (see conversation): 1) 1% lows, 2) Medium vs Expert FPS, 3) Windows export, 4) soak test, 5) fix soak bugs.
Rules honoured: no design/number/control changes, no push, no force ops. Design ideas go under "Ideas" below.

## Status
- [x] 1. 1% lows (3faec7c, review fixes in the next commit)
- [x] 2. Medium vs Expert average FPS
- [ ] 3. Windows export preset + clean export
- [ ] 4. Soak test (50 random rounds)
- [ ] 5. Fix soak-test bugs

## Log
(newest last)

### 1. 1% lows - root cause: the platform's presentation floor, not the game; real stalls fixed
Method: `tests/frame_profile.gd` splits every frame into script time (process_frame -> pre_draw), draw/present time
(pre_draw -> post_draw) and other, and tags frames by what the player was doing (real input path: hover, pick, inspect,
rotate, toss, wrong submit, quick-toss + settle).

Findings (1920x1080, Apple M4 Pro, windowed, vsync off in-process):
- Script time never exceeds ~1.8 ms in ANY gameplay phase. No first-use hitch on first hover / pick / tools / toss
  (so no shader or pipeline compile problem; warming shaders would not have helped, so I did not add it).
- 100% of spike frames (>6 ms) are in the draw/present phase, spread evenly over every tag including idle.
- A completely BLANK window (empty scene, one camera, no game code) has the same spikes: 1% low 58-66 FPS, 342-419
  frames over 6 ms in 8 s. Fullscreen did not help (53 FPS vsync off, 32 FPS vsync on). That is the macOS/Metal present
  and compositor floor on this machine. Windows needs its own measurement (not available here).
- GC is not a factor (GDScript is refcounted; no allocation churn in the frame loop).
- Settle animation and the picker cost ~0.3-0.9 ms/frame of script time, flat across tags.

Real stalls found and fixed:
- Round build blocked ONE frame: Medium 31 ms, Hard 118 ms, Expert 495 ms. Now built behind a "Preparing your order..."
  overlay, one pile per frame. Worst loading frame over 3 runs (mine + the reviewer's): Medium 22-45 ms, Hard 37-59 ms,
  Expert 62-88 ms. (I first reported 22/37/88 from a single run; the reviewer's rerun did not reproduce Medium/Hard,
  so the ranges above are the honest ones.) All of it is behind the overlay.
- Picker marched the ray through every pile every frame; added a bounding-sphere reject (small gain, 0.03-0.1 ms/frame).

Before / after 1% low FPS (same harness, play scenario, vsync off):

| Difficulty | before | after (all frames) | after (excluding loading frames) |
|---|---|---|---|
| Easy | 73.1 | 73.8 | 73.8 |
| Medium | 72.3 | 69.9 | 76.8 |
| Hard | 61.0 | 57.6 | 69.7 |
| Expert | 30.3 | 43.9 | 87.3 |

Reading: the only difference that matters is Expert (a 0.5 s freeze at round start is gone). The other rows are within
run-to-run noise, which on this machine is about +-10 FPS (blank window: 53-66). The game now sits at or above the
empty-window floor.

## Reviewer findings
Review 1 (of 3faec7c): no blockers/bugs. RISKS: (1) build-frame numbers did not reproduce -> corrected above;
(2) `_loading` could stick if a config failed to load -> now validated before the flag is set (and tested with a bad index);
(3) no test for the bounding reject / loading flow -> added to tests/round_flow_test.gd. NITs: overlay swallowed the
mouse-recapture click -> mouse_filter ignore; report said "hash pending" -> fixed; sphere margins are literals (left,
same as the existing `reach` literals, not a feel tunable); a round key pressed during loading (~5-20 frames) is dropped
by design. Fixes in 068daa7.

### 2. Why Medium averaged lower than Expert: measurement artifact, not scene cost
- In the first benchmark, Medium rows sat at 113-117 FPS while Hard/Expert showed 205-297. 117 is the 120 Hz display
  refresh: those rows were frames pinned to vsync (median frame 8.3-8.5 ms = one refresh interval), not a measure of how
  expensive the scene is. The benchmark relied on the `--disable-vsync` CLI flag, which on this Mac did not hold for the
  whole process, so some segments ran capped and others uncapped (a blank window flips the same way: 119 or 261-298 FPS).
- Evidence (consistent with, not proof of, the cause): with vsync disabled in-process (DisplayServer.window_set_vsync_mode) and the order shuffled three ways, Medium
  averaged 252-315 FPS and Expert 238-290 across all runs. Medium is never the slow one; Expert is slightly slower, as expected
  (more draws: ~200 vs ~125).
- Caveats the second reviewer raised: (a) I never showed WHEN the CLI flag stopped holding; macOS compositor/ProMotion pacing is
  an equally plausible cause of the capped segments; (b) Easy and Medium score the same (~295-307 FPS, median ~2.5 ms), so at
  this scale the benchmark is dominated by fixed per-frame overhead and the differences between difficulties are mostly
  noise; (c) rounds were unseeded, and one Hard "close" row swung 167 -> 295 FPS between runs, so run-to-run noise is much
  larger than the +-10 FPS I first claimed.
- Fix (methodology): tests/fps_benchmark.gd now disables vsync in-process by default (`vsync=1` to opt in), accepts
  `order=`, and prints the median frame time and a [REFRESH-CAPPED] flag on any segment whose median sits on a refresh
  interval (the check covers 30-240 Hz and the screen's real refresh rate, and needs a tight distribution), so a capped row
  can no longer be mistaken for a throughput number. `seed=N` makes the rounds identical between runs.

Review 2 (of 068daa7 + 6e871f9): no blockers/bugs. RISKS: item-2 "proof" overstated -> reworded with the reviewer's caveats;
refresh-cap flag only knew 60/120 Hz -> now 30-240 Hz + the screen's real rate. NITs: bad-index test thin -> now covers 99, -1,
too few anchors and checks the running round is undisturbed; benchmark unseeded -> `seed=`. Fixed in the commit after 6e871f9
(reviewed together with item 3).

## Blocked / skipped

## Questions for you
- Windows presentation floor is unmeasured (no Windows machine here). Worth a 30 s run of
  `tests/frame_profile.tscn` and `tests/fps_benchmark.tscn` on the target machine.

## Ideas (not implemented, design-related)
