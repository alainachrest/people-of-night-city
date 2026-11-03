-- The homes and workplaces of Night City: every outside door in the game's own
-- world data (data/places.lua, built by tools/build_places.py). A door that
-- never opens is a building with no interior: people reach it and go in out of
-- sight. A working door may lead somewhere V can go: if there's navmesh on both
-- sides of it, people walk in and are seen inside.
--
-- Places are registered with the shared core (Core.places) when they're first
-- needed, so every mod can see them: ids "ponc:<n>".

local Places = { list = {}, grid = {}, cell = 64, registered = {}, interiors = {} }

local USES = { home = "apartment", work = "workplace" }
local DISTRICT_NAMES = {
	watson = "Watson", westbrook = "Westbrook", citycenter = "City Center", heywood = "Heywood",
	santodomingo = "Santo Domingo", pacifica = "Pacifica", badlands = "Badlands",
}

local function key(cx, cy) return cx .. ":" .. cy end

function Places.load()
	if #Places.list > 0 then return #Places.list end
	local ok, rows = pcall(require, "data/places")
	if not ok or type(rows) ~= "table" then return 0 end
	for n, r in ipairs(rows) do
		local p = { id = "ponc:" .. n, n = n, x = r[1], y = r[2], z = r[3], yaw = r[4], use = r[5], door = r[6], district = r[7] }
		Places.list[n] = p
		local k = key(math.floor(p.x / Places.cell), math.floor(p.y / Places.cell))
		Places.grid[k] = Places.grid[k] or {}
		table.insert(Places.grid[k], p)
	end
	return #Places.list
end

function Places.get(id)
	local n = tonumber(tostring(id):match("^ponc:(%d+)$"))
	return n and Places.list[n] or nil
end

function Places.dist(a, x, y)
	local dx, dy = a.x - x, a.y - y
	return math.sqrt(dx * dx + dy * dy)
end

-- Places within r metres of (x, y), optionally only one use ("home"/"work").
function Places.near(x, y, r, use)
	local out = {}
	local c = Places.cell
	for cx = math.floor((x - r) / c), math.floor((x + r) / c) do
		for cy = math.floor((y - r) / c), math.floor((y + r) / c) do
			for _, p in ipairs(Places.grid[key(cx, cy)] or {}) do
				if (use == nil or p.use == use) and Places.dist(p, x, y) <= r then table.insert(out, p) end
			end
		end
	end
	return out
end

function Places.name(p)
	if p.id == "street" then return "the street" end
	local d = DISTRICT_NAMES[p.district] or p.district or "Night City"
	if p.use == "home" then return "Apartments, " .. d end
	if p.door == "shutter" then return "Shop, " .. d end
	return "Business, " .. d
end

-- Registers a place with the shared core (once).
function Places.register(Core, p)
	if Places.registered[p.id] then return end
	Places.registered[p.id] = true
	if Core == nil or Core.places == nil then return end
	if Core.places.get(p.id) then return end
	Core.places.register({
		id = p.id, name = Places.name(p), kind = (p.door == "shutter" and "shop") or USES[p.use] or p.use,
		district = p.district, pos = { x = p.x, y = p.y, z = p.z },
		tags = { "people-of-night-city", p.door },
	})
end

-- The way in: two points 3 m either side of the door. Which side is outside
-- isn't in the data, so it's worked out from where people come from.
function Places.sides(p)
	local a = math.rad(p.yaw or 0)
	local fx, fy = math.cos(a), math.sin(a)
	return { x = p.x + fx * 3, y = p.y + fy * 3, z = p.z }, { x = p.x - fx * 3, y = p.y - fy * 3, z = p.z },
		{ x = p.x + fy * 3, y = p.y - fx * 3, z = p.z }, { x = p.x - fy * 3, y = p.y + fx * 3, z = p.z }
end

-- A spot inside a place that has an interior (navmesh beyond its door), seen from
-- `from` (the side people come from), or nil. Remembered per place.
function Places.inside(World, p, from)
	if p.door == "decorative" then return nil end
	local cached = Places.interiors[p.id]
	if cached ~= nil then return cached or nil end
	local best
	local s = { Places.sides(p) }
	for i = 1, 4, 2 do
		local a, b = s[i], s[i + 1]
		local onA = World.onNavmesh(a.x, a.y, a.z, 1.0)
		local onB = World.onNavmesh(b.x, b.y, b.z, 1.0)
		if onA == nil or onB == nil then return nil end -- can't tell yet
		if onA and onB then
			-- navmesh both sides: the inside is the side away from where people came from
			local da = from and math.abs(a.x - from.x) + math.abs(a.y - from.y) or 0
			local db = from and math.abs(b.x - from.x) + math.abs(b.y - from.y) or 1
			best = da > db and a or b
			-- as far in as the navmesh goes (up to 9 m), so they're properly inside
			local dx, dy = (best.x - p.x) / 3, (best.y - p.y) / 3
			for _, d in ipairs({ 9, 6 }) do
				local q = { x = p.x + dx * d, y = p.y + dy * d, z = p.z }
				if World.onNavmesh(q.x, q.y, q.z, 1.0) then best = q break end
			end
			break
		end
	end
	Places.interiors[p.id] = best or false
	return best
end

return Places
