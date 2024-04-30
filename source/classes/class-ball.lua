local pd <const> = playdate
local gfx <const> = pd.graphics
local geo <const> = pd.geometry
local vec2 <const> = geo.vector2D.new
local sqrt <const> = math.sqrt

class("Ball").extends(gfx.sprite)

function Ball:init(posX, posY, currentBall)
	Ball.super.init(self)

	self.value = currentBall.value
	self.level = currentBall.level
	self.position = vec2(posX, posY)
	self.velocity = vec2(0.1, 4)
	self.radius = currentBall.radius

	self:setImage(self:getImage(currentBall.radius, currentBall.level))
	self:setCollideRect(0, 0, self.radius * 2, self.radius * 2)

	self.stoodStill = false
	self.stoodStillTick = 0
	self.activeBall = true
	self.killer = nil
end

function Ball:showToast(text, duration)
	local t = pd.frameTimer.new(duration, 0, 16, pd.easingFunctions.outElastic)
	t.updateCallback = function(timer)
		if not game then
			timer:remove()
			return
		end

		gfx.setImageDrawMode("fillWhite")
		game.font:drawTextAligned(text, self.position.x, self.position.y - self.radius - t.value,
			kTextAlignment.center)
		gfx.setImageDrawMode("copy")
	end
end

function Ball:getImage(radius, level)
	if game.ballValues[level].image then
		local img = gfx.image.new(game.ballValues[level].image)
		local im = gfx.image.new(2 * radius, 2 * radius)
		gfx.pushContext(im)
		img:draw(0, 0)
		gfx.setColor(gfx.kColorWhite)
		gfx.drawCircleAtPoint(radius, radius, radius)
		gfx.popContext()
		return im
	end
end

function Ball:levelUp()
	game.didCombo = true
	game.combo += 1
	local score = (self.value * 2)
	game.totalScore += score * game.combo

	-- Update the highest combo.
	if game.combo > game.highestCombo then
		game.highestCombo = game.combo
	end

	local text = game.combo > 1 and score .. "x" .. game.combo or score
	self:showToast(text, 30)

	self:unfreeze()
	self.level += 1

	game:setGuiImage()
	game.pop:play()

	-- If we've reached the last ball, remove self.
	if self.level > #game.ballValues then
		self:remove()
		return
	end

	local ballValues = game.ballValues[self.level]
	self.value = ballValues.value
	self.radius = ballValues.radius
	self:setImage(self:getImage(self.radius, self.level))
	self:setCollideRect(0, 0, self.radius * 2, self.radius * 2)

	-- Unfreeze any balls that the levelled up ball is touching.
	local _, _, collisions, numberOfCollisions = self:checkCollisions(self.x, self.y)

	for i = 1, numberOfCollisions do
		local other = collisions[i].other

		if other.className == "Ball" then
			other:unfreeze()
		end
	end
end

function Ball:unfreeze()
	self.stoodStill = false
	self.stoodStillTick = 0
end

function Ball:freeze()
	self.stoodStill = true
	self.activeBall = false

	-- Test if we're in the kill zone, if so, end the game.
	if self.position.y < game.killZone then
		self.killer = true
		game:gameOver(false)
	end
end

-- We'll use the bump.lua based AABB collision detection that Playdate SDK provides as
-- a first pass efficient detector, then pass to SDF distances when sprites overlap
function Ball:update()
	-- Don't check for collisions if the ball is standing still.
	-- Reset this flag if the ball starts moving again.
	if self.stoodStill then
		if self.velocity:magnitude() > 1 then
			self:unfreeze()
		else
			self.velocity.y = 0.5
			return
		end
	end

	if self.velocity:magnitude() < 0.4 or (self.velocity.y < 0.1 and self.velocity.y > 0) then
		self.stoodStillTick = self.stoodStillTick + 1
		if self.stoodStillTick > 20 then
			self:freeze()
		end
	end

	local realCollisions = 0
	local _, _, collisions, numberOfCollisions = self:checkCollisions(self.x, self.y)
	local collisionBottom = false

	for i = 1, numberOfCollisions do
		local normal = nil
		local other = collisions[i].other

		if other.className == "Ball" then
			local collisionDistance = geo.distanceToPoint(
				self.position.x,
				self.position.y,
				other.position.x,
				other.position.y
			)

			if collisionDistance - other.radius <= self.radius then
				realCollisions += 1

				-- Calculate the vector from circle1 center to circle2 center
				local dx = other.position.x - self.position.x
				local dy = other.position.y - self.position.y

				normal = vec2(-dx / collisionDistance, -dy / collisionDistance)

				local selfVelocity = self.velocity - self.velocity:projectedAlong(normal) * 1.25

				if other.stoodStill and self.activeBall then
					other.velocity = -(selfVelocity)
				end

				-- Move the ball out of the collision.
				self.position:addVector(normal * (self.radius - (collisionDistance - other.radius)))

				-- Update the ball velocity.
				self.velocity = selfVelocity

				-- Handle collisions of the same value.
				if other.level == self.level then
					if self.position.y > other.position.y then
						other:remove()
						self:levelUp()
					else
						self:remove()
						other:levelUp()
					end
				end
			end
		end

		-- Was this collision on the bottom?
		if nil ~= normal and normal.y == 1 then
			collisionBottom = true
		end

		-- Remove the collision from the list.
		collisions[i] = nil
	end

	-- Add gravity.
	if not collisionBottom then
		self.velocity.y = self.velocity.y + 0.3
	end

	-- Add friction.
	self.velocity:scale(0.99)

	-- Update the ball position.
	self.position:addVector(self.velocity)

	-- Don't let the ball go out of bounds.
	if self.position.x > 400 - self.radius then
		self.velocity.x = -self.velocity.x * 0.25
		self.position.x = 400 - self.radius
		realCollisions += 1
	end

	if self.position.x < 160 + self.radius then
		self.velocity.x = -self.velocity.x * 0.25
		self.position.x = 160 + self.radius
		realCollisions += 1
	end

	if self.position.y > 240 - self.radius then
		self.velocity.y = -self.velocity.y * 0.25
		self.position.y = 240 - self.radius
		realCollisions += 1
		self.velocity.x = self.velocity.x * 0.75
	end

	-- Play a click sound.
	if realCollisions > 0 and (self.velocity.y > 0.8 or self.velocity.y < -0.8) and not game.click:isPlaying() then
		game.click:play()
	end

	-- Finally, move the actual sprite.
	self:moveTo(self.position.x, self.position.y)
end

-- to enable multi-collision resolution
function Ball:collisionResponse(other)
	return "overlap"
end
