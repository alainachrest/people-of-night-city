-- The game's own people: civilians the game puts in the world (the crowd, and
-- people standing, sitting and leaning about) are removed near V, so the only
-- people in Night City's streets are ours. The game's walking crowd is also
-- turned off at the start (engine/config/platform/pc/people_of_night_city.ini).
--
-- Kept: our own people, anyone in a quest, vendors, police, gangs and anyone
-- else who isn't a civilian, companions, NPCs other mods spawned, and anyone
-- in combat.

local World = require("modules/world")

local Crowd = {
	settings = { replace = true },
	radius = 150,
	every = 2.0,
	timer = 0,
	removed = 0,
	kept = {},     -- entity hash -> why it was kept (for the window)
}

local function hash(ent)
	-- as a string: the game's 64-bit ids don't make the same table key twice
	local ok, h = pcall(function() return tostring(ent:GetEntityID().hash) end)
	return ok and h or nil
end

local function yes(fn)
	local ok, r = pcall(fn)
	return ok and r == true
end

-- Why an NPC of the game's should stay, or nil if it should go.
function Crowd.keep(npc, ours)
	local h = hash(npc)
	if h == nil then return "unknown" end
	if ours[h] then return "ours" end
	if yes(function() return npc:IsDead() end) then return "dead" end
	if yes(function() return Game.GetDynamicEntitySystem():IsManaged(npc:GetEntityID()) end) then return "spawned by a mod" end
	if yes(function() return npc:IsQuest() end) then return "quest" end
	if yes(function() return npc:IsVendor() end) then return "vendor" end
	if yes(function() return npc.isPlayerCompanionCached end) then return "companion" end
	if yes(function() return npc:IsPrevention() end) or yes(function() return npc:IsCharacterPolice() end) then return "police" end
	if yes(function() return npc:IsCharacterGanger() end) then return "gang" end
	if yes(function() return npc:IsInCombat() end) then return "in combat" end
	-- the crowd always goes; otherwise only civilians
	if yes(function() return npc:IsCrowd() end) then return nil end
	local civilian = yes(function() return npc:IsCharacterCivilian() end)
	if not civilian then
		local ok, faction = pcall(function()
			return TweakDBInterface.GetCharacterRecord(npc:GetRecordID()):Affiliation():GetID()
		end)
		civilian = ok and faction ~= nil and tostring(faction):find("Civilian") ~= nil
	end
	if not civilian then return "not a civilian" end
	return nil
end

-- The moment the game puts one of its NPCs in the world (which it does some
-- way off, as V comes near), it's looked at half a second later, once the
-- game has finished setting it up (so a quest NPC is known to be one), and, if it's one of the game's civilians, taken out
-- before V sees it. The sweep below is only for anyone already there.
Crowd.arrived = {}
function Crowd.now() return os.clock() end
Crowd.ours = function() return {} end   -- set by init: tostring(entity hash) -> true

function Crowd.init()
	pcall(function()
		Observe("ScriptedPuppet", "OnGameAttached", function(self)
			if Crowd.settings.replace then table.insert(Crowd.arrived, { npc = self, at = Crowd.now() }) end
		end)
	end)
end

function Crowd.frame()
	if #Crowd.arrived == 0 then return end
	local now, list, later = Crowd.now(), {}, {}
	for _, a in ipairs(Crowd.arrived) do
		if now - a.at >= 0.5 then table.insert(list, a.npc) else table.insert(later, a) end
	end
	Crowd.arrived = later
	if #list == 0 then return end
	local ours = Crowd.ours()
	for _, npc in ipairs(list) do
		local ok, isNpc = pcall(function() return npc:IsNPC() end)
		if ok and isNpc and Crowd.keep(npc, ours) == nil then
			if World.remove(npc) then Crowd.removed = Crowd.removed + 1 end
		end
	end
end

-- One sweep near V. `ours`: tostring(entity hash) -> true for the people this mod spawned.
function Crowd.update(dt, ours)
	if not Crowd.settings.replace then return end
	Crowd.timer = Crowd.timer + dt
	if Crowd.timer < Crowd.every then return end
	Crowd.timer = 0
	Crowd.kept = {}
	for _, npc in ipairs(World.npcsNear(Crowd.radius)) do
		local why = Crowd.keep(npc, ours)
		if why == nil then
			if World.remove(npc) then Crowd.removed = Crowd.removed + 1 end
		else
			Crowd.kept[why] = (Crowd.kept[why] or 0) + 1
		end
	end
end

return Crowd
