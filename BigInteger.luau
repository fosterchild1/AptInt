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

export type ValidConstructor = string | number | BigInteger | {number} | nil
export type ValidMetamethodArgument = string | number | BigInteger

export type BigInteger = setmetatable<{
	limbs: {number},
	signum: number,
	
	read clone: (n: BigInteger) -> BigInteger,
	
	read Negate: (n: BigInteger, inPlace: boolean) -> BigInteger,

	read ShiftLeft: (n: BigInteger, limbs: number) -> BigInteger,
	
	read AddRaw: (term: BigInteger, term: BigInteger) -> BigInteger,
	read SubtractRaw: (term: BigInteger, term: BigInteger) -> BigInteger,
	read MultiplyRaw: (factor: BigInteger, factor: BigInteger) -> BigInteger,
	read DivideRaw: (divisor: BigInteger) -> (BigInteger, BigInteger),
	
	read EqualsRaw: (self: BigInteger, num: BigInteger) -> boolean,
	read LowerThanRaw: (self: BigInteger, num: BigInteger) -> boolean,
	read LowerOrEqualToRaw: (self: BigInteger, num: BigInteger) -> boolean,
	
	read ToString: (self: BigInteger) -> string	
}, typeof(BigInteger)>

-- =======================
--> OPTIMIAZTION CONSTANTS
-- =======================

local log10: (number) -> number = math.log10
local floor: (number) -> number = math.floor
local ceil: (number) -> number = math.ceil
local max: (number) -> number = math.max
local sign: (number) -> number = math.sign

local tcreate: <V>(number, V?) -> {V} = table.create
local tinsert: <V>({V}, V) -> () & <V>({V}, number, V) -> () = table.insert
local tremove: <V>({V}, number?) -> V? = table.remove
local tclone: <T>({T}) -> {T} = table.clone

local sformat: (string, ...unknown) -> string = string.format

-- ==========
--> CONSTANTS
-- ==========

local KARATSUBA_THRESHOLD: number = 300 -- in limbs, limit where karatsuba is faster than normal multiplication
local SAFE_UNPACK_THRESHOLD: number = 8000 -- unpack() max size in limbs

local MAX_LOSSLESS_POW: number = 53 -- 2^53
local MAX_LOSSLESS_INT: number = 2^MAX_LOSSLESS_POW-1

local BASE_POW: number = 7 -- MUST SATISFY: 10^((BASE_POW+1) * 2) < 2^53, because of multiplying
local BASE: number = 10 ^ BASE_POW

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> ({number}, number)} = {
	["string"] = function(str: string): ({number}, number)
		local isNegative: boolean = str:sub(1, 1) == "-"
		local strStart: number = isNegative and 2 or 1
		
		local arr: {number} = {}
		
		local i: number = #str
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
		end
		local actualSign: number = sign(num)
		
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
		
		--[[assert(
			typeof(first) == "number",
			"attempt to create BigInteger from a table with non-int values"
		)]]
		
		return tbl, 1
	end,

	["nil"] = function(_: nil): ({number}, number)
		return {0}, 0
	end,
}

-- =================
--> HELPER FUNCTIONS
-- =================

local function ArgumentToBigInteger(num: ValidMetamethodArgument?, errContext: string): BigInteger
	local bigint: BigInteger;

	--> make sure toAdd is correct
	if getmetatable(num :: BigInteger?) == BigInteger then
		bigint = num :: BigInteger
	else
		local numType: string = typeof(num)
		
		assert(
			numType ~= "table" and typeConstructors[numType] ~= nil,
			`attempt to perform ({errContext}) on BigInteger and {numType}`
		)
		
		bigint = BigInteger.new(num)
	end

	return bigint
end

-- Split a digit into its low "d" limbs and its high limbs. For example, split_at(12345, 3) 
-- will extract the 3 final limbs, giving: high=12, low=345.
local function GetKaratsubaLower(int: BigInteger, n: number): BigInteger
	local limbs: {number} = int.limbs
	
	--> unsure if this is faster.
	if #limbs < SAFE_UNPACK_THRESHOLD then
		-- table.pack is faster here but FOR SOME REASON IT INCLUDES ["N"] IN THE ARRAY TOO?!
		return BigInteger.new({unpack(limbs, 1, n)})
	end
	
	local result: BigInteger = BigInteger.new(tcreate(n, 0))
	local resultlimbs: {number} = result.limbs
	
	for i: number = 1, n do
		resultlimbs[i] = limbs[i]
	end
	
	return result
end

local function GetKaratsubaUpper(int: BigInteger, n: number): BigInteger
	-- {select(unpack(x))} is faster, but unpack only works up to a certain degree.
	local limbs: {number} = int.limbs

	if #limbs < SAFE_UNPACK_THRESHOLD then
		-- select(n + 1, unpack(limbs)) is wayy faster than {unpack(limbs, n+1, #limbs)}
		return BigInteger.new({
			select(n + 1, unpack(limbs)) :: number
		})
	end
	
	local result: BigInteger = BigInteger.new() -- TODO: tcreate here
	local resultLimbs: {number} = result.limbs
	
	for i: number = n + 1, #limbs do
		tinsert(resultLimbs, limbs[i])
	end
	
	return result
end

local function MultiplyKaratsuba(x: BigInteger, y: BigInteger): BigInteger
	local m2: number = (max(#x.limbs, #y.limbs) + 1)//2

	local low1: BigInteger, low2: BigInteger = GetKaratsubaLower(x, m2), GetKaratsubaLower(y, m2)
	local high1: BigInteger, high2: BigInteger = GetKaratsubaUpper(x, m2), GetKaratsubaUpper(y, m2)
	
	local z0: BigInteger = low1:MultiplyRaw(low2)
	local z1: BigInteger = low1:AddRaw(high1):MultiplyRaw(low2:AddRaw(high2))
	local z2: BigInteger = high1:MultiplyRaw(high2)

	-- (z2 × BASE ^ (m2 × 2)) + ((z1 - z2 - z0) × BASE ^ m2) + z0
	-- since base is a power of 10, we can just prepend zeros to avoid slow exponentiation
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
	
	if #bigint.limbs == 0 then
		bigint.signum = 0
	end
end

-- ====================
--> METATABLE FUNCTIONS
-- ====================

-- Returns a new BigInteger from given argument
function BigInteger.new(num: ValidConstructor): BigInteger
	local limbs: {number}, signum: number = typeConstructors[typeof(num)](num)
	
	return setmetatable({
		limbs = limbs,
		signum = signum
	}, BigInteger) :: BigInteger
end

-- Returns a copy of the BigInteger.
function BigInteger.clone(n: BigInteger): BigInteger
	return setmetatable({
		limbs = tclone(n.limbs),
		signum = n.signum
	}, BigInteger) :: BigInteger
end

-- Returns a new BigInteger with its sign flipped.
function BigInteger:Negate(inPlace: boolean): BigInteger
	if inPlace then
		self.signum = -self.signum
		return self
	end
	
	local result: BigInteger = BigInteger.clone(self)
	result.signum = -result.signum
	
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
		return self:clone()
	elseif selfSign == 0 then
		return term:clone()
	elseif selfSign == -1 and summandSign == 1 then -- -a+b = b+(-a) = b-a
		return (self:Negate(false):SubtractRaw(term)):Negate(true)
	elseif not sameSign then -- +a+(-b)=a-b
		return self:SubtractRaw(term:Negate(true))
	end
	
	local limbsSummand: {number}, limbsSelf: {number} = term.limbs, self.limbs
	local limbsToAdd: number = max(#limbsSelf, #limbsSummand)

	local result: BigInteger = BigInteger.new(tcreate(limbsToAdd, 0))

	
	--> from right to left
	local carry: number = 0
	for i: number = 1, limbsToAdd do
		local sum: number = (limbsSelf[i] or 0) + (limbsSummand[i] or 0) + carry
		
		if sum >= BASE then
			carry = 1
			sum = sum - BASE
		else
			carry = 0
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
		return self:clone()
	elseif selfSign == 0 then
		return term:clone()
	elseif termSign == -1 and selfSign == 1 then -- a - (-b) = a + b
		return term:Negate(false):AddRaw(self)
	elseif sameSign and selfSign == -1 then -- (-a-(-b)) b-a
		return (self:Negate(false):SubtractRaw(term:Negate(false))):Negate(true)
	end
	
	if self:LowerThanRaw(term) then
		return term:SubtractRaw(self):Negate(true)
	end
	
	local result: BigInteger = BigInteger.new()
	
	local limbsSubrahend: {number} = term.limbs

	--> from right to left
	local borrow: number = 0
	for i: number, digit: number in self.limbs do
		local diff: number = digit - (limbsSubrahend[i] or 0) - borrow
		if diff < 0 then
			borrow = 1
			diff = diff + BASE
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
function BigInteger:MultiplyRaw(factor: BigInteger): BigInteger
	local selfSign: number, factorSign: number = self.signum, factor.signum
	
	--> CASES
	if selfSign == 0 or factorSign == 0 then
		return BigInteger.new()
	end
	
	local selflimbs: {number} = self.limbs
	local factorlimbs: {number} = factor.limbs
	
	if #selflimbs > KARATSUBA_THRESHOLD and #factorlimbs > KARATSUBA_THRESHOLD then
		return MultiplyKaratsuba(self, factor)
	end

	local result: BigInteger = BigInteger.new(tcreate(0, #selflimbs))
	
	-- do normal o(n^2) schoolgrade multiplication
	for i: number, digit: number in selflimbs do
		local carry: number = 0
		local prependedZeros: number = i - 1
		
		local mulResult: BigInteger = BigInteger.new(tcreate(prependedZeros + #factorlimbs, 0))
		
		for j: number, factorDigit: number in factorlimbs do
			local mul: number = digit * factorDigit + carry
			
			if mul > BASE then
				carry = mul // BASE
				mul = mul % BASE
			else
				carry = 0
			end
			mulResult.limbs[j + prependedZeros] = mul
		end
		
		--> carry can "ripple" through the number. for example: 9999 + 1
		while carry > 0 do
			local last: number? = mulResult.limbs[#mulResult.limbs + 1]
			local sum: number = (last or 0) + carry
			
			if sum >= BASE then
				carry = 1
				sum = sum - BASE
			else
				carry = 0
			end
			
			mulResult.limbs[#mulResult.limbs + 1] = sum
		end
		
		result = result:AddRaw(mulResult)
	end
	
	result.signum = (self.signum ~= factor.signum and -1 or 1)
	return result
end

-- Returns a BigInteger = x, whose value is equal to a / b.
function BigInteger:DivideRaw(divisor: BigInteger): (BigInteger, BigInteger)
	if divisor.signum == 0 or self.signum == 0 then
		return BigInteger.new(), BigInteger.new()
	end
	
	local U: {number}, V: {number} = self.limbs, divisor.limbs

	--> d0. defs
	local n: number = #V
	local m: number = #U - n
	
	--> d1. normalize
	local D: number = BASE // (V[#V] + 1)
	local Dint: BigInteger = BigInteger.new(D)
	local Vn: {number} = divisor:MultiplyRaw(Dint).limbs
	local Un: {number} = self:MultiplyRaw(Dint).limbs
	
	local Vnn: number = Vn[n]
	local penultimateVn: number = Vn[n-1] or 0

	local quotient: BigInteger = BigInteger.new(tcreate(m + 1, 0))
	
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
		local borrow: number = 0
		for i: number = 1, n do
			local p: number = qhat * Vn[i] + borrow
			local digitP: number = p % BASE

			local sub: number = Un[i + j] - digitP
			if sub < 0 then
				sub = sub + BASE
				borrow = 1
			else
				borrow = 0
			end
			
			Un[i + j] = sub
		end

		local lastSub: number = (Un[nPlusJ] or 0) - borrow
		Un[nPlusJ] = lastSub

		--> d6. add back
		if lastSub < 0 then
			quotient.limbs[j + 1] = qhat - 1
			local carry: number = 0
			
			for i: number = 1, n do
				local sum: number = Un[i + j] + Vn[i] + carry

				if sum >= BASE then
					carry = 1
					sum = sum - BASE
				else
					carry = 0
				end

				Un[i + j] = sum
			end
			
			Un[nPlusJ] = (Un[nPlusJ] + carry) % BASE
		else
			quotient.limbs[j + 1] = qhat
		end
	end
	
	local remainder: BigInteger = BigInteger.new(Un)
	StripLeadingZeros(remainder)
	StripLeadingZeros(quotient)
	
	--> d8. unnormalize
	local carry: number = 0
	local rmLimbs: {number} = remainder.limbs
	for i: number = #rmLimbs, 1, -1 do
		local x = carry * BASE + rmLimbs[i]
		rmLimbs[i] = x // D
		carry = x % D
	end
	
	if divisor.signum ~= self.signum then
		return quotient:Negate(true), remainder
	end

	return quotient, remainder
end

-- Returns a new string representation of a BigInteger
function BigInteger:ToString(): string
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

-- ==================
--> COMPARISON FUNCTIONS
-- ==================

-- Returns true if self == num, false if not.
function BigInteger:EqualsRaw(num: BigInteger): boolean
	if (#(self :: BigInteger).limbs ~= #num.limbs) or (self.signum ~= num.signum) then
		return false
	end
	
	for i: number, selfDigit: number in self.limbs do
		if selfDigit ~= num.limbs[i] then
			return false
		end
	end
	
	return true
end

-- Returns true if self < num, false if not.
function BigInteger:LowerThanRaw(num: BigInteger): boolean
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

-- Returns true if self <= num, false if not.
function BigInteger:LowerOrEqualToRaw(num: BigInteger): boolean
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

-- Returns a new BigInteger = x, where self * 10^(BASE*amount) = x
function BigInteger:LeftShift(amount: number): BigInteger
	local result: BigInteger = BigInteger.clone(self)
	
	local tbl: {number} = result.limbs
	
	for i: number = 1, amount do
		tinsert(tbl, 1, 0)
	end
	
	return result
end

-- ============
--> METAMETHODS
-- ============

BigInteger.__unm = function(num: ValidMetamethodArgument): BigInteger
	local bigint: BigInteger = ArgumentToBigInteger(num, "unm")
	
	return bigint:Negate(false)
end

BigInteger.__add = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): BigInteger
	local term1: BigInteger = ArgumentToBigInteger(a, "add")
	local term2: BigInteger = ArgumentToBigInteger(b, "add")
	
	return term1:AddRaw(term2)
end

BigInteger.__sub = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): BigInteger
	local term1: BigInteger = ArgumentToBigInteger(a, "sub")
	local term2: BigInteger = ArgumentToBigInteger(b, "sub")

	return term1:SubtractRaw(term2)
end

BigInteger.__mul = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): BigInteger
	local term1: BigInteger = ArgumentToBigInteger(a, "mul")
	local term2: BigInteger = ArgumentToBigInteger(b, "mul")

	return term1:MultiplyRaw(term2)
end

local function divMeta(a: ValidMetamethodArgument, b: ValidMetamethodArgument): BigInteger
	local term1: BigInteger = ArgumentToBigInteger(a, "div")
	local term2: BigInteger = ArgumentToBigInteger(b, "div")
	
	local quotient: BigInteger, _: BigInteger = term1:DivideRaw(term2)
	return quotient
end
BigInteger.__div, BigInteger.__idiv = divMeta, divMeta

BigInteger.__eq = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: BigInteger = ArgumentToBigInteger(a, "eq")
	local term2: BigInteger = ArgumentToBigInteger(b, "eq")
	
	return term1:EqualsRaw(term2)
end

BigInteger.__lt = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
	local term1: BigInteger = ArgumentToBigInteger(a, "lt")
	local term2: BigInteger = ArgumentToBigInteger(b, "lt")
	
	return term1:LowerThanRaw(term2)
end

BigInteger.__le = function(a: ValidMetamethodArgument, b: ValidMetamethodArgument): boolean
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
