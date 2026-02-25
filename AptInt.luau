--!optimize 2
--!native
--!strict

-- ===============================================================
--[[ 
-- AptInt.luau // fosterchild 2025 - Luau implementation of BigInteger, with added typechecking.
-- Licensed under The Unlicense.

-- Documentation and source can be found at: https://github.com/fosterchild1/AptInt/
--]]
-- ===============================================================

local AptInt = {}
AptInt.__index = AptInt

export type ValidConstructor = string | number | buffer | nil
export type ValidMetamethodArgument = string | number | AptInt

export type AptInt = setmetatable<{
	limbs: buffer,
	signum: number,

	read clone: (n: AptInt) -> AptInt,
	read Negate: (n: AptInt, inPlace: boolean?) -> AptInt,

	read AddRaw: (term: AptInt, term: AptInt, inPlace: boolean?) -> AptInt,
	read SubtractRaw: (term: AptInt, term: AptInt, inPlace: boolean?) -> AptInt,
	read MultiplyRaw: (factor: AptInt, factor: AptInt) -> AptInt,
	read DivideRaw: (dividend: AptInt, divisor: AptInt) -> (AptInt, AptInt),
	read ModRaw: (n: AptInt, div: AptInt) -> AptInt,
	read PowRaw: (n: AptInt, pow: AptInt) -> AptInt,
	read sqrt: (n: AptInt) -> AptInt,

	read EqualsRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerThanRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerOrEqualToRaw: (self: AptInt, num: AptInt) -> boolean,

	read LeftShift: (n: AptInt, n: number) -> AptInt,
	read RightShift: (n: AptInt, n: number) -> AptInt,
	
	read ToString: (n: AptInt) -> string,
	read ToNumber: (n: AptInt) -> number,
}, typeof(AptInt)>


-- ================================
--> OPTIMIAZTION FUNCTION CONSTANTS
-- ================================

local log10: (number) -> number = math.log10
local log: (number, number?) -> number = math.log
local floor: (number) -> number = math.floor
local ceil: (number) -> number = math.ceil
local max: (number, number) -> number = math.max
local min: (number, number) -> number = math.min
local abs: (number) -> number = math.abs
local sign: (number) -> number = math.sign

local tcreate: <V>(number, V) -> {V} = table.create
local tinsert: <V>({V}, V) -> () = table.insert
local tremove: ({number}, number?) -> number? = table.remove
local tconcat: <V>({V}, string?, number?, number?) -> string = table.concat
local tmove: ({number}, number, number, number, {number}?) -> {number} = table.move
local tclone: ({number}) -> {number} = table.clone

local bufcreate: (number) -> buffer = buffer.create
local bufwrite: (buffer, number, number) -> () = buffer.writef64
local bufread: (buffer, number) -> number = buffer.readf64
local bufcopy: (buffer, number, buffer, number?, number?) -> () = buffer.copy
local buflen: (buffer) -> number = buffer.len

local sformat: (string, ...unknown) -> string = string.format

-- =================
--> NORMAL CONSTANTS
-- =================

local KARATSUBA_THRESHOLD: number = 45 -- in limbs, limit where karatsuba is faster than normal multiplication
local SQRT_KARATSUBA_THRESHOLD: number = 32
local TOOM_THRESHOLD: number = 90
local BURNIKEL_THRESHOLD: number = 280
local MIN_BURNIKEL_OFFSET: number = 40
local MIN_MINADD_OFFSET: number = 20

local BASE_POW: number = 24 -- MUST SATISFY: 2^(BASE_POW*2) < 2^53, because of multiplyraw and divideraw
local BASE: number = 2^24 -- we use base 2^24 or else multiplication goes over 2^53
local BASE_MASK: number = 0xFFFFFF -- BASE - 1
local RADIX_CONST: number = 0.13841367062030677 -- log2(10)/BASE_POW

local TOSTRING_CHUNK_SIZE: number = 10^8

local AP_NEG_ONE: AptInt
local AP_ONE: AptInt
local AP_THREE: AptInt

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> (buffer, number)} = {
	["string"] = function(str: string): (buffer, number)
		local isNegative: boolean = str:sub(1, 1) == "-"
		if isNegative then
			str = str:sub(2, #str)
		end
		
		local convertedSize: number = max(ceil(#str * RADIX_CONST), 1)
		local buf: buffer = bufcreate(convertedSize * 8)
		
		--> convert from base 10 to base 2^k
		local bufIndex: number = 0
		while str ~= "0" do
			local carry: number = 0
			local out: {number} = {}

			for i: number = 1, #str do
				local digit: number = tonumber(str:sub(i, i)) or 0

				local p: number = carry * 10 + digit
				local q: number = p // BASE
				carry = p % BASE

				if #out == 0 and q == 0 then continue end
				tinsert(out, q)
			end

			bufwrite(buf, bufIndex, carry)
			bufIndex += 8 -- double = 8 bytes

			str = (#out > 0) and tconcat(out) or "0"
		end

		return buf, (isNegative and -1 or 1)
	end,

	["number"] = function(num: number): (buffer, number)
		local buf: buffer = bufcreate(8)
		if num == 0 then
			bufwrite(buf, 0, 0)
			return buf, 0
		elseif num == -1 then
			bufwrite(buf, 0, 1)
			return buf, -1
		end

		local actualSign: number = sign(num)
		num = abs(num)
		
		local convertedSize: number = max(ceil(log10(num) * RADIX_CONST), 1)
		local buf: buffer = bufcreate(convertedSize * 8)
		
		local bufIndex: number = 0
		while num > 0 do
			print(bufIndex, convertedSize * 8)
			bufwrite(buf, bufIndex, floor(num % BASE))
			num //= BASE
			bufIndex += 8 -- doubles are 8 bytes
		end

		return buf, actualSign
	end,

	["buffer"] = function(buf: buffer): (buffer, number)
		--> TODO: check if buf[0] is 0, then set signum to 0 and return bufcreate(8)
		return buf, 1
	end,

	["nil"] = function(_: nil): (buffer, number)
		return bufcreate(8), 0
	end,
}

-- ==================
--> PRIVATE FUNCTIONS
-- ==================

--> Strips the leading zeros from the limbs buffer. (eg. <code>[1, 3, 0, 0] -> [1, 3]</code>)
local function StripLeadingZeros(n: AptInt)
	local buf: buffer = n.limbs
	local offset: number = 0
	local len: number = buflen(buf)

	--> find the first non-zero limb
	while offset ~= len and bufread(buf, len-8-offset) == 0 do
		offset += 8
	end

	--> []
	if offset==buflen(buf) then
		n.signum = 0
		n.limbs = bufcreate(0)
		return
	end
	
	local newLimbs: buffer = bufcreate(len - offset)
	bufcopy(newLimbs, 0, buf, 0, len - offset)

	n.limbs = newLimbs
end

local function ArgumentToAptInt(num: ValidMetamethodArgument?, errContext: string): AptInt
	local bigint: AptInt;

	--> make sure toAdd is correct
	if getmetatable(num :: AptInt?) == AptInt then
		bigint = num :: AptInt
	else
		local numType: string = typeof(num)

		assert(
			typeConstructors[numType] ~= nil,
			`attempt to perform arithmetic ({errContext}) on AptInt and {numType}`
		)

		bigint = AptInt.new(num :: ValidConstructor)
	end

	return bigint
end

local function Div2InPlace(n: AptInt)
	local limbs: {number} = n.limbs
	local carry: number = 0
	
	for i: number = #limbs, 1, -1 do
		local x: number = limbs[i] + carry * BASE
		
		carry = x % 2
		limbs[i] = x // 2
	end
	
	StripLeadingZeros(n)
end


--> these functions esentially do the same thing. this is horrible code, but i dont wanna refactor it.

--> get lower n limbs
local function GetLower(int: AptInt, n: number): AptInt
	return AptInt.new(tmove(int.limbs, 1, n, 1, {}))
end

--> get upper n limbs
local function GetUpper(int: AptInt, n: number): AptInt
	return AptInt.new(tmove(int.limbs, n+1, #int.limbs, 1, {}))
end

--> get limbs from startIdx to endIdx
local function GetSlice(n: AptInt, startIdx: number, endIdx: number)
	return AptInt.new(tmove(n.limbs, startIdx, endIdx, 1, {}))
end

local function MinAdd(xLimbs: {number}, yLimbs: {number}, result: AptInt): AptInt
	--> since result has self's limbs, we can just iterate over y
	--> carry is 99.99% of times very small, so the while loop doesnt run much
	--> overall, runs in O(min(n, m)) time
	
	local rLimbs: {number} = result.limbs

	--> from right to left
	local carry: number = 0
	for i: number, yLimb: number in yLimbs do
		local sum: number = rLimbs[i] + yLimb + carry

		if sum >= BASE then
			carry = 1
			rLimbs[i] = sum - BASE
			continue
		end

		carry = 0
		rLimbs[i] = sum
	end
	
	if carry == 0 then return result end

	--> carry loop
	local resultIndex: number = #yLimbs
	while true do
		resultIndex += 1
		local sum: number = (rLimbs[resultIndex] or 0) + 1

		if sum >= BASE then
			rLimbs[resultIndex] = sum - BASE
			continue
		end

		rLimbs[resultIndex] = sum
		break
	end

	return result
end

local function MulKaratsuba(x: AptInt, y: AptInt): AptInt
	local m2: number = (max(#x.limbs, #y.limbs) + 1)//2

	local low1: AptInt, low2: AptInt = GetLower(x, m2), GetLower(y, m2)
	local high1: AptInt, high2: AptInt = GetUpper(x, m2), GetUpper(y, m2)

	local z0: AptInt = low1:MultiplyRaw(low2)
	local z1: AptInt = low1:AddRaw(high1, true):MultiplyRaw(low2:AddRaw(high2, true))
	local z2: AptInt = high1:MultiplyRaw(high2)

	-- result = z0 + ((z1 - z2 - z0) << m2) + (z2 << 2*m2)
	
	local result: AptInt = z2:LeftShift(2*m2)
		:AddRaw( 
			z1:SubtractRaw(z2:AddRaw(z0), true):LeftShift(m2)
		):AddRaw(z0, true)

	result.signum = x.signum * y.signum
	return result
end

local function MulToom3(x: AptInt, y: AptInt): AptInt
	local largest: number = max(#x.limbs, #y.limbs)
	
	local k: number = largest//3
	local r: number = largest*2//3
	
	-- get slices
	local x0: AptInt, x1: AptInt = GetSlice(x, 1, k), GetSlice(x, k+1, 2*k)
	local x2: AptInt = GetSlice(x, 2*k+1, 2*k+r)
	
	local y0: AptInt, y1: AptInt = GetSlice(y, 1, k), GetSlice(y, k+1, 2*k)
	local y2: AptInt = GetSlice(y, 2*k+1, 2*k+r)
	
	local v0: AptInt = x0:MultiplyRaw(y0)
	local da1: AptInt = x2:AddRaw(x0)
	local db1: AptInt = y2:AddRaw(y0)
	local vm1: AptInt = da1:SubtractRaw(x1):MultiplyRaw(db1:SubtractRaw(y1))
	
	da1:AddRaw(x1, true)
	db1:AddRaw(y1, true)
	
	local v1: AptInt = da1:MultiplyRaw(db1)
	da1:AddRaw(x2, true)
	db1:AddRaw(y2, true)
	
	local v2: AptInt = da1:AddRaw(da1, true):SubtractRaw(x0, true):MultiplyRaw(
		db1:AddRaw(db1, true):SubtractRaw(y0, true)
	)
	
	--> all divisions here are single-limb, so they are linear.
	local vinf: AptInt = x2:MultiplyRaw(y2)
	v2 = v2:SubtractRaw(vm1, true):DivideRaw(AP_THREE)
	local tm1: AptInt = v1:SubtractRaw(vm1); Div2InPlace(tm1)
	v1:SubtractRaw(v0, true)
	
	v2:SubtractRaw(v1, true); Div2InPlace(v2)
	v1:SubtractRaw(tm1, true):SubtractRaw(vinf, true)
	v2:SubtractRaw(vinf:AddRaw(vinf), true)
	tm1:SubtractRaw(v2, true)
	
	--> combine to get result
	local result: AptInt = vinf
		:LeftShift(k):AddRaw(v2)
		:LeftShift(k):AddRaw(v1)
		:LeftShift(k):AddRaw(tm1)
		:LeftShift(k):AddRaw(v0)

	result.signum = x.signum * y.signum
	return result
end

local function LowerThanAbsolute(x: AptInt, y: AptInt): boolean
	local xLimbs: buffer, yLimbs: buffer = x.limbs, y.limbs

	local xLen: number, yLen: number = buflen(xLimbs), buflen(yLimbs)
	if xLen < yLen then
		return true
	elseif yLen < xLen then
		return false
	end

	for i: number = xLen-8, 0, -8 do
		local xDigit: number, yDigit: number = bufread(xLimbs, i), bufread(yLimbs, i)
		if xDigit == yDigit then continue end

		return xDigit < yDigit
	end

	return false 
end

local function EqualsAbsolute(x: AptInt, y: AptInt): boolean
	local xLimbs: {number}, yLimbs: {number} = x.limbs, y.limbs

	if #xLimbs ~= #yLimbs then
		return false
	end

	for i: number, xLimb: number in xLimbs do
		if xLimb == yLimbs[i] then continue end

		return false
	end

	return true 
end

--> divsion stuff
local function CorrectRemainder(self: AptInt, divisor: AptInt, remainder: AptInt): AptInt
	local selfSign: number, divSign: number = self.signum, divisor.signum
	local sameSign: boolean = selfSign == divSign
	
	if sameSign and divSign == -1 then
		remainder.signum = -1
		return remainder
	elseif selfSign == 1 and divSign == -1 and remainder.signum ~= 0 then
		return divisor:AddRaw(remainder)
	elseif not sameSign and remainder.signum ~= 0 then -- selfsign -1, divsign 1
		remainder.signum = 1
		return divisor:SubtractRaw(remainder)
	end

	return remainder
end

--> KNUTHS
local function DivKnuths(self: AptInt, divisor: AptInt)
	--> d0. defs
	local U: {number}, V: {number} = self.limbs, divisor.limbs
	
	local n: number = #V
	local m: number = #U - n
	
	--> d1. normalize (get Vn and Un)
	local D: number = BASE // (V[n] + 1)
	local Dint: AptInt = AptInt.new({D})

	local Vn: {number} = divisor:MultiplyRaw(Dint).limbs
	local Un: AptInt = self:MultiplyRaw(Dint)
	local UnLimbs: {number} = Un.limbs

	local Vnn: number = Vn[n]
	local penultimateVn: number = Vn[n-1] or 0

	local quotient: AptInt = AptInt.new(tcreate(m + 1, 0))
	local qLimbs: {number} = quotient.limbs

	--> d2. init j
	local qhat: number, rhat: number = 0, 0
	for j: number = m, 0, -1 do
		--> d3. calculate qhat and rhat

		-- bigints for qhat and rhat are not needed, because un[x] is at most BASE
		-- currently, BASE * BASE + BASE < 2^53
		local nPlusJ: number = n + j + 1
		local top: number = (UnLimbs[nPlusJ] or 0) * BASE + (UnLimbs[nPlusJ - 1] or 0)
		qhat = top // Vnn
		rhat = top % Vnn

		if qhat == 0 then continue end

		--> first correction
		if qhat * penultimateVn > rhat * BASE + (UnLimbs[nPlusJ - 2] or 0) then
			qhat -= 1
			rhat += Vnn

			--> second correction
			if rhat < BASE and qhat * penultimateVn > rhat * BASE + (UnLimbs[nPlusJ - 2] or 0) then
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

			local diff: number = UnLimbs[i + j] - pDigit - borrow
			if diff < 0 then
				borrow = 1
				diff += BASE
			else
				borrow = 0
			end

			UnLimbs[i + j] = diff
		end

		local lastSub: number = (UnLimbs[nPlusJ] or 0) - carry - borrow
		UnLimbs[nPlusJ] = lastSub

		--> d6. add back
		if lastSub >= 0 then
			qLimbs[j + 1] = qhat
			continue
		end

		qLimbs[j + 1] = qhat - 1
		carry = 0

		for i: number = 1, n do
			local sum: number = UnLimbs[i + j] + Vn[i] + carry

			if sum >= BASE then
				carry = 1
				sum -= BASE
			else
				carry = 0
			end

			UnLimbs[i + j] = sum
		end

		UnLimbs[nPlusJ] = (UnLimbs[nPlusJ] + carry) % BASE
	end

	--> d8. unnormalize
	local carry: number = 0

	for i: number = #UnLimbs, 1, -1 do
		local x: number = carry * BASE + UnLimbs[i]

		carry = x % D 
		UnLimbs[i] = x // D
	end

	StripLeadingZeros(Un)
	StripLeadingZeros(quotient)
	
	return quotient, Un
end

--> BURNIKEL ZIEGLER
local function DivBZ3n2n(a1: AptInt, a2: AptInt, a3: AptInt, b1: AptInt, b2: AptInt): (AptInt, AptInt)
	--> Algorithm 2 from https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	local n: number = #b2.limbs
	
	local B: AptInt = b1:LeftShift(n):AddRaw(b2, true) -- [b1, b2]
	
	local q: AptInt, R: AptInt, D: AptInt
	if a1:LowerThanRaw(b1) then -- step 3a: a1 < b1
		local a1a2: AptInt = a1:LeftShift(n):AddRaw(a2, true)
		q, R = DivBZ2n1n(a1a2, b1)
		
		-- step 4: d = q * b2
		D = q:MultiplyRaw(b2)
	else -- step 3b: a1 >= b1
		q = AptInt.new(tcreate(n, BASE_MASK)) -- q = beta^n-1
		R = a1:SubtractRaw(b1, true):LeftShift(n):AddRaw(b1, true):AddRaw(a2, true) 
		-- ^ - [b1, 0] + [0, b1]
		
		-- step 4: D = (b2 << n) - b2
		D = b2:LeftShift(n):SubtractRaw(b2, true)
	end
	
	R = R:LeftShift(n):AddRaw(a3, true) -- paper says a4 but its actually a3

	--> q too large by atleast 1
	while R:LowerThanRaw(D) do
		q:SubtractRaw(AP_ONE, true)
		R:AddRaw(B, true)
	end

	R:SubtractRaw(D, true)
	return q, R
end

function DivBZ2n1n(A: AptInt, B: AptInt): (AptInt, AptInt)
	--> this function has to be global because of its use in DivBZ3n2n.
	--> Algorithm 1 from https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	local bLen: number = #B.limbs
	
	--> basecase
	if bLen % 2 == 1 or bLen < BURNIKEL_THRESHOLD then
		return DivKnuths(A, B)
	end
		
	local k: number = bLen/2
	
	--> get a1,a2,a3,a4 and b1,b2, where a=[a1,a2,a3,a4] and b=[b1,b2]
	local a1: AptInt, a2: AptInt = GetSlice(A, 3*k+1, 4*k), GetSlice(A, 2*k+1, 3*k)
	local a3: AptInt, a4: AptInt = GetSlice(A, k+1, 2*k), GetSlice(A, 1, k)
	local b1: AptInt, b2: AptInt = GetUpper(B, k), GetLower(B, k)
	
	--> get q1,R
	local q1: AptInt, r: AptInt = DivBZ3n2n(a1, a2, a3, b1, b2)
	local r1: AptInt, r2: AptInt = GetUpper(r, k), GetLower(r, k)
	local q2: AptInt, S: AptInt = DivBZ3n2n(r1, r2, a4, b1, b2)
	
	--> Q=[q1,q2]
	local Q: AptInt = q1:LeftShift(k):AddRaw(q2, true) -- Q = [q1,q2]
	return Q, S
end

local function DivBurnikelZiegler(A: AptInt, B: AptInt): (AptInt, AptInt)
	--> https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	--> https://github.com/leif-ibsen/BigInt/blob/master/Sources/BigInt/BurnikelZiegler.swift
	--> github.com/tbuktu/bigint/blob/master/src/main/java/java/math/MutableBigInteger.java#L1249
	
	--> this was a really horrible algorithm to implement. never again.
	
	--> 0. s = B length
	local s: number = #B.limbs
	
	--> 1. get m, j and n
	local m: number = 2^floor(log(s/BURNIKEL_THRESHOLD, 2) + 1)
	
	local j: number = ceil(s/m)
	local n: number = j * m
	
	--> 3. set sigma to normalize B and A, so that B[#B] >= BASE/2
	--> sigma is single-limb, so multiplication here is linear.
	local sigma: AptInt = AptInt.new({BASE // (B.limbs[s] + 1)})
	local shift: number = n-s
	
	local bShifted: AptInt, aShifted: AptInt = B:MultiplyRaw(sigma), A:MultiplyRaw(sigma)
	if shift > 0 then
		bShifted = bShifted:LeftShift(shift)
		aShifted = aShifted:LeftShift(shift)
	end
	
	local r: number = #aShifted.limbs
	s = #bShifted.limbs
	
	--> 5. calculate t: how many n-sized chunks are in A, t >= 2
	local t: number = max(ceil(r/n), 2)
	
	--> 6. z = [a[t-1], 0]. we add a[t-2] inside loop
	local z: AptInt = GetSlice(aShifted, (t-1)*n+1, r)
	
	--> 7. for i = t - 2, 1 do
	local quotient: AptInt = AptInt.new()
	quotient.limbs = {} -- so that the 1st leftshift doesnt offset it by 1
	for i: number = t-2, 0, -1 do
		--> get ai1
		local startIdx: number = i * n + 1
		local endIdx: number = (i + 1) * n
		local ai1: AptInt = GetSlice(aShifted, startIdx, endIdx)
		
		z = z:LeftShift(n):AddRaw(ai1, true)
		
		--> 8a. qi, ri
		local qi: AptInt, ri: AptInt = DivBZ2n1n(z, bShifted)
		quotient = quotient:AddRaw(qi:LeftShift(i * n), true)
		
		z = ri
	end
	
	StripLeadingZeros(quotient)
	z = z:DivideRaw(sigma)
	return quotient, z
end

--> SQRT STUFF
local function NewtonHeronSqrt(n: AptInt): AptInt
	local prev2: AptInt = AP_NEG_ONE:clone()
	local prev1: AptInt = AP_ONE:LeftShift((#n.limbs-1)//2) -- initial guess
	
	while true do
		local q: AptInt, _: AptInt = n:DivideRaw(prev1)
		local x1: AptInt = prev1:AddRaw(q); Div2InPlace(x1)

		local equals: boolean = EqualsAbsolute(x1, prev1)
		if equals then
			return x1
		end

		if EqualsAbsolute(x1, prev2) then
			return (LowerThanAbsolute(x1, prev1) and x1 or prev1) -- min(x1, prev1)
		end

		prev2, prev1 = prev1, x1
	end
end

local function KaratsubaSqrt(n: AptInt): (AptInt, AptInt)
	-- https://gmplib.org/manual/Square-Root-Algorithm
	-- https://en.wikipedia.org/wiki/Integer_square_root#Karatsuba_square_root_algorithm
	if n.signum ~= 1 then
		return AptInt.new(), AptInt.new()
	end
	
	--> needed here too
	local limbLen: number = #n.limbs
	if limbLen < SQRT_KARATSUBA_THRESHOLD then
		local sq = NewtonHeronSqrt(n)
		return sq, n:SubtractRaw(sq:MultiplyRaw(sq))
	end

	--> calculate a3, a1 and a0
	local m: number = limbLen//4
	local m2: number = m*2
	
	local a3a2: AptInt = GetUpper(n, m2) -- m2+1
	local a1: AptInt, a0: AptInt = GetSlice(n, m+1, m2), GetSlice(n, 1, m)
	
	local s1: AptInt, r1: AptInt = KaratsubaSqrt(a3a2)
	--local r1 = a3a2:SubtractRaw(s1:MultiplyRaw(s1))
	
	--> divrem (r1*b + a1, 2*s1)
	local q, u: AptInt = 
		r1:LeftShift(m):AddRaw(a1, true)
		:DivideRaw(s1:AddRaw(s1))
	
	-- s=s1*b+q
	-- r=u*b+a0-q^2
	local s: AptInt = s1:LeftShift(m):AddRaw(q, true)
	local r: AptInt = u:LeftShift(m):AddRaw(a0, true):SubtractRaw(q:MultiplyRaw(q), true)
	
	--> correct
	if r.signum == -1 then
		r = r:AddRaw(s:AddRaw(s), true):SubtractRaw(AP_ONE, true)
		s = s:SubtractRaw(AP_ONE, true)
	end
	
	return s, r
end

local function NegateRef(n: AptInt): AptInt
	return setmetatable({
		limbs = n.limbs,
		signum = -n.signum,
	}, AptInt) :: AptInt
end

-- ====================
--> METATABLE FUNCTIONS
-- ====================

-- Returns a new AptInt from the given argument.
function AptInt.new(num: ValidConstructor): AptInt
	local limbs: buffer, signum: number = typeConstructors[typeof(num)](num)

	return setmetatable({
		limbs = limbs,
		signum = signum
	}, AptInt) :: AptInt
end

--> this is ugly
AP_NEG_ONE = AptInt.new(-1)
AP_ONE = AptInt.new(1)
AP_THREE = AptInt.new(3)

-- Returns a copy of the AptInt.
function AptInt.clone(n: AptInt): AptInt
	local clonedLimbs: buffer = bufcreate(buflen(n.limbs))
	bufcopy(clonedLimbs, 0, n.limbs)
	
	return setmetatable({
		limbs = clonedLimbs,
		signum = n.signum
	}, AptInt) :: AptInt
end

-- Returns an AptInt with its sign flipped.
function AptInt:Negate(inPlace: boolean): AptInt
	if inPlace then
		self.signum = -self.signum
		return self :: AptInt
	end

	local result: AptInt = self:clone()
	result.signum = -result.signum

	return result
end

-- =====================
--> ARITHMETIC FUNCTIONS
-- =====================

-- Returns an AptInt equal to <code>a + b</code>.
function AptInt:AddRaw(term: AptInt, inPlace: boolean?): AptInt
	local selfSign: number, termSign: number = self.signum, term.signum
	
	--> CASES
	if termSign == 0 then
		return (inPlace and self or (self :: AptInt):clone())
	elseif selfSign == 0 then
		local clone: AptInt = term:clone()
		if inPlace then self = clone end
		
		return clone
	elseif selfSign == -1 and termSign == 1 then -- -a+b = b+(-a) = b-a
		return (NegateRef(self):SubtractRaw(term, inPlace)):Negate(true)
	elseif selfSign ~= termSign then -- +a+(-b)=a-b
		return self:SubtractRaw(NegateRef(term), inPlace)
	end

	local termLimbs: buffer, selfLimbs: buffer = term.limbs, self.limbs
	local termLen: number, selfLen: number = buflen(termLimbs), buflen(selfLimbs)
	
	--> choose the longer number to avoid extra "or 0" with selfDigit
	local result: AptInt
	if selfLen < termLen then
		result = term:clone()
		selfLimbs, termLimbs = termLimbs, selfLimbs
	else
		result = (inPlace and self or (self :: AptInt):clone())
	end
	
	--[[if abs(termLen - selfLen) > MIN_MINADD_OFFSET then
		return MinAdd(selfLimbs, termLimbs, result)
	end]]
	
	local termLen: number = buflen(term.limbs)
	local rLimbs: buffer = result.limbs
	
	--> from right to left
	local carry: number = 0
	--print(buflen(rLimbs)/8)
	for i: number = 0, buflen(rLimbs)-8, 8 do
		local sum: number = bufread(rLimbs, i) + (i < termLen and bufread(termLimbs, i) or 0) + carry

		if sum >= BASE then
			carry = 1
			bufwrite(rLimbs, i, sum - BASE)
			continue
		end

		carry = 0
		bufwrite(rLimbs, i, sum)
	end
	
	if carry > 0 then -- handle carry: reallocate to have 1 extra space and add carry
		local carryBuf: buffer = bufcreate(buflen(rLimbs) + 1)
		
		bufcopy(carryBuf, 0, rLimbs)
		bufwrite(carryBuf, buflen(rLimbs)-8, carry)		
		result.limbs = carryBuf
	end
	
	return result
end

-- Returns an AptInt equal to <code>a - b</code>.
function AptInt:SubtractRaw(term: AptInt, inPlace: boolean?): AptInt
	local selfSign: number, termSign: number = self.signum, term.signum
	
	--> CASES
	if termSign == 0 then -- b - 0 = 0
		return (inPlace and self or self:clone())
	elseif selfSign == 0 then -- 0 - b = -b
		local negate: AptInt = term:Negate()
		if inPlace then self = negate end
		
		return negate
	elseif termSign == -1 and selfSign == 1 then -- a-(-b) = a+b
		return NegateRef(term):AddRaw(self)
	elseif termSign == -1 and selfSign == -1 then -- (-a-(-b)) = b-a
		return (NegateRef(self):SubtractRaw(NegateRef(term), inPlace)):Negate(true)
	end
	
	if self:LowerThanRaw(term) then
		return term:SubtractRaw(self):Negate(true)
	end
	
	local result: AptInt = (inPlace and self or self:clone())
	local rLimbs: {number} = result.limbs
	
	local termLimbs: {number} = term.limbs
	--> from right to left
	local borrow: number = 0
	for i: number, digit: number in rLimbs do
		local diff: number = digit - (termLimbs[i] or 0) - borrow
		if diff < 0 then
			borrow = 1
			rLimbs[i] = diff + BASE
			continue
		end
		
		borrow = 0
		rLimbs[i] = diff
	end
	
	StripLeadingZeros(result)
	return result
end

-- Returns an AptInt equal to <code>a * b</code>.
function AptInt:MultiplyRaw(factor: AptInt): AptInt
	local selfSign: number, factorSign: number = self.signum, factor.signum

	--> CASES
	if selfSign == 0 or factorSign == 0 then
		return AptInt.new()
	end

	local selfLimbs: {number} = self.limbs
	local factorLimbs: {number} = factor.limbs
	local factorLen: number = #factorLimbs
	local selfLen: number = #selfLimbs

	--> single limb multiplication
	if factorLen == 1 then
		local mul: number = factorLimbs[1]

		local result: AptInt = self:clone()
		result.signum = selfSign * factorSign
		if mul == 1 then return result end

		local rLimbs: {number} = result.limbs

		local carry: number = 0
		for i: number, limb: number in selfLimbs do
			local p: number = limb * mul + carry

			if p > BASE then
				carry = p // BASE
				rLimbs[i] = p % BASE
				continue
			end

			carry = 0
			rLimbs[i] = p
		end

		if carry > 0 then
			tinsert(rLimbs, carry)
		end

		return result
	end
	
	if selfLen > TOOM_THRESHOLD and factorLen > TOOM_THRESHOLD then
		local result: AptInt = MulToom3(self, factor)
		StripLeadingZeros(result)
		return result
	elseif selfLen > KARATSUBA_THRESHOLD and factorLen > KARATSUBA_THRESHOLD then
		return MulKaratsuba(self, factor)
	end

	--> normal o(n^2) algorithm
	local len: number = selfLen + factorLen
	local result: AptInt = AptInt.new(tcreate(len, 0))
	local rLimbs: {number} = result.limbs
	
	local carry: number = 0
	factorLen -= 1
	for i: number = 1, len do
		local p: number = carry
		local iplus: number = i + 1
		
		for j: number = max(i - factorLen, 1), min(i, selfLen) do
			p += selfLimbs[j] * factorLimbs[iplus - j]
		end

		-- apply carry to current limb 
		if p >= BASE then 
			carry = p // BASE 
			rLimbs[i] = p % BASE
			continue
		end 
		
		carry = 0
		rLimbs[i] = p
	end
	
	StripLeadingZeros(result)
	result.signum = selfSign * factorSign
	return result
end

-- Returns the quotient and remainder of a / b.
function AptInt:DivideRaw(divisor: AptInt): (AptInt, AptInt)
	--> we use knuths algorithm D for division
	--> its a very lengthy and ugly algorithm

	local divSign: number, selfSign: number = divisor.signum, self.signum
	local sameSign: boolean = divSign == selfSign
	
	--> CASES
	if divSign == 0 or selfSign == 0 then -- dividing by 0
		return AptInt.new(), AptInt.new()
	elseif LowerThanAbsolute(self, divisor) then
		if selfSign == 1 and divSign == -1 then
			return AP_NEG_ONE:clone(), divisor:AddRaw(self)
		elseif selfSign == -1 and divSign == 1 then
			return AP_NEG_ONE:clone(), divisor:SubtractRaw(NegateRef(self))
		elseif sameSign and divSign == -1 then
			return AptInt.new(), (self :: AptInt):clone()
		end

		return AptInt.new(), (self :: AptInt):clone()
	elseif EqualsAbsolute(self, divisor) then -- -x/x = -1
		local div = AP_ONE:clone()
		div.signum = selfSign / divSign
		
		return div, AptInt.new()
	end

	local U: {number}, V: {number} = self.limbs, divisor.limbs

	--> single limb division
	if #V == 1 then
		local div: number = V[1]
		
		local quotient: AptInt = self:clone()
		quotient.signum = selfSign/divSign
		
		if div == 1 then
			return quotient, AptInt.new()
		end
		
		local qLimbs: {number} = quotient.limbs
		local carry: number = 0
		
		for i: number = #U, 1, -1 do
			local x: number = U[i] + carry * BASE
			local qDigit: number = x // div

			carry = x - qDigit * div
			qLimbs[i] = qDigit
		end
		
		StripLeadingZeros(quotient)
		if carry == 0 then
			return quotient, AptInt.new()
		end
		
		local remainder = CorrectRemainder(self, divisor, AptInt.new({carry}))
		return quotient, remainder
	end
	
	local quotient: AptInt, remainder: AptInt
	local diff = #U - #V
	if #V > BURNIKEL_THRESHOLD and #U > BURNIKEL_THRESHOLD and diff > MIN_BURNIKEL_OFFSET then
		quotient, remainder = DivBurnikelZiegler(self, divisor)
	else
		quotient, remainder = DivKnuths(self, divisor)
	end
	
	remainder = CorrectRemainder(self, divisor, remainder)
	quotient.signum = selfSign / divSign

	return quotient, remainder
end

-- Returns a new AptInt equal to <code>a % b</code>.
function AptInt:ModRaw(div: AptInt): AptInt
	local divLimbs: {number}, selfLimbs: {number} = div.limbs, self.limbs
	
	local selfSign: number, divSign: number = self.signum, div.signum

	local divFirst: number = divLimbs[1] * divSign
	local selfFirst: number = selfLimbs[1] * selfSign
	
	--> CASES
	if divSign == 0 or (#divLimbs == 1 and abs(divFirst) == 1) then
		return AptInt.new()
	elseif #selfLimbs == 1 and #divLimbs == 1 then
		return AptInt.new(selfFirst % divFirst)
	end

	local _: AptInt, r: AptInt = self:DivideRaw(div)
	return r
end

-- Returns a new AptInt equal to <code>a ^ b</code>.
function AptInt:PowRaw(pow: AptInt)
	local selfSign: number, powSign: number = self.signum, pow.signum
	local selfLimbs: {number}, powLimbs: {number} = self.limbs, pow.limbs
	--> CASES
	if powSign == 0 then
		return AP_ONE:clone()
	elseif selfSign == 0 or powSign == -1 then
		return AptInt.new()
	end

	if #powLimbs == 1 and powLimbs[1] == 1 then
		return self:clone()
	elseif #selfLimbs == 1 and selfLimbs[1] == 1 then
		return AP_ONE:clone()
	end
	
	local result: AptInt = AP_ONE:clone()
	local selfClone: AptInt = self:clone()

	--> single-limb exponentiation
	if #powLimbs == 1 then
		local n: number = powLimbs[1]
		while n > 0 do
			if n % 2 == 1 then
				result = selfClone:MultiplyRaw(result)
			end
			
			selfClone = selfClone:MultiplyRaw(selfClone)
			n //= 2
		end
		
		return result
	end

	--> exponentiation by squaring
	local powClone: AptInt = pow:clone()

	while powClone.signum == 1 do
		if powClone.limbs[1] % 2 == 1 then
			result = selfClone:MultiplyRaw(result)
		end

		selfClone = selfClone:MultiplyRaw(selfClone)
		Div2InPlace(powClone)
	end
	
	return result
end

-- Returns a new AptInt equal to <code>sqrt(n)</code>.
function AptInt:sqrt(): AptInt
	--> we compute the isqrt via Newton-Heron iteration for small numbers
	--> for big numbers, we use karatsuba square root algorithm

	if self.signum ~= 1 then
		return AptInt.new()
	end
	
	if #(self :: AptInt).limbs >= SQRT_KARATSUBA_THRESHOLD then
		local s, _ = KaratsubaSqrt(self)
		return s
	end
	
	return NewtonHeronSqrt(self)
end

-- ==================
--> QoL FUNCTIONS
-- ==================

-- Returns a new string representation of an AptInt
function AptInt:ToString(): string
	if self.signum == 0 then
		return "0"
	end
	
	--> we convert from base 2^k to base 10 in chunks of 8 digits
	--> 8 = max {k | 2^24 * 10^k < 2^53}
	local clone: AptInt = self:clone()
	local limbs: buffer = clone.limbs
	
	local chunkAmount: number = ceil(buflen(limbs) * log10(BASE) / floor(log10(TOSTRING_CHUNK_SIZE)))
	local chunks: {string} = tcreate(chunkAmount, "")
	
	local chunkIdx: number = chunkAmount
	local a = 0
	while buflen(limbs) > 0 do
		local carry: number = 0
		for i: number = buflen(limbs)-8, 0, -8 do
			local val: number = bufread(limbs, i) + carry * BASE
			
			carry = val % TOSTRING_CHUNK_SIZE
			bufwrite(limbs, i, val // TOSTRING_CHUNK_SIZE)
		end
		
		--> we write in reverse order
		chunks[chunkIdx] = sformat("%08d", carry)
		chunkIdx -= 1
		
		StripLeadingZeros(clone)
		limbs = clone.limbs
	end
	
	local str: string = tconcat(chunks):gsub("^0+", "") -- removes leading zeros, fast
	return self.signum == -1 and `-{str}` or str
end


-- Returns a double equal to <code>tonumber(x)</code>
function AptInt:ToNumber(): number
	return tonumber(self:ToString()) :: number -- faster than doing math.log10 stuff and blablabla
end

-- ==================
--> COMPARISON FUNCTIONS
-- ==================

-- Returns true if <code>self == num</code>.
function AptInt:EqualsRaw(num: AptInt): boolean
	if self.signum ~= num.signum then
		return false
	end

	return EqualsAbsolute(self, num)
end

-- Returns true if <code>self < num</code>.
function AptInt:LowerThanRaw(num: AptInt): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	
	--> check sign
	if selfSign < numSign then
		return true
	end

	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	if bothNegative then
		return LowerThanAbsolute(num, self)
	end
	
	return LowerThanAbsolute(self, num)
end

-- Returns true if <code>self <= num</code>.
function AptInt:LowerOrEqualToRaw(num: AptInt): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	local selfLen: number, numLen: number = #self.limbs, #num.limbs

	--> check sign
	if selfSign <= numSign then
		return true
	end

	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	--> check their lengths. for negative, the lowest is with the most limbs, and for positive its the lowest
	if bothNegative and selfLen >= numLen then
		return true
	elseif selfLen <= numLen then -- both positive
		return true
	end

	local selfLimbs: {number}, numlimbs: {number} = self.limbs, num.limbs
	if bothNegative then
		selfLimbs, numlimbs = numlimbs, selfLimbs
	end
	
	for i: number = #selfLimbs, 1, -1 do
		local sDigit: number, nDigit: number = selfLimbs[i], numlimbs[i] or 0
		if sDigit == nDigit then continue end
		return sDigit <= nDigit
	end

	return true 
end

-- ==================
--> OTHER FUNCTIONS
-- ==================

-- Returns a new AptInt equal to <code>n * BASE<sup>n</sup></code>
function AptInt:LeftShift(n: number): AptInt
	-- this is the fastest way to leftshift
	return AptInt.new(tmove(self.limbs, 1, #self.limbs, n+1, tcreate(n, 0)))
end

-- Returns a new AptInt equal to <code>n // 10<sup>(BASE * amount)</sup></code>
function AptInt:RightShift(n: number): AptInt
	local result: AptInt = self:clone()

	local tbl: {number} = result.limbs

	for i: number = 1, n do
		tremove(tbl, 1)
	end

	return result
end

-- ============
--> METAMETHODS
-- ============

AptInt.__unm = AptInt.Negate
AptInt.__tostring = AptInt.ToString

AptInt.__add = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "add")
	local term2: AptInt = ArgumentToAptInt(b, "add")

	return term1:AddRaw(term2)
end

AptInt.__sub = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "sub")
	local term2: AptInt = ArgumentToAptInt(b, "sub")

	return term1:SubtractRaw(term2)
end

AptInt.__mul = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "mul")
	local term2: AptInt = ArgumentToAptInt(b, "mul")

	return term1:MultiplyRaw(term2)
end

local function divMeta(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "div")
	local term2: AptInt = ArgumentToAptInt(b, "div")

	local quotient: AptInt, _: AptInt = term1:DivideRaw(term2)
	return quotient
end
AptInt.__div, AptInt.__idiv = divMeta, divMeta

AptInt.__mod = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "mod")
	local term2: AptInt = ArgumentToAptInt(b, "mod")

	return term1:ModRaw(term2)
end

AptInt.__pow = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): AptInt
	local term1: AptInt = ArgumentToAptInt(a, "pow")
	local term2: AptInt = ArgumentToAptInt(b, "pow")

	return term1:PowRaw(term2)
end

AptInt.__eq = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "eq")
	local term2: AptInt = ArgumentToAptInt(b, "eq")

	return term1:EqualsRaw(term2)
end

AptInt.__lt = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "lt")
	local term2: AptInt = ArgumentToAptInt(b, "lt")

	return term1:LowerThanRaw(term2)
end

AptInt.__le = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: AptInt = ArgumentToAptInt(a, "le")
	local term2: AptInt = ArgumentToAptInt(b, "le")

	return term1:LowerOrEqualToRaw(term2)
end

AptInt.__len = function(n: AptInt): number
	return #n.limbs
end

-- ===========
--> EXTENSIONS
-- ===========

function AptInt.Extend(func: (typeof(AptInt)) -> ())
	func(AptInt)
end

return AptInt
