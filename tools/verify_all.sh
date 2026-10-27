#!/bin/bash
# The release verify chain (docs/STATUS.md "how to run things"): the script check, the headless
# test suite, the lockstep test, the campaign_sim pins of both packs (format 6, legacy, and the current
# format 10) and the windowed input test,
# summarised one line per piece. Run from a clean checkout of the commit to verify:
#   tools/verify_all.sh <tag>            (outputs in $VERIFY_OUT, default /tmp/sc_verify)
# The last line is "VERIFY_DONE"; a release chain must require it AND no FAIL in the summary.
O=${VERIFY_OUT:-/tmp/sc_verify}; mkdir -p "$O"
P=${1:-vx}
tools/check_scripts.sh 2>&1 | tail -1 > $O/${P}_scr.txt
(godot --headless --script res://tests/determinism_test.gd > $O/${P}_det.txt 2>&1; godot --headless --script res://tests/custom_battle_test.gd > $O/${P}_cb.txt 2>&1; godot --headless --script res://tests/campaign_test.gd > $O/${P}_ct.txt 2>&1; godot --headless --script res://tests/pack_test.gd > $O/${P}_pk.txt 2>&1; godot --headless --script res://tests/battle_screen_test.gd > $O/${P}_bs.txt 2>&1) &
(godot --headless --script res://tests/lockstep_test.gd > $O/${P}_ls.txt 2>&1) &
(godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60 > $O/${P}_sim.txt 2>&1; godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60 --pack=west > $O/${P}_simw.txt 2>&1; godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60 --format=10 > $O/${P}_sim10.txt 2>&1; godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60 --pack=west --format=10 > $O/${P}_simw10.txt 2>&1) &
wait
# the input test needs a window (DISPLAY); it drops a drag / long-press check now and then: rerun on a FAIL
DISPLAY=${DISPLAY:-:0} timeout 900 godot --path . --resolution 1280x720 -s tests/input_test.gd > $O/${P}_inp.txt 2>&1
echo "== scr: $(cat $O/${P}_scr.txt)"
for f in det cb ct pk bs ls; do echo "== $f: $(grep -E '^RESULT|^FAIL' $O/${P}_$f.txt | tail -2 | tr '\n' ' ')"; done
echo "== sim: $(grep -o 'hash [0-9a-f]\{8\}' $O/${P}_sim.txt | awk '{printf "%s ", $2}')"
echo "== simw: $(grep -o 'hash [0-9a-f]\{8\}' $O/${P}_simw.txt | awk '{printf "%s ", $2}')"
echo "== sim10: $(grep -o 'hash [0-9a-f]\{8\}' $O/${P}_sim10.txt | awk '{printf "%s ", $2}')"
echo "== simw10: $(grep -o 'hash [0-9a-f]\{8\}' $O/${P}_simw10.txt | awk '{printf "%s ", $2}')"
echo "== inp: $(grep -E '^RESULT|^FAIL' $O/${P}_inp.txt | tail -2 | tr '\n' ' ')"
echo VERIFY_DONE
