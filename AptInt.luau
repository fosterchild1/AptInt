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

	read Negate: (n: AptInt, inPlace: boolean) -> AptInt,

	read LeftShift: (n: AptInt, amount: number) -> AptInt,
	read RightShift: (n: AptInt, amount: number) -> AptInt,

	read AddRaw: (term: AptInt, term: AptInt) -> AptInt,
	read SubtractRaw: (term: AptInt, term: AptInt) -> AptInt,
	read MultiplyRaw: (factor: AptInt, factor: AptInt) -> AptInt,
	read DivideRaw: (dividend: AptInt, divisor: AptInt) -> (AptInt, AptInt),
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
local max: (number) -> number = math.max
local min: (number) -> number = math.min
local abs: (number) -> number = math.abs
local sign: (number) -> number = math.sign

local tcreate: <V>(number, V?) -> {V} = table.create
local tinsert: <V>({V}, V) -> () & <V>({V}, number, V) -> () = table.insert
local tremove: <V>({V}, number?) -> V? = table.remove
local tmove: <V>({V}, number, number, number, {V}?) -> {V} = table.move
local tclone: <T>({T}) -> {T} = table.clone

local sformat: (string, ...unknown) -> string = string.format

-- =================
--> NORMAL CONSTANTS
-- =================

local KARATSUBA_THRESHOLD: number = 45 -- in limbs, limit where karatsuba is faster than normal multiplication
local SQRT_KARATSUBA_THRESHOLD: number = 32
local TOOM_THRESHOLD: number = 90
local SAFE_UNPACK_THRESHOLD: number = 8000 -- unpack() max size in limbs

local BASE_POW: number = 7 -- MUST SATISFY: 10^((BASE_POW+1) * 2) < 2^53, because of multiplyraw and divideraw
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
		local first: any = tbl[1]
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

local function ArgumentToAptInt(num: ValidMetamethodArgument?, errContext: string): AptInt
	local bigint: AptInt;

	--> make sure toAdd is correct
	if getmetatable(num :: AptInt?) == AptInt then
		bigint = num :: AptInt
	else
		local numType: string = typeof(num)

		if numType == "table" then
			assert(
				typeof((num :: {number})[1]) == "number",
				`attempt to perform ({errContext}) on AptInt and table of non-integers`
			)
		else
			assert(
				typeConstructors[numType] ~= nil,
				`attempt to perform ({errContext}) on AptInt and {numType}`
			)
		end


		bigint = AptInt.new(num :: ValidConstructor)
	end

	return bigint
end

-- Split a digit into its low "d" limbs and its high limbs. For example, split_at(12345, 3) 
-- will extract the 3 final limbs, giving: high=12, low=345.
local function GetKaratsubaLower(int: AptInt, n: number): AptInt
	return AptInt.new(tmove(int.limbs, 1, n, 1, {}))
end

local function GetKaratsubaUpper(int: AptInt, n: number): AptInt
	return AptInt.new(tmove(int.limbs, n+1, #int.limbs, 1, {}))
end

local function GetToomSlice(n: AptInt, startIdx: number, endIdx: number)
	return AptInt.new(tmove(n.limbs, startIdx, endIdx, 1, {}))
end

local function MultiplyKaratsuba(x: AptInt, y: AptInt): AptInt
	local m2: number = (max(#x.limbs, #y.limbs) + 1)//2

	local low1: AptInt, low2: AptInt = GetKaratsubaLower(x, m2), GetKaratsubaLower(y, m2)
	local high1: AptInt, high2: AptInt = GetKaratsubaUpper(x, m2), GetKaratsubaUpper(y, m2)

	local z0: AptInt = low1:MultiplyRaw(low2)
	local z1: AptInt = low1:AddRaw(high1):MultiplyRaw(low2:AddRaw(high2))
	local z2: AptInt = high1:MultiplyRaw(high2)

	-- (z2 × BASE ^ (m2 × 2)) + ((z1 - z2 - z0) × BASE ^ m2) + z0
	-- since base is a power of 10, we can just prepend zeros to avoid slow exponentiation
	-- => z0 + ((z1 - z2 - z0) << m2) + (z2 << m2 * 2)

	local result = z2:LeftShift(m2 * 2)
		:AddRaw(
			z1:SubtractRaw(z2:AddRaw(z0)):LeftShift(m2)
		)
		:AddRaw(z0)

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
	local x0: AptInt, x1: AptInt = GetToomSlice(x, 1, k), GetToomSlice(x, k+1, r)
	local x2: AptInt = GetToomSlice(x, r+1, largest)
	
	local y0: AptInt, y1: AptInt = GetToomSlice(y, 1, k), GetToomSlice(y, k+1, r)
	local y2: AptInt = GetToomSlice(y, r+1, largest)
	
	local v0: AptInt = x0:MultiplyRaw(y0)
	local da1: AptInt = x2:AddRaw(x0)
	local db1: AptInt = y2:AddRaw(y0)
	local vm1: AptInt = da1:SubtractRaw(x1):MultiplyRaw(db1:SubtractRaw(y1))
	
	da1 = da1:AddRaw(x1)
	db1 = db1:AddRaw(y1)
	
	local v1: AptInt = da1:MultiplyRaw(db1)
	da1 = da1:AddRaw(x2)
	db1 = db1:AddRaw(y2)
	
	local v2: AptInt = da1:AddRaw(da1):SubtractRaw(x0):MultiplyRaw(
		db1:AddRaw(db1):SubtractRaw(y0)
	)
	
	--> all divisions here are single-limb, so they are O(n).
	local vinf: AptInt = x2:MultiplyRaw(y2)
	local t2: AptInt = v2:SubtractRaw(vm1):DivideRaw(AP_THREE)
	local tm1: AptInt = v1:SubtractRaw(vm1):DivideRaw(AP_TWO)
	local t1: AptInt = v1:SubtractRaw(v0)
	
	t2 = t2:SubtractRaw(t1):DivideRaw(AP_TWO) 
	t1 = t1:SubtractRaw(tm1):SubtractRaw(vinf)
	t2 = t2:SubtractRaw(vinf:AddRaw(vinf))
	tm1 = tm1:SubtractRaw(t2)
	
	local result: AptInt = vinf
		:LeftShift(k):AddRaw(t2)
		:LeftShift(k):AddRaw(t1)
		:LeftShift(k):AddRaw(tm1)
		:LeftShift(k):AddRaw(v0)
	
	if x.signum ~= y.signum then
		return result:Negate(true)
	end
	
	return result
end

--> divsion stuff
local function CorrectRemainder(self: AptInt, divisor: AptInt, remainder: AptInt): AptInt
	local selfSign: number, divSign: number = self.signum, divisor.signum
	local sameSign: boolean = selfSign == divSign

	if sameSign then
		if divSign == -1 then
			return remainder:Negate(true)
		end

		return remainder
	elseif selfSign == 1 and divSign == -1 and remainder.signum ~= 0 then
		return divisor:AddRaw(remainder)
	elseif remainder.signum ~= 0 then
		return divisor:SubtractRaw(remainder)
	end

	return remainder
end

local function TryModExp(limb: number, div: number, base: number): (boolean, number)
	local log: number = log(div, base)
	if log ~= floor(log) or log > BASE_POW then -- log > BASE_POW since each power we check 1 more digit
		return false, 0
	end	

	return true, limb % div
end

local function LowerThanAbsolute(x: AptInt, y: AptInt): boolean
	local xLimbs: {number}, yLimbs: {number} = x.limbs, y.limbs

	if #xLimbs < #yLimbs then
		return true
	end

	for i: number = #xLimbs, 1, -1 do
		local xDigit: number, yDigit: number = xLimbs[i], yLimbs[i] or 0
		if xDigit == yDigit then continue end

		return xDigit < yDigit
	end

	return false 
end

--> SQRT STUFF
local function NewtonHeronSqrt(n: AptInt): AptInt
	local prev2: AptInt = AP_NEG_ONE:clone()
	local prev1: AptInt = AP_ONE:LeftShift(#n.limbs//2+1)

	while true do
		local q: AptInt, _: AptInt = n:DivideRaw(prev1)
		local x1: AptInt = prev1:AddRaw(q):DivideRaw(AP_TWO)

		local equals: boolean = x1:EqualsRaw(prev1)
		if equals then
			return x1
		end

		if x1:EqualsRaw(prev2) and not equals then
			return (x1:LowerThanRaw(prev1) and x1 or prev1) -- min(x1, prev1)
		end

		prev2, prev1 = prev1, x1
	end
end

local function KaratsubaSqrt(n: AptInt): (AptInt, AptInt)
	--> NOTE: even tho we dont have burnikel-ziegler division, this is still faster by a ton
	
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
	
	--> split must be even
	if limbLen % 2 ~= 0 then
		limbLen += 1
	end
	
	--> calculate a3, a2, a1 and a0
	local m2: number = ceil(limbLen / 2)
	if m2 % 2 ~= 0 then m2 += 1 end -- split must be even
	local m: number = m2 / 2
	
	local a3a2: AptInt, a1a0: AptInt = GetKaratsubaUpper(n, m2), GetKaratsubaLower(n, m2)
	local a1: AptInt, a0: AptInt = GetKaratsubaUpper(a1a0, m), GetKaratsubaLower(a1a0, m)
	
	local s1: AptInt, r1: AptInt = KaratsubaSqrt(a3a2)
	--local r1 = a3a2:SubtractRaw(s1:MultiplyRaw(s1))
	
	--> divrem (r1*b + a1, 2*s1)
	local q, u: AptInt = 
		r1:LeftShift(m):AddRaw(a1)
		:DivideRaw(s1:AddRaw(s1))

	--> get sqrt and correct
	local s: AptInt = s1:LeftShift(m):AddRaw(q) -- s=s1*b+q

	local r: AptInt = n:SubtractRaw(s:MultiplyRaw(s))
	
	if r.signum == -1 then
		r = r:AddRaw(s:AddRaw(s)):SubtractRaw(AP_ONE)
		s = s:SubtractRaw(AP_ONE)
	end
	
	return s, r
end

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
	return tclone(n :: {any}) :: AptInt -- copies metatable too
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
function AptInt:AddRaw(term: AptInt, inPlace: boolean): AptInt
	local selfSign: number, summandSign: number = self.signum, term.signum
	local sameSign: boolean = selfSign == summandSign

	--> CASES
	if summandSign == 0 then
		return (inPlace and self :: AptInt or self:clone())
	elseif selfSign == 0 then
		return (inPlace and term or term:clone())
	elseif selfSign == -1 and summandSign == 1 then -- -a+b = b+(-a) = b-a
		return (self:Negate(inPlace):SubtractRaw(term, inPlace)):Negate(true)
	elseif not sameSign then -- +a+(-b)=a-b
		return self:SubtractRaw(term:Negate(false), inPlace)
	end

	local summandLimbs: {number}, selfLimbs: {number} = term.limbs, self.limbs
	if #selfLimbs < #summandLimbs then
		selfLimbs, summandLimbs =  summandLimbs, selfLimbs
	end

	local rLimbs: {number} = (inPlace and self.limbs or tcreate(#selfLimbs, 0))

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

	local rAptInt: AptInt = (inPlace and self :: AptInt or AptInt.new(rLimbs))
	rAptInt.signum = (if sameSign and selfSign == -1 then -1 else 1)
	
	return rAptInt
end

-- Returns an AptInt, equal to <code>a - b</code>.
function AptInt:SubtractRaw(term: AptInt, inPlace: boolean?): AptInt
	local selfSign: number, termSign: number = self.signum, term.signum
	local sameSign: boolean = (selfSign == termSign)
	
	inPlace = if inPlace == nil then false else inPlace
	
	--> CASES
	if termSign == 0 then -- b - 0 = 0
		return (inPlace and self :: AptInt or self:clone())
	elseif selfSign == 0 then -- 0 - b = -b
		return term:Negate(false)
	elseif termSign == -1 and selfSign == 1 then -- a-(-b) = a+b
		return term:Negate(false):AddRaw(self, inPlace)
	elseif sameSign and selfSign == -1 then -- (-a-(-b)) = b-a
		return (self:Negate(inPlace):SubtractRaw(term:Negate(false), inPlace)):Negate(true)
	end

	if self:LowerThanRaw(term) then
		return (term:SubtractRaw(self)):Negate(true)
	end
	
	local selfLimbs: {number} = self.limbs
	local rLimbs: {number} = (inPlace and selfLimbs or tcreate(#selfLimbs, 0))

	local limbsSubrahend: {number} = term.limbs

	--> from right to left
	local borrow: number = 0
	for i: number, digit: number in selfLimbs do
		local diff: number = digit - (limbsSubrahend[i] or 0) - borrow
		if diff < 0 then
			borrow = 1
			diff += BASE
		else
			borrow = 0
		end
		
		rLimbs[i] = diff
	end

	--> StripLeadingZeros but on a table.
	while true do
		local len: number = #rLimbs
		if len == 1 or rLimbs[len] ~= 0 then break end
		
		rLimbs[len] = nil
	end

	if #rLimbs == 1 and rLimbs[#rLimbs] == 0 then
		return AptInt.new()
	end

	return (inPlace and self or AptInt.new(rLimbs))
end

-- Returns an AptInt equal to <code>a * b</code>.
function AptInt:MultiplyRaw(factor: AptInt): AptInt
	local selfSign: number, factorSign: number = self.signum, factor.signum

	--> CASES
	if selfSign == 0 or factorSign == 0 then
		return AptInt.new()
	end

	local selflimbs: {number} = self.limbs
	local factorlimbs: {number} = factor.limbs
	local factorLen: number = #factorlimbs
	local selfLen: number = #selflimbs

	--> single limb multiplication
	--[[if factorLen == 1 then
		local mul: number = factorlimbs[1]
		local result = self:clone() -- minor optimization over tcreate()
		if mul == 1 then 
			result.signum = selfSign * factorSign

			return result
		end

		local rLimbs: {number} = result.limbs

		local carry: number = 0
		for i: number, limb: number in selflimbs do
			local p: number = limb * mul + carry

			carry = p // BASE
			rLimbs[i] = p % BASE
		end

		if carry > 0 then
			tinsert(rLimbs, carry)
		end

		result.signum = selfSign * factorSign
		return result
	end]]
	
	if selfLen > TOOM_THRESHOLD and factorLen > TOOM_THRESHOLD then
		return MultiplyToomCook3(self, factor)
	elseif selfLen > KARATSUBA_THRESHOLD and factorLen > KARATSUBA_THRESHOLD then
		return MultiplyKaratsuba(self, factor)
	end

	--> normal o(n^2) algorithm
	local len: number = selfLen + factorLen
	local result: AptInt = AptInt.new(tcreate(len, 0))
	local rLimbs: {number} = result.limbs
	
	local carry: number = 0
	factorLen -= 1
	for i: number = 1, len do
		local sum: number = carry
		for j: number = max(i - factorLen, 1), min(i, selfLen) do
			sum += selflimbs[j] * factorlimbs[i - j + 1]
		end
		
		rLimbs[i] = sum % BASE
		carry = sum // BASE
	end

	StripLeadingZeros(result)
	result.signum = selfSign * factorSign
	return result
end

-- Returns the quotient and remainder of a / b.
function AptInt:DivideRaw(divisor: AptInt): (AptInt, AptInt)
	--> we use knuths algorithm D for division

	local divSign: number, selfSign: number = divisor.signum, self.signum
	local sameSign: boolean = divSign == selfSign
	
	inPlace = if inPlace ~= nil then inPlace else false

	--> CASES (oh dear..)
	--> TODO: refactor
	if divSign == 0 or selfSign == 0 then -- dividing by 0
		return AptInt.new(), AptInt.new()
	elseif LowerThanAbsolute(self, divisor) then
		if selfSign == 1 and divSign == -1 then
			return AptInt.new(-1), divisor:AddRaw(self)
		elseif selfSign == -1 and divSign == 1 then
			return AptInt.new(-1), divisor:SubtractRaw(self:Negate(false))
		elseif sameSign and divSign == -1 then
			return AptInt.new(), (self :: AptInt):clone()
		end

		return AptInt.new(), (self :: AptInt):clone()
	elseif self:EqualsRaw(divisor) then -- dividing x/x = 1
		return AptInt.new({1}), AptInt.new()
	elseif self:Negate(false):EqualsRaw(divisor) or self:EqualsRaw(divisor:Negate(false)) then -- -x/x = -1
		return AptInt.new(-1), AptInt.new()
	end

	local U: {number}, V: {number} = self.limbs, divisor.limbs

	--> single limb division
	if #V == 1 then
		local div: number = V[1]
		if div == 1 then
			local result = self:clone()
			result.signum = selfSign / divSign

			return result, AptInt.new()
		end

		local quotient: AptInt = AptInt.new(tcreate(#U - 1, 0))
		local qLimbs: {number} = quotient.limbs

		local carry: number = 0
		for i: number = #U, 1, -1 do
			local x: number = U[i] + carry * BASE
			local qDigit: number = x // div

			carry = x - qDigit * div
			qLimbs[i] = qDigit
		end

		quotient.signum = selfSign / divSign
		StripLeadingZeros(quotient)

		return quotient, AptInt.new({carry})
	end

	--> d0. defs
	local n: number = #V
	local m: number = #U - n

	--> d1. normalize (get Vn and Un)
	local D: number = BASE // (V[n] + 1)
	local Dint: AptInt = AptInt.new(D)

	local Vn: {number} = divisor:MultiplyRaw(Dint).limbs
	local Un: {number} = (self :: AptInt):MultiplyRaw(Dint).limbs

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
				diff += BASE
			else
				borrow = 0
			end

			Un[i + j] = diff
		end

		local lastSub: number = (Un[nPlusJ] or 0) - carry - borrow
		Un[nPlusJ] = lastSub

		--> d6. add back
		if lastSub >= 0 then
			qLimbs[j + 1] = qhat
			continue
		end

		qLimbs[j + 1] = qhat - 1
		carry = 0

		for i: number = 1, n do
			local sum: number = Un[i + j] + Vn[i] + carry

			if sum >= BASE then
				carry = 1
				sum -= BASE
			else
				carry = 0
			end

			Un[i + j] = sum
		end

		Un[nPlusJ] = (Un[nPlusJ] + carry) % BASE
	end

	local remainder: AptInt = AptInt.new(Un)

	--> d8. unnormalize
	local carry: number = 0
	local rmLimbs: {number} = remainder.limbs
	for i: number = #rmLimbs, 1, -1 do
		local x: number = carry * BASE + rmLimbs[i]
		rmLimbs[i] = x // D :: number
		carry = x % D :: number
	end

	StripLeadingZeros(remainder)
	StripLeadingZeros(quotient)

	--> return
	remainder = CorrectRemainder(self, divisor, remainder)
	if not sameSign then
		quotient:Negate(true)
	end

	return quotient, remainder
end

-- Returns a new AptInt equal to <code>a % b</code>.
function AptInt:ModRaw(div: AptInt): AptInt
	--> TODO: THIS IS REAAAAALLY UGLY.
	local divLimbs: {number} = div.limbs
	local divLimbAmount: number, selfLimbAmount: number = #divLimbs, #(self :: AptInt).limbs

	local selfSign: number, divSign: number = self.signum, div.signum

	local divFirst: number = divLimbs[1] * divSign
	local selfFirst: number = self.limbs[1] * selfSign

	if divSign == 0 or (divLimbAmount == 1 and abs(divFirst) == 1) then
		return AptInt.new()
	elseif selfLimbAmount == 1 and divLimbAmount == 1 then
		return AptInt.new({selfFirst % divFirst})
	elseif divLimbAmount ~= 1 then
		local _: AptInt, r: AptInt = self:DivideRaw(div)
		return r
	end

	--> single limb divisor optimizations
	-- we check trymodexp which is expensive and uses math.log.
	-- performance difference shouldnt matter that much, since
	-- single limb division already is insanely fast,
	-- but since we check once for each number, it adds up

	--> TODO: add argument that disables this modexp
	local success: boolean, mod: number = TryModExp(selfFirst, divFirst, 2) -- 2
	if success then return AptInt.new({mod}) end

	success, mod = TryModExp(selfFirst, divFirst, 5) -- 5
	if success then return AptInt.new({mod}) end

	success, mod =  TryModExp(selfFirst, divFirst, 10) -- 10
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
		return AptInt.new({1})
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
			if n % 2 ~= 0 then
				result = selfClone:MultiplyRaw(result)
			end

			selfClone = selfClone:MultiplyRaw(selfClone)
			n //= 2
		end

		return result
	end

	--> exponentiation by squaring
	local powClone: AptInt = pow:clone()

	while AP_ZERO:LowerThanRaw(result) do
		if powClone.limbs[1] % 2 ~= 0 then
			result = selfClone:MultiplyRaw(result)
			--powClone = powClone:SubtractRaw(AP_ONE)
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
	local numLimbs: {number} = num.limbs
	if (#(self :: AptInt).limbs ~= #numLimbs) or (self.signum ~= num.signum) then
		return false
	end

	for i: number, selfDigit: number in self.limbs do
		if selfDigit ~= numLimbs[i] then
			return false
		end
	end

	return true
end

-- Returns true if <code>self < num</code>.
function AptInt:LowerThanRaw(num: AptInt): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	local selfLen: number, numLen: number = #self.limbs, #num.limbs

	--> check sign
	if selfSign < numSign then
		return true
	end

	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	--> check their lengths. for negative, the lowest is with the most limbs, and for positive its the lowest
	if bothNegative and selfLen > numLen then
		return true
	elseif selfLen < numLen then -- both positive
		return true
	end

	local selflimbs: {number}, numlimbs: {number} = self.limbs, num.limbs
	for i: number = #selflimbs, 1, -1 do
		local sDigit: number, nDigit: number = selflimbs[i], numlimbs[i] or 0
		if sDigit == nDigit then continue end

		if bothNegative then
			return sDigit > nDigit
		end

		return sDigit < nDigit
	end

	return false 
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

	local selflimbs: {number}, numlimbs: {number} = self.limbs, num.limbs
	for i: number = #selflimbs, 1, -1 do
		local sDigit: number, nDigit: number = selflimbs[i], numlimbs[i] or 0
		if sDigit == nDigit then continue end

		if bothNegative then
			return sDigit >= nDigit
		end

		return sDigit <= nDigit
	end

	return true 
end

-- ==================
--> "BOOLEAN" FUNCTIONS
-- ==================

-- Returns a new AptInt equal to <code>n * 10<sup>(BASE * amount)</sup></code>
function AptInt:LeftShift(amount: number): AptInt
	--[[local result: AptInt = self:clone()
	local tbl: {number} = result.limbs

	for _: number = 1, amount do
		tinsert(tbl, 1, 0)
	end]]
	
	return AptInt.new(tmove(self.limbs, 1, #self.limbs, amount+1, tcreate(amount, 0))) -- way faster
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

AptInt.__unm = function(num: ValidMetamethodArgument): AptInt
	local bigint: AptInt = ArgumentToAptInt(num, "unm")

	return bigint:Negate(false)
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
	local term1: AptInt = ArgumentToAptInt(a, "mod")
	local term2: AptInt = ArgumentToAptInt(b, "mod")

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
