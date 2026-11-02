#!/usr/bin/env bash
# Runs every headless test and prints one PASS/FAIL line each.
#   tests/run_all.sh          full (about 15 min: zero_floating 200 rounds, soak 50 rounds)
#   tests/run_all.sh quick    about 1.5 min (20 / 8 rounds)
# Windowed tools (fps_benchmark, frame_profile) are not included.
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-godot}"
if [ "$1" = "quick" ]; then FLOOR_ROUNDS=20; SOAK_ROUNDS=8; GEN_ROUNDS=100; else FLOOR_ROUNDS=200; SOAK_ROUNDS=50; GEN_ROUNDS=1000; fi
LOGS="${TMPDIR:-/tmp}"
failed=0
run() { # name, then godot args
	local name="$1"; shift
	# Godot can exit 0 after a parse error in a -s script, so the log is checked too.
	if "$GODOT" --headless --path . "$@" > "$LOGS/test_$name.log" 2>&1 && ! grep -qE "SCRIPT ERROR|Parse Error" "$LOGS/test_$name.log"; then echo "PASS  $name"; else echo "FAIL  $name   (see $LOGS/test_$name.log)"; failed=1; fi
}
run pile_layout -s tests/pile_layout_test.gd
run toss_landing -s tests/toss_landing_test.gd
run challenge_generator -s tests/challenge_generator_test.gd -- rounds=$GEN_ROUNDS
run zero_floating -s tests/zero_floating_test.gd -- rounds=$FLOOR_ROUNDS
run round_flow tests/round_flow_test.tscn
run picker_stress tests/picker_stress_test.tscn
run soak tests/soak_test.tscn -- rounds=$SOAK_ROUNDS seed=1
exit $failed
