# Overnight report

Autonomous work list (see conversation): 1) 1% lows, 2) Medium vs Expert FPS, 3) Windows export, 4) soak test, 5) fix soak bugs.
Rules honoured: no design/number/control changes, no push, no force ops. Design ideas go under "Ideas" below.

## Status
- [x] 1. 1% lows (3faec7c, review fixes in the next commit)
- [ ] 2. Medium vs Expert average FPS
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
(none yet)

## Blocked / skipped

## Questions for you
- Windows presentation floor is unmeasured (no Windows machine here). Worth a 30 s run of
  `tests/frame_profile.tscn` and `tests/fps_benchmark.tscn` on the target machine.

## Ideas (not implemented, design-related)
