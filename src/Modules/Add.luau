--!native
--!strict
--!optimize 2

local Add = {}

local Constants = require("../Constants")

local abs: (number) -> number = math.abs

local tclone: ({number}) -> {number} = table.clone
local tinsert: ({number}, number) -> () = table.insert

local BASE: number = Constants.BASE
local MIN_MINADD_OFFSET: number = Constants.MIN_MINADD_OFFSET

local function MinAdd(term: {number}, result: {number}): {number}
	--> since result has self's limbs, we can just iterate over y
	--> carry is 99.99% of times very small, so the while loop doesnt run much
	--> overall faster
	
	--> from right to left
	local sum: number = 0
	for i: number, yLimb: number in term do
		sum += result[i] + yLimb

		if sum >= BASE then
			result[i] = sum - BASE
			sum = 1
			continue
		end

		result[i] = sum
		sum = 0
	end

	if sum == 0 then return result end

	--> carry loop
	local resultIndex: number = #term
	while true do
		resultIndex += 1
		sum = (result[resultIndex] or 0) + 1

		if sum >= BASE then
			result[resultIndex] = sum - BASE
			continue
		end

		result[resultIndex] = sum
		break
	end

	return result
end

function Add.AddLimbs(self: {number}, term: {number}, inPlace: boolean?): {number}
	local selfLen: number, termLen: number = #self, #term

	--> choose the longer number to avoid extra "or 0" with selfDigit
	local result: {number}
	if selfLen < termLen then
		result = tclone(term)
		self, term = term, self
	else
		result = (inPlace and self or tclone(self))
	end

	if abs(termLen - selfLen) > MIN_MINADD_OFFSET then
		return MinAdd(term, result)
	end
	
	--> from right to left
	local sum: number = 0
	for i: number, selfLimb: number in self do
		sum += selfLimb + (term[i] or 0)

		if sum >= BASE then
			result[i] = sum - BASE
			sum = 1
			continue
		end

		result[i] = sum
		sum = 0
	end

	if sum > 0 then tinsert(result, sum) end
	return result
end

return Add