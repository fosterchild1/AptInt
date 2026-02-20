--!native
--!strict
--!optimize 2

local Cmp = {}

local Utils = require("./Utils")
local Constants = require("../Constants")

function Cmp.LowerThan(x: {number}, y: {number}): boolean
	local xLen: number, yLen: number = #x, #y
	
	if xLen < yLen then
		return true
	elseif xLen > yLen then
		return false
	end
	
	for i: number = xLen, 1, -1 do
		local xLimb: number, yLimb: number = x[i], y[i]
		if xLimb == yLimb then continue end
		
		return xLimb < yLimb
	end

	return false 
end

function Cmp.LowerOrEqualTo(x: {number}, y: {number}): boolean
	local xLen: number, yLen: number = #x, #y
	if xLen < yLen then
		return true
	elseif xLen > yLen then
		return false
	end

	for i: number = xLen, 1, -1 do
		local xLimb: number, yLimb: number = x[i], y[i]
		if xLimb == yLimb then continue end
		
		return xLimb < yLimb
	end

	return true 
end

function Cmp.Equals(x: {number}, y: {number}): boolean
	if #x ~= #y then
		return false
	end

	for i: number, xLimb: number in x do
		if xLimb == y[i] then continue end
		return false
	end

	return true 
end

function Cmp.Compare(x: {number}, y: {number}): number
	local xLen: number, yLen: number = #x, #y
	if xLen < yLen then
		return -1
	elseif xLen > yLen then
		return 1
	end
	
	for i: number = xLen, 1, -1 do
		local xLimb: number, yLimb: number = x[i], y[i]
		if xLimb == yLimb then continue end
		return xLimb > yLimb and 1 or -1
	end
	
	return 0
end

return Cmp