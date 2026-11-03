-- People going about their day. Where everyone is comes from their routine in
-- the shared core (Core.routines) and the game clock, worked out on the spot
-- (nothing about it needs saving): when a routine moves someone to a new place
-- they leave a little after the hour, travel, and arrive. Only what happens near
-- V is acted out with a real NPC:
--
--   leaving   they come out of the door they were behind and walk off
--   arriving  they walk up to the door and go in; with no interior they're gone
--             from sight, with one they walk inside and stay there
--   inside    a place with an interior: they're there, seen, while V is near
--   around    no place to be (errands, the street): they wander near home
--   rough     homeless people at the spot they sleep rough by (asleep there too)
--   passing   people out and about whose home is further off: they walk V's
--             streets in place of the game's crowd (which this mod turns off)
--
-- Asleep at home, or anywhere V isn't, they're only in the numbers.

local World = require("modules/world")
local Places = require("modules/places")
local Population = require("modules/population")
local Traffic = require("modules/traffic")
local Spots = require("modules/spots")

local Life = {
	spawned = {},       -- person id -> { ent, task, ... }
	count = 0,
	plans = {},         -- person id -> cached plan for one game hour
	settings = { enabled = true, radius = 120, despawn = 170, max = 24, pedestrians = 20, useSpots = true },
	usedSpots = 0,      -- times someone has sat down, leant, ... (for the window)
	reach = 600,        -- people living this close to V can be out walking V's streets
	walked = {},        -- person id -> the half hour they last walked past V (once each)
	window = 200,       -- game seconds of walking shown when someone leaves or arrives
	speed = 9,          -- metres per game second travelling between places (by car, train)
	log = {},
}

-- Real time in seconds (tests set their own).
function Life.now() return os.clock() end

local function note(text)
	table.insert(Life.log, text)
	while #Life.log > 40 do table.remove(Life.log, 1) end
end
Life.note = note

local function dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Where someone should be
---------------------------------------------------------------------------

-- Someone's routine (Core.routines.get), kept for a minute: working out a
-- default routine looks through the city's places, which is too slow to do for
-- every person every second.
Life.routines = {}
local function routineOf(Core, id)
	local r = Life.routines[id]
	if r and os.clock() - r.at < 600 then return r.list end
	local list = Core.routines.get(id) or {}
	Life.routines[id] = { list = list, at = os.clock() }
	return list
end

-- Core.routines.whereIs, with the routine above (the same rules).
local function whereIs(Core, id, hour, weekday)
	local p = Core.people.get(id)
	if p == nil or p.status == "dead" or p.status == "missing" then return nil end
	if p.status == "hurt" then return { activity = "recovering", place = p.home } end
	for _, b in ipairs(routineOf(Core, id)) do
		local onDay = b.days == nil
		for _, d in ipairs(b.days or {}) do if d == weekday then onDay = true end end
		if onDay and Core.time.between(b.from, b.to, hour) then
			local place = b.place
			if place == "home" then place = p.home elseif place == "work" then place = p.place end
			return { activity = b.activity, place = place }
		end
	end
	return { activity = "around", place = nil }
end
Life.whereIs = whereIs

-- The current routine block (activity and place), when it started, and the one
-- before it. Cached for the game hour.
local function plan(Core, id, now)
	local key = now.day * 24 + now.hour
	local c = Life.plans[id]
	if c and c.key == key then return c end
	local cur = whereIs(Core, id, now.hour, now.weekday)
	if cur == nil then Life.plans[id] = { key = key } return Life.plans[id] end
	local back, h, wd, prev = 0, now.hour, now.weekday, nil
	while back < 23 do
		h = h - 1
		if h < 0 then h = 23 wd = (wd - 2) % 7 + 1 end
		local w = whereIs(Core, id, h, wd)
		if w == nil or w.place ~= cur.place or w.activity ~= cur.activity then prev = w break end
		back = back + 1
	end
	local start = (now.day * 24 + now.hour - back) * 3600
	local from = prev and prev.place and Places.get(prev.place)
	if from == nil and prev and prev.place == nil and cur.place then
		-- out and about before (errands near home): they set off from home
		local p = Core.people.get(id)
		from = p and p.home and Places.get(p.home) or nil
	end
	local to = cur.place and Places.get(cur.place)
	local jitter = Core.Rng.new("ponc", "leave", id, start):int(0, 1800)
	local travel = (from and to) and (dist(from, to) / Life.speed + 120) or 300
	c = { key = key, cur = cur, prev = prev, from = from, to = to,
		leave = start + jitter, arrive = start + jitter + travel }
	Life.plans[id] = c
	return c
end

-- What V would see of someone right now, near V's position v (or nil):
-- { kind = "leaving"|"arriving"|"inside"|"around", place, other, ... }
local function scene(Core, id, now, v, r)
	local c = plan(Core, id, now)
	if c.cur == nil then return nil end
	local t = now.seconds
	local p = Core.people.get(id)
	if p == nil or p.status == "dead" or p.status == "missing" then return nil end
	local home = p.home and Places.get(p.home)
	if Population.homeless[id] and home and (c.cur.place == nil or c.cur.place == p.home) then
		-- sleeping rough or hanging about their spot: always there, never indoors
		if dist(home, v) < r then
			return { kind = "rough", place = home, asleep = c.cur.activity == "sleep" }
		end
		return nil
	end
	if t < c.leave then
		-- still where they were before
		local where = c.from
		local act = c.prev and c.prev.activity
		if where then
			if act ~= "sleep" and dist(where, v) < r and Places.inside(World, where, v) then
				return { kind = "inside", place = where }
			end
			return nil
		end
		if home and dist(home, v) < r and act ~= "sleep" then return { kind = "around", place = home } end
		return nil
	end
	if t < c.arrive then
		if c.from and t < c.leave + Life.window and dist(c.from, v) < r then
			return { kind = "leaving", place = c.from, other = c.to }
		end
		if c.to and t > c.arrive - Life.window and dist(c.to, v) < r then
			return { kind = "arriving", place = c.to, other = c.from, left = c.arrive - t }
		end
		return nil
	end
	-- arrived
	if c.to then
		if c.cur.activity ~= "sleep" and dist(c.to, v) < r and Places.inside(World, c.to, v) then
			return { kind = "inside", place = c.to }
		end
		return nil
	end
	if home and dist(home, v) < r and c.cur.activity ~= "sleep" then return { kind = "around", place = home } end
	return nil
end
Life.scene = scene
Life.plan = plan

---------------------------------------------------------------------------
-- Acting it out
---------------------------------------------------------------------------

local function faction(Core, p)
	for _, a in ipairs(p.affiliations or {}) do
		if not a.secret then
			local o = Core.orgs and Core.orgs.get(a.org)
			return o and o.name or a.org
		end
	end
	return ""
end

local function spawn(Core, id, at, sc)
	local p = Core.people.get(id)
	if p == nil then return nil end
	local look = p.look or {}
	local pos = World.navPointNear(at.x, at.y, at.z, 4.0) or at
	local ent = World.spawnNPC(look.record or "Character.CorpoMan", pos.x, pos.y, pos.z, at.yaw or 0, look.appearance)
	if ent == nil then return nil end
	local s = { id = id, ent = ent, scene = sc.kind, place = sc.place and sc.place.id, born = Life.now(), named = false }
	Life.spawned[id] = s
	Life.count = Life.count + 1
	Core.people.bind(id, ent)
	note(p.name .. ": " .. sc.kind .. (sc.place and (" (" .. Places.name(sc.place) .. ")") or ""))
	return s
end

local leaveSpotLater
local function despawn(Core, s, why)
	if leaveSpotLater then leaveSpotLater(s) end
	World.despawn(s.ent)
	pcall(function() Core.people.unbind(s.id) end)
	Life.spawned[s.id] = nil
	Life.count = Life.count - 1
end

-- A point `d` metres from place p toward (or away from) another point.
local function toward(p, other, d)
	if other == nil then
		local a = math.rad((p.yaw or 0) + 90)
		return { x = p.x + math.cos(a) * d, y = p.y + math.sin(a) * d, z = p.z }
	end
	local dx, dy = other.x - p.x, other.y - p.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then return { x = p.x + d, y = p.y, z = p.z } end
	return { x = p.x + dx / len * math.min(d, len), y = p.y + dy / len * math.min(d, len), z = p.z }
end

-- Where a scene's NPC first appears.
local function startPoint(Core, sc, v, id)
	local pl = sc.place
	if sc.kind == "leaving" then return pl end
	if sc.kind == "inside" then return Places.inside(World, pl, v) or pl end
	if sc.kind == "arriving" then
		-- part way along, by how much of the walk is left
		local left = math.max(0, math.min(1, (sc.left or Life.window) / Life.window))
		return toward(pl, sc.other or v, 10 + 35 * left)
	end
	if sc.kind == "rough" then
		-- their own patch by the door, the same one every time
		local r = Core.Rng.new("ponc", "patch", id or "")
		local a = r:next() * math.pi * 2
		local d = 2 + r:next() * 4
		return World.navPointNear(pl.x + math.cos(a) * d, pl.y + math.sin(a) * d, pl.z, 3.0) or pl
	end
	if sc.kind == "passing" then return sc.from end
	if sc.kind == "around" then
		local r = Core.Rng.new("ponc", "around", pl.id, math.floor(Life.now() / 60))
		local a = r:next() * math.pi * 2
		return { x = pl.x + math.cos(a) * 20, y = pl.y + math.sin(a) * 20, z = pl.z }
	end
	return pl
end

-- Gives a spawned person something to do for their scene.
local SITTING = { sit = true, lean = true, idle = true }
local INSIDE = { sit = true, lean = true, idle = true, work = true }
local ROUGH = { rough = true, sit = true }

local function sleepy(sp) return sp.path:find("sleep") ~= nil or sp.path:find("__lie_") ~= nil end

-- A spot near pl for someone in this scene to use, or nil.
local function spotFor(Core, s, sc, pl, near)
	if not Life.settings.useSpots then return nil end
	local p = Core.people.get(s.id)
	local r = Core.Rng.new("ponc", "spot", s.id, math.floor(Life.now() / 30))
	local gender = p and p.gender
	if sc.kind == "rough" then
		local asleep = sc.asleep
		return Spots.claim(s.id, pl.x, pl.y, 35, ROUGH, r, gender, pl.z, function(sp)
			if sp.kind ~= "rough" then return not asleep and sp.path:find("ground") ~= nil end
			return sleepy(sp) == (asleep == true)
		end)
	elseif sc.kind == "around" then
		if not r:chance(0.6) then return nil end
		return Spots.claim(s.id, pl.x, pl.y, 50, SITTING, r, gender, pl.z, function(sp) return not sleepy(sp) end)
	elseif sc.kind == "inside" then
		local c = near or pl
		return Spots.claim(s.id, c.x, c.y, 20, INSIDE, r, gender, c.z, function(sp)
			return not sleepy(sp) and (sp.kind ~= "work" or (p ~= nil and p.place == (sc.place and sc.place.id)))
		end)
	end
	return nil
end

-- Done with a spot: get up, take the device away, free the spot.
local function leaveSpot(s)
	local t = s.task
	if t == nil or t.spot == nil then return end
	if t.device then
		if t.using then World.leaveSpot(s.ent) end
		World.despawnSpot(t.device)
	end
	Spots.release(t.spot, s.id)
	t.spot, t.device, t.using = nil, nil, false
end
Life.leaveSpot = leaveSpot
leaveSpotLater = leaveSpot

local function direct(Core, s, sc, v)
	leaveSpot(s)
	s.scene, s.place = sc.kind, sc.place and sc.place.id
	local pl = sc.place
	if (sc.kind == "rough" or sc.kind == "around" or sc.kind == "inside") and pl then
		local near = sc.kind == "inside" and Places.inside(World, pl, v) or nil
		local sp = spotFor(Core, s, sc, pl, near)
		if sp then
			local to = World.navPointNear(sp.x, sp.y, sp.z, 1.5) or sp
			local stay = (sc.kind == "rough" and sc.asleep) and 3600 or (sc.kind == "inside" and 400 or 90 + (#s.id % 7) * 25)
			s.task = { to = to, spot = sp, vanish = false, stay = stay, run = false }
			s.task.sent = World.walk(s.ent, to.x, to.y, to.z, false)
			s.task.since = Life.now()
			return
		end
	end
	if sc.kind == "leaving" then
		-- off toward where they're going; if that's close, all the way there
		local goal = sc.other
		if goal and dist(goal, pl) < 140 then
			s.task = { to = goal, vanish = true, run = false }
		else
			s.task = { to = toward(pl, goal, 45), vanish = true, run = false }
		end
	elseif sc.kind == "arriving" then
		local inside = Places.inside(World, pl, toward(pl, sc.other, 40))
		s.task = { to = inside or pl, vanish = inside == nil, run = false }
	elseif sc.kind == "inside" then
		s.task = { to = Places.inside(World, pl, v) or pl, vanish = false, idle = true }
	elseif sc.kind == "around" then
		local r = Core.Rng.new("ponc", "wander", s.id, math.floor(Life.now()))
		local a = r:next() * math.pi * 2
		local d = 10 + r:next() * 35
		local q = World.navPointNear(pl.x + math.cos(a) * d, pl.y + math.sin(a) * d, pl.z, 6.0)
		s.task = { to = q or pl, vanish = false, wander = true }
	end
	if s.task and s.task.to then
		s.task.sent = World.walk(s.ent, s.task.to.x, s.task.to.y, s.task.to.z, s.task.run)
		s.task.since = Life.now()
	end
end

-- Takes over someone already in the world (out of their car, at `place`).
function Life.adopt(Core, id, ent, place)
	if Life.spawned[id] then return end
	local s = { id = id, ent = ent, scene = "adopted", born = Life.now(), named = true }
	Life.spawned[id] = s
	Life.count = Life.count + 1
	local pos = World.npcPos(ent) or place
	local sc = { kind = "arriving", place = place, other = pos, left = 0 }
	direct(Core, s, sc, pos)
end

-- The finishing touches once the NPC is really there: its look is kept (so it
-- looks the same next time) and it scans as itself.
local function settle(Core, s)
	if s.named then return end
	if World.entity(s.ent) == nil then return end
	local p = Core.people.get(s.id)
	if p == nil then return end
	World.setScannerName(s.ent, p.name, faction(Core, p))
	if p.look and p.look.appearance == nil then
		local app = World.appearance(s.ent)
		if app then
			Core.people.update(s.id, { look = { record = p.look.record, appearance = app } }, "seen")
		end
	end
	s.named = true
end

local function step(Core, s, v)
	settle(Core, s)
	local here = World.npcPos(s.ent)
	local state = World.npcState(s.ent)
	if state == "dead" then
		-- the core marks them dead (people.tick); the body stays a while
		if not s.deadAt then s.deadAt = Life.now() end
		if Life.now() - s.deadAt > 60 or (here and dist(here, v) > Life.settings.despawn) then despawn(Core, s, "dead") end
		return
	end
	if here and dist(here, v) > Life.settings.despawn then despawn(Core, s, "out of range") return end
	local t = s.task
	if t == nil or t.to == nil then return end
	if t.spot then
		local clock = Life.now()
		if t.device == nil then
			if (here and dist(here, t.to) < 2.5) or World.moveState(s.ent) == 5 then
				t.device = World.spawnSpot(t.spot.path, t.spot.x, t.spot.y, t.spot.z, t.spot.yaw)
				t.placed = clock
				if t.device == nil then leaveSpot(s) s.task = nil end
			elseif clock - (t.since or 0) > 60 then
				leaveSpot(s) s.task = nil -- couldn't get there
			end
		elseif not t.using then
			if World.entity(t.device) and clock - t.placed > 0.5 then
				if World.useSpot(t.device, s.ent) then
					t.using, t.started = true, clock
					Life.usedSpots = Life.usedSpots + 1
				end
			elseif clock - t.placed > 8 then
				leaveSpot(s) s.task = nil
			end
		else
			if not t.checked and clock - t.started > 3 then
				t.checked = true
				if not World.inSpot(s.ent) then
					-- its animations don't fit them: not that workspot again for them
					local p = Core.people.get(s.id)
					Spots.misfit(t.spot, p and p.gender)
					leaveSpot(s) s.task = nil
					return
				end
			end
			if clock - t.started > t.stay then
				leaveSpot(s) s.task = nil -- something else next
			end
		end
		return
	end
	local reached = here and dist(here, t.to) < 1.6
	local ms = World.moveState(s.ent)
	if reached or ms == 5 then
		if t.vanish then despawn(Core, s, "went in") return end
		if t.wander then s.task = nil end -- pick another spot next time
		return
	end
	if ms == 6 or ms == 3 or (Life.now() - (t.since or 0) > 90) then
		-- couldn't get there (no path): gone out of sight if they were going in or away
		if t.vanish and (here == nil or dist(here, v) > 25) then despawn(Core, s, "lost") return end
		if t.wander then s.task = nil return end
		t.sent = World.walk(s.ent, t.to.x, t.to.y, t.to.z, t.run)
		t.since = Life.now()
	end
end

---------------------------------------------------------------------------
-- The streets: people out and about walk past V (in place of the game's crowd)
---------------------------------------------------------------------------

local function isOut(c, t)
	if c.cur == nil then return false end
	if t >= c.leave and t < c.arrive then return true end           -- on their way somewhere
	return c.cur.place == nil and c.cur.activity ~= "sleep"          -- errands, the street
end

-- A walk past V: from a point on the navmesh some way off, across to the far side.
local function passingWalk(Core, id, v, half)
	local r = Core.Rng.new("ponc", "pass", id, half)
	local a = r:next() * math.pi * 2
	local d1, d2 = 55 + r:next() * 45, 55 + r:next() * 45
	local b = a + math.pi + (r:next() - 0.5) * 1.6
	local from = World.navPointNear(v.x + math.cos(a) * d1, v.y + math.sin(a) * d1, v.z, 12.0)
	local to = World.navPointNear(v.x + math.cos(b) * d2, v.y + math.sin(b) * d2, v.z, 12.0)
	if from == nil or to == nil then return nil end
	if math.abs(from.z - v.z) > 12 then return nil end -- not on a roof or under the street
	from.id, to.id = "street", "street"
	return { kind = "passing", place = from, from = from, to = to }
end

local function passers(Core, now, v, taken)
	local want = Life.settings.pedestrians or 0
	if want <= 0 then return {} end
	local half = math.floor(now.seconds / 1800)
	local have = 0
	for _, s in pairs(Life.spawned) do if s.scene == "passing" then have = have + 1 end end
	if have >= want then return {} end
	-- the locals in a fixed order for this half hour (the same save, the same faces)
	local o = Life.order
	if o == nil or o.half ~= half or dist(o.at, v) > 100 or os.clock() - o.made > 30 then
		local list = Population.locals(v.x, v.y, Life.reach)
		local key = {}
		for _, id in ipairs(list) do key[id] = Core.Rng.new("ponc", "out", id, half):next() end
		table.sort(list, function(a, b) return key[a] < key[b] end)
		o = { half = half, at = { x = v.x, y = v.y }, made = os.clock(), ids = list }
		Life.order = o
	end
	local ids = o.ids
	local out, looked = {}, 0
	for _, id in ipairs(ids) do
		if have + #out >= want or looked > 80 then break end
		if not taken[id] and not Life.spawned[id] and not Traffic.cars[id] and Life.walked[id] ~= half then
			looked = looked + 1
			local p = Core.people.get(id)
			if p and p.status ~= "dead" and p.status ~= "missing" and p.status ~= "hurt" then
				local c = plan(Core, id, now)
				if isOut(c, now.seconds) and not Traffic.driving(Core, id, c, now.seconds) then
					local sc = passingWalk(Core, id, v, half)
					if sc then table.insert(out, { id = id, sc = sc }) end
				end
			end
		end
	end
	return out, half
end

-- One pass: who should be seen near V, spawn or direct them, and tidy up.
function Life.update(Core, now, v)
	if not Life.settings.enabled then
		for _, s in pairs(Life.spawned) do despawn(Core, s, "off") end
		return
	end
	local r = Life.settings.radius
	local wanted = {}
	local ids = Population.involved(v.x, v.y, r + 40)
	for _, id in ipairs(ids) do
		local sc = scene(Core, id, now, v, r)
		if sc then table.insert(wanted, { id = id, sc = sc, d = dist(sc.place, v) }) end
	end
	-- the brief moments first (someone coming out or going in), then the rest, nearest first
	local RANK = { leaving = 1, arriving = 1, inside = 2, around = 3, rough = 3 }
	table.sort(wanted, function(a, b)
		local ra, rb = RANK[a.sc.kind] or 3, RANK[b.sc.kind] or 3
		if ra ~= rb then return ra < rb end
		return a.d < b.d
	end)
	local keep = {}
	-- the people walking past V have their own limit
	local inScenes = 0
	for _, s in pairs(Life.spawned) do if s.scene ~= "passing" then inScenes = inScenes + 1 end end
	for i, w in ipairs(wanted) do
		if i > Life.settings.max then break end
		keep[w.id] = true
		local s = Life.spawned[w.id]
		if s == nil and Traffic.cars[w.id] then
			-- in their car
		elseif s == nil then
			if inScenes < Life.settings.max then
				s = spawn(Core, w.id, startPoint(Core, w.sc, v, w.id), w.sc)
				if s then s.pending = w.sc inScenes = inScenes + 1 end
			end
		elseif s.scene ~= w.sc.kind or s.place ~= (w.sc.place and w.sc.place.id) or (w.sc.kind == "rough" and s.asleep ~= w.sc.asleep) then
			s.asleep = w.sc.asleep
			direct(Core, s, w.sc, v)
		elseif s.task == nil and (w.sc.kind == "around" or w.sc.kind == "rough" or w.sc.kind == "inside") and World.entity(s.ent) then
			direct(Core, s, w.sc, v)
		end
	end
	-- people walking the streets: they keep walking until they're past
	for _, s in pairs(Life.spawned) do if s.scene == "passing" then keep[s.id] = true end end
	local walkers, half = passers(Core, now, v, keep)
	for _, w in ipairs(walkers) do
		if Life.count >= Life.settings.max + (Life.settings.pedestrians or 0) then break end
		local s = spawn(Core, w.id, w.sc.from, w.sc)
		if s then
			s.pending = w.sc
			keep[w.id] = true
			Life.walked[w.id] = half
		end
	end
	for id, s in pairs(Life.spawned) do
		if s.pending and World.entity(s.ent) then
			local sc = s.pending
			s.pending = nil
			direct(Core, s, sc, v)
		end
		if Life.spawned[id] then step(Core, s, v) end
		-- no longer part of any scene: finish what they're doing, then go
		if Life.spawned[id] and not keep[id] and s.task and not s.task.vanish and not s.pending then
			s.task.vanish = true
			if s.scene == "inside" or s.scene == "around" or s.scene == "rough" then despawn(Core, s, "scene over") end
		end
	end
end

function Life.clear(Core)
	for _, s in pairs(Life.spawned) do despawn(Core, s, "cleared") end
	Life.plans = {}
	Life.walked = {}
	Life.order = nil
	Spots.clear()
end

return Life
