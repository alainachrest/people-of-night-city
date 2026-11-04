-- Who lives where: the people of each home, made by the shared core's people
-- registry (Core.people.populate) the first time V comes near. The same save
-- always gets the same people; a new save, new ones. Each working adult works
-- at one of the workplaces nearest their home (picked from the seed). Anything
-- that happens to them later (a new job, getting hurt, dying) is the core's to
-- keep, and any mod can change it.

local Places = require("modules/places")
local Budget = require("modules/budget")
Places.budget = Budget

local Population = {
	homes = {},     -- place id -> { person ids }
	byHome = {},    -- place id -> ids (same as homes)
	byWork = {},    -- place id -> ids of people who work there
	streets = {},   -- place id -> ids of the homeless people who sleep rough by it
	homeless = {},  -- person id -> the place they sleep rough by
	known = {},     -- person id -> true
	count = 0,
	radius = 700,   -- homes this close to V get their people
	jobRadius = 2000, -- workplaces this close to a home can employ its people
	outer = 2000,   -- then, a few at a time, homes out to here (people who work near V)
}

-- Ways of life by district (weights).
local LIFE = {
	watson       = { worker = 5, vendor = 2, young = 2, nightlife = 1, street = 1, medical = 1 },
	westbrook    = { corpo = 2, rich = 2, nightlife = 3, worker = 2, young = 1 },
	citycenter   = { corpo = 6, rich = 2, worker = 1, nightlife = 1 },
	heywood      = { worker = 4, vendor = 3, young = 2, street = 1, medical = 1 },
	santodomingo = { worker = 6, vendor = 1, young = 1, street = 1 },
	pacifica     = { street = 4, worker = 2, young = 2, nightlife = 1 },
	badlands     = { nomad = 5, worker = 1, street = 1 },
}
-- How likely someone is to be out of work, by district.
local UNEMPLOYED = {
	watson = 0.15, westbrook = 0.06, citycenter = 0.04, heywood = 0.12,
	santodomingo = 0.15, pacifica = 0.35, badlands = 0.2,
}
-- One door in this many has people sleeping rough by it (more in poor districts).
local ROUGH = { pacifica = 12, santodomingo = 25, watson = 25, heywood = 35, badlands = 30, westbrook = 80, citycenter = 120 }

local JOBS = {
	shutter = { "shopkeeper", "shop assistant", "stock clerk" },
	freight = { "warehouse worker", "loader", "forklift driver" },
	door    = { "clerk", "receptionist", "technician", "security guard", "cleaner", "manager", "cook", "bartender" },
	decorative = { "clerk", "technician", "cleaner", "office worker", "cook", "mechanic", "courier" },
}

local function pick(rng, weights)
	local total = 0
	for _, w in pairs(weights) do total = total + w end
	local r = rng:next() * total
	local names = {}
	for k in pairs(weights) do table.insert(names, k) end
	table.sort(names)
	for _, k in ipairs(names) do
		r = r - weights[k]
		if r <= 0 then return k end
	end
	return names[#names]
end

local function addTo(index, key, id)
	index[key] = index[key] or {}
	for _, v in ipairs(index[key]) do if v == id then return end end
	table.insert(index[key], id)
end

-- The jobs people from a home can have ("placeId|job"): workplaces across a
-- good part of the city (people don't all work next door), a couple close by.
local function workplacesFor(Core, home)
	local all = Places.near(home.x, home.y, Population.jobRadius, "work")
	table.sort(all, function(a, b) return a.n < b.n end)
	local close, far = {}, {}
	for _, w in ipairs(all) do
		local d = Places.dist(w, home.x, home.y)
		if d < 300 then table.insert(close, w) elseif d >= 500 then table.insert(far, w) end
	end
	local r = Core.Rng.new("ponc", "workplaces", home.id)
	local picked = {}
	for i = 1, 2 do if #close > 0 then table.insert(picked, close[r:int(1, #close)]) end end
	for i = 1, 6 do if #far > 0 then table.insert(picked, far[r:int(1, #far)]) end end
	local out = {}
	for i = 1, #picked do
		local w = picked[i]
		local titles = JOBS[w.door] or JOBS.decorative
		local r = Core.Rng.new("ponc", "title", home.id, w.id)
		table.insert(out, w.id .. "|" .. titles[r:int(1, #titles)])
	end
	return out
end

-- The people of one home (made the first time, the same ones after). They're
-- made the same way every session, so nothing about them goes in the save
-- until something happens to them.
function Population.populate(Core, home)
	if Population.homes[home.id] then return Population.homes[home.id] end
	local rng = Core.Rng.new("ponc", "home", home.id)
	local life = pick(rng, LIFE[home.district] or LIFE.watson)
	local count = rng:int(1, 4)
	Places.register(Core, home)
	local working = life ~= "street"
	local jobs = working and workplacesFor(Core, home) or {}
	local ids = Core.people.populate(home.id, {
		count = count, lifestyle = life, district = home.district, home = home.id,
		job = "unemployed", employed = working and #jobs > 0, workplaces = jobs, remember = false,
		unemployed = UNEMPLOYED[home.district] or 0.1,
	}) or {}
	-- children: about a third of families (not on the street or on the road)
	if life ~= "street" and life ~= "nomad" and rng:chance(0.35) then
		local kids = Core.people.populate(home.id .. ":kids", {
			count = rng:int(1, 2), lifestyle = life == "rich" and "child_rich" or "child", district = home.district,
			home = home.id, job = "child", employed = false, minAge = 5, maxAge = 15, gangChance = 0, remember = false,
		}) or {}
		for _, k in ipairs(kids) do table.insert(ids, k) end
	end
	Population.homes[home.id] = ids
	for _, id in ipairs(ids) do
		Population.known[id] = true
		Population.count = Population.count + 1
		addTo(Population.byHome, home.id, id)
		local p = Core.people.get(id)
		if p and p.place and p.place ~= home.id and p.employed ~= false then
			local work = Places.get(p.place)
			if work then Places.register(Core, work) end
			addTo(Population.byWork, p.place, id)
		end
	end
	return ids
end

-- People with no home, sleeping rough by a door on the street. Made the same
-- way: the same save, the same people in the same spots.
function Population.populateStreet(Core, spot)
	if Population.streets[spot.id] then return Population.streets[spot.id] end
	local rng = Core.Rng.new("ponc", "rough", spot.id)
	local ids = Core.people.populate("ponc:street:" .. spot.n, {
		count = rng:int(1, 3), lifestyle = "street", district = spot.district, home = spot.id,
		job = "unemployed", employed = false, unemployed = 1, remember = false,
	}) or {}
	Population.streets[spot.id] = ids
	for _, id in ipairs(ids) do
		Population.known[id] = true
		Population.homeless[id] = spot.id
		Population.count = Population.count + 1
	end
	return ids
end

function Population.isRoughSpot(p)
	local every = ROUGH[p.district] or 40
	return p.n % every == 0
end

-- Gives the homes around V their people (a few per call, so it never stalls).
function Population.around(Core, x, y, budget)
	local made = 0
	budget = budget or 20
	-- the homes around V first, then further out (people who work near V live
	-- all over), a few at a time, so it never stalls
	local key = math.floor(x / 200) .. ":" .. math.floor(y / 200)
	if Population.ring == nil or Population.ring.key ~= key then
		local homes = Places.near(x, y, Population.outer, "home")
		local d = {}
		for _, h in ipairs(homes) do d[h] = Places.dist(h, x, y) end
		table.sort(homes, function(a, b) return d[a] < d[b] end)
		Population.ring = { key = key, homes = homes, d = d, next = 1 }
	end
	local ring = Population.ring
	while ring.next <= #ring.homes and made < budget do
		Budget.check()
		local h = ring.homes[ring.next]
		ring.next = ring.next + 1
		if not Population.homes[h.id] then
			Population.populate(Core, h)
			made = made + 1
			-- out past V's neighbourhood: fewer at a time
			if ring.d[h] > Population.radius and made >= math.ceil(budget / 3) then break end
		end
	end
	for _, p in ipairs(Places.near(x, y, Population.radius)) do
		Budget.check()
		if Population.isRoughSpot(p) and not Population.streets[p.id] then
			Population.populateStreet(Core, p)
		end
	end
	return made
end

-- The people whose home or workplace is within r metres of (x, y).
function Population.involved(x, y, r)
	local out, seen = {}, {}
	for _, p in ipairs(Places.near(x, y, r)) do
		for _, id in ipairs(Population.byHome[p.id] or {}) do
			if not seen[id] then seen[id] = true table.insert(out, id) end
		end
		for _, id in ipairs(Population.byWork[p.id] or {}) do
			if not seen[id] then seen[id] = true table.insert(out, id) end
		end
		for _, id in ipairs(Population.streets[p.id] or {}) do
			if not seen[id] then seen[id] = true table.insert(out, id) end
		end
	end
	return out
end

-- Everyone made so far whose home (or rough-sleeping spot) is within r metres
-- of (x, y): the people who could be out and about there.
function Population.locals(x, y, r)
	local out = {}
	for i, p in ipairs(Places.near(x, y, r)) do
		if i % 100 == 0 then Budget.check() end
		for _, id in ipairs(Population.byHome[p.id] or {}) do table.insert(out, id) end
		for _, id in ipairs(Population.streets[p.id] or {}) do table.insert(out, id) end
	end
	return out
end

function Population.reset()
	Population.homes, Population.byHome, Population.byWork, Population.known, Population.count = {}, {}, {}, {}, 0
	Population.streets, Population.homeless = {}, {}
	Population.ring = nil
end

return Population
