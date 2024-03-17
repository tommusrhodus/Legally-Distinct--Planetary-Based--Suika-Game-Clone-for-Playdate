local pd <const> = playdate
local gfx <const> = pd.graphics
local vec2 = pd.geometry.vector2D.new

class("Ball").extends(gfx.sprite)

function Ball:init(pos, currentBall)
	Ball.super.init(self)

	self.value = currentBall.value
	self.level = currentBall.level
	self.position = pos
	self.velocity = vec2(0.1, 4)
	self.radius = currentBall.radius
	self:setImage(self:draw(currentBall.radius, currentBall.level))
	local w, h = self:getSize()
	self:setCollideRect(-2, -2, w + 4, h + 4)
	self:moveTo(self.position:unpack())
	self.f = sdCircle
	self:setUpdatesEnabled(false)

	self.stoodStill = false
	self.stoodStillTick = 0

	self.ticks = 0
	self.activeBall = true
	self.group = math.random(1, 4)

	self.killer = nil
end

function Ball:showToast(text, duration)
	local t = pd.frameTimer.new(duration, 0, 16, pd.easingFunctions.outElastic)
	t.updateCallback = function()
		if not game then
			return
		end

		gfx.setImageDrawMode("fillWhite")
		game.font:drawTextAligned(text, self.position.x, self.position.y - self.radius - t.value,
			kTextAlignment.center)
		gfx.setImageDrawMode("copy")
	end
end

function Ball:draw(radius, level)
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

function Ball:distance(p)
	return sdCircle(self.position - p, self.radius)
end

function Ball:destroy()
	self:remove()
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

	local p = ParticleCircle(self.position:unpack())
	p:setColor(gfx.kColorWhite)
	p:setSize(5, 6)
	p:setMode(Particles.modes.DECAY)
	p:setSpeed(4, 9)
	p:add(15)

	game:setGuiImage()
	game.pop:play()

	-- If we're reached the last ball, destroy self.
	if self.level > #game.ballValues then
		self:destroy()
		return
	end

	local ballValues = game.ballValues[self.level]
	self.value = ballValues.value
	self.radius = ballValues.radius
	self:setImage(self:draw(self.radius, self.level))
	local w, h = self:getSize()
	self:setCollideRect(-2, -2, w + 4, h + 4)

	-- Unfreeze any balls that the levelled up ball is touching.
	local _, _, collisions, numberOfCollisions = self:checkCollisions(self.x, self.y)

	for i = 1, numberOfCollisions do
		if collisions[i].other.className == "Ball" then
			collisions[i].other:unfreeze()
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
	self.ticks += 1

	-- Don't check for collisions if the ball is standing still.
	-- Reset this flag if the ball starts moving again.
	if self.stoodStill then
		if self.velocity:magnitude() > 1 then
			self:unfreeze()
		else
			self.velocity.y = 0.3
			return
		end
	end

	if self.velocity:magnitude() < 0.4 or math.abs(self.velocity.y) < 0.1 then
		self.stoodStillTick = self.stoodStillTick + 1
		if self.stoodStillTick > 20 then
			self:freeze()
		end
	end

	local _, _, collisions, numberOfCollisions = self:checkCollisions(self.x, self.y)
	local collisionBottom = false

	for i = 1, numberOfCollisions do
		local collisionDistance = collisions[i].other:distance(self.position)

		if collisionDistance <= self.radius then
			-- Play a click sound.
			if self.velocity:magnitude() > 0.8 and not game.click:isPlaying() then
				game.click:play()
			end

			local args = collisions[i].other.className == "Wall" and
				{ vec2(collisions[i].other.a, collisions[i].other.b) } or
				{ collisions[i].other.radius }

			local normal = calcNormalizedGradient(
				self.position,
				collisions[i].other.f,
				collisions[i].other.position,
				args
			)

			if collisions[i].other.stoodStill and self.activeBall then
				collisions[i].other.velocity = -(self.velocity - self.velocity:projectedAlong(normal) * 1.3)
			end

			-- Update the ball position.
			self.position = self.position + normal * (self.radius - collisionDistance)

			-- Update the ball velocity.
			self.velocity = (self.velocity - self.velocity:projectedAlong(normal) * 2) * 0.65

			-- Handle collisions of the same value.
			if collisions[i].other.level == self.level then
				if self.ticks > collisions[i].other.ticks then
					collisions[i].other:destroy()
					self:levelUp()
				else
					self:destroy()
					collisions[i].other:levelUp()
				end
			end

			-- Was this collision on the bottom?
			if normal.y == 1 then
				collisionBottom = true
			end

			-- Remove the collision from the list.
			collisions[i] = nil
		end
	end

	-- Add gravity.
	if not collisionBottom then
		self.velocity.y = self.velocity.y + 0.3
	end

	-- Add friction.
	self.velocity = self.velocity * 0.99

	self.position = self.position + self.velocity
	self:moveTo(self.position:unpack())

	-- Don't let the ball go out of bounds.
	if self.position.x > 400 - self.radius then
		self.position.x = 400 - self.radius
		self:moveTo(self.position:unpack())
	end

	if self.position.x < 160 + self.radius then
		self.position.x = 160 + self.radius
		self:moveTo(self.position:unpack())
	end

	if self.position.y > 245 - self.radius then
		self.position.y = 240 - self.radius
		self:moveTo(self.position:unpack())
	end
end

-- to enable multi-collision resolution
function Ball:collisionResponse(other)
	return "overlap"
end
