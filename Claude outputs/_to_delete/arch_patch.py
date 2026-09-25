import io, re, sys
p = 'ARCHITECTURE.md'
s = io.open(p, encoding='utf-8').read()

def sub_once(old, new):
    global s
    assert s.count(old) == 1, ("anchor not unique: " + old[:60])
    s = s.replace(old, new, 1)

# --- 1. section 7: RunDirector, now partly implemented
old_rd = """### RunDirector
Day counter, day/night phase, and wave composition per night. Waves scale by
**shape, not only by number**: later nights favour fewer, tougher enemies or
larger fragile swarms rather than simply multiplying the count, which keeps the
entity budget bounded as runs get long.
"""
new_rd = """### RunDirector
Implemented in Stage 3: the day counter and the day/night phases (see "Day,
night and the end of a run" below). Still to come with enemies (Stage 4): wave
composition per night. Waves will scale by **shape, not only by number** --
later nights favour fewer, tougher enemies or larger fragile swarms rather than
simply multiplying the count, which keeps the entity budget bounded as runs get
long. The day counter is what makes them stronger, so waves hang off
`phase_changed` and read `day`.
"""
sub_once(old_rd, new_rd)

# --- 2. the Stage 3 section, before Stage 3b
anchor = "### Planned: Stage 3b\n"
stage3 = """### Day, night and the end of a run (implemented, Stage 3)

`game/run_director.gd`. A plain `RefCounted` owned by `main.gd`, stepped first
in `_simulate()` so a phase change takes effect on the same tick the workers
decide what to do with it.

- **Counted in ticks**, like everything else (section 5): the cycle pauses with
  the game and runs faster at 2x and 4x. 120 s of day, then 60 s of night, at
  speed 1. A run starts at dawn of day 1; the day number goes up at dawn.
- **Two signals.** `day_started(day)` fires at dawn, before `phase_changed`, so
  a listener that cares only about new days never has to test the flag.
  `phase_changed(is_night, day)` fires at both ends.
- **The light.** `light_colour()` returns what the world is tinted with, and
  `main.gd` copies it into a `CanvasModulate` once a frame. The modulate is a
  child of `Main`, so it colours the *world* canvas layer and leaves every UI
  layer alone -- the resource bar stays readable at midnight. **Both twilights
  belong to the night**: dusk is its first 6 s and dawn its last. Days are
  therefore always fully lit, including the first one, where the player is
  still placing their base, and the light is continuous across both boundaries
  because the night begins and ends at zero darkness.
- **Night behaviour** lives in `UnitSystem`, not in the director: `main.gd`
  sets `units.night` and calls `on_night_started()` / `on_day_started()`.
  Everyone walks home and waits inside, with one exception -- **builders still
  take REPAIR jobs**, which means standing in the open to do it. That is the
  intended risk once enemies exist. Carriers leave drops where they lie until
  dawn. The commuting first miner is released from its mine at dusk,
  *remembers which mine it was*, and is sent back at dawn unless the player
  gave it another one meanwhile or its mine is gone.
- **Autosave at dawn.** `day_started` calls `save_run()`. A lost run therefore
  costs at most one day, and the day boundary is the one moment when nobody is
  mid-job.
- **The day bar** (`UI/day_bar.gd`) sits under the resource bar: day number,
  sun or moon, and a bar that *drains* as the phase runs out. It polls the
  director once a frame rather than listening for a signal, because the bar
  moves every frame anyway; the text is only rewritten when it changes.
- **Death.** The base falling is the end of the run. `main.gd` hears
  `level.building_removed` for type `base`, pauses the clock under its own
  reason `game_over` (never popped), deletes the run save, updates the profile
  (`runs_ended`, `best_day`, `total_ticks`) and shows `UI/run_summary.gd` over
  the frozen world: days survived, time, workers, resources, best day, and one
  **Return to title** button. `_run_over` makes `save_run()` a no-op afterwards,
  so quitting from the summary cannot write the dead run back over the deletion.
- **Tuning** lives on `RunDirector` itself: `day_seconds`, `night_seconds`,
  `twilight_seconds`, `night_light`, `night_colour`.
- **Dev shortcuts:** Ctrl+T skips to the end of the current phase, Ctrl+K
  destroys the base (both debug-only, per the key-bindings rules).

"""
sub_once(anchor, stage3 + anchor)

# --- 3. dev shortcut list
sub_once("""**F3** stat overlay (every modifier source and every resolved
stat, live).""",
"""**F3** stat overlay (every modifier source and every resolved
stat, live), **Ctrl+T** skip to dusk or dawn, **Ctrl+K** destroy the base
(which ends the run, for testing the summary).""")

# --- 4. section 9: what a run save holds
sub_once("""    level, clock, economy, roster, shop, modifiers, units
""",
"""    level, clock, economy, roster, shop, modifiers, units,
    unlocks, inventory, forest, lava, director
""")

# --- 5. autosave
sub_once("""### Autosave

Not implemented yet, deliberately. Saving mid-combat with hundreds of entities
is a frame hitch, and the natural checkpoint is a day boundary, which needs
`RunDirector` (Stage 3). `save_run()` is ready to be called from there.""",
"""### Autosave

At **dawn**, and nowhere else (Stage 3). Saving mid-combat with hundreds of
entities is a frame hitch, and the day boundary is the natural checkpoint: a
lost run costs at most one day, and nobody is mid-job. `RunDirector.day_started`
calls `main.gd.save_run()`.

When the base falls the run save is **deleted**, not written: `main.gd` sets
`_run_over`, which makes every later `save_run()` a no-op, so quitting from the
run summary cannot resurrect a dead run.""")

io.open(p, 'w', encoding='utf-8').write(s)
print("ARCHITECTURE.md patched")
