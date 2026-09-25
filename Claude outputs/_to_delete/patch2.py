import io

def patch(path, pairs):
    s = io.open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path + " anchor not unique: " + old[:70])
        s = s.replace(old, new, 1)
    io.open(path, 'w', encoding='utf-8').write(s)
    print("patched", path)

patch('ARCHITECTURE.md', [
 # night behaviour: mines idle
 ("""  *remembers which mine it was*, and is sent back at dawn unless the player
  gave it another one meanwhile or its mine is gone.""",
  """  *remembers which mine it was*, and is sent back at dawn unless the player
  gave it another one meanwhile or its mine is gone.
- **Mines stand idle at night.** `_gather` returns immediately while `night`
  is set, so a miner who moves into a house *after* dusk sleeps there and
  produces nothing until dawn. Part-finished work is kept, so a night costs
  exactly the night and not the progress before it."""),
 # the tint's alpha
 ("""  layer alone -- the resource bar stays readable at midnight. **Both twilights""",
  """  layer alone -- the resource bar stays readable at midnight. The tint is
  always **opaque**: a CanvasModulate multiplies alpha too, so a tint with
  alpha below 1 would make the world translucent rather than dark. **Both
  twilights"""),
 # the glow
 ("""- **Tuning** lives on `RunDirector` itself:""",
  """- **The building glow** (`buildings/building_glow.gd`) is a faint warm halo
  over every *finished player* building, so the base and the houses stay
  readable once the world goes dark. Trees, stumps and mines do not glow:
  `get_building_data` returning non-null is exactly the test for "the player
  built this". One `MultiMeshInstance2D`, one draw call however many buildings
  stand (D2); the instance list is rebuilt only when buildings change, and the
  per-frame work is one `modulate`. The falloff texture is generated in code,
  so the halo needs no art.
  The halo blends **additively** onto a canvas the CanvasModulate has already
  darkened -- and a CanvasModulate multiplies everything on its layer, the halo
  included -- so `set_night` divides the halo's colour by the tint. Without
  that, the glow would be dimmed by exactly the darkness it exists to fight,
  and changing `night_light` would silently change the glow with it. It sits
  above the ground and the buildings it lights, below the units.
- **Tuning** lives on `RunDirector` itself:"""),
 ("""  `twilight_seconds`, `night_light`, `night_colour`.""",
  """  `twilight_seconds`, `night_light`, `night_colour`; the halo's warmth, size
  and strength are exports on `BuildingGlow`."""),
])

patch('TODO.md', [
 ("""- [x] Night: everyone goes home; builders still take repair jobs, which means
      standing in the open; carriers leave drops until dawn""",
  """- [x] Night: everyone goes home; builders still take repair jobs, which means
      standing in the open; carriers leave drops until dawn
- [x] Mines stand idle at night, including a miner who moves into a house
      after dusk
- [x] A faint warm halo over finished player buildings at night (one MultiMesh,
      generated falloff texture, no art needed)"""),
])

patch('docs/DESIGN.md', [
 ("""- **The world darkens at night**, easing in at dusk and out at dawn. The UI
  does not darken.""",
  """- **The world darkens at night**, easing in at dusk and out at dawn. The UI
  does not darken. Finished player buildings carry a **faint warm glow** so
  they stay readable in the dark; trees and mines do not."""),
 ("""  it is a risk the player chooses to take. Carriers leave dropped resources
  where they lie until morning, and mines stand idle.""",
  """  it is a risk the player chooses to take. Carriers leave dropped resources
  where they lie until morning, and **mines stand idle** — a miner sent to a
  mine after dusk moves in and sleeps, and produces nothing until dawn."""),
])
