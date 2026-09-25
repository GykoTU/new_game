import io
p = 'docs/DESIGN.md'
s = io.open(p, encoding='utf-8').read()

old_commuter = """  base and commutes again. (Later, with day/night, it walks home at night.)"""
new_commuter = """  base and commutes again. At night it walks home to the base and goes back
  to the same mine at dawn."""
assert s.count(old_commuter) == 1
s = s.replace(old_commuter, new_commuter, 1)

anchor = "## Exploration (decided)"
day_night = """## Day and night (decided)

- A run is measured in **days**. **120 seconds of day, 60 seconds of night**
  (simulation time, so the cycle pauses and speeds up with the game). The run
  starts at dawn of day 1; the day number goes up at each dawn.
- **The world darkens at night**, easing in at dusk and out at dawn. The UI
  does not darken.
- **At night everyone goes home** — except **builders, who still repair**.
  Repairing means leaving the house while enemies are out, which is the point:
  it is a risk the player chooses to take. Carriers leave dropped resources
  where they lie until morning, and mines stand idle.
- **Waves come at night** and get stronger with the day number (Stage 4).
- The game **autosaves at dawn**.

## The end of a run (decided)

- The run ends when **the base is destroyed**. Nothing else ends it.
- Time stops, the run save is deleted, and a **summary** appears over the
  frozen world: days survived, time, workers, resources, and the best day
  reached across all runs. One button: **Return to title**.
- The permanent profile keeps `runs_started`, `runs_ended`, `best_day` and
  total time played. Meta currency joins it later (Stage 8).

"""
assert s.count(anchor) == 1
s = s.replace(anchor, day_night + anchor, 1)
io.open(p, 'w', encoding='utf-8').write(s)
print("DESIGN.md patched")
