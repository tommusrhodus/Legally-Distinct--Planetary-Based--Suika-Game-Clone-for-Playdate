import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/frameTimer"
import "CoreLibs/timer"
import "CoreLibs/easing"
import "CoreLibs/qrcode"
import "CoreLibs/keyboard"
import "external/particles.lua"
import "external/cheat-codes.lua"

import "classes/class-ball.lua"
import "classes/class-game.lua"
import "classes/class-menu.lua"
import "classes/class-modal.lua"

local pd <const> = playdate
local gfx <const> = pd.graphics
local disp <const> = pd.display

-- Is this the free build or not?
isFreeBuild = false

-- Setup game constants.
disp.setRefreshRate(28)
gfx.clear(gfx.kColorBlack)
gfx.setBackgroundColor(gfx.kColorBlack)
pd.setMenuImage(gfx.image.new("assets/images/menu-image.png"))

-- Load soundtrack.
soundtrack = pd.sound.fileplayer.new("assets/sounds/soundtrack")
soundtrack:play(0)

-- Load save data, if none is found, create placeholder data.
function loadData()
	local saveData = pd.datastore.read("ldpbsgcfpd")

	-- If no data was found, insert placeholder data.
	if nil == saveData then
		saveData = {
			kawaii = false,
			audio = "all",
			score = {
				{
					name = "TommusRhodus",
					value = 10000
				},
				{
					name = "TommusRhodus",
					value = 1000
				},
				{
					name = "TommusRhodus",
					value = 100
				},
				{
					name = "TommusRhodus",
					value = 10
				}
			},
			combo = {
				{
					name = "TommusRhodus",
					value = 30
				},
				{
					name = "TommusRhodus",
					value = 20
				},
				{
					name = "TommusRhodus",
					value = 10
				},
				{
					name = "TommusRhodus",
					value = 1
				}
			}
		}
		pd.datastore.write(saveData, "ldpbsgcfpd")
	end

	-- Backfill kawaii save data.
	if not saveData.kawaii then
		saveData.kawaii = false
		pd.datastore.write(saveData, "ldpbsgcfpd")
	end

	return saveData
end

saveData = loadData()

function saveGameData()
	pd.datastore.write(saveData, "ldpbsgcfpd")
end

menu = Menu()

function startGame()
	gfx.sprite.performOnAllSprites(function(sprite)
		sprite:remove()
	end)

	menu = nil
	gfx.clear(gfx.kColorBlack)

	local data = loadData()

	game = Game(data.kawaii)
	game:setGuiImage()
	game.guiImage:add()
end

function restartGame()
	gfx.sprite.performOnAllSprites(function(sprite)
		sprite:remove()
	end)

	game = nil
	startGame()
end

function endGame()
	gfx.sprite.performOnAllSprites(function(sprite)
		sprite:remove()
	end)

	-- Remove custom menu items.
	pd.getSystemMenu():removeAllMenuItems()
	game = nil
	gfx.clear(gfx.kColorBlack)
	menu = Menu()
end

function pd.update()
	gfx.sprite.update()
	pd.frameTimer.updateTimers()

	if game then
		game:update()
	end

	if menu then
		menu:update()
	end
end
