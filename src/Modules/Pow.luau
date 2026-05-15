--!native
--!strict
--!optimize 2

local Pow = {}

local Utils = require("./Utils")
local Constants = require("../Constants")
local Mul = require("./Mul")
local Div = require("./Div")

function Pow.PowByInt(limbs: {number}, exp: number): {number}
	local result: {number} = {1}
	while exp > 0 do
		if exp % 2 == 1 then
			result = Mul.MulLimbs(limbs, result)
		end

		limbs = Mul.MulLimbs(limbs, limbs)
		exp //= 2
	end

	return result
end

function Pow.PowLimbs(limbs: {number}, exp: {number}): {number}
	--> exponentiation by squaring
	local result: {number} = {1}
	while #exp > 0 do
		if exp[1] % 2 == 1 then
			result = Mul.MulLimbs(result, limbs)
		end

		limbs = Mul.MulLimbs(limbs, limbs)
		Div.DivByInt(exp, 2, true)
	end
	
	return result
end

return table.freeze(Pow)