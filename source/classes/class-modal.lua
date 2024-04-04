local pd <const> = playdate
local gfx <const> = pd.graphics
local kbd <const> = pd.keyboard

class("Modal").extends(gfx.sprite)

function Modal:init()
	Modal.super.init(self)

	self.score = game.totalScore
	self.combo = game.highestCombo
	self.bigFont = gfx.font.new("assets/fonts/Nontendo-Bold-2x")

	self.newHighscore = 0
	self.newMaxCombo = 0

	local highScoreText = ""
	local maxComboText = ""

	-- Remove highscore stuff in the free build.
	if not isFreeBuild then
		for i = 1, #saveData.score do
			if self.score > saveData.score[i].value then
				self.newHighscore = i
				highScoreText = "NEW HIGHSCORE!"
				break
			end
		end

		for i = 1, #saveData.combo do
			if self.combo > saveData.combo[i].value then
				self.newMaxCombo = i
				maxComboText = "NEW MAX COMBO!"
				break
			end
		end
	end

	local image = gfx.image.new(400, 240)
	local bg = gfx.image.new("assets/images/modal-bg.png")
	gfx.pushContext(image)

	bg:draw(0, 0)

	gfx.setImageDrawMode("fillWhite")
	self.bigFont:drawTextAligned("GAME OVER", 300, 30, kTextAlignment.center)
	game.font:drawTextAligned("SCORE\n" .. self.score .. "\n" .. highScoreText, 300, 70, kTextAlignment.center)
	game.font:drawTextAligned("MAX COMBO\n" .. self.combo .. "\n" .. maxComboText, 300, 140, kTextAlignment
		.center)
	gfx.setImageDrawMode("copy")

	gfx.popContext()

	self:setImage(image)
	self:moveTo(0, 0)
	self:setUpdatesEnabled(false)
	self:setCenter(0, 0)
	self:setVisible(false)

	kbd.keyboardDidHideCallback = function()
		if kbd.text == "" then
			return
		end

		if self.newHighscore > 0 then
			table.insert(saveData.score, self.newHighscore, {
				name = kbd.text,
				value = self.score
			})
			table.remove(saveData.score)
		end

		if self.newMaxCombo > 0 then
			table.insert(saveData.combo, self.newMaxCombo, {
				name = kbd.text,
				value = self.combo
			})
			table.remove(saveData.combo)
		end

		saveGameData()
		endGame()
	end
end

function Modal:update()
	pd.timer.updateTimers()

	if not self:isVisible() then
		return
	end

	if not isFreeBuild then
		if self.newHighscore > 0 or self.newMaxCombo > 0 then
			if pd.buttonJustPressed("a") or pd.buttonJustPressed("b") and not kbd.isVisible() then
				kbd.show()
			end

			if kbd:isVisible() then
				gfx.setColor(gfx.kColorBlack)
				gfx.fillRect(0, 0, 400, 240)

				gfx.setImageDrawMode("fillWhite")
				game.font:drawTextAligned("ENTER YOUR NAME", 100, 70, kTextAlignment.center)
				self.bigFont:drawTextAligned(kbd.text, 100, 110, kTextAlignment.center)
				gfx.setImageDrawMode("copy")
			end

			return
		end
	end

	if pd.buttonJustPressed("a") then
		game:gameOver(true)
	end

	if pd.buttonJustPressed("b") then
		endGame()
	end
end
