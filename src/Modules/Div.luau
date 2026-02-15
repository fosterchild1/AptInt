--!native
--!strict
--!optimize 2

local Div = {}

local Utils = require("./Utils")
local Constants = require("../Constants")
local Mul = require("./Mul")
local Add = require("./Add")
local Sub = require("./Sub")
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

local max: (number, number) -> number = math.max
local ceil: (number) -> number = math.ceil
local log: (number, number) -> number = math.log
local floor: (number) -> number = math.floor

local tclone: ({number}) -> {number} = table.clone
local tcreate: (number, number) -> {number} = table.create

-- =================
--> NORMAL CONSTANTS
-- =================

local BURNIKEL_THRESHOLD: number = Constants.BURNIKEL_THRESHOLD
local MIN_BURNIKEL_OFFSET: number = Constants.MIN_BURNIKEL_OFFSET

local BASE: number = Constants.BASE
local BASE_MASK: number = Constants.BASE_MASK

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
	
	return quotient, Un
end

--> BURNIKEL ZIEGLER
local function DivBZ3n2n(a1: {number}, a2: {number}, a3: {number}, b1: {number}, b2: {number}): 
	({number}, {number})
	
	--> Algorithm 2 from https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	local n: number = #b2

	local B: {number} = AddLimbs(LeftShift(b1, n), b2, true) -- [b1, b2]

	local q: {number}, R: {number}, D: {number}
	if Cmp.LowerThan(a1, b1) then -- step 3a: a1 < b1
		local a1a2: {number} = AddLimbs(LeftShift(a1, n), a2, true)
		q, R = DivBZ2n1n(a1a2, b1)

		-- step 4: d = q * b2
		D = Mul.MulLimbs(q, b2)
	else -- step 3b: a1 >= b1
		q = tcreate(n, BASE_MASK) -- q = beta^n-1
		
		R = LeftShift(SubLimbs(a1, b1, true), n) -- [a1, 0] - [b1, 0]
		R = AddLimbs(AddLimbs(R, a1, true), a2, true) -- [0, a2] + [0, b1]

		-- step 4: D = (b2 << n) - b2
		D = SubLimbs(LeftShift(b2, n), b2, true)
	end

	R = AddLimbs(LeftShift(R, n), a3, true) -- paper says a4 but its actually a3

	--> q too large by atleast 1
	while Cmp.LowerThan(R, D) do
		SubLimbs(q, {1}, true)
		AddLimbs(R, B, true)
	end

	SubLimbs(R, D, true)
	return q, R
end

function DivBZ2n1n(A: {number}, B: {number}): ({number}, {number})
	--> this function has to be global because of its use in DivBZ3n2n.
	--> Algorithm 1 from https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	local bLen: number = #B

	--> basecase
	if bLen % 2 == 1 or bLen < BURNIKEL_THRESHOLD then
		return DivKnuths(A, B)
	end

	local k: number = bLen/2

	--> get a1,a2,a3,a4 and b1,b2, where a=[a1,a2,a3,a4] and b=[b1,b2]
	local a1: {number}, a2: {number} = GetSlice(A, 3*k+1, 4*k), GetSlice(A, 2*k+1, 3*k)
	local a3: {number}, a4: {number} = GetSlice(A, k+1, 2*k), GetSlice(A, 1, k)
	local b1: {number}, b2: {number} = GetUpper(B, k), GetLower(B, k)

	--> get q1,R
	local q1: {number}, r: {number} = DivBZ3n2n(a1, a2, a3, b1, b2)
	local r1: {number}, r2: {number} = GetUpper(r, k), GetLower(r, k)
	local q2: {number}, S: {number} = DivBZ3n2n(r1, r2, a4, b1, b2)

	--> Q=[q1,q2]
	local Q: {number} = AddLimbs(LeftShift(q1, k), q2, true) -- Q = [q1,q2]
	return Q, S
end

local function DivBurnikelZiegler(A: {number}, B: {number}): ({number}, {number})
	--> https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	--> https://github.com/leif-ibsen/BigInt/blob/master/Sources/BigInt/BurnikelZiegler.swift
	--> github.com/tbuktu/bigint/blob/master/src/main/java/java/math/MutableBigInteger.java#L1249

	--> this was a really horrible algorithm to implement. never again.

	--> 0. s = B length
	local s: number = #B

	--> 1. get m, j and n
	local m: number = 2^floor(log(s/BURNIKEL_THRESHOLD, 2) + 1)

	local j: number = ceil(s/m)
	local n: number = j * m

	--> 3. set sigma to normalize B and A, so that B[#B] >= BASE/2
	--> sigma is single-limb, so multiplication here is linear.
	local sigma: number = BASE // (B[s] + 1)
	local shift: number = n-s

	local bShifted: {number}, aShifted: {number} = Mul.MulByInt(B, sigma), Mul.MulByInt(A, sigma)
	if shift > 0 then
		bShifted = LeftShift(bShifted, shift)
		aShifted = LeftShift(aShifted, shift)
	end

	local r: number = #aShifted
	s = #bShifted

	--> 5. calculate t: how many n-sized chunks are in A, t >= 2
	local t: number = max(ceil(r/n), 2)

	--> 6. z = [a[t-1], 0]. we add a[t-2] inside loop
	local z: {number} = GetSlice(aShifted, (t-1)*n+1, r)

	--> 7. for i = t - 2, 1 do
	local quotient: {number} = {}
	for i: number = t-2, 0, -1 do
		--> get ai1
		local startIdx: number = i * n + 1
		local endIdx: number = (i + 1) * n
		local ai1: {number} = GetSlice(aShifted, startIdx, endIdx)

		z = AddLimbs(LeftShift(z, n), ai1, true)

		--> 8a. qi, ri
		local qi: {number}, ri: {number} = DivBZ2n1n(z, bShifted)
		quotient = AddLimbs(quotient, LeftShift(qi, i*n), true)

		z = ri
	end

	z = Utils.DivByInt(z, sigma)
	return quotient, z
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
	
	Utils.StripLeadingZeros(quotient)
	return quotient, remainder :: {number}
end

return Div