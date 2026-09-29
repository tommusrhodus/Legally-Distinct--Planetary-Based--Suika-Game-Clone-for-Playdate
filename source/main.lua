-- The game was originally tuned for 28fps, with timings counted in frames.
-- Everything now runs on real time, so convert those frame counts.
function framesToMs(frames)
	return frames * 1000 / 28
end

import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
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
isFreeBuild = true

-- Setup game constants. Physics runs at a fixed rate on real time, so the
-- display can refresh as fast as the hardware allows.
disp.setRefreshRate(50)
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
	game:addGui()
end

function restartGame()
	gfx.sprite.performOnAllSprites(function(sprite)
		sprite:remove()
	end)

	game = nil
	startGame()
end

function endGame()
	physics.clear()

	gfx.sprite.performOnAllSprites(function(sprite)
		sprite:remove()
	end)

	-- Remove custom menu items.
	pd.getSystemMenu():removeAllMenuItems()
	game = nil
	gfx.clear(gfx.kColorBlack)
	menu = Menu()
end

-- Longest frame time passed on to movement, so a stall (loading, the system
-- menu) doesn't make the cursor or effects jump.
local kMaxFrameTime <const> = 1 / 15

function pd.update()
	local dt = math.min(pd.getElapsedTime(), kMaxFrameTime)
	pd.resetElapsedTime()

	-- Input and physics first so the sprites drawn this frame are current.
	if game then
		game:update(dt)
	end

	gfx.sprite.update()
	pd.timer.updateTimers()

	if game then
		game:draw(dt)
	end

	if menu then
		menu:update()
	end
end
