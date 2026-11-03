# People of Night City

The people in the CyberScript shared core's registry
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
  work somewhere within 2 km of home (a couple of jobs close by, most further
  off), so most of them commute. Homes further out get their people a few at a
  time, so the people who work near V are there too. Some are out of work (more
  in poor districts: 35% in Pacifica, 4% in City Center).
- **Homeless people** sleep rough by a door on the street (1-3 at one door in
  12 in Pacifica, fewer elsewhere). They have no home, no job and no wage, and
  they're at their spot day and night, asleep there too.
- **Money** is the core's: everyone pays living costs daily; only people with a
  job are paid, weekly (on Fridays).
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
  - homeless people are at their spot;
  - **the streets**: the game's own crowd of pedestrians is turned off
    (`engine/config/platform/pc/people_of_night_city.ini`; traffic is left as
    it is; delete the file to have the game's crowd back). In its place, people
    who live within 600 m of V and are out (on errands, on their way somewhere)
    walk past V (20 at once, adjustable). Each walks past at most once every
    half hour;
  - **traffic**: the game's traffic is turned off too (same `.ini`). Someone on
    their way somewhere 150 m or more away, who has a car (more likely for
    corpos and the rich, never for the homeless), is driving it: near V they're
    a real car, them at the wheel, driving on the roads to where they're
    actually going. So the roads are busy at shift changes and quiet at 3am.
    Everyone has the same car every time. When they get there and V is near,
    they get out and walk in; the car stays parked. Up to 15 cars at once
    (adjustable);
  - **sitting, leaning, doing things**: people use the same spots the game's
    own NPCs use, with the same animations: 63,882 of them, from the game files
    (benches, chairs, bar stools, couches, walls and rails to lean on, smoking,
    phones, drinks, vending machines, food stalls). Someone with time near home
    often goes and sits or leans somewhere; someone at a place with an
    interior sits at the bar or a table (or works, if it's their workplace);
    homeless people go through bins, warm their hands, beg, and at night
    sleep on the ground or a bench. One person per spot. A spot whose
    animations don't fit someone's body isn't used for them again;
  - **things in hand**: 8 in 10 people carry something their body has the walk
    for: a phone or tablet, a bag, a can or bottle, a cigarette, and an
    umbrella when it rains (in rain, fewer other things; in a downpour, only
    umbrellas). The same person carries the same thing in the same weather.
    They put it away to sit, lean or drive, and take it out again after;
  - **the game's other people** (standing, sitting, leaning about) are removed
    within 150 m of V, so the only civilians around are ours. Kept: anyone in a
    quest, vendors, police, gangs and other non-civilians, companions, NPCs other
    mods spawned, and anyone in combat. "Replace the game's people with ours" in
    the window turns this off;
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
