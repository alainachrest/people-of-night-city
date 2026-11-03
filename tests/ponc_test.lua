-- Headless test of People of Night City against the real shared core.
--   luajit tests/ponc_test.lua MODROOT CORESTUB_DIR
-- CORESTUB_DIR: a folder with core_stub.lua (the Real Netrunning test host).
local modroot, stubdir = arg[1], arg[2]
package.path = modroot .. "/?.lua;" .. stubdir .. "/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(n, c) if c then pass = pass + 1 else fail = fail + 1 print("FAIL " .. n) end end

local events = {}
function registerForEvent(n, f) events[n] = f end
function registerHotkey() end
local CORESTUB = dofile(stubdir .. "/core_stub.lua")()
local Core = CORESTUB.core
function GetMod(n) if n == "cyberscript" then return CORESTUB.mod end end
local clock = 3600 * 24 * 10 + 3600 * 8 -- day 10, 08:00
Core.host.gameSeconds = function() return clock end

-- the game, as far as the mod uses it
local V = { x = 0, y = 0, z = 0 }
local npcs, nextId = {}, 0
local walks = {}
-- what CyberScript's host reports about a spawned NPC (see sharedcore.lua)
Core.host.entityState = function(e) local n = npcs and npcs[e] if n == nil then return "gone" end return n.dead and "dead" or "alive" end
local function ent(id) return npcs[id] end
DynamicEntitySpec = { new = function() return {} end }
Vector4 = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
EulerAngles = { new = function() return { ToQuat = function() return {} end } end }
Enum = { new = function(a, b) return b end }
local system = {
	WalkNPC = function(_, id, x, y, z, run) if npcs[id] then table.insert(walks, { id = id, x = x, y = y, run = run }) npcs[id].target = { x = x, y = y, z = z } return true end return false end,
	MoveState = function(_, id) local n = npcs[id] if n and n.target and math.abs(n.pos.x - n.target.x) + math.abs(n.pos.y - n.target.y) < 0.5 then return 5 end return 2 end,
	Forget = function() end,
	SetScannerName = function(_, id, name) if npcs[id] then npcs[id].scanName = name end end,
}
function GetSingleton() return { GetSystemRequestsHandler = function() return { IsPreGame = function() return false end } end } end
local navmeshEverywhere = true
Game = {
	GetPlayer = function() return { GetWorldPosition = function() return V end, IsAttached = function() return true end } end,
	GetSystemRequestsHandler = function() return { IsGameInMenu = function() return false end } end,
	GetScriptableSystemsContainer = function() return { Get = function() return system end } end,
	GetDynamicEntitySystem = function() return {
		CreateEntity = function(_, spec) nextId = nextId + 1 local id = { hash = nextId }
			npcs[id] = { spec = spec, pos = { x = spec.position.x, y = spec.position.y, z = spec.position.z } } return id end,
		DeleteEntity = function(_, id) npcs[id] = nil end } end,
	FindEntityByID = function(id)
		local n = npcs[id]
		if n == nil then return nil end
		return { GetWorldPosition = function() return n.pos end, IsDead = function() return n.dead == true end,
			IsDefeated = function() return false end,
			GetCurrentAppearanceName = function() return { value = "appearance_" .. id.hash } end }
	end,
	GetNavigationSystem = function() return {
		IsPointOnNavmesh = function(_, p) return navmeshEverywhere end,
		FindPointInSphere = function(_, p) return { status = "OK", point = p } end } end,
	NameToString = function(n) return n.value end,
}

assert(loadfile(modroot .. "/init.lua"))()
events.onInit()
-- (a save is loaded in the core stub; give the core a moment, like the game does)
local function tick(sec) for _ = 1, sec * 10 do Core.update(0.1) events.onUpdate(0.1) end end
-- every NPC walking arrives at once (moves straight to its target)
local function arrive() for _, n in pairs(npcs) do if n.target then n.pos = { x = n.target.x, y = n.target.y, z = n.target.z } end end end

local Places = require("modules/places")
local Population = require("modules/population")
local Life = require("modules/life")
tick(1.2)
check("places loaded", #Places.list > 8000)

-- stand in the middle of a busy block of Watson
local busiest, best = nil, 0
for i = 1, #Places.list, 7 do
	local p = Places.list[i]
	if p.district == "watson" then
		local n = #Places.near(p.x, p.y, 150)
		if n > best then busiest, best = p, n end
	end
end
V = { x = busiest.x, y = busiest.y, z = busiest.z }
tick(12)
check("homes near V get their people", Population.count > 50)
check("people are in the core registry", Core.people.get(next(Population.known)) ~= nil)
local worker
for id in pairs(Population.known) do
	local p = Core.people.get(id)
	if p and p.place and p.place ~= p.home and p.job ~= "unemployed" then worker = p break end
end
check("working people get a job at a workplace nearby", worker ~= nil and Places.get(worker.place) ~= nil and Places.get(worker.place).use == "work")
check("their workplace is a core place", worker and Core.places.get(worker.place) ~= nil)
check("they have a work block in their routine", worker and (function()
	for _, b in ipairs(Core.routines.get(worker.id)) do if b.activity == "work" then return true end end
end)())

local jobless, homeless, rough = 0, 0, 0
for id in pairs(Population.known) do
	local p = Core.people.get(id)
	if p.job == "unemployed" and p.lifestyle ~= "street" then jobless = jobless + 1 end
	if Population.homeless[id] then homeless = homeless + 1 if p.employed == false and (p.wage or 0) == 0 then rough = rough + 1 end end
end
print("unemployed", jobless, "homeless", homeless)
check("some people are out of work", jobless > 0)
check("some people are homeless, with no job or wage", homeless > 0 and rough == homeless)

-- same save, same people
local before = {}
for id in pairs(Population.known) do before[id] = Core.people.get(id).name end
Population.reset()
Population.around(Core, V.x, V.y, 1000)
local same = true
for id, name in pairs(before) do local p = Core.people.get(id) if not p or p.name ~= name then same = false end end
check("the same save gets the same people", same)

-- run a day near V
local seen, kinds = 0, {}
for h = 0, 23 do
	clock = 3600 * 24 * 11 + 3600 * h
	for _ = 1, 36 do
		clock = clock + 100
		tick(1.1)
		for _, s in pairs(Life.spawned) do kinds[s.scene] = (kinds[s.scene] or 0) + 1 end
		arrive()
		tick(1.1)
	end
	seen = math.max(seen, Life.count)
end
check("people are seen near V during the day", seen > 0)
check("people leave and arrive", (kinds.leaving or 0) > 0 and (kinds.arriving or 0) > 0)
for k, n in pairs(kinds) do print("scene", k, n) end
check("never more than the limit", seen <= Life.settings.max + Life.settings.pedestrians)
check("people walk the streets past V", (kinds.passing or 0) > 0)
check("homeless people are at their spot", (kinds.rough or 0) > 0)
local named = 0
for _, n in pairs(npcs) do if n.scanName then named = named + 1 end end
check("spawned people scan as themselves", named > 0)
local looked = 0
for id in pairs(Population.known) do local p = Core.people.get(id) if p.look and p.look.appearance then looked = looked + 1 end end
check("a seen person keeps their look", looked > 0)
check("seen people are bound to their NPC", (function() for id in pairs(Life.spawned) do return Core.people.entityFor(id) ~= nil end return true end)())

do
	local st = Core.state().people
	local changed, placesKept = 0, 0
	local fields = {}
	for _, ch in pairs(st.changes) do
		changed = changed + 1
		for k in pairs(ch) do fields[k] = (fields[k] or 0) + 1 end
	end
	for k, n in pairs(fields) do print("saved field", k, n) end
	for _ in pairs(st.places) do placesKept = placesKept + 1 end
	print("saved: changed people", changed, "places kept", placesKept, "of people", Population.count)
	-- (the core's daily payday saves everyone's money: that's the core's economy, not this mod)
	local other = 0
	for _, ch in pairs(st.changes) do for k in pairs(ch) do if k ~= "money" and k ~= "broke" then other = other + 1 break end end end
	check("the save only holds what happened to people (not who they are)", placesKept == 0 and other < Population.count / 4)
end

-- buildings with no interior: people who arrive vanish into them
navmeshEverywhere = false
Places.interiors = {}
Life.clear(Core)
local vanished = false
for h = 6, 10 do
	clock = 3600 * 24 * 12 + 3600 * h
	for _ = 1, 12 do
		clock = clock + 300
		tick(1.1)
		local had = {}
		for id, s in pairs(Life.spawned) do if s.scene == "arriving" then had[id] = true end end
		arrive()
		tick(1.1)
		for id in pairs(had) do if Life.spawned[id] == nil then vanished = true end end
	end
end
check("arriving at a building with no interior, they go in out of sight", vanished)

-- off: everyone goes
Life.settings.enabled = false
tick(1.2)
check("switching off clears everyone", Life.count == 0)
Life.settings.enabled = true

-- a person who dies stays dead in the core
local id, s
for i, x in pairs(Life.spawned) do id, s = i, x break end
if s == nil then
	clock = 3600 * 24 * 13 + 3600 * 8 + 600
	tick(2.2)
	for i, x in pairs(Life.spawned) do id, s = i, x break end
end
if s then
	npcs[s.ent].dead = true
	tick(2.5)
	check("killing one of them kills the person", Core.people.get(id).status == "dead")
	local again = false
	for d = 14, 15 do
		clock = 3600 * 24 * d + 3600 * 12
		tick(2.2)
		-- (their body can still be lying there; a new NPC for them would be them coming back)
		if Life.spawned[id] and Life.spawned[id] ~= s then again = true end
	end
	check("the dead don't come back", not again)
else
	check("someone to kill", false)
end

print(string.format("people %d, homes %d", Population.count, (function() local n = 0 for _ in pairs(Population.homes) do n = n + 1 end return n end)()))
print("passed " .. pass .. ", failed " .. fail)
