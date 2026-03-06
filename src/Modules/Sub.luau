--!native
--!strict
--!optimize 2

local Sub = {}

local Utils = require("./Utils")
local Constants = require("../Constants")

local tclone: ({number}) -> {number} = table.clone

local BASE: number = Constants.BASE

function Sub.SubByInt(self: {number}, num: number, inPlace: boolean?): {number}
	local result: {number} = (inPlace and self or tclone(self))
	local diff: number = result[1] - num
	
	if diff >= 0 then result[1] = diff return result end
	
	--> first step of carry loop: carry = num
	result[1] = diff + BASE
	
	local resultIndex: number = 2
	while true do
    	diff = (result[resultIndex] or 0) - 1
    	if diff < 0 then
			result[resultIndex] = diff + BASE
			resultIndex += 1
        	continue
		end
		
		result[resultIndex] = diff
		break
    end
	
	Utils.StripLeadingZeros(self)
	return result
end

function Sub.SubLimbs(self: {number}, term: {number}, inPlace: boolean?): {number}
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

return Sub