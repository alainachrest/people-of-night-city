-- Spreads the mod's work over frames: the once-a-second pass runs as a
-- coroutine, and its loops call Budget.check(), which hands the frame back to
-- the game once this frame's share of time (a couple of milliseconds) is used.
-- So there's no frame where the mod does everything at once (no stutter).
local Budget = { ms = 2.0, deadline = math.huge }

function Budget.start()
	Budget.deadline = os.clock() + Budget.ms / 1000
end

function Budget.check()
	if os.clock() > Budget.deadline then
		local co, main = coroutine.running()
		if co and not main then coroutine.yield() end
	end
end

return Budget
