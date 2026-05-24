--!native
--!strict
--!optimize 2

local Add = {}

local Constants = require("../Constants")
local Utils = require("./Utils")

const abs: (number) -> number = math.abs

const tclone: ({number}) -> {number} = table.clone
const tinsert: ({number}, number) -> () = table.insert
const tmove: ({number}, number, number, number, {number}) -> {number} = table.move

const BASE: number = Constants.BASE
const MIN_MINADD_OFFSET: number = Constants.MIN_MINADD_OFFSET

function Add.AddByInt(self: {number}, sum: number, inPlace: boolean?): {number}
	local result: {number} = (inPlace and self or tclone(self))

	--> carry loop
	local resultIndex: number = 1
	while true do
		sum += result[resultIndex] or 0

		if sum >= BASE then
			result[resultIndex] = sum - BASE
			resultIndex += 1
			sum = 1
			continue
		end

		result[resultIndex] = sum
		break
	end

	return result
end

function Add.AddLimbs(self: {number}, term: {number}, inPlace: boolean?): {number}
	local selfLen: number, termLen: number = #self, #term

	--> choose the longer number to be self
	local result: {number}
	if selfLen < termLen then
		result = Utils.GetAlloc(termLen, term)
		self, term = term, self
		selfLen, termLen = termLen, selfLen
	else
		result = (inPlace and self or Utils.GetAlloc(selfLen, self))
	end

	--> smaller number first, to avoid "or 0" inside loop
	local sum: number = 0
	for i: number, termLimb: number in term do
		sum += termLimb + self[i]

		if sum >= BASE then
			result[i] = sum - BASE
			sum = 1
			continue
		end

		result[i] = sum
		sum = 0
	end

	--> add the larger number's extra limbs
	for i: number = termLen + 1, selfLen do
		sum += self[i]
		if sum >= BASE then
			result[i] = sum - BASE
			sum = 1
			continue
		end

		--> no more carry: just copy the other limbs, nothing will change
		result[i] = sum
		if i < selfLen then
			tmove(self, i + 1, selfLen, i + 1, result)
		end
		return result
	end

	if sum > 0 then tinsert(result, sum) end
	return result
end

return table.freeze(Add)