--!native
--!strict
--!optimize 2

local Mul = {}

local Utils = require("./Utils")
local Constants = require("../Constants")
local Add = require("./Add")
local Sub = require("./Sub")

-- ================================
--> OPTIMIAZTION FUNCTION CONSTANTS
-- ================================

local GetUpper: ({number}, number) -> {number} = Utils.GetUpper
local GetLower: ({number}, number) -> {number} = Utils.GetLower
local GetSlice: ({number}, number, number) -> {number} = Utils.GetSlice
local LeftShift: ({number}, number) -> {number} = Utils.LeftShift

local AddLimbs: ({number}, {number}, boolean?) -> {number} = Add.AddLimbs
local SubLimbs: ({number}, {number}, boolean?) -> {number} = Sub.SubLimbs

local max: (number, number) -> number = math.max
local min: (number, number) -> number = math.min

local tclone: ({number}) -> {number} = table.clone
local tcreate: (number, number) -> {number} = table.create
local tinsert: ({number}, number) -> () = table.insert

-- =================
--> NORMAL CONSTANTS
-- =================

local KARATSUBA_THRESHOLD: number = Constants.KARATSUBA_THRESHOLD
local TOOM3_THRESHOLD: number = Constants.TOOM3_THRESHOLD

local BASE: number = Constants.BASE

-- ==========
--> FUNCTIONS
-- ==========

function Mul.MulByInt(self: {number}, num: number): {number}
	local result: {number} = tclone(self)
	
	local carry: number = 0
	for i: number, limb: number in result do
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
	local result: {number} = tcreate(len, 0)

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

	Utils.StripLeadingZeros(result)
	return result
end

local function MulKaratsuba(x: {number}, y: {number}): {number}
	local m2: number = (max(#x, #y) + 1)//2

	local low1: {number}, low2: {number} = GetLower(x, m2), GetLower(y, m2)
	local high1: {number}, high2: {number} = GetUpper(x, m2), GetUpper(y, m2)

	local z0: {number} = Mul.MulLimbs(low1, low2)
	local z1: {number} = Mul.MulLimbs(AddLimbs(low1, high1, true), AddLimbs(low2, high2, true))
	local z2: {number} = Mul.MulLimbs(high1, high2)

	-- result = z0 + ((z1 - z2 - z0) << m2) + (z2 << 2*m2)
	-- => (z2 << m2 + (z1 - (z2 + z0))) << m2 + z0
	local result: {number} = LeftShift(z2, m2)
	
	SubLimbs(z1, AddLimbs(z2, z0, true), true)
	result = AddLimbs(result, z1, true)
	
	result = LeftShift(result, m2)
	AddLimbs(result, z0, true)
	
	return result
end


local function MulToom3(x: {number}, y: {number}): {number}
	local largest: number = max(#x, #y)

	local k: number = largest//3
	local r: number = largest*2//3

	--> get slices
	local x0: {number}, x1: {number} = GetSlice(x, 1, k), GetSlice(x, k+1, 2*k)
	local x2: {number} = GetSlice(x, 2*k+1, 2*k+r)

	local y0: {number}, y1: {number} = GetSlice(y, 1, k), GetSlice(y, k+1, 2*k)
	local y2: {number} = GetSlice(y, 2*k+1, 2*k+r)
	--print(#x0.limbs, #x1.limbs, #x2.limbs)
	--print(#y0.limbs, #y1.limbs, #y2.limbs)

	local v0: {number} = Mul.MulLimbs(x0, y0)
	local vinf: {number} = Mul.MulLimbs(x2, y2)
	
	local da1: {number} = AddLimbs(x2, x0)
	local db1: {number} = AddLimbs(y2, y0)
	local vm1: {number} = Mul.MulLimbs(SubLimbs(da1, x1), SubLimbs(db1, y1))
	
	da1 = AddLimbs(da1, x1, true)
	db1 = AddLimbs(db1, y1, true)

	local v1: {number} = Mul.MulLimbs(da1, db1)
	da1 = AddLimbs(da1, x2, true)
	db1 = AddLimbs(db1, y2, true)

	local v2: {number} = SubLimbs(AddLimbs(da1, da1, true), x0, true)
	v2 = Mul.MulLimbs(v2, SubLimbs(AddLimbs(db1, db1, true), y0, true))
	
	--> all divisions here are single-limb, so they are linear.
	v2 = Utils.DivByInt(SubLimbs(v2, vm1, true), 3)
	local tm1: {number} = Utils.DivByInt(SubLimbs(v1, vm1), 2)
	v1 = SubLimbs(v1, v0, true)
	
	v2 = Utils.DivByInt(SubLimbs(v2, v1, true), 2)
	v1 = SubLimbs(SubLimbs(v1, tm1, true), vinf, true)
	v2 = SubLimbs(v2, AddLimbs(vinf, vinf), true)
	tm1 = SubLimbs(tm1, v2, true)

	--> combine to get result
	local result: {number} = LeftShift(vinf, k)
	result = AddLimbs(result, v2, true); result = LeftShift(result, k)
	result = AddLimbs(result, v1, true); result = LeftShift(result, k)
	result = AddLimbs(result, tm1, true); result = LeftShift(result, k)
	result = AddLimbs(result, v0, true)

	return result
end

function Mul.MulLimbs(self: {number}, factor: {number}): {number}
	local factorLen: number = #factor
	local selfLen: number = #self
	
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

return Mul