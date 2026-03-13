--!native
--!strict
--!optimize 2

local Utils = {}

local Constants = require("../Constants")

local tinsert: ({number}, number) -> () = table.insert
local tcreate: (number, number) -> {number} = table.create
local tclone: ({number}) -> {number} = table.clone
local tmove: ({number}, number, number, number, {number}) -> {number} = table.move

local BASE: number = Constants.BASE

function Utils.StripLeadingZeros(array: {number}): ()
	local len: number = #array
	while len > 0 and array[len] == 0 do
		array[len] = nil
		len -= 1
	end
end

function Utils.GetLower(limbs: {number}, n: number): {number}
	return tmove(limbs, 1, n, 1, {})
end

--> get upper n limbs
function Utils.GetUpper(limbs: {number}, n: number): {number}
	return tmove(limbs, n+1, #limbs, 1, {})
end

--> get limbs from startIdx to endIdx
function Utils.GetSlice(limbs: {number}, startIdx: number, endIdx: number): {number}
	return tmove(limbs, startIdx, endIdx, 1, {})
end

function Utils.LeftShift(limbs: {number}, amount: number): {number}
	-- this is the fastest way to leftshift
	return tmove(limbs, 1, #limbs, amount+1, tcreate(amount, 0))
end

function Utils.DivByInt(limbs: {number}, div: number, inPlace: boolean?): ({number}, {number})
	local quotient: {number} = (inPlace and limbs or tclone(limbs))

	local carry: number = 0
	for i: number = #limbs, 1, -1 do
		local x: number = limbs[i] + carry * BASE
		local qDigit: number = x // div

		carry = x - qDigit * div
		quotient[i] = qDigit
	end

	Utils.StripLeadingZeros(quotient)
	if carry == 0 then
		return quotient, {}
	end

	return quotient, {carry}
end

return Utils