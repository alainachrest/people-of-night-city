# People of Night City

A Cyberpunk 2077 mod: the people in the CyberScript shared core's registry
living their lives in the world. They go to work, come home and wander their
neighbourhood, and you can meet the same person again and again.

Needs CyberScript with the shared core (API 2+: the `api-hooks-and-2.5` branch of
[alainachrest/cyberscript-cp2077-fork](https://github.com/alainachrest/cyberscript-cp2077-fork)),
Cyber Engine Tweaks, redscript and Codeware. Doesn't touch Gangs of Night City.

## How it works

- **Homes and workplaces** are the outside doors of Night City's buildings, taken
  from the game's own world data (8,302 doors: 5,711 homes, 2,591 workplaces).
  Single doors are homes; double doors, shop shutters and freight doors are
  workplaces.
- **People**: the first time V comes within 700 m of a home, the core makes its
  people (1-4, `Core.people.populate`), from the save's seed: the same save always
  has the same people. Their way of life depends on the district. Working people
  work at one of the workplaces nearest their home.
- **Their day** is their routine in the core (`Core.routines`): sleep, work,
  leisure, errands. When a routine moves someone to a new place, they leave a
  little after the hour, travel (by car or train, out of sight), and arrive.
- **What V sees** (within 120 m, 24 people at most, both adjustable):
  - someone leaving comes out of their door and walks off;
  - someone arriving walks up to the door. A door that never opens is a building
    with no interior: they go in and are gone from sight until they come out
    again. If there's navmesh on both sides of the door (an interior V can walk
    into), they walk inside and stay there, seen;
  - someone with no place to be wanders near home;
  - asleep, or anywhere V isn't, they're only in the numbers.
- Each person keeps their look (the appearance they first had), scans as
  themselves (name and any open affiliation), and is bound to their NPC in the
  core: kill one and that person is dead for good.

Nothing about who people are goes in the save (they're rebuilt from the seed);
only what happens to them does.

## The window

CET overlay > **People of Night City**: on/off, how far away people are seen,
how many at once, who lives and works near you and what they're doing, the
places near you (door type, interior, people), and what just happened.

## Building the places

`tools/build_places.py` turns `data/doors.json` (the doors, extracted from the
game's exterior streaming sectors) into the mod's `data/places.lua`:

    python tools/build_places.py <cyberscript>/mod/data/districts.json \
        bin/x64/plugins/cyber_engine_tweaks/mods/people_of_night_city/data/places.lua

`tools/extract_doors.py` is how `doors.json` was made (it reads the game's
archive, using the navmesh framework's `cr2w.py` and a Kraken decompressor).

## Tests

    luajit tests/ponc_test.lua bin/x64/plugins/cyber_engine_tweaks/mods/people_of_night_city <folder with core_stub.lua>
