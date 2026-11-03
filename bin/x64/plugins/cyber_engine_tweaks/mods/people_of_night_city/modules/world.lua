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

-- Spawns a vehicle from a record. Returns its entity id.
function World.spawnVehicle(record, x, y, z, yaw)
	return try(function()
		local spec = DynamicEntitySpec.new()
		spec.recordID = record
		spec.position = Vector4.new(x, y, z, 1.0)
		spec.orientation = EulerAngles.new(0, 0, yaw or 0):ToQuat()
		spec.alwaysSpawned = true
		spec.persistState = false
		spec.persistSpawn = false
		return Game.GetDynamicEntitySystem():CreateEntity(spec)
	end)
end

-- Puts an NPC in a vehicle's seat (default the driver's).
function World.mount(npcId, vehId, seat, out)
	return try(function()
		local npc, veh = Game.FindEntityByID(npcId), Game.FindEntityByID(vehId)
		if npc == nil or veh == nil then return false end
		local cmd = NewObject(out and "AIUnmountCommand" or "AIMountCommand")
		local data = MountEventData.new()
		data.mountParentEntityId = vehId
		data.isInstant = not out
		data.setEntityVisibleWhenMountFinish = true
		data.removePitchRollRotationOnDismount = false
		data.ignoreHLS = false
		data.mountEventOptions = NewObject("handle:gameMountEventOptions")
		data.mountEventOptions.silentUnmount = false
		data.mountEventOptions.entityID = vehId
		data.mountEventOptions.alive = true
		data.mountEventOptions.occupiedByNeutral = true
		data.slotName = seat or "seat_front_left"
		cmd.mountData = data
		cmd = cmd:Copy()
		npc:GetAIControllerComponent():SendCommand(cmd)
		return true
	end) == true
end

-- Gets an NPC out of a vehicle.
function World.unmount(npcId, vehId, seat)
	return World.mount(npcId, vehId, seat, true)
end

-- Is someone sitting in the vehicle's driver's seat?
function World.hasDriver(vehId)
	return try(function()
		local veh = Game.FindEntityByID(vehId)
		if veh == nil then return false end
		return VehicleComponent.HasActiveDriver(Game.GetPlayer():GetGame(), veh, vehId)
	end) == true
end

-- Has a vehicle with a driver drive itself, on the roads and with the traffic
-- rules, to a point.
function World.drive(vehId, x, y, z, minSpeed, maxSpeed)
	return try(function()
		local veh = Game.FindEntityByID(vehId)
		if veh == nil then return false end
		local cmd = NewObject("handle:AIVehicleDriveToPointAutonomousCommand")
		cmd.maxSpeed = maxSpeed or 14
		cmd.minSpeed = minSpeed or 6
		cmd.clearTrafficOnPath = false
		cmd.minimumDistanceToTarget = 4
		cmd.targetPosition = Vector4.Vector4To3(Vector4.new(x, y, z, 1))
		cmd.driveDownTheRoadIndefinitely = false
		cmd.needDriver = true
		cmd.useKinematic = true
		cmd = cmd:Copy()
		local ev = NewObject("handle:AINPCCommandEvent")
		ev.command = cmd
		veh:QueueEvent(ev)
		return true
	end) == true
end

-- A point on the roads (the vehicles' navmesh) near a point, or nil.
function World.roadPointNear(x, y, z, radius)
	return World.navPointNear(x, y, z, radius, "Vehicle")
end

-- Every NPC within r metres of V (the game's and anyone else's).
function World.npcsNear(r)
	return try(function()
		local query = Game["TSQ_NPC;"]()
		query.maxDistance = r
		local ok, parts = Game.GetTargetingSystem():GetTargetParts(Game.GetPlayer(), query)
		local out = {}
		if not ok or parts == nil then return out end
		for _, part in ipairs(parts) do
			local e = part:GetComponent(part):GetEntity()
			if e and e:IsNPC() then table.insert(out, e) end
		end
		return out
	end) or {}
end

-- Takes one of the game's NPCs out of the world.
function World.remove(npc)
	return try(function() npc:Dispose() return true end) == true
end

-- Workspots ----------------------------------------------------------------------
-- A spot is used through a workspot device (an entity with only a workspot
-- component, archive/pc/mod/PeopleOfNightCity.archive) put where the spot is,
-- given the spot's workspot resource as it's assembled.

World.DEVICE = "people_of_night_city\\workspot_device.ent"
World.assembling = {}  -- entity hash -> workspot path

-- Hooks the entity builder (once, at start): fills in our devices' workspots.
function World.init()
	pcall(function()
		Observe("EntityBuilder", "OnAssemble", function(_, event)
			local ok, ent = pcall(function() return event:GetEntity() end)
			if not ok or ent == nil then return end
			local h = tostring(ent:GetEntityID().hash)
			local path = World.assembling[h]
			if path == nil then return end
			World.assembling[h] = nil
			try(function()
				local c = ent:FindComponentByName("workspot")
				c.workspotResource = ResRef.FromString(path)
			end)
		end)
	end)
end

function World.spawnSpot(path, x, y, z, yaw)
	return try(function()
		local spec = StaticEntitySpec.new()
		spec.templatePath = World.DEVICE
		spec.position = Vector4.new(x, y, z, 1.0)
		spec.orientation = EulerAngles.new(0, 0, yaw or 0):ToQuat()
		spec.attached = true
		local id = Game.GetStaticEntitySystem():SpawnEntity(spec)
		if id then World.assembling[tostring(id.hash)] = path end
		return id
	end)
end

function World.despawnSpot(id)
	if id == nil then return end
	World.assembling[tostring(id.hash)] = nil
	try(function() Game.GetStaticEntitySystem():DespawnEntity(id) end)
end

-- Starts the spot's workspot on an NPC (it sits, leans, ...). true if started.
function World.useSpot(deviceId, npcId)
	return try(function()
		local dev, npc = Game.FindEntityByID(deviceId), Game.FindEntityByID(npcId)
		if dev == nil or npc == nil then return false end
		Game.GetWorkspotSystem():PlayInDeviceSimple(dev, npc, false, "workspot", "", "", 0,
			gameWorkspotSlidingBehaviour.PlayAtResourcePosition)
		return true
	end) == true
end

function World.inSpot(npcId)
	return try(function()
		local npc = Game.FindEntityByID(npcId)
		return npc ~= nil and Game.GetWorkspotSystem():IsActorInWorkspot(npc)
	end) == true
end

-- Gets up / stops what they were doing at the spot.
function World.leaveSpot(npcId)
	try(function()
		local npc = Game.FindEntityByID(npcId)
		if npc then Game.GetWorkspotSystem():SendFastExitSignal(npc, Vector3.new(0, 0, 0), false, false, true) end
	end)
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
function World.navPointNear(x, y, z, radius, agent)
	local ns = nav()
	if ns == nil then return nil end
	return try(function()
		local r = ns:FindPointInSphere(Vector4.new(x, y, z, 1.0), radius or 3.0, Enum.new("NavGenAgentSize", agent or "Human"), false)
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
