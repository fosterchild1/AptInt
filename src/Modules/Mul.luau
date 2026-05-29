--!native
--!strict
--!optimize 2

local Mul = {}

local Utils = require("./Utils")
local Constants = require("../Constants")
local Add = require("./Add")
local Sub = require("./Sub")
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

const max: (number, number) -> number = math.max
const min: (number, number) -> number = math.min

const tclone: ({number}) -> {number} = table.clone
const tinsert: ({number}, number) -> () = table.insert

-- =================
--> NORMAL CONSTANTS
-- =================

const KARATSUBA_THRESHOLD: number = Constants.KARATSUBA_THRESHOLD
const TOOM3_THRESHOLD: number = Constants.TOOM3_THRESHOLD

const BASE: number = Constants.BASE

-- ==========
--> FUNCTIONS
-- ==========

local function DynamicReturn(arr: {number}): ()
	local size: number = #arr
	if size < KARATSUBA_THRESHOLD then
		return ReturnAlloc(arr, #arr//2) -- karatsuba splits in halves
	end
	
	ReturnAlloc(arr, #arr//3) -- toom cook splits in thirds
end

function Mul.MulByInt(self: {number}, num: number): {number}
	local result: {number} = Utils.GetAlloc(#self, self)
	
	local carry: number = 0
	for i: number, limb: number in self do
		local product: number = limb * num + carry

		carry = product // BASE
		result[i] = product % BASE
	end

	if carry > 0 then
		tinsert(result, carry)
	end

	return result
end

-- Normal O(n^2) algorithm
local function MulLimbsBasecase(self: {number}, factor: {number}): {number}
	local selfLen: number, factorLen: number = #self, #factor
	local len: number = selfLen + factorLen
	local result: {number} = Utils.GetAlloc(len)
	
	factorLen -= 1
	local carry: number = 0
	for i: number = 1, len do
		local p: number = carry
		local iplus: number = i + 1
		
		for j: number = max(i - factorLen, 1), min(i, selfLen) do
			p += self[j] * factor[iplus - j]
		end

		-- apply carry to current limb 
		if p >= BASE then 
			carry = p // BASE 
			result[i] = p % BASE
			continue
		end 

		carry = 0
		result[i] = p
	end
	
	return result
end

local function MulKaratsuba(x: {number}, y: {number}): {number}
	local m2: number = (max(#x, #y) + 1)//2

	local low1: {number}, low2: {number} = GetLower(x, m2), GetLower(y, m2)
	local high1: {number}, high2: {number} = GetUpper(x, m2), GetUpper(y, m2)

	local z0: {number} = Mul.MulLimbs(low1, low2)
	local z1: {number} = Mul.MulLimbs(AddLimbs(low1, high1, true), AddLimbs(low2, high2, true))

	ReturnAlloc(low2)
	local z2: {number} = Mul.MulLimbs(high1, high2)
	ReturnAlloc(high2)
	
	-- result = z0 + ((z1 - z2 - z0) << m2) + (z2 << 2*m2)
	-- => (z2 << m2 + (z1 - (z2 + z0))) << m2 + z0
	local result: {number} = LeftShift(z2, m2)	
	SubLimbs(z1, AddLimbs(z2, z0, true), true)
	result = AddLimbs(result, z1, true)
	
	LeftShift(result, m2, true)
	AddLimbs(result, z0, true)
	
	ReturnAlloc(low1); ReturnAlloc(high1)
	ReturnAlloc(z0, m2); ReturnAlloc(z1, m2); ReturnAlloc(z2, m2)
	return result
end

local function MulToom3(x: {number}, y: {number}): {number}
	local largest: number = max(#x, #y)

	local k: number = largest//3
	local khalf: number = k//2
	local r: number = largest*2//3

	--> get slices
	local x0: {number}, x1: {number} = GetLower(x, k), GetSlice(x, k+1, 2*k)
	local x2: {number} = GetSlice(x, 2*k+1, 2*k+r)

	local y0: {number}, y1: {number} = GetLower(y, k), GetSlice(y, k+1, 2*k)
	local y2: {number} = GetSlice(y, 2*k+1, 2*k+r)
	
	local da1: {number} = AddLimbs(x2, x0)
	local db1: {number} = AddLimbs(y2, y0)
	
	--> these can be negative so we have to account for their sign
	local da1neg: boolean, db1neg: boolean = Cmp.LowerThan(da1, x1), Cmp.LowerThan(db1, y1)
	local vm1lhs: {number} = da1neg and SubLimbs(x1, da1) or SubLimbs(da1, x1)
	local vm1rhs: {number} = db1neg and SubLimbs(y1, db1) or SubLimbs(db1, y1)
	
	local vm1: {number} = Mul.MulLimbs(vm1lhs, vm1rhs)
	local vm1neg: boolean = da1neg ~= db1neg
	
	da1 = AddLimbs(da1, x1, true)
	db1 = AddLimbs(db1, y1, true)

	DynamicReturn(x1); DynamicReturn(y1)
	DynamicReturn(vm1lhs); DynamicReturn(vm1rhs)
	local v0: {number} = Mul.MulLimbs(x0, y0)
	local v1: {number} = Mul.MulLimbs(da1, db1)
	
	da1 = AddLimbs(da1, x2, true)
	db1 = AddLimbs(db1, y2, true)

	local v2: {number} = SubLimbs(AddLimbs(da1, da1, true), x0, true)
	v2 = Mul.MulLimbs(v2, SubLimbs(AddLimbs(db1, db1, true), y0, true))
	
	DynamicReturn(da1); DynamicReturn(db1)
	DynamicReturn(x0); DynamicReturn(y0)
	local vinf: {number} = Mul.MulLimbs(x2, y2)
	
	--> all divisions here are single-limb, so they are linear.
	v2 = (vm1neg and AddLimbs(v2, vm1, true) or SubLimbs(v2, vm1, true))
	local tm1: {number} = vm1neg and AddLimbs(v1, vm1) or SubLimbs(v1, vm1)
	Utils.DivByInt(v2, 3, true)
	Utils.DivByInt(tm1, 2, true)
	
	v1 = SubLimbs(v1, v0, true)
	
	ReturnAlloc(vm1)
	local vinf2: {number} = AddLimbs(vinf, vinf)
	
	Utils.DivByInt(SubLimbs(v2, v1, true), 2, true)
	v1 = SubLimbs(SubLimbs(v1, tm1, true), vinf, true)
	v2 = SubLimbs(v2, vinf2, true)
	tm1 = SubLimbs(tm1, v2, true)
	
	--> combine to get result = (vinf << 4k) + (v2 << 3k) + (v1 << 2k) + (tm1 << k) + v0
	local result: {number} = LeftShift(vinf, k, true)
	result = AddLimbs(result, v2, true)
	
	LeftShift(result, k, true)
	AddLimbs(result, v1, true)
	
	LeftShift(result, k, true)
	AddLimbs(result, tm1, true)
	
	LeftShift(result, k, true)
	AddLimbs(result, v0, true)
	
	--> inside toomcook3, all mullimbs are placed right after eachother
	--> these will be reused by getslice and adds/subs in next toomcook3 call
	ReturnAlloc(x2); ReturnAlloc(y2)
	ReturnAlloc(vinf2, khalf)
	ReturnAlloc(v0, khalf); ReturnAlloc(v1, khalf); ReturnAlloc(v2, khalf); ReturnAlloc(tm1, khalf)
	--> dont return vinf, as its the result
	return result
end

function Mul.MulLimbs(self: {number}, factor: {number}): {number}
	local selfLen: number, factorLen: number = #self, #factor
	
	local result: {number}
	if selfLen < KARATSUBA_THRESHOLD or factorLen < KARATSUBA_THRESHOLD then
		result = MulLimbsBasecase(self, factor)
	elseif selfLen < TOOM3_THRESHOLD or factorLen < TOOM3_THRESHOLD then
		result = MulKaratsuba(self, factor)
	else
		result = MulToom3(self, factor)
	end
	
	Utils.StripLeadingZeros(result)
	return result
end

return table.freeze(Mul)