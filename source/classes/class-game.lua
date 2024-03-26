class('Game').extends()

local pd <const> = playdate
local gfx <const> = pd.graphics
local disp <const> = pd.display
local vec2 <const> = pd.geometry.vector2D.new
local snd <const> = pd.sound

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

	self.ticks = 0

	-- Create walls to hold the ball in the screen.
	local sw, sh = disp.getSize()
	Wall(0, sh / 2, 160, sh / 2):add()   -- left
	Wall(sw + 10, sh / 2, 10, sh / 2):add() -- right
	Wall(sw / 2, sh + 10, sw / 2, 10):add() -- bottom

	self.positionTimer = pd.frameTimer.new(26, 0, 15, playdate.easingFunctions.outElastic)
	self.positionTimer.discardOnCompletion = false

	self.playerPosition = vec2(280, 15)
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

	-- Typography.
	self.font = gfx.font.new("assets/fonts/font-full-circle")

	self:setupSystemMenu()

	self.killZone = 40
	self.gameOverModal = nil

	self.shareScoreQR = nil
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

function Game:setGuiImage()
	if nil == self.guiImage then
		local image = self:getGuiImage()
		self.guiImage = gfx.sprite.new(image)
		self.guiImage:setUpdatesEnabled(false)
		self.guiImage:moveTo(0, 0)
		self.guiImage:setCenter(0, 0)
	else
		self.guiImage:setImage(self:getGuiImage())
	end
end

function Game:getGuiImage()
	local gui = gfx.image.new(400, 240)
	local space = gfx.image.new("assets/images/space.png")
	local guibg = gfx.image.new("assets/images/gui.png")

	gfx.pushContext(gui)

	guibg:draw(0, 0)

	gfx.setImageDrawMode("fillWhite")
	self.font:drawTextAligned("NEXT PLANET", 80, 107, kTextAlignment.center)
	gfx.setImageDrawMode("copy")

	-- Draw the score.
	gfx.setImageDrawMode("fillWhite")
	self.font:drawTextAligned("SCORE\n" .. self.totalScore, 80, 200, kTextAlignment.center)

	self.font:drawTextAligned("COMBO\n" .. self.combo, 80, 155, kTextAlignment.center)
	gfx.setImageDrawMode("copy")

	-- Draw the space background.
	space:draw(160, 0)

	-- Draw the next ball at the top of the screen.
	gfx.setColor(gfx.kColorWhite)
	gfx.setDitherPattern(0.95)
	gfx.fillCircleAtPoint(80, 60, 42)
	Ball:getImage(self.nextBall.radius, self.nextBall.level):drawCentered(80, 60)

	-- Draw exclusion zone at top of play area.
	gfx.fillRect(160, 0, 240, self.killZone)
	gfx.setDitherPattern(0)

	-- Draw divider line.
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(160, 0, 2, 240)

	gfx.popContext()
	return gui
end

function Game:getBall()
	self.positionTimer:reset()
	self.positionTimer.delay = 10

	local level = math.random(1, 5)

	self.positionTimer.startValue = self.ballValues[level].radius * -1
	return self.ballValues[level]
end

function Game:dropBall()
	if false == self.didCombo then
		self.combo = 0
	end

	self.didCombo = false

	Ball(self.playerPosition, self.currentBall):add()

	self.currentBall = self.nextBall
	self.nextBall = self:getBall()
	self.currentBallImage = Ball:getImage(self.currentBall.radius, self.currentBall.level)
	self:setGuiImage()
end

function Game:fixPlayerBounds()
	-- Don't let the player go off the screen.
	if self.playerPosition.x > 400 - (self.currentBall.radius) then
		self.playerPosition.x = 400 - (self.currentBall.radius)
	end

	-- Don't let the player go off the screen.
	if self.playerPosition.x < 160 + (self.currentBall.radius) then
		self.playerPosition.x = 160 + (self.currentBall.radius)
	end
end

function Game:gameOver(restart)
	-- get all sprites and remove them.
	gfx.sprite.performOnAllSprites(function(sprite)
		sprite:setUpdatesEnabled(false)

		if nil == sprite.killer or not sprite.killer then
			sprite:setStencilPattern({ 0xff, 0x00, 0x00, 0xff, 0x00, 0x00, 0xff, 0x00 })
		end
	end)

	if restart then
		-- get all sprites and remove them.
		gfx.sprite.performOnAllSprites(function(sprite)
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

	gfx.sprite.performOnAllSprites(function(sprite)
		sprite:setUpdatesEnabled(false)
	end)

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

function Game:draw()
	if nil == self.currentBallImage then
		self.currentBallImage = Ball:getImage(self.currentBall.radius, self.currentBall.level)
	end

	-- Draw the current ball at the player position.
	self.currentBallImage:draw(
		self.playerPosition.x - self.currentBall.radius,
		self.positionTimer.value - self.currentBall.radius
	)

	gfx.setColor(gfx.kColorWhite)
	gfx.setDitherPattern(0.8, gfx.image.kDitherTypeHorizontalLine)
	gfx.drawLine(self.playerPosition.x, self.killZone, self.playerPosition.x, 240)
	gfx.setDitherPattern(0)
end

function Game:update()
	self.ticks += 1

	if nil ~= self.gameOverModal then
		self.gameOverModal:update()

		if not self.gameOverModal:isVisible() then
			gfx.setImageDrawMode("fillWhite")
			self.font:drawTextAligned('LOADING...', 200, 120, kTextAlignment.center)
			gfx.setImageDrawMode("copy")
		end

		return
	end

	-- Crank input.
	if not pd.isCrankDocked() then
		local _, acceleratedChange = pd.getCrankChange()
		self.playerPosition.x += acceleratedChange

		self:fixPlayerBounds()
	end

	-- Move the player with arrow keys.
	if pd.buttonIsPressed("Left") then
		self.playerPosition.x -= 3
		self:fixPlayerBounds()
	end

	if pd.buttonIsPressed("Right") then
		self.playerPosition.x += 3
		self:fixPlayerBounds()
	end

	-- Drop a ball.
	if pd.buttonJustPressed("A") or pd.buttonJustPressed("Down") or pd.buttonJustPressed("B") then
		if self.positionTimer.value == self.positionTimer.endValue then
			self:dropBall()
		end
	end

	self:draw()

	if pd.isSimulator then
		playdate.drawFPS(0, 0)
	end

	-- Update balls.
	gfx.sprite.performOnAllSprites(function(sprite)
		-- Only run this on balls.
		if sprite.className ~= "Ball" then
			return
		end

		-- Update ball groups alternately.
		if sprite.group == self.ticks then
			sprite:update()
			return
		end

		-- Update the active ball every frame.
		if sprite.activeBall then
			sprite:update()
		end
	end)

	if self.ticks == 3 then
		self.ticks = 0
	end
end
