--!native
--!strict
--!optimize 2

local Sqrt = {}

local Utils = require("./Utils")
local Constants = require("../Constants")
local Add = require("./Add")
local Sub = require("./Sub")
local Mul = require("./Mul")
local Div = require("./Div")
local Cmp = require("./Cmp")

-- ================================
--> OPTIMIAZTION FUNCTION CONSTANTS
-- ================================

local GetUpper: ({number}, number) -> {number} = Utils.GetUpper
local GetLower: ({number}, number) -> {number} = Utils.GetLower
local GetSlice: ({number}, number, number) -> {number} = Utils.GetSlice
local LeftShift: ({number}, number) -> {number} = Utils.LeftShift

local AddLimbs: ({number}, {number}, boolean?) -> {number} = Add.AddLimbs
local SubLimbs: ({number}, {number}, boolean?) -> {number} = Sub.SubLimbs

local Equals: ({number}, {number}) -> boolean = Cmp.Equals
local LowerThan: ({number}, {number}) -> boolean = Cmp.LowerThan

-- =================
--> NORMAL CONSTANTS
-- =================

local tcreate: (number, number) -> {number} = table.create

local SQRT_KARATSUBA_THRESHOLD: number = Constants.SQRT_KARATSUBA_THRESHOLD

local function NewtonHeronSqrt(n: {number}): {number}
	local prev2: {number} = {1}
	
	--> AP_ONE:LeftShift((#n.limbs-1)//2) -- initial guess
	local prev1: {number} = tcreate(#n//2, 0)
	prev1[#prev1] = 1

	while true do
		local q: {number}, _: {number} = Div.DivLimbs(n, prev1)
		local x1: {number} = Div.DivByInt(AddLimbs(prev1, q), 2, true)

		if Equals(x1, prev1) then
			return x1
		end

		if Equals(x1, prev2) then
			return (LowerThan(x1, prev1) and x1 or prev1) -- min(x1, prev1)
		end

		prev2, prev1 = prev1, x1
	end
end

local function KaratsubaSqrt(n: {number}): ({number}, {number})
	-- https://gmplib.org/manual/Square-Root-Algorithm
	-- https://en.wikipedia.org/wiki/Integer_square_root#Karatsuba_square_root_algorithm

	--> needed here too
	local limbLen: number = #n
	if limbLen < SQRT_KARATSUBA_THRESHOLD then
		local sq: {number} = NewtonHeronSqrt(n)
		return sq, SubLimbs(n, Mul.MulLimbs(sq, sq))
	end

	--> calculate a3, a1 and a0
	local m: number = limbLen//4
	local m2: number = m*2

	local a3a2: {number} = GetUpper(n, m2) -- m2+1
	local a1: {number}, a0: {number} = GetSlice(n, m+1, m2), GetSlice(n, 1, m)

	local s1: {number}, r1: {number} = KaratsubaSqrt(a3a2)
	--local r1 = a3a2:SubtractRaw(s1:MultiplyRaw(s1))

	--> divrem (r1*b + a1, 2*s1)
	local r1b: {number} = AddLimbs(LeftShift(r1, m), a1, true)
	local ds1: {number} = AddLimbs(s1, s1)
	local q: {number}, u: {number} = Div.DivLimbs(r1b, ds1)

	-- s=s1*b+q
	-- r=u*b+a0-q^2
	local s: {number} = AddLimbs(LeftShift(s1, m), q, true)
	
	local qSquared: {number} = Mul.MulLimbs(q, q)
	local r: {number} = AddLimbs(LeftShift(u, m), a0, true)
	local willCorrect: boolean = Cmp.LowerThan(r, qSquared) -- if r will be negative
	r = SubLimbs(r, qSquared, true)
	
	--> correct
	if willCorrect then
		r = SubLimbs(AddLimbs(r, AddLimbs(s, s), true), {1}, true)
		s = SubLimbs(s, {1}, true)
	end

	return s, r
end

function Sqrt.ISqrtLimbs(limbs: {number}): {number}
	if #limbs >= SQRT_KARATSUBA_THRESHOLD then
		local s: {number}, _: {number} = KaratsubaSqrt(limbs)
		return s
	end

	return NewtonHeronSqrt(limbs)
end

return Sqrt