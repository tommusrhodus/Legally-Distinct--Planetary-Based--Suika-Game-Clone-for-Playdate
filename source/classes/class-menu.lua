local pd <const> = playdate
local gfx <const> = pd.graphics

class('Menu').extends()

function Menu:init()
	local bgimage = gfx.image.new("assets/images/menu-bg.png")
	self.bg = gfx.sprite.new(bgimage)
	self.bg:moveTo(0, 0)
	self.bg:setCenter(0, 0)
	self.bg:setUpdatesEnabled(false)

	local suikaText = gfx.image.new("assets/images/suika.png")
	self.suikaText = gfx.sprite.new(suikaText)
	self.suikaText:moveTo(600, 120)
	self.suikaText:setUpdatesEnabled(false)

	local legalText = gfx.image.new("assets/images/legally.png")
	self.legalText = gfx.sprite.new(legalText)
	self.legalText:moveTo(600, 32)
	self.legalText:setUpdatesEnabled(false)

	local planetText = gfx.image.new("assets/images/planetary.png")
	self.planetText = gfx.sprite.new(planetText)
	self.planetText:moveTo(-200, 80)
	self.planetText:setUpdatesEnabled(false)

	local playdateText = gfx.image.new("assets/images/playdate.png")
	self.playdateText = gfx.sprite.new(playdateText)
	self.playdateText:moveTo(200, 300)
	self.playdateText:setUpdatesEnabled(false)

	self.font = gfx.font.new("assets/fonts/font-full-circle")
	self.bigFont = gfx.font.new("assets/fonts/Nontendo-Bold-2x")

	-- Animate the images in.
	local legalTimer = pd.frameTimer.new(40, 600, 200, pd.easingFunctions.outElastic)
	legalTimer.updateCallback = function()
		self.legalText:moveTo(legalTimer.value, 20)
	end

	local planetTimer = pd.frameTimer.new(40, -200, 200, pd.easingFunctions.outElastic)
	planetTimer.updateCallback = function()
		self.planetText:moveTo(planetTimer.value, 57)
	end

	local suikaTimer = pd.frameTimer.new(40, 600, 200, pd.easingFunctions.outElastic)
	suikaTimer.updateCallback = function()
		self.suikaText:moveTo(suikaTimer.value, 100)
	end

	local playdateTimer = pd.frameTimer.new(40, -200, 200, pd.easingFunctions.outElastic)
	playdateTimer.updateCallback = function()
		self.playdateText:moveTo(playdateTimer.value, 140)
	end

	self.credits = {
		{
			qr   = "assets/images/TommusRhodus.png",
			url  = "https://tomrhodes.blog/",
			name = "TommusRhodus",
			role = "Developer"
		},
		{
			qr   = "assets/images/Chiphead64.png",
			url  = "https://chiphead64.itch.io/dreamy-space-soundtrack",
			name = "Chiphead64",
			role = "Soundtrack"
		},
		{
			qr   = "assets/images/PossiblyAxolotl.png",
			url  = "https://github.com/PossiblyAxolotl/pdParticles",
			name = "PossiblyAxolotl",
			role = "Particles System"
		},
		{
			qr   = "assets/images/pdstuff.png",
			url  = "https://github.com/pdstuff/PlaydateSDF",
			name = "pdstuff",
			role = "Signed Distance\nFunctions Library"
		},
		{
			qr   = "assets/images/Deep-Fold.png",
			url  = "https://deep-fold.itch.io/space-background-generator",
			name = "Deep-Fold",
			role = "Space Background\nSprite Generator"
		},
		{
			qr   = "assets/images/Norma2D.png",
			url  = "https://norma-2d.itch.io/celestial-objects-pixel-art-pack",
			name = "Norma2D",
			role = "Planet Sprites"
		},
	}

	self.creditsScreenSprite = gfx.sprite.new(gfx.image.new(400, 240 * #self.credits))
	self.creditsScreenSprite:setCenter(0, 0)
	self.creditsScreenSprite:moveTo(0, 0)

	self.highscoresScreenSprite = gfx.sprite.new(gfx.image.new("assets/images/modal-bg.png"))
	self.highscoresScreenSprite:setCenter(0, 0)
	self.highscoresScreenSprite:moveTo(0, 0)

	self.currentOption = 1
	self.activeScreen = self.currentOption
	self:addSprites()

	self.options = {
		{
			name = "Start Game",
			action = function()
				self:removeSprites()
				startGame()
			end
		},
		{
			name = "Highscores",
			action = function()
				self:highscoresScreen()
			end
		},
		{
			name = "Credits",
			action = function()
				self:creditsScreen()
			end
		}
	}

	-- Remove highscores option if free build.
	if isFreeBuild then
		table.remove(self.options, 2)
	end
end

function Menu:highscoresScreen()
	self:removeSprites()
	self.activeScreen = 2

	local screen = self.highscoresScreenSprite:getImage()
	gfx.pushContext(screen)

	gfx.setImageDrawMode("fillWhite")

	self.bigFont:drawTextAligned("HIGHSCORE", 100, 10, kTextAlignment.center)
	self.bigFont:drawTextAligned("MAX COMBO", 300, 10, kTextAlignment.center)

	for i = 1, #saveData.score do
		self.font:drawTextAligned(saveData.score[i].name, 100, 45 + (40 * (i - 1)), kTextAlignment.center)
		self.font:drawTextAligned(saveData.score[i].value, 100, 60 + (40 * (i - 1)), kTextAlignment.center)
	end

	for i = 1, #saveData.combo do
		self.font:drawTextAligned(saveData.combo[i].name, 300, 45 + (40 * (i - 1)), kTextAlignment.center)
		self.font:drawTextAligned(saveData.combo[i].value, 300, 60 + (40 * (i - 1)), kTextAlignment.center)
	end

	gfx.popContext()
	self.highscoresScreenSprite:setImage(screen)
	self.highscoresScreenSprite:add()
end

function Menu:addSprites()
	self.bg:add()
	self.suikaText:add()
	self.legalText:add()
	self.planetText:add()
	self.playdateText:add()
end

function Menu:removeSprites()
	self.bg:remove()
	self.suikaText:remove()
	self.legalText:remove()
	self.planetText:remove()
	self.playdateText:remove()
end

function Menu:creditsScreen()
	self:removeSprites()
	self.activeScreen = 3
	self:createCreditsScreen()
	self.creditsScreenSprite:add()
end

function Menu:removeCreditsScreen()
	self.creditsScreenSprite:moveTo(0, 0)
	self.creditsScreenSprite:remove()
	self:addSprites()
	self.activeScreen = 1
end

function Menu:removeHighscoreScreen()
	self.highscoresScreenSprite:remove()
	self:addSprites()
	self.activeScreen = 1
end

function Menu:createCreditsScreen()
	local sectionBg = gfx.image.new("assets/images/modal-bg.png")
	for i = 1, #self.credits do
		-- This creates a new QR code for each credit.
		--[[gfx.generateQRCode(self.credits[i].url, 140, function(qr)
			pd.simulator.writeToFile(qr, "~/" ..self.credits[i].name .. ".png")
			print("QR code generated for " .. self.credits[i].name)
		end)]]
		--

		local screen = self.creditsScreenSprite:getImage()
		local qr = gfx.image.new(self.credits[i].qr)
		local yOffset = (i - 1) * 240

		gfx.pushContext(screen)

		sectionBg:draw(0, yOffset)

		qr:draw(20, yOffset + 20)
		gfx.setImageDrawMode("fillWhite")
		self.bigFont:drawText(self.credits[i].name, 200, yOffset + 20)
		self.font:drawText(self.credits[i].role, 200, yOffset + 50)
		gfx.setImageDrawMode("copy")

		gfx.popContext()

		self.creditsScreenSprite:setImage(screen)
	end
end

function Menu:update()
	if self.activeScreen == 2 then
		if pd.buttonJustPressed("a") or pd.buttonJustPressed("b") or pd.buttonJustPressed("up") or pd.buttonJustPressed("down") or pd.buttonJustPressed("left") or pd.buttonJustPressed("right") then
			self:removeHighscoreScreen()
			return
		end
	end

	if pd.buttonJustPressed("a") then
		if self.activeScreen == 1 then
			self.options[self.currentOption].action()
		end

		if self.activeScreen == 3 then
			self.creditsScreenSprite:moveBy(0, -240)

			-- Close credits at end.
			if self.creditsScreenSprite.y < -240 * (#self.credits - 1) then
				self:removeCreditsScreen()
			end
		end
	end

	if pd.buttonIsPressed("b") then
		if self.activeScreen == 2 then
			self:removeHighscoreScreen()
		end

		if self.activeScreen == 3 then
			self:removeCreditsScreen()
		end
	end

	if pd.buttonJustPressed("up") then
		if self.activeScreen == 1 then
			self.currentOption = self.currentOption - 1
			if self.currentOption < 1 then
				self.currentOption = #self.options
			end
		end

		-- Credits screen.
		if self.activeScreen == 3 then
			self.creditsScreenSprite:moveBy(0, 240)

			if self.creditsScreenSprite.y > 0 then
				self.creditsScreenSprite:moveTo(0, 0)
			end
		end
	end

	if pd.buttonJustPressed("down") then
		if self.activeScreen == 1 then
			self.currentOption = self.currentOption + 1
			if self.currentOption > #self.options then
				self.currentOption = 1
			end
		end

		-- Credits screen.
		if self.activeScreen == 3 then
			self.creditsScreenSprite:moveBy(0, -240)

			-- Close credits at end.
			if self.creditsScreenSprite.y < -240 * (#self.credits - 1) then
				self:removeCreditsScreen()
			end
		end
	end

	-- Start game button.
	if self.activeScreen == 1 then
		gfx.setImageDrawMode("fillWhite")
		for i = 1, #self.options do
			local text = self.options[i].name

			if i == self.currentOption then
				text = "> " .. text .. " <"
			end

			self.font:drawTextAligned(text, 200, 175 + (20 * (i - 1)), kTextAlignment.center)
		end

		gfx.setImageDrawMode("copy")
	end
end
