# Balance harness

Measure and decide are separate tasks: a script measures (no model needed, or Haiku to run it), the change
agent edits the sim and reads only a few-hundred-token summary, never battle logs.

## A balance pass

1. **Before.** `python3 tools/balance/measure.py tools/balance/plans/west_walls.json` on HEAD. The first run
   measures (one Godot process per town x walls x 4 seeds, `cores - 2` at a time); later runs on the same code
   print `cached` and return at once.
2. **Change.** The change agent edits `sim/` or `campaign/`. Nothing else is needed: the cache key is a hash of
   every file under `sim/` and `campaign/`, so the edit is a new key and the "before" results stay.
3. **After.** The same `measure.py` command again (new code hash, measured afresh). Note the printed hashes.
4. **Compare.** `python3 tools/balance/table.py west_walls@<before-hash> west_walls` prints a Markdown
   before -> after table (for STATUS / AI.md); add `--json` for the summary. With no `@hash` a name means the
   current code. A path to a `results.jsonl` or a run directory works too. One argument prints one set.
5. **Decide.** The deciding agent reads the `--json` output only: pooled rows per walls level, the cells whose
   change is beyond the interval, a few hundred tokens.

Before a lever, `ls tools/balance/out/<plan>/` shows the hashes on disk. To keep a "before" safe from a later
`--force`, copy its `results.jsonl` somewhere and pass the path.

## Files

- `measure.py PLAN [--jobs N] [--seeds N] [--force] [--dry] [--timeout S]`: runs the plan's jobs, writes
  `out/<plan>/<code-hash>/{results.jsonl,done.txt,logs/}` and nowhere else. Jobs already done under the same
  hash are skipped (so `--seeds 8` first and the 16-seed plan later only runs the second half). `--force`
  deletes that run and re-measures. Only its own Godot children are ever signalled (Ctrl-C ends them; finished
  jobs are kept). Prints a progress line per job and a one-line summary. Exit 1 if a job failed (its log path is
  printed; failed jobs are not cached). Set `GODOT=/path/to/godot` if `godot` is not on PATH.
- `table.py [BEFORE] AFTER [--json] [--seeds N]`: Markdown or JSON summaries. town_balance: attacker wins % per
  town x walls with the 95 % Wilson half-width, pooled rows and column, median minutes to decide, gate-down share
  and minute; two sets add a diff with `*` where the change exceeds the two intervals combined (sqrt of the sum of
  squares); a cell is compared on the seeds both sets have. open_town, sea: per group means / counts, same diff.
  campaign_sim: each seed's hash against `pins.json` (`ok` / `DIFFERS`).
- `plans/*.json`: the standard plans. `probe` is `town_balance`, `open_town`, `sea` or `campaign_sim`. Keys:
  `pack`, `towns` (`key` or `key:level`), `walls`, `seeds`, `seed0`, `chunk` (seeds per process, default 4),
  `skills` (open_town), `layouts`, `modes` (sea), `packs`, `turns` (campaign_sim), `args` (extra probe flags,
  e.g. `["--skill=1"]`), `parallelism`.
  - `rome_walls` (6 Rome towns x walls 1-3 x 16 seeds; `rome_walls_full` 32), `west_walls` (16 Spanish towns x
    walls 0-2 x 16), `west_named` (Havana, Cartagena, Port Royal, Veracruz, Santo Domingo, Natchez, Tayasal),
    `sea` (5 layouts x 2 modes x 24 seeds), `open_town` (Havana, Cartagena, Santo Domingo, walls 0, 8 seeds),
    `campaign_pins` (both packs 6 seeds x 60 turns; ~minutes).
- `pins.json`: the campaign_sim hashes in force (seeds 1000 + 77 n); `docs/STATUS.md` "Verification pins" is the source of truth. When a change legitimately moves them,
  update this file in the same change as the STATUS row, as the pins in STATUS.
- The probes (`tests/town_balance.gd`, `sea_probe.gd`, `open_town_probe.gd`, `campaign_sim.gd`) take
  `--json=PATH`: one JSON line a battle / sea battle / seed. Default off; their printed output is unchanged.

## Notes

- Results are exact: the sim is deterministic, so a cached or re-run result is identical for the same code.
  Intervals are sampling intervals over seeds (the seed count is the only noise), not run-to-run noise.
- Results depend only on `sim/` and `campaign/` (the hash). If a probe script or the scenario code in `tests/`
  changes, use `--force`.
- Stay off other agents' toes: check `uptime`/`pgrep godot` and use `--jobs` below `cores - 2` when other
  measurements are running.
