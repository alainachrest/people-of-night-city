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
--
-- Asleep at home, or anywhere V isn't, they're only in the numbers.

local World = require("modules/world")
local Places = require("modules/places")
local Population = require("modules/population")

local Life = {
	spawned = {},       -- person id -> { ent, task, ... }
	count = 0,
	plans = {},         -- person id -> cached plan for one game hour
	settings = { enabled = true, radius = 120, despawn = 170, max = 24 },
	window = 200,       -- game seconds of walking shown when someone leaves or arrives
	speed = 9,          -- metres per game second travelling between places (by car, train)
	log = {},
}

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
	if r and os.clock() - r.at < 60 then return r.list end
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
	local s = { id = id, ent = ent, scene = sc.kind, place = sc.place and sc.place.id, born = os.clock(), named = false }
	Life.spawned[id] = s
	Life.count = Life.count + 1
	Core.people.bind(id, ent)
	note(p.name .. ": " .. sc.kind .. (sc.place and (" (" .. Places.name(sc.place) .. ")") or ""))
	return s
end

local function despawn(Core, s, why)
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

-- Gives a spawned person something to do for their scene.
local function direct(Core, s, sc, v)
	s.scene, s.place = sc.kind, sc.place and sc.place.id
	local pl = sc.place
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
		local r = Core.Rng.new("ponc", "wander", s.id, math.floor(os.clock()))
		local a = r:next() * math.pi * 2
		local d = 10 + r:next() * 35
		local q = World.navPointNear(pl.x + math.cos(a) * d, pl.y + math.sin(a) * d, pl.z, 6.0)
		s.task = { to = q or pl, vanish = false, wander = true }
	end
	if s.task and s.task.to then
		s.task.sent = World.walk(s.ent, s.task.to.x, s.task.to.y, s.task.to.z, s.task.run)
		s.task.since = os.clock()
	end
end

-- Where a scene's NPC first appears.
local function startPoint(Core, sc, v)
	local pl = sc.place
	if sc.kind == "leaving" then return pl end
	if sc.kind == "inside" then return Places.inside(World, pl, v) or pl end
	if sc.kind == "arriving" then
		-- part way along, by how much of the walk is left
		local left = math.max(0, math.min(1, (sc.left or Life.window) / Life.window))
		return toward(pl, sc.other or v, 10 + 35 * left)
	end
	if sc.kind == "around" then
		local r = Core.Rng.new("ponc", "around", pl.id, math.floor(os.clock() / 60))
		local a = r:next() * math.pi * 2
		return { x = pl.x + math.cos(a) * 20, y = pl.y + math.sin(a) * 20, z = pl.z }
	end
	return pl
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
		if not s.deadAt then s.deadAt = os.clock() end
		if os.clock() - s.deadAt > 60 or (here and dist(here, v) > Life.settings.despawn) then despawn(Core, s, "dead") end
		return
	end
	if here and dist(here, v) > Life.settings.despawn then despawn(Core, s, "out of range") return end
	local t = s.task
	if t == nil or t.to == nil then return end
	local reached = here and dist(here, t.to) < 1.6
	local ms = World.moveState(s.ent)
	if reached or ms == 5 then
		if t.vanish then despawn(Core, s, "went in") return end
		if t.wander then s.task = nil end -- pick another spot next time
		return
	end
	if ms == 6 or ms == 3 or (os.clock() - (t.since or 0) > 90) then
		-- couldn't get there (no path): gone out of sight if they were going in or away
		if t.vanish and (here == nil or dist(here, v) > 25) then despawn(Core, s, "lost") return end
		if t.wander then s.task = nil return end
		t.sent = World.walk(s.ent, t.to.x, t.to.y, t.to.z, t.run)
		t.since = os.clock()
	end
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
	table.sort(wanted, function(a, b) return a.d < b.d end)
	local keep = {}
	for i, w in ipairs(wanted) do
		if i > Life.settings.max then break end
		keep[w.id] = true
		local s = Life.spawned[w.id]
		if s == nil then
			if Life.count < Life.settings.max then
				s = spawn(Core, w.id, startPoint(Core, w.sc, v), w.sc)
				if s then s.pending = w.sc end
			end
		elseif s.scene ~= w.sc.kind or s.place ~= (w.sc.place and w.sc.place.id) then
			direct(Core, s, w.sc, v)
		elseif s.task == nil and w.sc.kind == "around" and World.entity(s.ent) then
			direct(Core, s, w.sc, v)
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
			if s.scene == "inside" or s.scene == "around" then despawn(Core, s, "scene over") end
		end
	end
end

function Life.clear(Core)
	for _, s in pairs(Life.spawned) do despawn(Core, s, "cleared") end
	Life.plans = {}
end

return Life
