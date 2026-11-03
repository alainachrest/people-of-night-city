-- Roads: where cars can drive, from the game's own vehicle navmesh (the
-- navigation sectors in the game files, tools/extract_roads.py), as points
-- about 20 m apart (data/roads.lua), kept as flat x, y, z lists per grid cell. Cars come into view on one and drive to
-- one near where their driver is going.

local Roads = { grid = {}, cell = 32, count = 0, loaded = false }

local function key(cx, cy) return cx * 100000 + cy end

function Roads.load()
	if Roads.loaded then return Roads.count end
	local ok, data = pcall(require, "data/roads")
	if not ok or type(data) ~= "table" then return 0 end
	local n = 0
	for x, y, z in (data.rows or ""):gmatch("(%S+) (%S+) (%S+)") do
		n = n + 1
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		local c = key(math.floor(x / Roads.cell), math.floor(y / Roads.cell))
		local g = Roads.grid[c]
		if g == nil then g = {} Roads.grid[c] = g end
		local k = #g
		g[k + 1], g[k + 2], g[k + 3] = x, y, z
	end
	Roads.count, Roads.loaded = n, true
	return n
end

-- The road point nearest (x, y) within r metres (and within 8 m in height of
-- z, if given), or nil.
function Roads.near(x, y, z, r)
	r = r or 25
	local best, bd = nil, r * r
	local c0, c1 = math.floor((x - r) / Roads.cell), math.floor((x + r) / Roads.cell)
	local r0, r1 = math.floor((y - r) / Roads.cell), math.floor((y + r) / Roads.cell)
	for cx = c0, c1 do
		for cy = r0, r1 do
			local g = Roads.grid[key(cx, cy)]
			if g then
				for i = 1, #g, 3 do
					local dx, dy = g[i] - x, g[i + 1] - y
					local d = dx * dx + dy * dy
					if d <= bd and (z == nil or math.abs(g[i + 2] - z) < 8) then
						best, bd = { x = g[i], y = g[i + 1], z = g[i + 2] }, d
					end
				end
			end
		end
	end
	return best
end

return Roads
