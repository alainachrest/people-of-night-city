-- Traffic: our people on the road. Someone on their way between two places far
-- enough apart, who has a car, is driving it: near V they're a real car with
-- them at the wheel, driving (on the roads, with the traffic rules) to where
-- they're actually going. So the roads are busy when people go to and from
-- work and quiet in the small hours, and the game's own traffic is turned off
-- (engine/config/platform/pc/people_of_night_city.ini).
--
-- Each car: spawned on a road some way from V on the side they're coming from,
-- its driver put in the driver's seat, then off. Gone once it's well past V.

local World = require("modules/world")
local Places = require("modules/places")
local Population = require("modules/population")

local Traffic = {
	settings = { enabled = true, cars = 15 },
	cars = {},        -- person id -> { veh, npc, stage, ... }
	count = 0,
	driven = {},      -- person id -> the trip (leave time) they were last shown driving
	reach = 1200,     -- people living this close to V can drive past
	despawn = 260,
	minTrip = 150,    -- shorter trips are walked
	sight = 80,       -- a car that has got where it's going stays parked while V is this close
	log = nil,
	tally = {},       -- what happened when cars were wanted (for the log)
}

local function tally(k) Traffic.tally[k] = (Traffic.tally[k] or 0) + 1 end
function Traffic.summary()
	local t = {}
	for k, n in pairs(Traffic.tally) do t[#t + 1] = k .. " " .. n end
	table.sort(t)
	return #t > 0 and table.concat(t, ", ") or "nobody driving yet"
end

-- How likely someone is to have a car, by way of life.
local CAR = { corpo = 0.8, rich = 1.0, worker = 0.45, vendor = 0.55, young = 0.35, nightlife = 0.5, medical = 0.6, nomad = 1.0, street = 0 }

local MODELS = {
	cheap = { "Vehicle.v_standard2_makigai_maimai_player", "Vehicle.v_standard2_archer_hella_player",
		"Vehicle.v_standard2_villefort_cortes_player", "Vehicle.v_standard2_thorton_galena_player",
		"Vehicle.v_standard25_thorton_colby_player", "Vehicle.v_standard2_chevalier_thrax_player" },
	work = { "Vehicle.v_standard25_thorton_colby_pickup_player", "Vehicle.v_standard3_thorton_mackinaw_player",
		"Vehicle.v_standard25_mahir_supron_player", "Vehicle.v_standard25_villefort_columbus_player" },
	good = { "Vehicle.v_standard3_chevalier_emperor_player", "Vehicle.v_standard2_archer_quartz_player",
		"Vehicle.v_sport2_mizutani_shion_player", "Vehicle.v_sport2_villefort_alvarado_player" },
	rich = { "Vehicle.v_sport1_rayfield_aerondight_player", "Vehicle.v_sport2_porsche_911turbo_player",
		"Vehicle.v_sport2_mizutani_shion_player" },
	bike = { "Vehicle.v_sportbike2_arch_player", "Vehicle.v_sportbike1_yaiba_kusanagi_player",
		"Vehicle.v_sportbike3_brennan_apollo_player" },
	nomad = { "Vehicle.v_standard2_thorton_galena_nomad_player", "Vehicle.v_standard25_thorton_colby_nomad_player",
		"Vehicle.v_sport2_quadra_type66_nomad_player" },
}
local KIND = { corpo = "good", rich = "rich", worker = "work", vendor = "work", young = "bike", nightlife = "cheap", medical = "cheap", nomad = "nomad" }

local function dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function note(text) if Traffic.log then Traffic.log("car: " .. text) end end

-- Whether a person has a car, and which (the same one every time).
function Traffic.carOf(Core, p)
	local r = Core.Rng.new("ponc", "car", p.id)
	if not r:chance(CAR[p.lifestyle or "worker"] or 0.4) then return nil end
	local list = MODELS[KIND[p.lifestyle or "worker"] or "cheap"]
	if r:chance(0.25) then list = MODELS.cheap end
	return list[r:int(1, #list)]
end

-- Is this person (plan c, at time t) driving right now?
-- Where a trip starts: the place they were, or home (out on errands first).
local function origin(Core, id, c)
	if c.from then return c.from end
	local p = Core.people.get(id)
	return p and p.home and Places.get(p.home) or nil
end

function Traffic.driving(Core, id, c, t)
	if c == nil or c.cur == nil or c.to == nil then return false end
	if t < c.leave or t >= c.arrive then return false end
	local from = origin(Core, id, c)
	if from == nil or dist(from, c.to) < Traffic.minTrip then return false end
	local p = Core.people.get(id)
	return p ~= nil and Traffic.carOf(Core, p) ~= nil
end

-- Where a car comes into view: a road on the side they're coming from.
local function entry(Core, id, c, v)
	local r = Core.Rng.new("ponc", "road", id, c.leave)
	local from = origin(Core, id, c)
	local ax, ay = from.x - v.x, from.y - v.y
	local len = math.sqrt(ax * ax + ay * ay)
	if len < 1 then ax, ay, len = 1, 0, 1 end
	-- from where they set off if that's near; otherwise down the road that way
	if len < 170 then
		local q = World.roadPointNear(from.x, from.y, from.z, 40)
		if q and math.abs(q.z - v.z) < 15 then return q end
	end
	local a = math.atan2(ay, ax) + (r:next() - 0.5) * 1.2
	for _, d in ipairs({ 140, 110, 170, 90 }) do
		local q = World.roadPointNear(v.x + math.cos(a) * d, v.y + math.sin(a) * d, v.z, 25)
		if q and math.abs(q.z - v.z) < 15 then return q end
	end
	return nil
end

local function remove(Core, car, why)
	if car.npc then
		World.despawn(car.npc)
		pcall(function() Core.people.unbind(car.id) end)
	end
	World.despawn(car.veh)
	Traffic.cars[car.id] = nil
	Traffic.count = Traffic.count - 1
end

local function start(Core, id, c, v, model)
	local at = entry(Core, id, c, v)
	if at == nil then tally("no road near V") return end
	local p = Core.people.get(id)
	local yaw = math.deg(math.atan2(c.to.y - at.y, c.to.x - at.x)) - 90
	local veh = World.spawnVehicle(model, at.x, at.y, at.z + 0.3, yaw)
	if veh == nil then tally("car spawn failed") return end
	local look = p.look or {}
	local npc = World.spawnNPC(look.record or "Character.CorpoMan", at.x + 2.5, at.y, at.z, yaw, look.appearance)
	if npc == nil then World.despawn(veh) return end
	Traffic.cars[id] = { id = id, veh = veh, npc = npc, stage = "spawning", since = os.clock(), to = c.to, model = model }
	Traffic.count = Traffic.count + 1
	Traffic.driven[id] = c.leave
	tally("set off")
	Core.people.bind(id, npc)
	note(p.name .. " driving to " .. Places.name(c.to))
end

local function step(Core, car, v)
	local vp = World.npcPos(car.veh)
	if vp and dist(vp, v) > Traffic.despawn then remove(Core, car, "past") return end
	local age = os.clock() - car.since
	if car.stage == "spawning" then
		if World.entity(car.veh) and World.entity(car.npc) then
			World.setScannerName(car.npc, Core.people.get(car.id).name, "")
			car.held = World.stowHeld(car.npc)
			World.mount(car.npc, car.veh, "seat_front_left")
			car.stage, car.since = "mounting", os.clock()
		elseif age > 10 then
			note("car never appeared (" .. car.model .. ")")
			tally("never appeared")
			remove(Core, car, "never spawned")
		end
	elseif car.stage == "mounting" then
		if World.hasDriver(car.veh) or age > 3 then
			local goal = World.roadPointNear(car.to.x, car.to.y, car.to.z, 40) or car.to
			-- (put away anything they were given since, too)
			local more = World.stowHeld(car.npc)
			if more then car.held = car.held or {} for _, h in ipairs(more) do table.insert(car.held, h) end end
			World.drive(car.veh, goal.x, goal.y, goal.z, 6, 14)
			car.stage, car.since = "driving", os.clock()
		end
	elseif car.stage == "driving" then
		if World.npcState(car.npc) == "dead" then car.stage = "dead" return end
		-- arrived: parked there; gone once V isn't watching (stuck: the same)
		if vp and dist(vp, car.to) < 25 then
			car.stage = "parked"
			-- V is near: they get out and walk in (Life takes them from here)
			if dist(vp, v) < Traffic.sight and Traffic.handOver then
				World.unmount(car.npc, car.veh, "seat_front_left")
				car.handedAt = os.clock()
			end
			return
		end
		if age > 300 and (vp == nil or dist(vp, v) > Traffic.sight) then remove(Core, car, "stuck") end
	elseif car.stage == "parked" and car.handedAt and car.npc then
		-- out of the car: from here they're Life's, the car stays parked
		if os.clock() - car.handedAt > 2 or not World.hasDriver(car.veh) then
			World.restoreHeld(car.npc, car.held)
			Traffic.handOver(car.id, car.npc, car.to)
			car.npc = nil
		end
	elseif car.stage == "parked" or car.stage == "dead" then
		if vp == nil or dist(vp, v) > Traffic.sight then remove(Core, car, car.stage) end
	end
end

-- One pass. plan(id) gives a person's plan for now (from Life).
function Traffic.update(Core, now, v, plan)
	if not Traffic.settings.enabled then
		for _, car in pairs(Traffic.cars) do remove(Core, car, "off") end
		return
	end
	for _, car in pairs(Traffic.cars) do step(Core, car, v) end
	local want = Traffic.settings.cars or 0
	if Traffic.count >= want then return end
	-- who might drive past: the locals in a fixed order for this half hour,
	-- worked out again only when V has moved on or the half hour changes
	local half = math.floor(now.seconds / 1800)
	local o = Traffic.order
	if o == nil or o.half ~= half or dist(o.at, v) > 150 or os.clock() - o.made > 30 then
		local ids = Population.locals(v.x, v.y, Traffic.reach)
		local key = {}
		for _, id in ipairs(ids) do key[id] = Core.Rng.new("ponc", "drive", id, half):next() end
		table.sort(ids, function(a, b) return key[a] < key[b] end)
		o = { half = half, at = { x = v.x, y = v.y }, made = os.clock(), ids = ids, next = 1 }
		Traffic.order = o
	end
	-- a slice of them each pass, round and round
	local looked, started, n = 0, 0, #o.ids
	while looked < math.min(60, n) do
		if Traffic.count >= want or started >= 2 then break end
		local id = o.ids[o.next]
		o.next = o.next % n + 1
		looked = looked + 1
		if Traffic.cars[id] == nil and not (Traffic.busy and Traffic.busy(id)) then
			local c = plan(id)
			local driving = Traffic.driving(Core, id, c, now.seconds)
			if driving then tally("drivers seen") end
			if driving and Traffic.driven[id] ~= c.leave then
				local p = Core.people.get(id)
				local model = p and p.status == "alive" and Traffic.carOf(Core, p)
				if model then start(Core, id, c, v, model) started = started + 1 end
			end
		end
	end
end

function Traffic.clear(Core)
	for _, car in pairs(Traffic.cars) do remove(Core, car, "cleared") end
	Traffic.driven = {}
	Traffic.order = nil
end

return Traffic
