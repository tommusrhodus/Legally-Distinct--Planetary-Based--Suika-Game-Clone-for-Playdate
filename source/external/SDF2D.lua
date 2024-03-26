-- The SDF's in this library are ports of the GLSL functions
-- available at https://iquilezles.org/articles/distfunctions2d/

import "CoreLibs/object"
--import "utils.lua"

local vec2 = playdate.geometry.vector2D.new

local sin = math.sin
local cos = math.cos
local atan = math.atan
local abs = math.abs
local max = math.max
local min = math.min
local sqrt = math.sqrt

--[[
Calculate a normalized gradient from nearby points to find the direction of the
shortest path to the surface. We compute the gradient vector, and then normalize
the magnitude to remove local variations of the slope. This approach provides a 
directionally accurate vector for collision responses or for guiding movements.
]]
function calcNormalizedGradient(p, f, o, params) -- p:point, o:offset, f:sdf, params:params to sdf
	local eps = 1e-4
	local ds = {f(vec2(p.x + eps, p.y)-o, table.unpack(params)),
				f(vec2(p.x - eps, p.y)-o, table.unpack(params)),
				f(vec2(p.x, p.y + eps)-o, table.unpack(params)),
				f(vec2(p.x, p.y - eps)-o, table.unpack(params))}
	return vec2((ds[1]-ds[2])/(2*eps), (ds[3]-ds[4])/(2*eps)):normalized()
end

local function vecAbs2D(a) return vec2(abs(a.x),abs(a.y)) end

-- Circle (https://www.shadertoy.com/view/3ltSW2)
function sdCircle(p, r)
	return p:magnitude() - r
end

-- Box (https://www.youtube.com/watch?v=62-pRVZuS5c)
function sdBox(p, b)
	local d = vecAbs2D(p) - b
	local od = vec2(max(d.x, 0), max(d.y, 0)):magnitude()
	local id = min(max(d.x, d.y), 0)
	return od + id
end

-- Segment (https://www.shadertoy.com/view/3tdSDj
function sdSegment(p, a, b)

	local pa = p - a
	local ba = b - a
--	local h = max(0, min(1, pa:dotProduct(ba) / ba:dotProduct(ba)))
	local h = max(0, min(1, (pa*ba) / (ba*ba)))
	return (pa - ba * h):magnitude()

end
