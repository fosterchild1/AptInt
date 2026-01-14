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

export type ValidConstructor = string | number | {number} | nil
export type ValidMetamethodArgument = string | number | AptInt

export type AptInt = setmetatable<{
	limbs: {number},
	signum: number,

	read clone: (n: AptInt) -> AptInt,

	read Negate: (n: AptInt, inPlace: boolean?) -> AptInt,

	read LeftShift: (n: AptInt, amount: number) -> AptInt,
	read RightShift: (n: AptInt, amount: number) -> AptInt,

	read AddRaw: (term: AptInt, term: AptInt, inPlace: boolean?) -> AptInt,
	read SubtractRaw: (term: AptInt, term: AptInt, inPlace: boolean?) -> AptInt,
	read MultiplyRaw: (factor: AptInt, factor: AptInt, inPlace: boolean?) -> AptInt,
	read DivideRaw: (dividend: AptInt, divisor: AptInt, inPlace: boolean?) -> (AptInt, AptInt),
	read ModRaw: (n: AptInt, div: AptInt) -> AptInt,
	read PowRaw: (n: AptInt, pow: AptInt) -> AptInt,
	read sqrt: (n: AptInt) -> AptInt,

	read EqualsRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerThanRaw: (self: AptInt, num: AptInt) -> boolean,
	read LowerOrEqualToRaw: (self: AptInt, num: AptInt) -> boolean,

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
local max: (...number) -> number = math.max
local min: (...number) -> number = math.min
local abs: (number) -> number = math.abs
local sign: (number) -> number = math.sign

local bband: (number, number) -> number = bit32.band
local brshift: (number, number) -> number = bit32.rshift

local tcreate: <V>(number, V?) -> {V} = table.create
local tinsert: <V>({V}, V) -> () & <V>({V}, number, V) -> () = table.insert
local tremove: <V>({V}, number?) -> V? = table.remove
local tconcat: <V>({V}, string?, number?, number?) ->string = table.concat
local tmove: <V>({V}, number, number, number, {V}?) -> {V} = table.move
local tclone: <T>({T}) -> {T} = table.clone

local sformat: (string, ...unknown) -> string = string.format

-- =================
--> NORMAL CONSTANTS
-- =================

local KARATSUBA_THRESHOLD: number = 45 -- in limbs, limit where karatsuba is faster than normal multiplication
local SQRT_KARATSUBA_THRESHOLD: number = 32
local TOOM_THRESHOLD: number = 90
local BURNIKEL_THRESHOLD: number = 16

local BASE_POW: number = 7 -- MUST SATISFY: 10^(BASE_POW*2) < 2^53, because of multiplyraw and divideraw
local BASE: number = 10 ^ BASE_POW

local AP_NEG_ONE: AptInt
local AP_ZERO: AptInt
local AP_ONE: AptInt
local AP_TWO: AptInt
local AP_THREE: AptInt

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> ({number}, number)} = {
	["string"] = function(str: string): ({number}, number)
		local isNegative: boolean = str:sub(1, 1) == "-"
		local strStart: number = isNegative and 2 or 1

		local i: number = #str
		local arr: {number} = {}

		repeat
			local chars: string = str:sub(max(i - BASE_POW + 1, strStart), i)
			local num: number? = tonumber(chars)
			if not num then break end

			i -= BASE_POW
			tinsert(arr, num)
		until i < strStart

		return arr, (isNegative and -1 or 1)
	end,

	["number"] = function(num: number): ({number}, number)
		if num == 0 then
			return {0}, 0
		elseif num == -1 then
			return {1}, -1
		end

		local actualSign: number = sign(num)
		num = abs(num)

		local arr: {number} = {}
		while num > 0 do
			tinsert(arr, floor(num % BASE))
			num //= BASE
		end

		return arr, actualSign
	end,

	["table"] = function(tbl: {any}): ({number}, number)	
		local first: number = tbl[1]
		if not first then
			return {0}, 0
		end
		
		return tbl, 1
	end,

	["nil"] = function(_: nil): ({number}, number)
		return {0}, 0
	end,
}

-- =================
--> HELPER FUNCTIONS
-- =================

local function StripLeadingZeros(n: AptInt)
	local limbs: {number} = n.limbs
	while true do
		local limbLen: number = #limbs
		if limbLen == 1 or limbs[limbLen] ~= 0 then break end

		limbs[limbLen] = nil
	end

	if #limbs == 1 and limbs[#limbs] == 0 then
		n.signum = 0
	end
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
			`attempt to perform ({errContext}) on AptInt and {numType}`
		)

		bigint = AptInt.new(num :: ValidConstructor)
	end

	return bigint
end

--> these functions esentially do the same thing. this is horrible code, but i dont wanna refactor it.

--> get highest n limbs
local function GetLower(int: AptInt, n: number): AptInt
	return AptInt.new(tmove(int.limbs, 1, n, 1, {}))
end

--> get lowest n limsb
local function GetUpper(int: AptInt, n: number): AptInt
	return AptInt.new(tmove(int.limbs, n+1, #int.limbs, 1, {}))
end

--> get limbs from startIdx to endIdx
local function GetSlice(n: AptInt, startIdx: number, endIdx: number)
	return AptInt.new(tmove(n.limbs, startIdx, endIdx, 1, {}))
end

--> Used in Burnikel-Ziegler division
local function GetBlock(A: AptInt, blockIdx: number, n: number): AptInt
	local startIdx: number = blockIdx * n + 1
	local endIdx: number = min((blockIdx + 1) * n, #A.limbs)
	
	if startIdx > #A.limbs then
		return AptInt.new()
	end

	return AptInt.new(tmove(A.limbs, startIdx, endIdx, 1, {}))
end

local function MultiplyKaratsuba(x: AptInt, y: AptInt): AptInt
	local m2: number = (max(#x.limbs, #y.limbs) + 1)//2

	local low1: AptInt, low2: AptInt = GetLower(x, m2), GetLower(y, m2)
	local high1: AptInt, high2: AptInt = GetUpper(x, m2), GetUpper(y, m2)

	local z0: AptInt = low1:MultiplyRaw(low2)
	local z1: AptInt = low1:AddRaw(high1):MultiplyRaw(low2:AddRaw(high2, true))
	local z2: AptInt = high1:MultiplyRaw(high2)

	-- (z2 × BASE ^ (m2 × 2)) + ((z1 - z2 - z0) × BASE ^ m2) + z0
	-- since base is a power of 10, we can just prepend zeros to avoid slow exponentiation
	-- => z0 + ((z1 - z2 - z0) << m2) + (z2 << m2 * 2)

	local result = z2:LeftShift(m2 * 2)
		:AddRaw(
			z1:SubtractRaw(z2:AddRaw(z0, true), true):LeftShift(m2), true
		)
		:AddRaw(z0, true)

	if x.signum ~= y.signum then
		return result:Negate(true)
	end

	return result
end

local function MultiplyToomCook3(x: AptInt, y: AptInt): AptInt
	local largest: number = max(#x.limbs, #y.limbs)
	
	local k: number = largest//3
	local r: number = largest*2//3
	
	-- get slices
	local x0: AptInt, x1: AptInt = GetSlice(x, 1, k), GetSlice(x, k+1, r)
	local x2: AptInt = GetSlice(x, r+1, largest)
	
	local y0: AptInt, y1: AptInt = GetSlice(y, 1, k), GetSlice(y, k+1, r)
	local y2: AptInt = GetSlice(y, r+1, largest)
	
	local v0: AptInt = x0:MultiplyRaw(y0)
	local da1: AptInt = x2:AddRaw(x0)
	local db1: AptInt = y2:AddRaw(y0)
	local vm1: AptInt = da1:SubtractRaw(x1):MultiplyRaw(db1:SubtractRaw(y1))
	
	da1 = da1:AddRaw(x1, true)
	db1 = db1:AddRaw(y1, true)
	
	local v1: AptInt = da1:MultiplyRaw(db1)
	da1 = da1:AddRaw(x2, true)
	db1 = db1:AddRaw(y2, true)
	
	local v2: AptInt = da1:AddRaw(da1, true):SubtractRaw(x0, true):MultiplyRaw(
		db1:AddRaw(db1, true):SubtractRaw(y0, true), true
	)
	
	--> all divisions here are single-limb, so they are linear.
	local vinf: AptInt = x2:MultiplyRaw(y2)
	v2:SubtractRaw(vm1, true):DivideRaw(AP_THREE, true)
	local tm1: AptInt = v1:SubtractRaw(vm1):DivideRaw(AP_TWO, true)
	v1:SubtractRaw(v0, true)
	
	v2:SubtractRaw(v1, true):DivideRaw(AP_TWO, true) 
	v1:SubtractRaw(tm1, true):SubtractRaw(vinf, true)
	v2:SubtractRaw(vinf:AddRaw(vinf), true)
	tm1:SubtractRaw(v2, true)
	
	local result: AptInt = vinf
		:LeftShift(k):AddRaw(v2, true)
		:LeftShift(k):AddRaw(v1, true)
		:LeftShift(k):AddRaw(tm1, true)
		:LeftShift(k):AddRaw(v0, true)
	
	if x.signum ~= y.signum then
		return result:Negate(true)
	end
	
	return result
end

local function LowerThanAbsolute(x: AptInt, y: AptInt): boolean
	local xLimbs: {number}, yLimbs: {number} = x.limbs, y.limbs

	local xLen: number, yLen: number = #xLimbs, #yLimbs
	if xLen < yLen then
		return true
	elseif yLen < xLen then
		return false
	end

	for i: number = xLen, 1, -1 do
		local xDigit: number, yDigit: number = xLimbs[i], yLimbs[i]
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
	
	local a1a2: AptInt = a1:LeftShift(#a2.limbs):AddRaw(a2)
	
	local q: AptInt, r1: AptInt, D: AptInt
	if a1:LowerThanRaw(b1) then -- step 3a: a1 < b1
		q, r1 = DivBZ2n1n(a1a2, b1)
		
		-- step 4: d = q * b2
		D = q:MultiplyRaw(b2)
	else -- step 3b: a1 >= b1
		q = AptInt.new(tcreate(n, BASE-1)) -- q = beta^n-1
		r1 = a1a2:SubtractRaw(b1:LeftShift(n)):AddRaw(b1) -- - [b1, 0] + [0, b1]
		
		-- step 4: D = (b2 << n) - b2
		D = b2:LeftShift(n):SubtractRaw(b2)
	end
	
	local R: AptInt = r1:LeftShift(n):AddRaw(a3) -- paper says a4 but its actually a3
	
	--> q too large by atleast 1
	local B: AptInt = b1:LeftShift(n):AddRaw(b2) -- [b1, b2]
	while R.signum == -1 do
		q = q:SubtractRaw(AP_ONE)
		R = R:AddRaw(B)
	end
	
	R = R:SubtractRaw(D)
	return q, R
end

function DivBZ2n1n(n: AptInt, b: AptInt): (AptInt, AptInt)
	--> this function has to be global because of its use in DivBZ3n2n.
	--> Algorithm 1 from https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	local nLen: number = #b.limbs
	if bband(nLen, 1) == 1 or nLen < BURNIKEL_THRESHOLD then
		if not LowerThanAbsolute(n, b) then
			return DivKnuths(n, b)
		end

		return AptInt.new(), b:clone()
	end
	
	local nHalf: number = nLen/2+1
	--print(#n.limbs, nLen)
	local a1a2: AptInt, a3a4: AptInt = GetUpper(n, nHalf), GetLower(n, nHalf)
	local a1: AptInt, a2: AptInt = GetUpper(a1a2, nHalf//2), GetLower(a1a2, nHalf//2)
	local a3: AptInt, a4: AptInt = GetUpper(a3a4, nHalf//2), GetLower(a3a4, nHalf//2)
	
	local b1: AptInt, b2: AptInt = GetUpper(b, nHalf), GetLower(b, nHalf)
	
	--> get q1,R
	local q1: AptInt, r: AptInt = DivBZ3n2n(a1, a2, a3, b1, b2)
	local r1: AptInt, r2: AptInt = GetUpper(r, nHalf), GetLower(r, nHalf)
	
	local q2: AptInt, S: AptInt = DivBZ3n2n(r1, r2, a4, b1, b2)
	
	--> get Q
	--print(q1, q2)
	if q2.signum == 0 then
		return q1, S
	end
	
	local Q: AptInt = q1:LeftShift(nHalf):AddRaw(q2) -- Q = [q1,q2]
	return Q, S
end

local function DivBurnikelZiegler(A: AptInt, B: AptInt): (AptInt, AptInt)
	--> https://pure.mpg.de/rest/items/item_1819444_4/component/file_2599480/content
	--> https://github.com/wyndavies/LongInteger/blob/master/LongIntegers/LongInteger.cpp#L3128
	local s: number = #B.limbs
	
	--> 1. set m to the next power of 2 abov the len of B 
	local m: number = 2^ceil(log(s, 2)) 
	
	local j: number = ceil(s/m)
	local n: number = j * m
	
	--> 3. set sigma to normalize B and A, so that B[#B] >= BASE/2
	--> sigma is single-limb, so multiplication here is linear.
	local sigma: AptInt = AptInt.new(
		max((BASE-1) // B.limbs[s], 1)
	)
	
	local shift = n-s
	
	local bShifted = B:MultiplyRaw(sigma):LeftShift(shift)
	local aShifted = A:MultiplyRaw(sigma):LeftShift(shift)
	
	--> 5. calculate t: how many n-sized chunks are in A, t >= 2
	local t: number = max(ceil(#aShifted.limbs / n), 2)
	
	--> 6. init z
	local z: AptInt, a2: AptInt = GetBlock(aShifted, t-1, n), GetBlock(aShifted, t-2, n)
	
	if a2.signum ~= 0 then
		z = z:LeftShift(n):AddRaw(a2) -- z = [a1, a2].
	end
	
	--> 7. for i = t - 2, 1 do
	local quotient: AptInt = AptInt.new()
	for i: number = t-2, 1, -1 do
		--> 8a. qi, ri
		local qi: AptInt, ri: AptInt = DivBZ2n1n(z, bShifted)
		
		--> 8b. z = [ri, a_i-1]
		local ai1: AptInt = GetBlock(aShifted, i-1, n)
		z = ri:LeftShift(n):AddRaw(ai1)
		--print(qi, ri)
		--print(i)
		quotient = quotient:LeftShift(n):AddRaw(qi)
	end
	
	-- final iteration of step 8: do the loop one more time for i=0 but leave z unchanged
	local qi: AptInt, ri: AptInt = DivBZ2n1n(z, bShifted)
	quotient = quotient:AddRaw(qi)
	
	ri = ri:DivideRaw(sigma)
	return quotient, ri
end

local function TryModExp(limb: number, div: number, base: number): (boolean, number)
	local log: number = log(div, base)
	if log ~= floor(log) or log > BASE_POW then -- log > BASE_POW since each power we check 1 more digit
		return false, 0
	end	

	return true, limb % div
end

--> SQRT STUFF
local function NewtonHeronSqrt(n: AptInt): AptInt
	local prev2: AptInt = AP_NEG_ONE:clone()
	local prev1: AptInt = AP_ONE:LeftShift((#n.limbs-1)//2)
	
	while true do
		local q: AptInt, _: AptInt = n:DivideRaw(prev1)
		local x1: AptInt = prev1:AddRaw(q):DivideRaw(AP_TWO, true)

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

	--> calculate a3, a2, a1 and a0
	local m: number = (limbLen + 1)//4
	local m2: number = m*2
	
	local a3a2: AptInt, a1a0: AptInt = GetUpper(n, m2), GetLower(n, m2)
	local a1: AptInt, a0: AptInt = GetUpper(a1a0, m), GetLower(a1a0, m)
	
	local s1: AptInt, r1: AptInt = KaratsubaSqrt(a3a2)
	--local r1 = a3a2:SubtractRaw(s1:MultiplyRaw(s1))
	
	--> divrem (r1*b + a1, 2*s1)
	local q, u: AptInt = 
		r1:LeftShift(m):AddRaw(a1)
		:DivideRaw(s1:AddRaw(s1))

	--> get sqrt and correct
	local s: AptInt = s1:LeftShift(m):AddRaw(q) -- s=s1*b+q

	local r: AptInt = u:LeftShift(m):AddRaw(a0):SubtractRaw(q:MultiplyRaw(q))
	
	if r.signum == -1 then
		r=r:AddRaw(s:AddRaw(s)):SubtractRaw(AP_ONE)
		s=s:SubtractRaw(AP_ONE)
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
	local limbs: {number}, signum: number = typeConstructors[typeof(num)](num)

	return setmetatable({
		limbs = limbs,
		signum = signum
	}, AptInt) :: AptInt
end

--> this is ugly
AP_NEG_ONE = AptInt.new(-1)
AP_ZERO = AptInt.new()
AP_ONE = AptInt.new({1})
AP_TWO = AptInt.new({2})
AP_THREE = AptInt.new({3})

-- Returns a copy of the AptInt.
function AptInt.clone(n: AptInt): AptInt
	return setmetatable({
		limbs = tclone(n.limbs),
		signum = n.signum
	}, AptInt) :: AptInt
end

-- Returns an AptInt with its sign flipped.
function AptInt:Negate(inPlace: boolean): AptInt
	if inPlace then
		self.signum = -self.signum
		return self
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
	local selfSign: number, summandSign: number = self.signum, term.signum
	local sameSign: boolean = selfSign == summandSign
	
	--> CASES
	if summandSign == 0 then
		return self:clone()
	elseif selfSign == 0 then
		return term:clone()
	elseif selfSign == -1 and summandSign == 1 then -- -a+b = b+(-a) = b-a
		return (NegateRef(self):SubtractRaw(term, inPlace)):Negate(true)
	elseif not sameSign then -- +a+(-b)=a-b
		return self:SubtractRaw(NegateRef(term), inPlace)
	end

	local summandLimbs: {number}, selfLimbs: {number} = term.limbs, self.limbs
	if #selfLimbs < #summandLimbs then
		selfLimbs, summandLimbs =  summandLimbs, selfLimbs
	end

	local result: AptInt = (inPlace and self or self:clone())
	local rLimbs: {number} = result.limbs

	--> from right to left
	local carry: number = 0
	for i: number, selfDigit: number in selfLimbs do
		local sum: number = selfDigit + (summandLimbs[i] or 0) + carry

		if sum >= BASE then
			carry = 1
			sum -= BASE
		else
			carry = 0
		end

		rLimbs[i] = sum
	end

	if carry > 0 then
		tinsert(rLimbs, carry)
	end
	
	result.signum = (if sameSign and selfSign == -1 then -1 else 1)
	return result
end

-- Returns an AptInt, equal to <code>a - b</code>.
function AptInt:SubtractRaw(term: AptInt, inPlace: boolean?): AptInt
	local selfSign: number, termSign: number = self.signum, term.signum
	
	--> CASES
	if termSign == 0 then -- b - 0 = 0
		return self:clone()
	elseif selfSign == 0 then -- 0 - b = -b
		return term:Negate()
	elseif termSign == -1 and selfSign == 1 then -- a-(-b) = a+b
		return NegateRef(term):AddRaw(self)
	elseif selfSign == termSign and selfSign == -1 then -- (-a-(-b)) = b-a
		return (NegateRef(self):SubtractRaw(NegateRef(term), inPlace)):Negate(true)
	end
	
	if self:LowerThanRaw(term) then
		return term:SubtractRaw(self):Negate(true)
	end

	local result: AptInt = (inPlace and self or self:clone())
	local rLimbs: {number} = result.limbs
	
	local limbsSubrahend: {number} = term.limbs

	--> from right to left
	local borrow: number = 0
	for i: number, digit: number in rLimbs do
		local diff: number = digit - (limbsSubrahend[i] or 0) - borrow
		if diff < 0 then
			borrow = 1
			diff += BASE
		else
			borrow = 0
		end
		
		rLimbs[i] = diff
	end
	
	StripLeadingZeros(result)
	return result
end

-- Returns an AptInt equal to <code>a * b</code>.
function AptInt:MultiplyRaw(factor: AptInt, inPlace: boolean?): AptInt
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
		local result: AptInt = (inPlace and self or self:clone())
		
		if mul == 1 then 
			result.signum = selfSign * factorSign

			return result
		end

		local rLimbs: {number} = result.limbs

		local carry: number = 0
		for i: number, limb: number in selfLimbs do
			local p: number = limb * mul + carry
			
			if p > BASE then
				carry = p // BASE
				p %= BASE
			else
				carry = 0
			end
			
			rLimbs[i] = p
		end

		if carry > 0 then
			tinsert(rLimbs, carry)
		end

		result.signum = selfSign * factorSign
		return result
	end
	
	if selfLen > TOOM_THRESHOLD and factorLen > TOOM_THRESHOLD then
		return MultiplyToomCook3(self, factor)
	elseif selfLen > KARATSUBA_THRESHOLD and factorLen > KARATSUBA_THRESHOLD then
		return MultiplyKaratsuba(self, factor)
	end

	--> normal o(n^2) algorithm
	local len: number = selfLen + factorLen
	local result: AptInt = (inPlace and self or AptInt.new(tcreate(len, 0)))
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
			p %= BASE
		else
			carry = 0
		end

		rLimbs[i] = p
	end
	
	StripLeadingZeros(result)
	result.signum = selfSign * factorSign
	return result
end

-- Returns the quotient and remainder of a / b.
function AptInt:DivideRaw(divisor: AptInt, inPlace: boolean?): (AptInt, AptInt)
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
		
		local quotient: AptInt = (inPlace and self or self:clone())
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
	if #V > BURNIKEL_THRESHOLD and #U > BURNIKEL_THRESHOLD then
		quotient, remainder = DivBurnikelZiegler(self, divisor)
	else
		quotient, remainder = DivKnuths(self, divisor)
	end
	
	remainder = CorrectRemainder(self, divisor, remainder)
	if self.signum ~= divisor.signum then
		quotient:Negate(true)
	end
	
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
	
	--> single limb divisor optimizations

	local success: boolean, mod: number = TryModExp(selfFirst, divFirst, 2) -- 2
	if success then return AptInt.new({mod}) end

	success, mod = TryModExp(selfFirst, divFirst, 5) -- 5
	if success then return AptInt.new({mod}) end

	success, mod = TryModExp(selfFirst, divFirst, 10) -- 10
	if success then return AptInt.new({mod}) end

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
			if bband(n, 1) == 1 then
				result = selfClone:MultiplyRaw(result)
			end

			selfClone = selfClone:MultiplyRaw(selfClone)
			n = brshift(n, 1)
		end
		
		return result
	end

	--> exponentiation by squaring
	local powClone: AptInt = pow:clone()

	while powClone.signum == 1 do
		if bband(powClone.limbs[1], 1) == 1 then
			result = selfClone:MultiplyRaw(result)
		end

		selfClone = selfClone:MultiplyRaw(selfClone)
		powClone = powClone:DivideRaw(AP_TWO)
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
	local str: string = (self.signum == -1 and "-" or "")
	if self.signum == 0 then
		return "0"
	end

	local limbs: {number} = self.limbs
	str ..=limbs[#limbs]

	local formatStr: string = `%0{BASE_POW}d`

	--> from left to right
	for i: number = #limbs - 1, 1, -1 do
		str ..= sformat(formatStr, limbs[i]) -- prepend dem zeros
	end

	return str
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
--> "BOOLEAN" FUNCTIONS
-- ==================

-- Returns a new AptInt equal to <code>n * 10<sup>(BASE * amount)</sup></code>
function AptInt:LeftShift(amount: number): AptInt
	-- this is the fastest way to leftshift.
	return AptInt.new(tmove(self.limbs, 1, #self.limbs, amount+1, tcreate(amount, 0)))
end

-- Returns a new AptInt equal to <code>n // 10<sup>(BASE * amount)</sup></code>
function AptInt:RightShift(amount: number): AptInt
	local result: AptInt = self:clone()

	local tbl: {number} = result.limbs

	for i: number = 1, amount do
		tremove(tbl, 1)
	end

	return result
end

-- ============
--> METAMETHODS
-- ============

AptInt.__unm = function(num: AptInt): AptInt
	return num:Negate()
end

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

AptInt.__tostring = function(n: AptInt): string
	return n:ToString()
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
