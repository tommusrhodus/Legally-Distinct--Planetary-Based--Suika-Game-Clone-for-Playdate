class('Game').extends()

local pd <const> = playdate
local gfx <const> = pd.graphics
local snd <const> = pd.sound
local spr <const> = gfx.sprite
local floor <const> = math.floor

-- The cursor used to move 3px per frame at 28fps.
local kButtonSpeed <const> = 3 * 28

-- How long a planet can sit above the kill line before the game ends.
local kKillTime <const> = 1.0

-- Draw order. Balls use the default of 0.
local kZKillZone <const> = -20
local kZGui <const> = -10

function Game:init(kawaii)
	-- A table to hold all the ball values.
	self.ballValues = {
		{
			name = "moon",
			value = 2,
			radius = 10,
			level = 1,
			image = kawaii and "assets/images/moon-kawaii.png" or "assets/images/moon.png",
			images = {}
		},
		{
			name = "mercury",
			value = 4,
			radius = 14,
			level = 2,
			image = kawaii and "assets/images/mercury-kawaii.png" or "assets/images/mercury.png",
			images = {}
		},
		{
			name = "mars",
			value = 8,
			radius = 16,
			level = 3,
			image = kawaii and "assets/images/mars-kawaii.png" or "assets/images/mars.png",
			images = {}
		},
		{
			name = "venus",
			value = 16,
			radius = 18,
			level = 4,
			image = kawaii and "assets/images/venus-kawaii.png" or "assets/images/venus.png",
			images = {}
		},
		{
			name = "earth",
			value = 32,
			radius = 20,
			level = 5,
			image = kawaii and "assets/images/earth-kawaii.png" or "assets/images/earth.png",
			images = {}
		},
		{
			name = "neptune",
			value = 64,
			radius = 22,
			level = 6,
			image = kawaii and "assets/images/neptune-kawaii.png" or "assets/images/neptune.png",
			images = {}
		},
		{
			name = "uranus",
			value = 128,
			radius = 26,
			level = 7,
			image = kawaii and "assets/images/uranus-kawaii.png" or "assets/images/uranus.png",
			images = {}
		},
		{
			name = "saturn",
			value = 256,
			radius = 30,
			level = 8,
			image = kawaii and "assets/images/saturn-kawaii.png" or "assets/images/saturn.png",
			images = {}
		},
		{
			name = "jupiter",
			value = 512,
			radius = 34,
			level = 9,
			image = kawaii and "assets/images/jupiter-kawaii.png" or "assets/images/jupiter.png",
			images = {}
		},
		{
			name = "sun",
			value = 1024,
			radius = 40,
			level = 10,
			image = kawaii and "assets/images/sun-kawaii.png" or "assets/images/sun.png",
			images = {}
		},
		{
			name = "blackhole",
			value = 2048,
			radius = 48,
			level = 11,
			image = kawaii and "assets/images/blackhole-kawaii.png" or "assets/images/blackhole.png",
			images = {}
		}
	}

	self:loadBallImages()

	self.killZone = 40

	local radii = {}
	for i = 1, #self.ballValues do
		radii[i] = self.ballValues[i].radius
	end

	physics.init(table.unpack(radii))
	physics.setKillLine(self.killZone, kKillTime)

	-- Balls by physics id, and balls still growing after a merge.
	self.balls = {}
	self.growing = {}

	-- Emitters from a previous game are finished; don't keep updating them.
	Particles:removeAll()

	self.positionTimer = pd.timer.new(framesToMs(26), 0, 15, playdate.easingFunctions.outElastic)
	self.positionTimer.discardOnCompletion = false

	self.playerX = 280
	self.playerY = 15
	self.nextBall = self:getBall()
	self.currentBall = self:getBall()
	self.currentBallImage = nil

	self.totalScore = 0
	self.combo = 0
	self.didCombo = false
	self.highestCombo = 0

	self.pop = snd.sampleplayer.new("assets/sounds/merge.wav")
	self.click = snd.sampleplayer.new("assets/sounds/click1.wav")
	self.boom = snd.sampleplayer.new("assets/sounds/boom.wav")

	self:setDefaultAudio()

	self.guiImage = nil
	self.killZoneImage = nil

	-- Typography.
	self.font = gfx.font.new("assets/fonts/font-full-circle")

	self:setupSystemMenu()

	self.gameOverModal = nil
	self.gameOverBackground = spr.new(gfx.image.new("assets/images/menu-bg.png"))
	self.gameOverBackground:setUpdatesEnabled(false)
	self.gameOverBackground:moveTo(0, 0)
	self.gameOverBackground:setCenter(0, 0)
	self.gameOverBackground:setZIndex(-1000)

	self.shareScoreQR = nil
	self.guideLine = self:getGuideLine()

	self.gameBg = gfx.image.new("assets/images/game-bg.png")
	self.bgOffset = self:getBackgroundOffset()

	spr.setBackgroundDrawingCallback(function()
		self.gameBg:draw(self.bgOffset, 0)
	end)
end

-- Loads each planet's art once and prepares the images used while a merged
-- planet grows from the previous size to its own.
function Game:loadBallImages()
	self.ballImages = {}

	for level = 1, #self.ballValues do
		local values = self.ballValues[level]
		values.art = gfx.image.new(values.image)

		local from = level > 1 and self.ballValues[level - 1].radius or values.radius

		for radius = from, values.radius do
			self:getBallImage(level, radius)
		end
	end
end

function Game:getBallImage(level, radius)
	local values = self.ballValues[level]
	radius = radius or values.radius

	local key = level * 256 + radius
	local image = self.ballImages[key]

	if image then
		return image
	end

	image = gfx.image.new(2 * radius, 2 * radius)
	gfx.pushContext(image)

	if radius == values.radius then
		values.art:draw(0, 0)
	else
		values.art:drawScaled(0, 0, radius / values.radius)
	end

	gfx.setColor(gfx.kColorWhite)
	gfx.drawCircleAtPoint(radius, radius, radius)
	gfx.popContext()

	self.ballImages[key] = image
	return image
end

function Game:getGuideLine()
	local image = gfx.image.new(1, 240 - self.killZone)

	gfx.pushContext(image)
	gfx.setColor(gfx.kColorWhite)
	gfx.setDitherPattern(0.8, gfx.image.kDitherTypeHorizontalLine)
	gfx.drawLine(0, 0, 0, 240 - self.killZone)
	gfx.setDitherPattern(0)
	gfx.popContext()

	return image
end

-- The background shifts with the cursor for a parallax effect.
function Game:getBackgroundOffset()
	local bgX = self.playerX - 160
	return floor(bgX * (25 - (-25)) / 240 + (-25))
end

function Game:setDefaultAudio()
	soundtrack:setVolume(0)
	self.pop:setVolume(0)
	self.click:setVolume(0)
	self.boom:setVolume(0)

	if saveData.audio == "all" then
		self.pop:setVolume(1)
		self.click:setVolume(0.25)
		self.boom:setVolume(0.75)
		soundtrack:setVolume(0.8)
	elseif saveData.audio == "music" then
		soundtrack:setVolume(1)
	elseif saveData.audio == "fx" then
		self.pop:setVolume(1)
		self.click:setVolume(0.25)
		self.boom:setVolume(0.75)
	end
end

-- Setup system menu options.
function Game:setupSystemMenu()
	local menu = pd.getSystemMenu()

	-- Add an option to quit to main menu.
	menu:addMenuItem("Quit to Menu", function()
		endGame()
	end)

	-- Add option to restart game.
	menu:addMenuItem("Restart Game", function()
		self:gameOver(true)
	end)

	-- Add a checkmark menu item to toggle the display's inverted mode.
	menu:addOptionsMenuItem("Audio", { "all", "music", "fx", "none" }, saveData.audio, function(value)
		soundtrack:setVolume(0)
		self.pop:setVolume(0)
		self.click:setVolume(0)
		self.boom:setVolume(0)

		if value == "all" then
			self.pop:setVolume(1)
			self.click:setVolume(0.25)
			self.boom:setVolume(0.75)
			soundtrack:setVolume(0.8)
		elseif value == "music" then
			soundtrack:setVolume(1)
		elseif value == "fx" then
			self.pop:setVolume(1)
			self.click:setVolume(0.25)
			self.boom:setVolume(0.75)
		end

		saveData.audio = value
		saveGameData()
	end)
end

-- The GUI is split in two so that balls moving in the play area don't have to
-- redraw a full screen overlay: the left panel with the score and next planet,
-- and the static kill zone band across the top of the play area.
function Game:setGuiImage()
	if nil == self.guiImage then
		self.guiImage = spr.new(gfx.image.new(162, 240))
		self.guiImage:setUpdatesEnabled(false)
		self.guiImage:setCenter(0, 0)
		self.guiImage:moveTo(0, 0)
		self.guiImage:setZIndex(kZGui)

		self.killZoneImage = spr.new(self:getKillZoneImage())
		self.killZoneImage:setUpdatesEnabled(false)
		self.killZoneImage:setCenter(0, 0)
		self.killZoneImage:moveTo(160, 0)
		self.killZoneImage:setZIndex(kZKillZone)
	end

	self:drawGuiImage(self.guiImage:getImage())
	self.guiImage:markDirty()
end

function Game:addGui()
	self.guiImage:add()
	self.killZoneImage:add()
end

function Game:drawGuiImage(gui)
	gui:clear(gfx.kColorClear)
	gfx.pushContext(gui)

	gfx.setImageDrawMode("fillWhite")
	self.font:drawTextAligned("NEXT PLANET", 80, 107, kTextAlignment.center)
	gfx.setImageDrawMode("copy")

	-- Draw the score.
	gfx.setImageDrawMode("fillWhite")
	self.font:drawTextAligned("SCORE\n" .. self.totalScore, 80, 200, kTextAlignment.center)

	self.font:drawTextAligned("COMBO\n" .. self.combo, 80, 155, kTextAlignment.center)
	gfx.setImageDrawMode("copy")

	-- Draw the next ball at the top of the screen.
	gfx.setColor(gfx.kColorWhite)
	gfx.setDitherPattern(0.95)
	gfx.fillCircleAtPoint(80, 60, 42)
	self:getBallImage(self.nextBall.level):drawCentered(80, 60)
	gfx.setDitherPattern(0)

	-- Draw divider line.
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(160, 0, 2, 240)

	gfx.popContext()
end

-- Exclusion zone at the top of the play area. It starts at x=160 so the dither
-- pattern lines up with the screen exactly as it did in the full screen GUI.
function Game:getKillZoneImage()
	local image = gfx.image.new(240, self.killZone)

	gfx.pushContext(image)
	gfx.setColor(gfx.kColorWhite)
	gfx.setDitherPattern(0.95)
	gfx.fillRect(0, 0, 240, self.killZone)
	gfx.setDitherPattern(0)
	gfx.popContext()

	return image
end

function Game:getBall()
	self.positionTimer:reset()
	self.positionTimer.delay = framesToMs(10)

	local level = math.random(1, 5)

	self.positionTimer.startValue = self.ballValues[level].radius * -1
	return self.ballValues[level]
end

function Game:dropBall()
	if false == self.didCombo then
		self.combo = 0
	end

	self.didCombo = false

	local ball = Ball(self.playerX, self.playerY, self.currentBall)

	-- The physics world holds far more balls than fit on screen, but don't
	-- leave an unsimulated sprite behind if it's ever full.
	if nil == ball.id then
		return
	end

	ball:add()
	self.balls[ball.id] = ball

	self.currentBall = self.nextBall
	self.nextBall = self:getBall()
	self.currentBallImage = self:getBallImage(self.currentBall.level)
	self:setGuiImage()
end

function Game:removeBall(ball)
	self.balls[ball.id] = nil
	self.growing[ball] = nil
	ball:remove()
end

-- Shows the merged planet at its physics radius while it grows.
function Game:growBall(ball)
	ball.shownRadius = nil
	self.growing[ball] = true
	self:updateGrowingBall(ball)
end

function Game:updateGrowingBall(ball)
	local radius, target = physics.radius(ball.id)

	if nil == radius then
		self.growing[ball] = nil
		return
	end

	local shown = floor(radius + 0.5)

	if shown ~= ball.shownRadius then
		ball.shownRadius = shown
		ball:setImage(self:getBallImage(ball.level, shown))
	end

	if radius >= target then
		self.growing[ball] = nil
	end
end

function Game:fixPlayerBounds()
	-- Don't let the player go off the screen.
	if self.playerX > 400 - (self.currentBall.radius) then
		self.playerX = 400 - (self.currentBall.radius)
	end

	-- Don't let the player go off the screen.
	if self.playerX < 160 + (self.currentBall.radius) then
		self.playerX = 160 + (self.currentBall.radius)
	end

	-- Redraw the background only when the parallax offset actually moves.
	local offset = self:getBackgroundOffset()

	if offset ~= self.bgOffset then
		self.bgOffset = offset
		spr.redrawBackground()
	end
end

function Game:gameOver(restart)
	-- Stop simulating. The physics world forgets the sprites, which are about to be removed.
	physics.clear()
	self.growing = {}

	-- Blank out all sprites apart from the killer.
	spr.performOnAllSprites(function(sprite)
		if sprite.killer then
			return
		end

		sprite:remove()
	end)

	self.gameOverBackground:add()

	if restart then
		-- get all sprites and remove them.
		spr.performOnAllSprites(function(sprite)
			sprite:remove()
		end)

		-- Remove custom menu items.
		pd.getSystemMenu():removeAllMenuItems()

		restartGame()
	else
		self.boom:play()
		self:showGameOverModal()
	end
end

function Game:showGameOverModal()
	if nil == self.gameOverModal then
		self.gameOverModal = Modal()
	end

	local url = "https://tomrhodes.blog/ldpbsgcfpd/?score=" .. self.totalScore .. "&combo=" .. self.highestCombo

	-- Open the modal after the QR code is generated.
	gfx.generateQRCode(url, 140, function(qr)
		local modalImage = self.gameOverModal:getImage()
		gfx.pushContext(modalImage)
		gfx.setImageDrawMode("fillWhite")
		self.font:drawTextAligned("SHARE YOUR SCORE", 85, 170, kTextAlignment.center)
		gfx.setImageDrawMode("copy")
		qr:draw(20, 30)
		gfx.popContext()

		self.gameOverModal:setImage(modalImage)
		self.gameOverModal:add()
		self.gameOverModal:setVisible(true)
	end)
end

function Game:handleEvent(kind, a, b, level, x, y)
	if kind == physics.kEventMerge then
		local survivor = self.balls[a]
		local merged = self.balls[b]

		if merged then
			self:removeBall(merged)
		end

		if survivor then
			survivor:levelUp(x, y)
		end
	elseif kind == physics.kEventGameOver then
		local killer = self.balls[a]

		if killer then
			killer.killer = true
		end

		self:gameOver(false)
	end
end

-- Input and simulation. Runs before the sprites are drawn.
function Game:update(dt)
	if nil ~= self.gameOverModal then
		return
	end

	-- Crank input.
	if not pd.isCrankDocked() then
		local _, acceleratedChange = pd.getCrankChange()

		if acceleratedChange ~= 0 then
			self.playerX += acceleratedChange
			self:fixPlayerBounds()
		end
	end

	-- Move the player with arrow keys.
	if pd.buttonIsPressed("Left") then
		self.playerX -= kButtonSpeed * dt
		self:fixPlayerBounds()
	end

	if pd.buttonIsPressed("Right") then
		self.playerX += kButtonSpeed * dt
		self:fixPlayerBounds()
	end

	-- Drop a ball.
	if pd.buttonJustPressed("A") or pd.buttonJustPressed("Down") or pd.buttonJustPressed("B") then
		if self.positionTimer.value == self.positionTimer.endValue then
			self:dropBall()
		end
	end

	local eventCount, impact = physics.update(dt)

	for i = 1, eventCount do
		self:handleEvent(physics.event(i))

		if nil ~= self.gameOverModal then
			return
		end
	end

	for ball in pairs(self.growing) do
		self:updateGrowingBall(ball)
	end

	-- Play a click sound.
	if impact and not self.click:isPlaying() then
		self.click:play()
	end
end

-- Immediate mode drawing on top of the sprites.
function Game:draw(dt)
	Particles.update(dt)

	if nil ~= self.gameOverModal then
		self.gameOverModal:update()

		if not self.gameOverModal:isVisible() then
			gfx.setImageDrawMode("fillWhite")
			self.font:drawTextAligned('GAME OVER\nLOADING HIGHSCORES...', 200, 110, kTextAlignment.center)
			gfx.setImageDrawMode("copy")
		end

		return
	end

	local radius = self.currentBall.radius
	local playerX = self.playerX

	if nil == self.currentBallImage then
		self.currentBallImage = self:getBallImage(self.currentBall.level)
	end

	-- Draw the current ball at the player position.
	self.currentBallImage:draw(
		floor(playerX - radius + 0.5),
		self.positionTimer.value - radius
	)

	self.guideLine:draw(playerX, self.killZone)
end
