local pd <const> = playdate
local gfx <const> = pd.graphics

-- The original game moved balls once per frame at 28fps. Its launch velocity of
-- (0.1, 4) per frame is expressed per second here.
local kDropVelocityX <const> = 0.1 * 28
local kDropVelocityY <const> = 4 * 28

class("Ball").extends(gfx.sprite)

-- Balls are simulated by the C physics world (src/physics.c), which also moves
-- this sprite every frame. The Lua side handles what a merge means for the game.
function Ball:init(x, y, currentBall)
	Ball.super.init(self)

	self.value = currentBall.value
	self.level = currentBall.level
	self.radius = currentBall.radius
	self:setImage(game:getBallImage(self.level))
	self:setUpdatesEnabled(false)
	self:moveTo(x, y)

	self.killer = nil
	self.id = physics.add(x, y, kDropVelocityX, kDropVelocityY, self.level, self)
end

function Ball:showToast(text, duration)
	local t = pd.timer.new(duration, 0, 16, pd.easingFunctions.outElastic)
	t.updateCallback = function()
		if not game then
			return
		end

		gfx.setImageDrawMode("fillWhite")
		game.font:drawTextAligned(text, self.x, self.y - self.radius - t.value,
			kTextAlignment.center)
		gfx.setImageDrawMode("copy")
	end
end

-- Called when this ball survives a merge. The physics world has already
-- removed the other ball and started growing this one.
function Ball:levelUp(x, y)
	game.didCombo = true
	game.combo += 1
	local score = (self.value * 2)
	game.totalScore += score * game.combo

	-- Update the highest combo.
	if game.combo > game.highestCombo then
		game.highestCombo = game.combo
	end

	local text = game.combo > 1 and score .. "x" .. game.combo or score
	self:showToast(text, framesToMs(30))

	self.level += 1

	local p = ParticleCircle(x, y)
	p:setColor(gfx.kColorWhite)
	p:setSize(5, 6)
	p:setMode(Particles.modes.DECAY)
	p:setSpeed(4, 9)
	p:add(15)

	game:setGuiImage()
	game.pop:play()

	-- If we're reached the last ball, destroy self.
	if self.level > #game.ballValues then
		game:removeBall(self)
		return
	end

	local ballValues = game.ballValues[self.level]
	self.value = ballValues.value
	self.radius = ballValues.radius
	game:growBall(self)
end
