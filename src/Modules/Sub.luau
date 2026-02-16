--!native
--!strict
--!optimize 2

local Subtraction = {}

local Utils = require("./Utils")
local Constants = require("../Constants")

local tclone: ({number}) -> {number} = table.clone

local BASE: number = Constants.BASE

function Subtraction.SubLimbs(self: {number}, term: {number}, inPlace: boolean?): {number}
	local result: {number} = (inPlace and self or tclone(self))
	
	local diff: number = 0
	for i: number, selfDigit: number in result do
		diff += selfDigit - (term[i] or 0)
		
		if diff < 0 then
			result[i] = diff + BASE
			diff = -1
			continue
		end

		result[i] = diff
		diff = 0
	end
	
	Utils.StripLeadingZeros(result)
	return result
end

return Subtraction