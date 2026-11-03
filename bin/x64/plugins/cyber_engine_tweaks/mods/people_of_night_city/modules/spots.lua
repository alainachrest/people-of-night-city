-- Spots: where the game's own NPCs sit, lean, smoke, drink, use things, and
-- (homeless people) sleep rough, from the game files (data/spots.lua). Our
-- people use the same spots, with the same animations (the spot's workspot).
-- One person per spot at a time.

local Spots = {
	list = {},     -- { x, y, z, yaw, path, kind, n }
	grid = {},
	cell = 32,
	paths = {},
	taken = {},    -- spot n -> person id
	bad = {},      -- workspot path .. ":" .. gender -> true (its animations don't fit them)
	loaded = false,
}

local KINDS = { s = "sit", l = "lean", i = "idle", r = "rough", w = "work" }

local function key(cx, cy) return cx * 100000 + cy end

function Spots.load()
	if Spots.loaded then return #Spots.list end
	local ok, data = pcall(require, "data/spots")
	if not ok or type(data) ~= "table" then return 0 end
	Spots.paths = data.paths or {}
	local n = 0
	for x, y, z, yaw, w, k in (data.rows or ""):gmatch("(%S+) (%S+) (%S+) (%S+) (%d+) (%a)") do
		n = n + 1
		local s = { x = tonumber(x), y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw),
			path = Spots.paths[tonumber(w)], kind = KINDS[k] or "idle", n = n }
		Spots.list[n] = s
		local c = key(math.floor(s.x / Spots.cell), math.floor(s.y / Spots.cell))
		local g = Spots.grid[c]
		if g == nil then g = {} Spots.grid[c] = g end
		g[#g + 1] = s
	end
	Spots.loaded = true
	return n
end

local function d2(s, x, y) local dx, dy = s.x - x, s.y - y return dx * dx + dy * dy end

-- Spots within r metres of (x, y) (and within 4 m in height of z, if given),
-- of the given kinds ({ sit = true, ... }), nearest first.
function Spots.near(x, y, r, kinds, z)
	local out = {}
	local c0, c1 = math.floor((x - r) / Spots.cell), math.floor((x + r) / Spots.cell)
	local r0, r1 = math.floor((y - r) / Spots.cell), math.floor((y + r) / Spots.cell)
	for cx = c0, c1 do
		for cy = r0, r1 do
			for _, s in ipairs(Spots.grid[key(cx, cy)] or {}) do
				if (kinds == nil or kinds[s.kind]) and d2(s, x, y) <= r * r and (z == nil or math.abs(s.z - z) < 4) then
					out[#out + 1] = s
				end
			end
		end
	end
	table.sort(out, function(a, b) return d2(a, x, y) < d2(b, x, y) end)
	return out
end

-- Claims a free spot for a person near (x, y): one of the nearest few, picked
-- by rng. Returns the spot or nil.
function Spots.claim(id, x, y, r, kinds, rng, gender, z, fits)
	local free = {}
	for _, s in ipairs(Spots.near(x, y, r, kinds, z)) do
		if Spots.taken[s.n] == nil and not Spots.bad[s.path .. ":" .. (gender or "")] and (fits == nil or fits(s)) then
			free[#free + 1] = s
			if #free >= 8 then break end
		end
	end
	if #free == 0 then return nil end
	local s = free[rng and rng:int(1, #free) or 1]
	Spots.taken[s.n] = id
	return s
end

function Spots.release(s, id)
	if s and Spots.taken[s.n] == id then Spots.taken[s.n] = nil end
end

-- The workspot doesn't work for this kind of body: don't use it for them again.
function Spots.misfit(s, gender)
	if s then Spots.bad[s.path .. ":" .. (gender or "")] = true end
end

function Spots.clear() Spots.taken = {} end

return Spots
