-- Who lives where: the people of each home, made by the shared core's people
-- registry (Core.people.populate) the first time V comes near. The same save
-- always gets the same people; a new save, new ones. Each working adult works
-- at one of the workplaces nearest their home (picked from the seed). Anything
-- that happens to them later (a new job, getting hurt, dying) is the core's to
-- keep, and any mod can change it.

local Places = require("modules/places")

local Population = {
	homes = {},     -- place id -> { person ids }
	byHome = {},    -- place id -> ids (same as homes)
	byWork = {},    -- place id -> ids of people who work there
	known = {},     -- person id -> true
	count = 0,
	radius = 700,   -- homes this close to V get their people
	jobRadius = 800, -- workplaces this close to a home can employ its people
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

-- The jobs people from a home can have: the workplaces nearest it ("placeId|job").
local function workplacesFor(Core, home)
	local near = Places.near(home.x, home.y, Population.jobRadius, "work")
	table.sort(near, function(a, b) return Places.dist(a, home.x, home.y) < Places.dist(b, home.x, home.y) end)
	local out = {}
	for i = 1, math.min(8, #near) do
		local w = near[i]
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
	}) or {}
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

-- Gives the homes around V their people (a few per call, so it never stalls).
function Population.around(Core, x, y, budget)
	local made = 0
	local homes = Places.near(x, y, Population.radius, "home")
	table.sort(homes, function(a, b) return Places.dist(a, x, y) < Places.dist(b, x, y) end)
	for _, h in ipairs(homes) do
		if not Population.homes[h.id] then
			Population.populate(Core, h)
			made = made + 1
			if made >= (budget or 20) then break end
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
	end
	return out
end

function Population.reset()
	Population.homes, Population.byHome, Population.byWork, Population.known, Population.count = {}, {}, {}, {}, 0
end

return Population
