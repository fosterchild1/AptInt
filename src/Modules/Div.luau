--!native
--!strict
--!optimize 2

local Div = {}

local Utils = require("./Utils")
local Constants = require("../Constants")
local Mul = require("./Mul")

local tclone: ({number}) -> {number} = table.clone
local tcreate: (number, number) -> {number} = table.create

local BURNIKEL_THRESHOLD: number = Constants.BURNIKEL_THRESHOLD
local MIN_BURNIKEL_OFFSET: number = Constants.MIN_BURNIKEL_OFFSET

local BASE: number = Constants.BASE

local function DivKnuths(U: {number}, V: {number}): ({number}, {number})
	--> d0. defs
	local n: number = #V
	local m: number = #U - n

	--> d1. normalize (get Vn and Un)
	local D: number = BASE // (V[n] + 1)

	local Un: {number} = Mul.MulByInt(U, D)
	local Vn: {number} = Mul.MulByInt(V, D)

	local Vnn: number = Vn[n]
	local penultimateVn: number = Vn[n-1] or 0

	local quotient: {number} = tcreate(m + 1, 0)
	
	--> d2. init j
	local qhat: number, rhat: number = 0, 0
	for j: number = m, 0, -1 do
		--> d3. calculate qhat and rhat
		local nPlusJ: number = n + j + 1
		local top: number = (Un[nPlusJ] or 0) * BASE + (Un[nPlusJ - 1] or 0)
		qhat = top // Vnn
		rhat = top % Vnn

		if qhat == 0 then continue end

		--> first correction
		if qhat * penultimateVn > rhat * BASE + (Un[nPlusJ - 2] or 0) then
			qhat -= 1
			rhat += Vnn

			--> second correction
			if rhat < BASE and qhat * penultimateVn > rhat * BASE + (Un[nPlusJ - 2] or 0) then
				qhat -= 1
			end
		end

		--> d4. multiply & subtract
		local carry: number = 0
		local borrow: number = 0

		for i: number = 1, n do
			local p: number = qhat * Vn[i] + carry
			carry = p // BASE
			local pDigit: number = p % BASE

			local diff: number = Un[i + j] - pDigit - borrow
			if diff < 0 then
				borrow = 1
				Un[i + j] = diff + BASE
				continue
			end

			borrow = 0
			Un[i + j] = diff
		end

		local lastSub: number = (Un[nPlusJ] or 0) - carry - borrow
		Un[nPlusJ] = lastSub

		--> d6. add back
		if lastSub >= 0 then
			quotient[j + 1] = qhat
			continue
		end

		quotient[j + 1] = qhat - 1
		carry = 0

		for i: number = 1, n do
			local sum: number = Un[i + j] + Vn[i] + carry

			if sum >= BASE then
				carry = 1
				Un[i + j] = sum - BASE
				continue
			end

			carry = 0
			Un[i + j] = sum
		end

		Un[nPlusJ] = (Un[nPlusJ] + carry) % BASE
	end

	--> d8. unnormalize
	local carry: number = 0

	for i: number = #Un, 1, -1 do
		local x: number = carry * BASE + Un[i]

		carry = x % D 
		Un[i] = x // D
	end

	Utils.StripLeadingZeros(Un)
	Utils.StripLeadingZeros(quotient)

	return quotient, Un
end

--> this is needed in multiplication too
Div.DivByInt = Utils.DivByInt

function Div.DivLimbs(self: {number}, divisor: {number}): ({number}, {number})
	local diff: number = #self - #divisor
	
	local quotient: {number}, remainder: {number}
	if #self > BURNIKEL_THRESHOLD and #divisor > BURNIKEL_THRESHOLD and diff > MIN_BURNIKEL_OFFSET then
		quotient, remainder = DivBurnikelZiegler(self, divisor)
	else
		quotient, remainder = DivKnuths(self, divisor)
	end

	return quotient, remainder
end

return Div