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
local navmeshEverywhere = true
local inHand = {}  -- npc id -> what they carry
local given = 0
local system = {
	WalkNPC = function(_, id, x, y, z, run) if npcs[id] then table.insert(walks, { id = id, x = x, y = y, run = run }) npcs[id].target = { x = x, y = y, z = z } return true end return false end,
	MoveState = function(_, id) local n = npcs[id] if n and n.target and math.abs(n.pos.x - n.target.x) + math.abs(n.pos.y - n.target.y) < 0.5 then return 5 end return 2 end,
	Forget = function() end,
	SetScannerName = function(_, id, name) if npcs[id] then npcs[id].scanName = name end end,
	NavPoint = function(_, x, y, z) return { x = x, y = y, z = z, w = 1 } end,
	OnNavmesh = function() return navmeshEverywhere end,
	GiveCarryItem = function(_, id, pick) if npcs[id] and pick % 10 < 8 then inHand[id] = "Items.locomotion_crowd_cellphone" given = given + 1 return inHand[id] end return "" end,
}
function GetSingleton() return { GetSystemRequestsHandler = function() return { IsPreGame = function() return false end } end } end
local mounted, drives = {}, 0
function NewObject(cls) local o = { cls = cls } function o:Copy() return self end return o end
MountEventData = { new = function() return {} end }
VehicleComponent = { HasActiveDriver = function(_, id) return mounted[id] ~= nil end,
	IsMountedToVehicle = function(_, npc) for _, who in pairs(mounted) do if who == npc.id then return true end end return false end }
Vector4.Vector4To3 = function(v) return v end
local devices, playing, observers, assembleQueue = {}, {}, {}, {}
TweakDBID = { new = function(s) return s end }
function Observe(cls, fn, cb) observers[cls .. "." .. fn] = cb end
ResRef = { FromString = function(p) return p end }
Vector3 = { new = function() return {} end }
gameWorkspotSlidingBehaviour = { PlayAtResourcePosition = 0 }
StaticEntitySpec = { new = function() return {} end }
Game = {
	GetPlayer = function() return { GetWorldPosition = function() return V end, IsAttached = function() return true end, GetGame = function() return {} end } end,
	GetSystemRequestsHandler = function() return { IsGameInMenu = function() return false end, IsGamePaused = function() return gamePaused == true end } end,
	GetScriptableSystemsContainer = function() return { Get = function() return system end } end,
	["TSQ_NPC;"] = function() return {} end,
	GetMountingFacility = function() return { Mount = function(_, req) mounted[req.lowLevelMountingInfo.parentId] = req.lowLevelMountingInfo.childId end } end,
	GetTransactionSystem = function() return {
		GetItemInSlot = function(_, npc, slot) local it = inHand[npc.id] if it and slot == "AttachmentSlots.WeaponRight" then return { GetItemID = function() return it end } end end,
		RemoveItemFromSlot = function(_, npc, slot) inHand[npc.id] = nil return true end,
		AddItemToSlot = function(_, npc, slot, item) inHand[npc.id] = item return true end } end,
	GetTargetingSystem = function() return { GetTargetParts = function() return false, nil end } end,
	GetStaticEntitySystem = function() return {
		SpawnEntity = function(_, spec) nextId = nextId + 1 local id = { hash = nextId }
			local comp = {}
			devices[id] = { spec = spec, comp = comp }
			npcs[id] = { pos = { x = spec.position.x, y = spec.position.y, z = spec.position.z }, device = true }
			-- assembled a moment later, as in the game
			table.insert(assembleQueue, function()
				local cb = observers["EntityBuilder.OnAssemble"]
				if cb then cb(nil, { GetEntity = function() return { GetEntityID = function() return id end,
					FindComponentByName = function() return comp end } end }) end
			end)
			return id end,
		DespawnEntity = function(_, id) devices[id] = nil npcs[id] = nil end } end,
	GetWorkspotSystem = function() return {
		PlayInDeviceSimple = function(_, dev, npc) playing[npc.id] = dev.id end,
		IsActorInWorkspot = function(_, npc) return playing[npc.id] ~= nil end,
		SendFastExitSignal = function(_, npc) playing[npc.id] = nil end } end,
	GetDynamicEntitySystem = function() return {
		CreateEntity = function(_, spec) nextId = nextId + 1 local id = { hash = nextId }
			npcs[id] = { spec = spec, pos = { x = spec.position.x, y = spec.position.y, z = spec.position.z } } return id end,
		DeleteEntity = function(_, id) npcs[id] = nil end } end,
	FindEntityByID = function(id)
		local n = npcs[id]
		if n == nil then return nil end
		return { id = id, GetWorldPosition = function() return n.pos end, IsDead = function() return n.dead == true end,
			IsDefeated = function() return false end,
			GetAIControllerComponent = function() return { SendCommand = function(_, cmd) if cmd.cls == "AIUnmountCommand" then mounted[cmd.mountData.mountParentEntityId] = nil else mounted[cmd.mountData.mountParentEntityId] = id end end } end,
			QueueEvent = function(_, ev) drives = drives + 1 n.target = ev.command.targetPosition end,
			GetCurrentAppearanceName = function() return { value = "appearance_" .. id.hash } end }
	end,
	GetNavigationSystem = function() return {
		IsPointOnNavmesh = function(_, p) return navmeshEverywhere end,
		FindPointInSphere = function(_, p) return { status = "OK", point = p } end } end,
	NameToString = function(n) return n.value end,
}

if os.getenv("PROF") then dofile(os.getenv("PROF")) end -- PROFILE_HOOK
assert(loadfile(modroot .. "/init.lua"))()
events.onInit()
-- (a save is loaded in the core stub; give the core a moment, like the game does)
local simt = 0
local frames, slowest, slowFrames = 0, 0, 0
local function tick(sec)
	for _ = 1, sec * 10 do
		simt = simt + 0.1
		local q = assembleQueue assembleQueue = {}
		for _, f in ipairs(q) do f() end
		Core.update(0.1)
		local t0 = os.clock()
		events.onUpdate(0.1)
		local ft = os.clock() - t0
		frames = frames + 1
		if ft > slowest then slowest = ft end
		if ft > 0.008 then slowFrames = slowFrames + 1 end
	end
end
-- every NPC walking arrives at once (moves straight to its target)
local function arrive() for _, n in pairs(npcs) do if n.target then n.pos = { x = n.target.x, y = n.target.y, z = n.target.z } end end end

local Places = require("modules/places")
local Population = require("modules/population")
local Life = require("modules/life")
Life.now = function() return simt end
require("modules/budget").ms = os.getenv("BUDGET_MS") and tonumber(os.getenv("BUDGET_MS")) or 100000
require("modules/crowd").now = function() return simt end
local World = require("modules/world")
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
	if p and p.place and p.place ~= p.home and p.job ~= "unemployed" and p.job ~= "child" then worker = p break end
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
local kids, kidsPaid = 0, 0
for id in pairs(Population.known) do
	local p = Core.people.get(id)
	if p.lifestyle == "child" or p.lifestyle == "child_rich" then
		kids = kids + 1
		if p.age >= 16 or (p.wage or 0) > 0 or p.employed ~= false or p.look.record:find("Child") == nil then kidsPaid = kidsPaid + 1 end
	end
end
print("children", kids)
check("families have children (under 16, no job or wage, child bodies)", kids > 0 and kidsPaid == 0)
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
do
	local using, kinds2, sat = 0, {}, 0
	for _ in pairs(playing) do using = using + 1 end
	print("using spots now", using, "spots in use", (function() local n = 0 for _ in pairs(require("modules/spots").taken) do n = n + 1 end return n end)())
	check("people sit, lean and use things at the game's spots", Life.usedSpots > 0)
	local sittingWithItem = 0
	for npc in pairs(playing) do if inHand[npc] then sittingWithItem = sittingWithItem + 1 end end
	check("people carry things (phone, bag, can... umbrella in the rain)", given > 0)
	check("nobody sits or leans with something in hand", using > 0 and sittingWithItem == 0)
	check("each spot's workspot is set on its device", (function() for _, d in pairs(devices) do return d.comp.workspotResource ~= nil end return true end)())
end

-- traffic: our people driving where they're going, busier at rush hour than at night
do
	local Traffic = require("modules/traffic")
	local function carsAt(hour)
		Traffic.clear(Core)
		local most = 0
		for m = 0, 50, 5 do
			clock = 3600 * 24 * 16 + 3600 * hour + m * 60
			tick(4)
			most = math.max(most, Traffic.count)
		end
		return most
	end
	local rush = carsAt(8)
	local driving, owner = false, nil
	for id, car in pairs(Traffic.cars) do
		owner = id
		if car.stage == "driving" or car.stage == "parked" then driving = true end
	end
	check("each car has its owner at the wheel, driving", driving and next(mounted) ~= nil and drives > 0)
	local night = carsAt(3)
	print("cars at 08:00", rush, "at 03:00", night)
	check("people drive past V, more at rush hour than at night", rush > 0 and rush > night)
	local p = owner and Core.people.get(owner)
	check("a person drives the same car every time", p == nil or Traffic.carOf(Core, p) == Traffic.carOf(Core, p))
	Traffic.clear(Core)
end
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
	clock = 3600 * 24 * 15 + 3600 * h -- a Tuesday (day 12 is a Saturday: no work)
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

-- paused: nothing happens at all (no spawning, removing or walk orders)
do
	local function snapshot() local n = 0 for _ in pairs(npcs) do n = n + 1 end return n, #walks end
	local n0, w0 = snapshot()
	gamePaused = true
	clock = clock + 3600
	tick(5)
	local n1, w1 = snapshot()
	gamePaused = false
	check("nothing happens while the game is paused", n0 == n1 and w0 == w1)
end

-- off: everyone goes
Life.settings.enabled = false
tick(3.5) -- (after a pause the mod waits 2 s before carrying on)
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

-- the game's own people near V
do
	local Crowd = require("modules/crowd")
	local function npc(h, t)
		t = t or {}
		return { GetEntityID = function() return { hash = h } end, IsNPC = function() return true end,
			IsDead = function() return false end, IsQuest = function() return t.quest == true end,
			IsCrowd = function() return t.crowd == true end, IsCharacterCivilian = function() return t.civ == true end,
			IsCharacterGanger = function() return t.gang == true end, IsCharacterPolice = function() return false end,
			IsPrevention = function() return false end, IsInCombat = function() return false end,
			IsVendor = function() return t.vendor == true end, GetRecordID = function() return "x" end,
			Dispose = function() t.gone = true end, t = t }
	end
	local list = { npc(1, { crowd = true, civ = true }), npc(2, { civ = true }), npc(3, { civ = true, quest = true }),
		npc(4, { gang = true }), npc(5, { civ = true, vendor = true }), npc(6, { civ = true }) }
	World.npcsNear = function() return list end
	TweakDBInterface = { GetCharacterRecord = function() return { Affiliation = function() return { GetID = function() return "Factions.Gang" end } end } end }
	Crowd.timer = 99
	Crowd.update(0, { [tostring(6)] = true })
	local w = list
	check("the game's crowd and civilians near V are removed", w[1].t.gone and w[2].t.gone)
	-- as the game puts its NPCs in the world: gone half a second later, before V is near
	local cb = observers["ScriptedPuppet.OnGameAttached"]
	local fresh, questy = npc(7, { civ = true }), npc(8, { civ = true, quest = true })
	if cb then cb(fresh) cb(questy) end
	tick(1)
	check("the game's civilians are taken out as they appear", cb ~= nil and fresh.t.gone == true and not questy.t.gone)
	check("quest people, gangs, vendors and ours are kept", not w[3].t.gone and not w[4].t.gone and not w[5].t.gone and not w[6].t.gone)
end

print(string.format("people %d, homes %d", Population.count, (function() local n = 0 for _ in pairs(Population.homes) do n = n + 1 end return n end)()))
if PROFILE then for k, v in pairs(PROFILE) do print(string.format("PROF %-26s calls %5d  avg %6.2f ms  max %7.2f ms", k, v.n, v.t / v.n * 1000, v.max * 1000)) end end
if GAPS then local l = {} for k, v in pairs(GAPS) do l[#l + 1] = { k, v } end table.sort(l, function(a, b) return a[2] > b[2] end) for i = 1, math.min(8, #l) do print(string.format("GAP %.0f ms %s", l[i][2] * 1000, l[i][1])) end end
print(string.format("frames %d, slowest %.1f ms, over 8 ms: %d", frames, slowest * 1000, slowFrames))
print("passed " .. pass .. ", failed " .. fail)
