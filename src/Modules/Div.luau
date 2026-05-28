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

const ReturnAlloc = Utils.ReturnAlloc
const GetUpper = Utils.GetUpper
const GetLower = Utils.GetLower
const GetSlice = Utils.GetSlice
const LeftShift = Utils.LeftShift

const AddLimbs = Add.AddLimbs
const SubLimbs = Sub.SubLimbs

const max: (number, number) -> number = math.max
const ceil: (number) -> number = math.ceil
const log: (number, number) -> number = math.log
const floor: (number) -> number = math.floor

const tclone: ({number}) -> {number} = table.clone
const tcreate: (number, number?) -> {number} = table.create
const tmove: ({number}, number, number, number, {number}) -> {number} = table.move
local tclear: ({number}) -> () = table.clear

-- =================
--> NORMAL CONSTANTS
-- =================

const BURNIKEL_THRESHOLD: number = Constants.BURNIKEL_THRESHOLD
const MIN_BURNIKEL_OFFSET: number = Constants.MIN_BURNIKEL_OFFSET

const BASE: number = Constants.BASE
const BASE_MASK: number = Constants.BASE_MASK

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

	local quotient: {number} = Utils.GetAlloc(m + 1)

	--> pad Un up to its max potential length
	--> avoids (un[nPlusJ] or 0). no table.move cause its slower
	for i: number = #Un + 1, m + n + 1 do
		Un[i] = 0
	end

	--> d2. init j
	local qhat: number, rhat: number = 0, 0
	for j: number = m, 0, -1 do
		--> d3. calculate qhat and rhat
		local nPlusJ: number = n + j + 1
		local top: number = Un[nPlusJ] * BASE + Un[nPlusJ - 1]
		qhat = top // Vnn
		rhat = top % Vnn

		--> first correction
		if qhat * penultimateVn > rhat * BASE + Un[nPlusJ - 2] then
			qhat -= 1
			rhat += Vnn

			--> second correction
			if rhat < BASE and qhat * penultimateVn > rhat * BASE + Un[nPlusJ - 2] then
				qhat -= 1
			end
		end

		if qhat == 0 then 
			quotient[j + 1] = 0
			continue 
		end

		--> d4. multiply & subtract
		--> wtf
		local k: number = 0
		for i: number = 1, n do
			local exact: number = Un[i + j] - qhat * Vn[i] + k
			k = exact // BASE

			Un[i + j] = exact - k * BASE
		end

		local lastSub: number = Un[nPlusJ] + k 
		Un[nPlusJ] = lastSub

		--> d6. add back
		if lastSub >= 0 then
			quotient[j + 1] = qhat
			continue
		end

		quotient[j + 1] = qhat - 1

		local carry: number = 0
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

	local q: {number}, R: {number}, D: {number}
	if Cmp.LowerThan(a1, b1) then -- step 3a: a1 < b1
		local a1a2: {number} = AddLimbs(LeftShift(a1, n), a2, true)
		q, R = DivBZ2n1n(a1a2, b1, true)

		-- step 4: d = q * b2
		if #q == 0 then
			D = {}
		else
			D = Mul.MulLimbs(q, b2)
		end
	else -- step 3b: a1 >= b1
		q = tcreate(n, BASE_MASK) -- q = beta^n-1

		R = LeftShift(SubLimbs(a1, b1, true), n) -- [a1, 0] - [b1, 0]
		R = AddLimbs(AddLimbs(R, b1, true), a2, true) -- [0, a2] + [0, b1]

		-- step 4: D = (b2 << n) - b2
		D = SubLimbs(LeftShift(b2, n), b2, true)
	end

	AddLimbs(LeftShift(R, n, true), a3, true) -- paper says a4 but its actually a3
	
	--> only do B = if R<D. comparison runs twice but comparison never was slow
	if Cmp.LowerThan(R, D) then
		local B: {number} = AddLimbs(LeftShift(b1, n), b2, true) -- [b1, b2]
		
		while Cmp.LowerThan(R, D) do
			Sub.SubByInt(q, 1, true)
			AddLimbs(R, B, true)
		end
	end
	
	SubLimbs(R, D, true)
	return q, R
end

function DivBZ2n1n(A: {number}, B: {number}, noRet: boolean?): ({number}, {number})
	--> this function has to be global because of its use in DivBZ3n2n.
	--> Algorithm 1 from https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content

	--> NOT REUSED: a4, b1, b2
	local bLen: number = #B
	
	--> basecase
	if bLen % 2 == 1 or bLen < BURNIKEL_THRESHOLD then
		local q: {number}, r: {number} = DivKnuths(A, B)
		Utils.StripLeadingZeros(q)
		return q, r
	end

	local k: number = bLen//2

	--> get a1,a2,a3,a4 and b1,b2, where a=[a1,a2,a3,a4] and b=[b1,b2]
	local a1: {number}, a2: {number} = GetSlice(A, 3*k+1, 4*k), GetSlice(A, 2*k+1, 3*k)
	local a3: {number} = GetSlice(A, k+1, 2*k)
	local b1: {number}, b2: {number} = GetUpper(B, k), GetLower(B, k)

	--> get q1,R
	local q1: {number}, r: {number} = DivBZ3n2n(a1, a2, a3, b1, b2)
	
	--ReturnAlloc(a2); ReturnAlloc(a3) -- r1 & r2 takes a2 & a3's place
	local r1: {number}, r2: {number} = GetUpper(r, k), GetLower(r, k)
	local a4: {number} = GetLower(A, k)
	local q2: {number}, S: {number} = DivBZ3n2n(r1, r2, a4, b1, b2)

	--> Q=[q1,q2]
	local Q: {number} = AddLimbs(LeftShift(q1, k, true), q2, true) -- Q = [q1,q2]

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
		bShifted = LeftShift(bShifted, shift, true)
		aShifted = LeftShift(aShifted, shift, true)
	end

	local r: number = #aShifted
	s = #bShifted

	--> 5. calculate t: how many n-sized chunks are in A, t >= 2
	local t: number = max(ceil(r/n), 2)

	--> 6. calculate z
	local zHi: {number} = GetSlice(aShifted, (t - 1) * n + 1, t * n)
	local zLo: {number} = GetSlice(aShifted, (t - 2) * n + 1, (t - 1) * n)
	local z: {number} = AddLimbs(LeftShift(zHi, n, true), zLo, true)

	--> 7. for i = t - 2, 1 do
	local quotient: {number} = {}
	for i: number = t-2, 1, -1 do
		--> 8a. qi, ri
		local qi: {number}, ri: {number} = DivBZ2n1n(z, bShifted)
		quotient = AddLimbs(quotient, LeftShift(qi, i*n, true), true)
		
		--> get ai1
		local startIdx: number = (i- 1) * n + 1
		local endIdx: number = i * n
		local ai1: {number} = GetSlice(aShifted, startIdx, endIdx)

		z = AddLimbs(LeftShift(ri, n, true), ai1, true)
	end
	
	local qi: {number}, ri: {number} = DivBZ2n1n(z, bShifted)
	quotient = AddLimbs(quotient, qi, true)
	z = ri
	
	--> undo shifts from step 3
	Utils.DivByInt(z, sigma, true)
	
	if shift > 0 then
		local len: number = #z
		
		if len > shift then
			tmove(z, shift + 1, len, 1, z)
			for i: number = len - shift + 1, len do
				z[i] = nil
			end
		elseif len > 0 then
			tclear(z)
		end
	end
	
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
	return quotient, remainder
end

return table.freeze(Div)