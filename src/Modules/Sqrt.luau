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

const ReturnAlloc = Utils.ReturnAlloc
const GetUpper = Utils.GetUpper
const GetLower = Utils.GetLower
const GetSlice = Utils.GetSlice
const LeftShift = Utils.LeftShift

const AddLimbs = Add.AddLimbs
const SubLimbs = Sub.SubLimbs

-- =================
--> NORMAL CONSTANTS
-- =================

const tcreate: (number, number) -> {number} = table.create

const SQRT_KARATSUBA_THRESHOLD: number = Constants.SQRT_KARATSUBA_THRESHOLD
const SQRT_NEWTON_THRESHOLD: number = Constants.SQRT_NEWTON_THRESHOLD

local function BinarySearchSqrt(n: {number}) : {number}
	--> get low and high, range of high to low is BASE
	--> at most BASE_POW checks
	
	local half: number = (#n + 1)//2
	local low: {number} = tcreate(half, 0) -- initial guess
	low[#low] = 1
	
	local high: {number} = tcreate(half+1, 0)
	high[#high] = 1
	
	while Cmp.LowerOrEqualTo(low, high) do
		local mid: {number} = AddLimbs(low, high)
		Div.DivByInt(mid, 2, true)
		
		local sq: {number} = Mul.MulLimbs(mid, mid)
		local comparison: number = Cmp.Compare(sq, n)
		if comparison == 0 then -- sq == n
			return mid
		elseif comparison == -1 then -- sq < n
			low = Add.AddByInt(mid, 1, true)
			continue
		end
		
		high = Sub.SubByInt(mid, 1, true)
	end
	
	return high
end

local function NewtonHeronSqrt(n: {number}): {number}
	local prev2: {number} = {1}
	
	-- local prev1 = AP_ONE:LeftShift((#n.limbs-1)//2) -- initial guess
	local prev1: {number} = tcreate(#n//2, 0)-- ^^
	prev1[#prev1] = 1
	
	while true do
		local q: {number}, _: {number} = Div.DivLimbs(n, prev1)
		local x1: {number} = Div.DivByInt(AddLimbs(prev1, q), 2, true)
		
		--> Cmp.Compare isnt faster here because LowerThan only runs once
		--> Cmp.Equals is way faster
		if Cmp.Equals(x1, prev1) then
			return x1
		end
		
		if Cmp.Equals(x1, prev2) then
			return (Cmp.LowerThan(x1, prev1) and x1 or prev1) -- min(x1, prev1)
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
		local isq: {number} = Sqrt.ISqrtLimbs(n)
		local isqSq: {number} = Mul.MulLimbs(isq, isq)
		local remainder: {number} = SubLimbs(n, isqSq)
		
		ReturnAlloc(isqSq)
		return isq, remainder
	end
	--> calculate a3, a1 and a0
	local m: number = limbLen//4
	local m2: number = m*2

	local a3a2: {number} = GetUpper(n, m2) -- m2+1
	local s1: {number}, r1: {number} = KaratsubaSqrt(a3a2)
	
	local a1: {number} = GetSlice(n, m+1, m2)
	
	--> divrem (r1*b + a1, 2*s1)
	local r1b: {number} = AddLimbs(LeftShift(r1, m, true), a1, true)
	ReturnAlloc(a1) -- free up a1, then a0 takes its place
	local a0: {number} = GetLower(n, m)
	
	local ds1: {number} = AddLimbs(s1, s1)
	local q: {number}, u: {number} = Div.DivLimbs(r1b, ds1)
	ReturnAlloc(r1b); ReturnAlloc(ds1)

	-- s=s1*b+q
	-- r=u*b+a0-q^2
	local s: {number} = AddLimbs(LeftShift(s1, m, true), q, true)
	
	ReturnAlloc(a3a2) -- return a3a2, qsquared will take its place
	local qSquared: {number} = Mul.MulLimbs(q, q)
	
	local r: {number} = AddLimbs(LeftShift(u, m, true), a0, true)
	ReturnAlloc(a0); ReturnAlloc(q)
	
	local willCorrect: boolean = Cmp.LowerThan(r, qSquared) -- if r will be negative
	r = SubLimbs(r, qSquared, true)
	ReturnAlloc(qSquared)
	
	--> correct
	if willCorrect then
		r = Sub.SubByInt(AddLimbs(r, AddLimbs(s, s), true), 1, true)
		s = Sub.SubByInt(s, 1, true)
	end

	return s, r
end

function Sqrt.ISqrtLimbs(limbs: {number}): {number}
	local len: number = #limbs
	
	if len >= SQRT_KARATSUBA_THRESHOLD then
		local s: {number}, _: {number} = KaratsubaSqrt(limbs)
		return s
	elseif len >= SQRT_NEWTON_THRESHOLD then
		return NewtonHeronSqrt(limbs)
	end

	return BinarySearchSqrt(limbs)
end

return table.freeze(Sqrt)