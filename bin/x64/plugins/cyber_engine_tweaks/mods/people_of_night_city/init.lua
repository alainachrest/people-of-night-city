--[[
People of Night City

The people in the shared core's registry (CyberScript, API 2+) living their
lives in the world: going to work, coming home, wandering their neighbourhood.
Homes and workplaces are the outside doors of Night City's buildings, from the
game's own world data. A building with a door that never opens has no interior:
people reach it and go in out of sight. One V can walk into: they go in and are
seen there.

Doesn't touch Gangs of Night City.
]]

local PoNC = {
	version = "0.1.0",
	ready = false,
	timer = 0,
	popTimer = 0,
	overlay = false,
	status = "starting",
}

local World = require("modules/world")
local Places = require("modules/places")
local Population = require("modules/population")
local Life = require("modules/life")
local Crowd = require("modules/crowd")
local Traffic = require("modules/traffic")
local Spots = require("modules/spots")
Traffic.log = Life.note
Traffic.busy = function(id) return Life.spawned[id] ~= nil end
Traffic.handOver = function(id, ent, place) if PoNC.core then Life.adopt(PoNC.core, id, ent, place) end end

local CORE_MISSING = "People of Night City needs CyberScript with the shared core (API 2): the api-hooks-and-2.5 build of CyberScript."
local SETTINGS_FILE = "settings.txt"

local function log(text) print("[People of Night City] " .. text) end

local function core()
	if PoNC.core then return PoNC.core end
	local ok, mod = pcall(GetMod, "cyberscript")
	if not ok or mod == nil or mod.api == nil then return nil end
	if (mod.api.apiVersion or 0) < 2 or mod.api.core == nil then return nil end
	PoNC.core = mod.api.core
	return PoNC.core
end

---------------------------------------------------------------------------
-- Settings (settings.txt in this folder: key = value)
---------------------------------------------------------------------------

local function loadSettings()
	local f = io.open(SETTINGS_FILE, "r")
	if not f then return end
	for line in f:lines() do
		local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		if k == "replaceGamePeople" then Crowd.settings.replace = v == "true"
		elseif k == "traffic" then Traffic.settings.enabled = v == "true"
		elseif k == "cars" then Traffic.settings.cars = tonumber(v) or Traffic.settings.cars
		elseif k and Life.settings[k] ~= nil then
			if type(Life.settings[k]) == "boolean" then Life.settings[k] = v == "true"
			else Life.settings[k] = tonumber(v) or Life.settings[k] end
		end
	end
	f:close()
end

local function saveSettings()
	local f = io.open(SETTINGS_FILE, "w")
	if not f then return end
	for _, k in ipairs({ "enabled", "radius", "despawn", "max", "pedestrians", "useSpots" }) do
		f:write(k .. " = " .. tostring(Life.settings[k]) .. "\n")
	end
	f:write("replaceGamePeople = " .. tostring(Crowd.settings.replace) .. "\n")
	f:write("traffic = " .. tostring(Traffic.settings.enabled) .. "\n")
	f:write("cars = " .. tostring(Traffic.settings.cars) .. "\n")
	f:close()
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

-- In a loaded game (the same check CyberScript makes).
local function inGame()
	return World.try(function()
		local p = Game.GetPlayer()
		return p ~= nil and p:IsAttached() and not GetSingleton("inkMenuScenario"):GetSystemRequestsHandler():IsPreGame()
	end) == true
end

local function update(dt)
	PoNC.timer = PoNC.timer + dt
	PoNC.popTimer = PoNC.popTimer + dt
	if PoNC.timer < 1.0 then return end
	PoNC.timer = 0
	local Core = core()
	if Core == nil then PoNC.status = CORE_MISSING return end
	if Core.state() == nil then PoNC.status = "waiting for CyberScript to load the save" return end
	if not inGame() then
		PoNC.status = "waiting for the game to load" .. (World.lastError and (" (" .. World.lastError .. ")") or "")
		return
	end
	if #Places.list == 0 then
		local n = Places.load()
		log(n .. " homes and workplaces")
		log(Spots.load() .. " spots to sit, lean and do things at")
	end
	local v = World.playerPos()
	if v == nil then return end
	-- a different save: start over (the core rebuilds the same people for this one)
	if PoNC.boundTo ~= Core.state() then
		PoNC.boundTo = Core.state()
		Life.clear(Core)
		Traffic.clear(Core)
		Population.reset()
	end
	if PoNC.popTimer >= 3.0 then
		PoNC.popTimer = 0
		Population.around(Core, v.x, v.y, 25)
	end
	local now = Core.time.now()
	local ok, err = pcall(Life.update, Core, now, v)
	if not ok then
		PoNC.status = "error: " .. tostring(err)
		log(PoNC.status)
		return
	end
	local ok3, err3 = pcall(Traffic.update, Core, now, v, function(id) return Life.plan(Core, id, now) end)
	if not ok3 then log("traffic: " .. tostring(err3)) end
	local ours = {}
	for _, sp in pairs(Life.spawned) do if sp.ent and sp.ent.hash then ours[sp.ent.hash] = true end end
	for _, car in pairs(Traffic.cars) do if car.npc and car.npc.hash then ours[car.npc.hash] = true end end
	local ok2, err2 = pcall(Crowd.update, PoNC.crowdDt or 1.0, ours)
	if not ok2 then log("crowd: " .. tostring(err2)) end
	PoNC.status = "running"
	PoNC.ready = true
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function nearbyLines(Core)
	local v = World.playerPos()
	if v == nil then return {} end
	local now = Core.time.now()
	local lines = {}
	for _, id in ipairs(Population.involved(v.x, v.y, 150)) do
		local p = Core.people.get(id)
		if p then
			local w = Life.whereIs(Core, id, now.hour, now.weekday)
			local sc = Life.scene(Core, id, now, v, Life.settings.radius)
			local where = w and w.place and Places.get(w.place)
			table.insert(lines, {
				d = where and Places.dist(where, v.x, v.y) or 9999,
				text = string.format("%s (%s, %s): %s%s%s", p.name, p.job or "?", p.lifestyle or "?",
					w and w.activity or "nowhere",
					where and (" at " .. Places.name(where) .. string.format(" %dm", math.floor(Places.dist(where, v.x, v.y)))) or "",
					sc and ("  [" .. sc.kind .. (Life.spawned[id] and ", seen" or "") .. "]") or ""),
			})
		end
	end
	table.sort(lines, function(a, b) return a.d < b.d end)
	return lines
end

local function draw()
	if not PoNC.overlay then return end
	if not ImGui.Begin("People of Night City") then ImGui.End() return end
	local Core = core()
	ImGui.Text("v" .. PoNC.version .. "   " .. PoNC.status)
	ImGui.Text(string.format("Homes and workplaces: %d   Homes with people: %d   People: %d   Out and about near you: %d",
		#Places.list, (function() local n = 0 for _ in pairs(Population.homes) do n = n + 1 end return n end)(),
		Population.count, Life.count))
	local changed
	Life.settings.enabled, changed = ImGui.Checkbox("People out and about", Life.settings.enabled)
	if changed then saveSettings() end
	local r
	r, changed = ImGui.SliderInt("Seen within (m)", Life.settings.radius, 40, 200)
	if changed then Life.settings.radius = r Life.settings.despawn = r + 50 saveSettings() end
	r, changed = ImGui.SliderInt("Most at once", Life.settings.max, 4, 60)
	if changed then Life.settings.max = r saveSettings() end
	r, changed = ImGui.SliderInt("People on the streets", Life.settings.pedestrians or 0, 0, 40)
	if changed then Life.settings.pedestrians = r saveSettings() end
	Life.settings.useSpots, changed = ImGui.Checkbox("Sit, lean and use things (the game's spots)", Life.settings.useSpots)
	if changed then saveSettings() end
	Traffic.settings.enabled, changed = ImGui.Checkbox("Our people driving (traffic)", Traffic.settings.enabled)
	if changed then saveSettings() end
	r, changed = ImGui.SliderInt("Cars on the road", Traffic.settings.cars or 0, 0, 40)
	if changed then Traffic.settings.cars = r saveSettings() end
	ImGui.Text("Cars near you: " .. Traffic.count)
	Crowd.settings.replace, changed = ImGui.Checkbox("Replace the game's people with ours", Crowd.settings.replace)
	if changed then saveSettings() end
	local kept = {}
	for why, n in pairs(Crowd.kept) do table.insert(kept, why .. " " .. n) end
	table.sort(kept)
	ImGui.Text(string.format("Game NPCs removed: %d   Kept nearby: %s", Crowd.removed, #kept > 0 and table.concat(kept, ", ") or "none"))
	if ImGui.Button("Clear everyone near me") and Core then Life.clear(Core) Traffic.clear(Core) end
	if Core and Core.state() and ImGui.CollapsingHeader("People near you") then
		local lines = nearbyLines(Core)
		for i = 1, math.min(#lines, 40) do ImGui.Text(lines[i].text) end
		if #lines == 0 then ImGui.Text("Nobody lives or works near here.") end
	end
	if ImGui.CollapsingHeader("Places near you") then
		local v = World.playerPos()
		if v then
			local list = Places.near(v.x, v.y, 60)
			table.sort(list, function(a, b) return Places.dist(a, v.x, v.y) < Places.dist(b, v.x, v.y) end)
			for i = 1, math.min(#list, 20) do
				local p = list[i]
				local inside = Places.interiors[p.id]
				ImGui.Text(string.format("%s  %dm  door: %s  interior: %s  people: %d", Places.name(p),
					math.floor(Places.dist(p, v.x, v.y)), p.door,
					inside == nil and "not checked" or (inside and "yes" or "no"),
					#(Population.byHome[p.id] or {}) + #(Population.byWork[p.id] or {})))
			end
		end
	end
	if ImGui.CollapsingHeader("What just happened") then
		for i = #Life.log, math.max(1, #Life.log - 20), -1 do ImGui.Text(Life.log[i]) end
	end
	ImGui.End()
end

registerForEvent("onInit", function()
	loadSettings()
	World.init()
	log("v" .. PoNC.version .. " loaded")
end)
registerForEvent("onUpdate", function(dt) update(dt) end)
registerForEvent("onOverlayOpen", function() PoNC.overlay = true end)
registerForEvent("onOverlayClose", function() PoNC.overlay = false end)
registerForEvent("onDraw", draw)
registerForEvent("onShutdown", function()
	local Core = core()
	if Core then Life.clear(Core) Traffic.clear(Core) end
end)

-- For other mods: GetMod("people_of_night_city")
return {
	version = PoNC.version,
	places = Places,
	population = Population,
	life = Life,
}
