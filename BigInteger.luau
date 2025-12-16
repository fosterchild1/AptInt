--!optimize 2
--!native
--!strict

-- ===============================================================
--[[ 
-- BigInteger.luau // fosterchild 2025 - Luau implementation of Java's BigInteger, with added typechecking.
-- Licensed under The Unlicense.

-- Documentation and source can be found at: https://github.com/fosterchild1/BigInteger.luau/tree/main
--]]
-- ===============================================================

-- INSPO: https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/math/BigInteger.java

local BigInteger = {}
BigInteger.__index = BigInteger

export type ValidConstructor = string & number & BigInteger & {number} & nil

export type BigInteger = setmetatable<{
	limbs: {number},
	signum: number,
	
	read __unm: (n: ValidConstructor) -> BigInteger,
	read __add: (a: ValidConstructor, b: ValidConstructor) -> BigInteger,
	read __sub: (a: ValidConstructor, b: ValidConstructor) -> BigInteger,
	read __eq: (a: ValidConstructor, b: ValidConstructor) -> boolean,
	read __lt: (a: ValidConstructor, b: ValidConstructor) -> boolean,
	read __le: (a: ValidConstructor, b: ValidConstructor) -> boolean,
	read __tostring: (n: BigInteger) -> string,
	read __len: (n: BigInteger) -> number,
	
	read Negate: (n: BigInteger, inPlace: boolean) -> BigInteger,

	read ShiftLeft: (n: BigInteger, limbs: number) -> BigInteger,
	
	read AddRaw: (term: BigInteger, term: BigInteger) -> BigInteger,
	read SubtractRaw: (term: BigInteger, term: BigInteger) -> BigInteger,
	read MultiplyRaw: (factor: BigInteger, factor: BigInteger) -> BigInteger,
	read EqualsRaw: (self: BigInteger, num: BigInteger) -> boolean,
	read LowerThanRaw: (self: BigInteger, num: BigInteger) -> boolean,
	read LowerOrEqualToRaw: (self: BigInteger, num: BigInteger) -> boolean,
	read ToString: (self: BigInteger) -> string,
	
	read Abs: (n: BigInteger) -> BigInteger
	
}, typeof(BigInteger)>

-- =======================
--> OPTIMIAZTION CONSTANTS
-- =======================

local log10: (number) -> number = math.log10
local floor: (number) -> number = math.floor
local ceil: (number) -> number = math.ceil
local max: (number) -> number = math.max
local sign: (number) -> number = math.sign

local rshift: (number, number) -> number = bit32.rshift
local lshift: (number, number) -> number = bit32.lshift
local band: (number, number) -> number = bit32.band
local bor: (number, number) -> number = bit32.bor

local tcreate = table.create
local tinsert: <V>({V}, V) -> () & <V>({V}, number, V) -> () = table.insert
local tremove = table.remove

local sformat: (string, ...unknown) -> string = string.format

-- ==========
--> CONSTANTS
-- ==========

local KARATSUBA_THRESHOLD: number = 10 -- in limbs
local MAX_LOSSLESS_POW: number = 53 -- 2^53
local BASE_POW: number = 6 -- MUST SATISFY: 10^((BASE_POW+1) * 2) < 2^53, because of multiplying
local BASE: number = 10 ^ BASE_POW

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> ({number}, number)} = {
	["string"] = function(str: string): ({number}, number)
		local isNegative: boolean = str:sub(1, 1) == "-"
		
		local arr: {number} = {}
		
		local i: number = #str
		repeat
			local chars: string = str:sub(math.max(i - BASE_POW + 1, 1), i)
			local num: number? = tonumber(chars)
			if not num then break end
			
			i -= BASE_POW
			tinsert(arr, num)
		until i < (isNegative and 2 or 1)
		
		return arr, (isNegative and -1 or 1)
	end,

	["number"] = function(num: number): ({number}, number)
		if num == 0 then
			return {0}, 0
		end

		local limbs: number = ceil(log10(num))
		local arr: {number} = tcreate(limbs, 0)

		for i: number = 1, limbs do
			arr[i] = floor(num % 10)
			num //= 10
		end

		return arr, (sign(num))
	end,
	
	["table"] = function(tbl: {any}): ({number}, number)
		local first: any = tbl[1]
		if not first then
			return {}, 0
		end
		
		assert(
			typeof(first) == "number",
			"attempt to create BigInteger from a table with non-int values"
		)
		
		return tbl, 1
	end,

	["nil"] = function(_: nil): ({number}, number)
		return {}, 0
	end,
}

-- =================
--> HELPER FUNCTIONS
-- =================

local function ArgumentToBigInteger(num: number | BigInteger, errContext: string): BigInteger
	local bigint: BigInteger;

	--> make sure toAdd is correct
	if typeof(num) == "number" then
		assert(num < 2^MAX_LOSSLESS_POW, "non-BigInteger number should be lower than 2^53.")

		bigint = BigInteger.new(num)
	else
		assert(
			getmetatable(num) == BigInteger, 
			`attempt to perform arithmetic ({errContext}) on BigInteger and {typeof(num)}`
		)

		bigint = num
	end

	return bigint
end

-- Split a digit into its low "d" limbs and its high limbs. For example, split_at(12345, 3) 
-- will extract the 3 final limbs, giving: high=12, low=345.
local function GetKaratsubaLower(int: BigInteger, n: number): BigInteger
	local new: {number} = {}
	local limbs: {number} = int.limbs
	
	for i: number = 1, #limbs - n do
		tinsert(new, limbs[i])
	end
	
	return BigInteger.new(new)
end

local function GetKaratsubaUpper(int: BigInteger, n: number): BigInteger
	-- select(#x - half, unpack(x)) this is faster, but unpack only works up to a certain degree. fml
	-- TODO: figure out that limit and implement this for numbers under that limit (limit is >1k for sure)

	local new: {number} = {}
	local limbs: {number} = int.limbs
	
	for i: number = #limbs - n + 1, #limbs do
		tinsert(new, limbs[i])
	end

	return BigInteger.new(new)
end

local function MultiplyKaratsuba(x: BigInteger, y: BigInteger): BigInteger
	local m2: number = max(#x, #y)//2

	local low1: BigInteger, low2: BigInteger = GetKaratsubaLower(x, m2), GetKaratsubaLower(y, m2)
	local high1: BigInteger, high2: BigInteger = GetKaratsubaUpper(x, m2), GetKaratsubaUpper(y, m2)
	
	local z0: BigInteger = low1:MultiplyRaw(low2)
	local z1: BigInteger = low1:AddRaw(high1):MultiplyRaw(low2:AddRaw(high2))
	local z2: BigInteger = high1:MultiplyRaw(high2)

	-- (z2 × BASE ^ (m2 × 2)) + ((z1 - z2 - z0) × BASE ^ m2) + z0
	-- since base is 10, we can just prepend zeros to avoid slow exponentiation
	local result = z2:LeftShift(m2 * 2)
		:AddRaw(
			(z1:SubtractRaw(z2):SubtractRaw(z0)):LeftShift(m2)
		)
		:AddRaw(z0)
	
	if x.signum ~= y.signum then
		return result:Negate(true)
	end
	
	return result
end

local function StripLeadingZeros(bigint: BigInteger)
	while #bigint > 1 and bigint.limbs[#bigint] == 0 do
		tremove(bigint.limbs, #bigint.limbs)
	end
end

-- ====================
--> METATABLE FUNCTIONS
-- ====================

-- Returns a new BigInteger from given argument
function BigInteger.new(num: string | number | {number}?): BigInteger
	local limbs: {number}, signum: number = typeConstructors[typeof(num)](num)
	
	return setmetatable({
		limbs = limbs,
		signum = signum
	}, BigInteger) :: BigInteger
end

-- Returns a new BigInteger with its sign flipped.
function BigInteger:Negate(inPlace: boolean): BigInteger
	if inPlace then
		self.signum = -self.signum
		return self
	end
	
	local result: BigInteger = BigInteger.new(self.limbs)
	result.signum = -(self :: BigInteger).signum
	
	return result
end
-- =====================
--> ARITHMETIC FUNCTIONS
-- =====================

-- Returns a new BigInteger = x, whose value is equal to a + b.
function BigInteger:AddRaw(term: BigInteger): BigInteger
	local selfSign: number, summandSign: number = self.signum, term.signum
	local sameSign: boolean = selfSign == summandSign
	
	--> CASES
	if summandSign == 0 then
		return self
	elseif selfSign == -1 and summandSign == 1 then -- -a+b = b+(-a) = b-a
		return (self:Negate(false):SubtractRaw(term)):Negate(true)
	elseif not sameSign then -- +a+(-b)=a-b
		return self:SubtractRaw(term:Negate(true))
	end
	
	local result: BigInteger = BigInteger.new()
	
	-- largest
	local limbsToAdd: number = math.max(#self, #term)
	
	local limbsSummand: {number}, limbsSelf: {number} = term.limbs, self.limbs
	
	--> from right to left
	local carry: number = 0
	for i: number = 1, limbsToAdd do
		local sum: number = (limbsSelf[i] :: number or 0) + (limbsSummand[i] :: number or 0) + carry
		print(limbsSelf[i], limbsSummand[i], sum, carry)
		if sum >= BASE then
			carry = 1
			sum = sum - BASE
			print(carry, sum)
		else
			carry = 0
			print("r")
		end
		
		result.limbs[i] = sum
	end

	if carry > 0 then
		result.limbs[limbsToAdd + 1] = carry
	end
	
	result.signum = (if sameSign and selfSign == -1 then -1 else 1)
	return result
end

-- Returns a new BigInteger = x, whose value is equal to a - b.
function BigInteger:SubtractRaw(term: BigInteger): BigInteger
	local selfSign: number, termSign: number = self.signum, term.signum
	local sameSign: boolean = (selfSign == termSign)
	
	--> CASES
	if termSign == 0 then
		return self
	elseif termSign == -1 and selfSign == 1 then
		return term:Negate(false):AddRaw(self)
	elseif sameSign and selfSign == -1 then -- (-a-(-b)) b-a
		return (self:Negate(false):SubtractRaw(term:Negate(false))):Negate(true)
	end
	
	if self:LowerThanRaw(term) then
		return term:SubtractRaw(self):Negate(true)
	end
	
	local result: BigInteger = BigInteger.new()
	
	local limbsSelf: {number}, limbsSubrahend: {number} = self.limbs, term.limbs

	--> from right to left
	local borrow: number = 0
	for i: number, digit: number in limbsSelf do
		local diff: number = digit - (limbsSubrahend[i] :: number or 0) - borrow
		if diff < 0 then
			borrow = 1
			diff = diff + 10
		else
			borrow = 0
		end
		
		result.limbs[i] = diff
	end
	
	StripLeadingZeros(result)
	
	result.signum = 1
	return result
end

-- Returns a BigInteger = x, whose value is equal to a * b.
function BigInteger:MultiplyRaw(factor: BigInteger)
	local selfSign: number, factorSign: number = self.signum, factor.signum
	
	--> CASES
	if selfSign == 0 or factorSign == 0 then
		return BigInteger.new()
	end
	
	local selflimbs: {number} = self.limbs
	local factorlimbs: {number} = factor.limbs
	
	if #self > KARATSUBA_THRESHOLD or #factor > KARATSUBA_THRESHOLD then
		return MultiplyKaratsuba(self, factor)
	end

	local result: BigInteger = BigInteger.new()
	
	-- do normal o(n^2) schoolgrade multiplication
	for i: number, digit: number in selflimbs do
		local carry: number = 0
		local prependedZeros: number = i - 1
		
		local mulResult: BigInteger = BigInteger.new(tcreate(prependedZeros, 0)) -- prepend zeros
		
		for j: number, factorDigit: number in factorlimbs do
			local mul: number = digit * factorDigit + carry
			
			if mul > 9 then
				carry = mul // 10
				mul = mul % 10
			else
				carry = 0
			end
			
			mulResult.limbs[j + prependedZeros] = mul
		end
		
		--> carry can "ripple" through the number. for example: 9999 + 1
		while carry > 0 do
			local last: number? = mulResult.limbs[#mulResult + 1]
			local sum: number = (last or 0) + carry
			
			if sum > 9 then
				carry = 1
				sum = sum - 10
			else
				carry = 0
			end
			
			mulResult.limbs[#mulResult + 1] = sum
		end
		
		result = result:AddRaw(mulResult)
	end
	
	result.signum = (self.signum ~= factor.signum and -1 or 1)
	return result
end

-- Returns a new string representation of a BigInteger
function BigInteger:ToString(): string
	local str: string = (self.signum == -1 and "-" or "")
	
	local limbs: {number} = self.limbs

	--> from left to right
	for i: number = #limbs, 1, -1 do
		str ..= sformat("%06d", limbs[i]) -- prepend dem zeros
	end

	return str
end

-- ==================
--> COMPARISON FUNCTIONS
-- ==================

-- Returns true if self == num, false if not.
function BigInteger:EqualsRaw(num: BigInteger): boolean
	if (#(self :: BigInteger) ~= #num) or (self.signum ~= num.signum) then
		return false
	end
	
	for i: number, selfDigit: number in (self :: BigInteger).limbs do
		if selfDigit ~= num.limbs[i] then
			return false
		end
	end
	
	return true
end

-- Returns true if self < num, false if not.
function BigInteger:LowerThanRaw(num: BigInteger): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	local selfLen: number, numLen: number = #(self :: BigInteger), #num
	
	--> check sign
	if selfSign < numSign then
		return true
	end
	-- -317314, -717729
	local bothNegative: boolean = (selfSign == numSign and selfSign == -1)
	--> check their lengths. for negative, the lowest is with the most limbs, and for positive its the lowest
	if bothNegative and selfLen > numLen then
		return true
	elseif selfLen < numLen then -- both positive
		return true
	end
	
	local selflimbs: {number}, numlimbs: {number} = self.limbs, num.limbs
	for i: number = #(self :: BigInteger), 1, -1 do
		local sDigit: number, nDigit: number = selflimbs[i], numlimbs[i] or 0
		if sDigit == nDigit then continue end
		
		if bothNegative then
			return sDigit > nDigit
		end
		
		return sDigit < nDigit
	end

	return false 
end

-- Returns true if self <= num, false if not.
function BigInteger:LowerOrEqualToRaw(num: BigInteger): boolean
	local selfSign: number, numSign: number = self.signum, num.signum
	local selfLen: number, numLen: number = #(self :: BigInteger), #num

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
	for i: number = #(self :: BigInteger), 1, -1 do
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

-- Returns a new BigInteger = x, where self * 10^limbs = x
function BigInteger:LeftShift(amount: number)
	local result = BigInteger.new(self.limbs)
	
	local tbl: {number} = result.limbs
	
	for i = 1, amount do
		tinsert(tbl, 1, 0)
	end
	
	return result
end

-- ============
--> METAMETHODS
-- ============

BigInteger.__unm = function(num: ValidConstructor): BigInteger
	local bigint: BigInteger = ArgumentToBigInteger(num, "unm")
	
	return bigint:Negate(false)
end

BigInteger.__add = function(a: ValidConstructor, b: ValidConstructor): BigInteger
	local term1: BigInteger = ArgumentToBigInteger(a, "add")
	local term2: BigInteger = ArgumentToBigInteger(b, "add")
	
	return term1:AddRaw(term2)
end

BigInteger.__sub = function(a: ValidConstructor, b: ValidConstructor): BigInteger
	local term1: BigInteger = ArgumentToBigInteger(a, "sub")
	local term2: BigInteger = ArgumentToBigInteger(b, "sub")

	return term1:SubtractRaw(term2)
end

BigInteger.__eq = function(a: ValidConstructor, b: ValidConstructor): boolean
	local term1: BigInteger = ArgumentToBigInteger(a, "eq")
	local term2: BigInteger = ArgumentToBigInteger(b, "eq")
	
	return term1:EqualsRaw(term2)
end

BigInteger.__lt = function(a: ValidConstructor, b: ValidConstructor): boolean
	local term1: BigInteger = ArgumentToBigInteger(a, "lt")
	local term2: BigInteger = ArgumentToBigInteger(b, "lt")
	
	return term1:LowerThanRaw(term2)
end

BigInteger.__le = function(a: ValidConstructor, b: ValidConstructor): boolean
	local term1: BigInteger = ArgumentToBigInteger(a, "le")
	local term2: BigInteger = ArgumentToBigInteger(b, "le")

	return term1:LowerOrEqualToRaw(term2)
end

BigInteger.__tostring = function(n: BigInteger): string
	return n:ToString()
end

BigInteger.__len = function(n: BigInteger): number
	return rawlen(n.limbs)
end

-- ===========
--> EXTENSIONS
-- ===========
function BigInteger.Extend(func: (typeof(BigInteger)) -> ())
	func(BigInteger)
end

return BigInteger
