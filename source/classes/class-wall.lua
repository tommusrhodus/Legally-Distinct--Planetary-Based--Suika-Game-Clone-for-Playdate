local gfx = playdate.graphics
local vec2 = playdate.geometry.vector2D.new

class("Wall").extends(gfx.sprite)

function Wall:init(x, y, a, b)
	Wall.super.init(self)
	self.position = vec2(x, y)
	self.a = a
	self.b = b
	self:setImage(self:draw())
	self:setCollideRect(0, 0, self:getSize())
	self:moveTo(self.position:unpack())
	self.f = sdBox
end

function Wall:draw()
	local im = gfx.image.new(self.a * 2, self.b * 2)
	gfx.pushContext(im)
	gfx.fillRect(0, 0, self.a * 2, self.b * 2)
	gfx.popContext()
	return im
end

function Wall:distance(p)
	return sdBox(self.position - p, vec2(self.a, self.b))
end
