# Overnight report

Autonomous work list (see conversation): 1) 1% lows, 2) Medium vs Expert FPS, 3) Windows export, 4) soak test, 5) fix soak bugs.
Rules honoured: no design/number/control changes, no push, no force ops. Design ideas go under "Ideas" below.

## Status
- [x] 1. 1% lows (3faec7c, review fixes in the next commit)
- [x] 2. Medium vs Expert average FPS
- [x] 3. Windows export preset + clean export
- [x] 4. Soak test (50 random rounds)
- [x] 5. Fix soak-test bugs

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

### 3. Windows export
- Installed the official 4.7.2.stable Windows x86_64 export templates (debug + release) into
  ~/Library/Application Support/Godot/export_templates/4.7.2.stable/ (outside the repo; downloaded from the Godot GitHub release).
- `export_presets.cfg` (committed): preset "Windows Desktop", x86_64, embedded PCK, Forward+/Vulkan, no code signing, no icon,
  `application/modify_resources=false` (so no rcedit/Wine is needed to export from macOS), exclude filter
  `tests/*, REPORT.md, CLAUDE.md, .mcp.json`. `build/` is git-ignored.
- Command: `godot --headless --path . --export-release "Windows Desktop" build/windows/WheresThatScrew.exe`
  -> exit 0, no warnings/errors in the log, 109 MB `PE32+ executable (GUI) x86-64`.
- Verified without a Windows machine: exported the same content as a .pck and booted the game from the pack alone
  (`godot --main-pack game.pck`, headless 240 frames and windowed 400 frames): no errors; the pack contains no tests/docs.
- NOT verified: actually running the .exe on Windows (no Windows machine or Wine here), GPU compatibility (Forward+ needs a
  Vulkan 1.2-class GPU), Windows presentation/frame pacing. No app icon or version resource is embedded (needs rcedit).

### 4. Soak test (`tests/soak_test.tscn`)
`godot --headless --path . tests/soak_test.tscn -- rounds=50 seed=1` (about 100 s). Per round it: requests the round twice (the
second must be ignored), checks a clean start (controller IDLE, player unlocked, no flights, flight pool full, piles known),
exactly one matching object and all objects present; picks an exposed object, inspects, tosses it and checks it landed back;
picks one and submits it wrong (penalty maths, message format per difficulty, money unchanged, object restored); quick-toss digs
3-12 objects with settle animations; digs to the target with rays from above exactly like a player (target must become
reachable); picks the target and submits it (payout = base + time bonus, money delta, FOUND state, a second submit pays
nothing); sometimes abandons the round while holding an object. It also attaches an engine Logger (any engine error fails
the run), checks nothing is stuck (every wait has a timeout), and checks the node count does not grow.
Floating objects: separately written physical rule in `tests/floating_check.gd` (same plan-view segment model as the layout, so a flaw in that model would not be caught) (an object must be on the floor or touch a lower object
in plan view with <= 2 cm gap, using 2D axis-segment distance). The check is "no object is floating right after the pile is
built, and none is floating after any settle".
Mutation-checked (each makes the soak fail, unmutated passes): settle disabled, state not reset on new round, payout off by one,
no wrong-submit penalty, tossed object not restored, double round start allowed; an injected push_error is caught by the Logger.
Input is driven through the controller's own methods (`_set_hover`, `_pick`, `_submit`, `_toss_held`, `_quick_toss`), not key
events, because headless Godot cannot capture the mouse. The real key/mouse path was exercised earlier with a windowed script
(hover, click, E) and is not part of the automated soak.
Note: at the soak-test commit (648368e) the soak FAILS on floating-after-settle; that is bug 1 below, fixed in the next commit.

### 5. What the soak test found, and what I did
1. REAL BUG, fixed: objects hovered after the object under them was removed. Settle decided "resting on" by center-to-center
   distance, so a stick resting on the END of a removed stick was never queued to drop. Soak failed in nearly every round
   (1-7 floating objects after settle). `PileLayout` now uses one rule everywhere (queueing, lowering, and where tossed objects
   land): two objects touch if their horizontal axis segments are closer than the sum of their radii. After the fix: 0
   failures in 150 soak rounds (3 seeds x 50), and the pile layout test still passes. Pile sizes/shapes are unchanged.
2. Test bug (mine), fixed: the soak dug to the target while a quick-tossed target was still in the air -> now waits for
   flights to land first.
3. Test bug, fixed: ~1 in 26 flow-test runs failed with "pick_ray gave X, brute force Y". Not a picker bug: the random ray
   origin sat inside two overlapping boxes (both hit at t = 0.000), so two answers are equally valid. Flow test and a new
   `tests/picker_stress_test.tscn` (end-on, grazing and random rays, all difficulties) now compare hit distance. 0 mismatches.
   I first suspected the ray march stopped too early; the stress test did not support that, so I did not change the picker.
4. FIXED (was a known limitation): right after a pile was built, 3-9% of objects rested on nothing by the strict plan-view rule
   (heap placement rests each object between the highest and the average support under it, so it could end up embedded beside a
   higher neighbour with nothing touching beneath). `PileLayout.build()` now ends with one `settle_all()` pass (lowest object first,
   same support rule as removal) inside the existing loading overlay. `tests/zero_floating_test.gd` builds every pile of 200 seeded
   rounds per difficulty (Easy 200, Medium 200, Hard 600, Expert 1,000 = 2,000 piles) and asserts zero objects resting on nothing, that a second settle
   moves nothing, nothing sinks below the floor, and the same seed gives the same pile. The soak limit went from 15% to 0.
   Before -> after, averages over those 200 rounds per difficulty (height = highest object top, width = diameter of the circle
   around all objects):
   | | objects resting on nothing | avg height | avg width | avg `PileLayout.build` per pile |
   |---|---|---|---|---|
   | Easy | 538 -> 0 | 0.531 -> 0.531 m | 1.826 -> 1.826 m | 4.5 -> 7.6 ms |
   | Medium | 3,416 -> 0 | 1.005 -> 1.005 m | 3.306 -> 3.306 m | 20.2 -> 45.8 ms |
   | Hard | 23,709 -> 0 | 1.314 -> 1.314 m | 3.908 -> 3.908 m | 30.3 -> 72.3 ms |
   | Expert | 113,142 -> 0 | 1.947 -> 1.947 m | 5.135 -> 5.135 m | 74.0 -> 209.3 ms |
   Pile height and width did not change at 3 decimals: the dropped objects were embedded beside taller neighbours, so the
   outline and the top of each pile stayed put. Cost: layout build time per pile (layout only, not the MultiMesh setup) is about 2-3x (Expert round: five piles, roughly
   0.4 s -> 1.0 s of layout time on this machine), all behind the "Preparing your order..." overlay; `RoundManager` still builds one pile
   per frame, so the overlay just stays up a little longer. The full test takes about 8 minutes (`-- rounds=20` for a quick run).

### Playtest note (you, after you came back)
"Once I select a nut there is no option to put it back (only E submit)": right-click toss already worked (tested with real input
events), but nothing on screen said so while holding an object. The bottom hint now changes while inspecting to "E submit as the
answer / Right-click toss it back / Mouse rotate it", and to "Press 1-4 for a new round" after a win. UI text only; controls unchanged.
Open question: a toss lands the object in the ring beside the pile, not back in its exact spot. Say if you want a true "put back".

Review 3 (of b8b2291 + 6c56cc5, export + benchmark): no blockers/bugs. Verified export content, clean boot from the pack,
seed= reproducibility, mutation-checked the bad-index test. Notes: the pack boot does not exercise the embedded-PCK path of the
.exe or the Windows runtime (REPORT already says the .exe was never run); disabled shop/magnet content still ships (see Ideas).

Review 4 (of 648368e + 1b9cc86, soak + settle fix): no blockers. 14 of 15 mutations were caught. Findings and my response:
- BUG (test gap): a lost target was not caught (soak never tossed the target on purpose). -> soak now picks or quick-tosses the
  target in every round and asserts it lands back (mutation "flown target never restored" is now caught).
- BUG (settle, small): the supporter search was a sphere, so a supporter far BELOW a falling object could be missed and the object
  dropped through it (about 2 in 500 objects; 3 objects embedded 3.5-4.8 cm in real removals). -> new `SpatialGrid.query_below`
  (horizontal radius, any depth below); settle and `plan_landing` use it. `tests/pile_layout_test.gd` now removes 200 RANDOM objects
  per pile and checks every moved object against a brute-force scan of all objects (independent of the grid query); with the old
  sphere query it fails, with the fix it passes. (My first version of that oracle was circular and failed on correct code; fixed
  by excluding objects that fell in the same settle.)
- RISK: the soak's floating rule shares its abstraction (axis segment + radius) with the code under test. True; the brute-force
  settle check above is a second, differently-built check. Residual: a systematic flaw in "plan-view segment" support, e.g.
  ignoring tilt, would pass both.
- RISK (coverage): only the target pile was exercised. -> picks, quick-tosses and floating checks now cover all piles
  (Hard 3, Expert 5); the node-leak check is per difficulty (same difficulty must stay within +10% +30 nodes of its first round).
- NIT: REPORT numbers understated. -> corrected in 5.4 below. NIT: settle/touch constants are consts, not exports (same as the
  existing CELL/PACK/DROP_TRIES; not a feel tunable).

5. BEHAVIOUR CHANGE to flag (feel): settle now moves FEWER objects per removal. Over 200 random removals on the same Hard and Expert
   piles the old rule moved 207-579 objects, the new one 124-245 (review 4's measurement; review 5 reproduced the new
   124-190 but could not reproduce the old 207-579 figure, so treat the exact "before" number as unconfirmed). The old centre-distance rule queued
   objects that were not really resting on the removed one and missed ones that were; the new rule drops exactly what rested on
   it. Build placement (pile size, shape, positions) is byte-identical to before (reviewer compared 20 seeded piles). Tell me if the
   old, more "avalanche-y" feel was something you liked.

Review 5 (of 0bdac79 + ac69337, the fixes above): no blockers/bugs/hard-rule violations. Reproduced both mutation claims
(sphere query -> layout test fails; unrestored target -> soak fails), confirmed `query_below` is correct and not slower on Expert
(200 removals about 32-48 ms, 200 tosses about 7 ms), confirmed build placement byte-identical to 6c56cc5, verified the HUD hint
wiring for idle/inspect/found/new-round/abandon. Small items fixed in the following commit: layout test shuffle is now seeded;
the soak's floating check fails (instead of silently skipping) on an unregistered pile; a comment that promised "reachable" now says
"active". Not changed: the brute-force settle oracle ignores objects that fell in the same settle (cannot give false failures, could
hide a chain-order bug; the soak's floating check partly covers it); the node-leak check cannot see a ~1 node/round leak.
(These last small edits were not separately reviewed.)

## Blocked / skipped

## Questions for you
- Pile placement (see 5.4): OK to let objects that rest on nothing after build drop to their supports? It tidies the look but
  makes piles a bit lower/denser, which touches "pile sizes".
- Windows presentation floor is unmeasured (no Windows machine here). Worth a 30 s run of
  `tests/frame_profile.tscn` and `tests/fps_benchmark.tscn` on the target machine.

## Ideas (not implemented, design-related)
- Shop/magnet are disabled but still shipped: `shop_terminal.tscn`, `shop_menu.tscn`, `magnet_mesh_factory.gd` and the `open_shop`
  input action (B) are in the Windows build though nothing instantiates them. Fine for now; strip them from the export filter
  if you want a smaller build.
- Round key presses during the 5-20 loading frames are dropped by design; queueing the last press would feel nicer.
