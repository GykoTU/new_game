import io
p = 'TODO.md'
s = io.open(p, encoding='utf-8').read()
old = """## Stage 3 — Day/night and the run

- [ ] `RunDirector`: day counter, day/night phases, phase events
- [ ] Autosave at day boundaries (calls `main.gd.save_run()`)
- [ ] Day/night visual treatment
- [ ] The commuting first miner walks home at night
- [~] Run save/continue works; destroying it on base death waits for
      `RunDirector` (`SaveManager.delete_run()` is ready)
- [ ] Death, run summary, return to title
"""
new = """## Stage 3 — Day/night and the run

- [x] `RunDirector`: day counter, 120 s day / 60 s night in ticks, phase
      signals (`day_started`, `phase_changed`), saved with the run
- [x] Autosave at dawn (calls `main.gd.save_run()`)
- [x] Day/night visual treatment: a `CanvasModulate` in the world (not over
      the UI), easing through dusk and dawn; both twilights belong to the
      night, so days are always fully lit
- [x] Day bar under the resource bar: day number, sun/moon, a bar that drains
      as the phase runs out
- [x] Night: everyone goes home; builders still take repair jobs, which means
      standing in the open; carriers leave drops until dawn
- [x] The commuting first miner walks home at night and returns to the same
      mine at dawn
- [x] Death: the base falling pauses the clock, deletes the run save, updates
      the profile (`runs_ended`, `best_day`, `total_ticks`)
- [x] Run summary over the frozen world, one "Return to title" button
- [x] Dev shortcuts: Ctrl+T skip to dusk/dawn, Ctrl+K destroy the base
- [ ] Art: `assets/ui/sun.png`, `assets/ui/moon.png` (32x32) — placeholder
      checker until they exist
- [ ] Balancing pass on day and night length once enemies exist (Stage 4)
"""
assert s.count(old) == 1
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
print("TODO.md patched")
