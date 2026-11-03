-- Everything People of Night City asks of the game, in one place. Every call is
-- guarded: a failed game call returns nil instead of breaking the mod.

local World = { lastError = nil }

local function try(fn)
	local ok, result = pcall(fn)
	if not ok then
		World.lastError = tostring(result)
		return nil
	end
	return result
end
World.try = try

local function system()
	return Game.GetScriptableSystemsContainer():Get("PeopleOfNightCity.PoNCSystem")
end

function World.playerPos()
	return try(function()
		local p = Game.GetPlayer():GetWorldPosition()
		return { x = p.x, y = p.y, z = p.z }
	end)
end

-- Spawns a crowd NPC from a record (optionally a set appearance). Returns its entity id.
function World.spawnNPC(record, x, y, z, yaw, appearance)
	return try(function()
		local spec = DynamicEntitySpec.new()
		spec.recordID = record
		if appearance and appearance ~= "" then spec.appearanceName = appearance end
		spec.position = Vector4.new(x, y, z, 1.0)
		spec.orientation = EulerAngles.new(0, 0, yaw or 0):ToQuat()
		spec.alwaysSpawned = true
		spec.persistState = false
		spec.persistSpawn = false
		return Game.GetDynamicEntitySystem():CreateEntity(spec)
	end)
end

function World.despawn(id)
	if id == nil then return end
	try(function() system():Forget(id) end)
	try(function() Game.GetDynamicEntitySystem():DeleteEntity(id) end)
end

-- The spawned NPC, or nil (not spawned yet, or gone).
function World.entity(id)
	if id == nil then return nil end
	return try(function() return Game.FindEntityByID(id) end)
end

function World.npcPos(id)
	return try(function()
		local e = Game.FindEntityByID(id)
		if e == nil then return nil end
		local p = e:GetWorldPosition()
		return { x = p.x, y = p.y, z = p.z }
	end)
end

-- "alive", "dead" or "down", or nil if it isn't there.
function World.npcState(id)
	return try(function()
		local e = Game.FindEntityByID(id)
		if e == nil then return nil end
		if e:IsDead() then return "dead" end
		local down = false
		pcall(function() if e:IsDefeated() then down = true end end)
		return down and "down" or "alive"
	end)
end

function World.appearance(id)
	return try(function()
		local e = Game.FindEntityByID(id)
		if e == nil then return nil end
		local name = e:GetCurrentAppearanceName()
		local s = name and (name.value or Game.NameToString(name))
		if s == nil or s == "" or s == "None" then return nil end
		return s
	end)
end

-- Walks (run: runs) a spawned NPC to a point on the navmesh. true if it took the order.
function World.walk(id, x, y, z, run)
	return try(function() return system():WalkNPC(id, x, y, z, run == true) end) == true
end

-- 0 NotExecuting, 1 Enqueued, 2 Executing, 3 Cancelled, 4 Interrupted, 5 Success, 6 Failure, -1 none
function World.moveState(id)
	return try(function() return system():MoveState(id) end) or -1
end

function World.setScannerName(id, name, faction)
	try(function() system():SetScannerName(id, name, faction or "") end)
end

-- Navmesh ------------------------------------------------------------------------

local function nav()
	return try(function() return Game.GetNavigationSystem() end)
		or try(function() return Game.NavigationSystem() end)
end

-- Is there navmesh at a point (within `tolerance` metres)?
function World.onNavmesh(x, y, z, tolerance)
	local ns = nav()
	if ns == nil then return nil end
	return try(function() return ns:IsPointOnNavmesh(Vector4.new(x, y, z, 1.0), tolerance or 0.5) end)
end

-- A point on the navmesh within `radius` of a point, or nil.
function World.navPointNear(x, y, z, radius)
	local ns = nav()
	if ns == nil then return nil end
	return try(function()
		local r = ns:FindPointInSphere(Vector4.new(x, y, z, 1.0), radius or 3.0, Enum.new("NavGenAgentSize", "Human"), false)
		if r == nil or r.point == nil then return nil end
		-- worldNavigationRequestStatus: OK (0) when a point was found
		local status = r.status
		local text = tostring(status)
		local ok = status == nil or status == 0 or text:find("OK") ~= nil or text:find("Success") ~= nil
		if not ok then return nil end
		if r.point.x == 0 and r.point.y == 0 and r.point.z == 0 then return nil end
		return { x = r.point.x, y = r.point.y, z = r.point.z }
	end)
end

return World
