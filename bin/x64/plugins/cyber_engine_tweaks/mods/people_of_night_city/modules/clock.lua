-- The mod's clock: real seconds, not counting time the game was paused (so
-- nothing times out all at once when the game carries on).
local Clock = { pausedFor = 0, pausedAt = nil }

function Clock.now()
	return (Clock.pausedAt or os.clock()) - Clock.pausedFor
end

function Clock.pause()
	if Clock.pausedAt == nil then Clock.pausedAt = os.clock() end
end

function Clock.resume()
	if Clock.pausedAt then
		Clock.pausedFor = Clock.pausedFor + (os.clock() - Clock.pausedAt)
		Clock.pausedAt = nil
	end
end

return Clock
