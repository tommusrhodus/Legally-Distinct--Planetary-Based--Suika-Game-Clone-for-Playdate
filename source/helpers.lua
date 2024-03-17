-- This function relies on the use of timers, so the timer core library
-- must be imported, and updateTimers() must be called in the update loop
function screenShake(shakeTime, shakeMagnitude)
	-- Creating a value timer that goes from shakeMagnitude to 0, over
	-- the course of 'shakeTime' milliseconds
	local shakeTimer = playdate.timer.new(shakeTime, shakeMagnitude, 0)
	-- Every frame when the timer is active, we shake the screen
	shakeTimer.updateCallback = function(thisTimer)
		-- Using the timer value, so the shaking magnitude
		-- gradually decreases over time
		local magnitude = math.floor(thisTimer.value)
		local shakeX = math.random(-magnitude, magnitude)
		local shakeY = math.random(-magnitude, magnitude)
		playdate.display.setOffset(shakeX, shakeY)
	end
	-- Resetting the display offset at the end of the screen shake
	shakeTimer.timerEndedCallback = function()
		playdate.display.setOffset(0, 0)
	end
end

-- This function is used to round a number to the nearest integer.
function round(num)
	return math.floor(num + 0.5)
end
