--!native
--!strict
--!optimize 2

local Sqrt = {}

local Utils = require("./Utils")
local Constants = require("../Constants")
local Cmp = require("./Cmp")

local Equals: ({number}, {number}) -> boolean = Cmp.Equals
local LowerThan: ({number}, {number}) -> boolean = Cmp.LowerThan

local tcreate: (number, number) -> {number} = table.create

local SQRT_KARATSUBA_THRESHOLD: number = Constants.SQRT_KARATSUBA_THRESHOLD

local function NewtonHeronSqrt(n: {number})
	local prev2: {number} = {1}
	
	--> AP_ONE:LeftShift((#n.limbs-1)//2) -- initial guess
	local prev1: {number} = tcreate(#n//2, 0)
	prev1[#prev1] = 1

	while true do
		local q: {number}, _: {number} = n:DivideRaw(prev1)
		local x1: {number} = prev1:AddRaw(q); Div2InPlace(x1)

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
	local limbLen: number = #n.limbs
	if limbLen < SQRT_KARATSUBA_THRESHOLD then
		local sq = NewtonHeronSqrt(n)
		return sq, n:SubtractRaw(sq:MultiplyRaw(sq))
	end

	--> calculate a3, a1 and a0
	local m: number = limbLen//4
	local m2: number = m*2

	local a3a2: {number} = GetUpper(n, m2) -- m2+1
	local a1: {number}, a0: {number} = GetSlice(n, m+1, m2), GetSlice(n, 1, m)

	local s1: {number}, r1: {number} = KaratsubaSqrt(a3a2)
	--local r1 = a3a2:SubtractRaw(s1:MultiplyRaw(s1))

	--> divrem (r1*b + a1, 2*s1)
	local q, u: {number} = 
		r1:LeftShift(m):AddRaw(a1, true)
		:DivideRaw(s1:AddRaw(s1))

	-- s=s1*b+q
	-- r=u*b+a0-q^2
	local s: {number} = s1:LeftShift(m):AddRaw(q, true)
	local r: {number} = u:LeftShift(m):AddRaw(a0, true):SubtractRaw(q:MultiplyRaw(q), true)

	--> correct
	if r.signum == -1 then
		r = r:AddRaw(s:AddRaw(s), true):SubtractRaw(AP_ONE, true)
		s = s:SubtractRaw(AP_ONE, true)
	end

	return s, r
end

function Sqrt.ISqrtLimbs(limbs: {number})
	if #limbs >= SQRT_KARATSUBA_THRESHOLD then
		local s, _ = KaratsubaSqrt(limbs)
		return s
	end

	return NewtonHeronSqrt(limbs)
end

return Sqrt