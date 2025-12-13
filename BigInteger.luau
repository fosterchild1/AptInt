--!optimize 2
--!native
--!strict

-- INSPO: https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/math/BigInteger.java

local BigInteger = {}
BigInteger.__index = BigInteger

export type BigInteger = setmetatable<{
	digits: {number},
	signum: number,
	
	read __unm: (self: BigInteger) -> BigInteger,
	read __add: (self: BigInteger, summand: BigInteger | number) -> BigInteger,
	read __sub: (self: BigInteger, subrahend: BigInteger | number) -> BigInteger,
	read __tostring: (self: BigInteger) -> string,
	read __len: (self: BigInteger) -> number,
	
	read Sign: (self: BigInteger) -> number,
	read Negate: (self: BigInteger) -> BigInteger,
	
	read ShiftLeft: (self: BigInteger, digits: number) -> BigInteger,
	
	read AddRaw: (self: BigInteger, summand: BigInteger) -> BigInteger,
	read SubtractRaw: (self: BigInteger, subrahend: BigInteger) -> BigInteger,
	read MultiplyRaw: (self: BigInteger, factor: BigInteger) -> BigInteger,
	read ToStringRaw: (self: BigInteger) -> string
	
}, typeof(BigInteger)>

local log10: (number) -> number = math.log10
local floor: (number) -> number = math.floor
local ceil: (number) -> number = math.ceil
local max: (number) -> number = math.max

local rshift: (number, number) -> number = bit32.rshift
local lshift: (number, number) -> number = bit32.lshift
local band: (number, number) -> number = bit32.band
local bor: (number, number) -> number = bit32.bor

local tcreate = table.create
local tinsert: <V>({V}, V) -> () & <V>({V}, number, V) -> () = table.insert
local tremove = table.remove

local KARATSUBA_THRESHOLD: number = 5 -- in digits
local MAX_LOSSLESS_POW: number = 53
local MAX_BIT32_POW: number = 30 -- Bit32 only works from -2^31 to 2^31, anything over that and it overflows

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> {number}} = {
	["string"] = function(str: string): {number}
		local isNegative: boolean = str:sub(1, 1) == "-"
		local startIdx: number = isNegative and 2 or 1
		
		local digitStr: string = str:sub(startIdx)
		local len: number = #digitStr

		local arr: {number} = tcreate(len, 0)
		
		for i: number = 1, len do
			local char: string = digitStr:sub(i, i)
			local digit: number? = tonumber(char)

			assert(
				digit, 
				`attempt to create BigInteger from string containing non-digit characters: {str}`)
			
			arr[len - i + 1 ] = digit
		end
		
		return arr
	end,

	["number"] = function(num: number): {number}
		if num == 0 then
			return {0}
		end

		local digits: number = ceil(log10(num))
		local arr: {number} = tcreate(digits, 0)

		for i: number = 1, digits do
			arr[i] = floor(num % 10)
			num //= 10
		end

		return arr
	end,
	
	["table"] = function(tbl: {any}): {number}
		local first: any = tbl[1]
		if not first then
			return {}
		end
		
		assert(
			typeof(first) == "number",
			"attempt to create BigInteger from a table with non-int values"
		)
		
		return tbl
	end,

	["nil"] = function(_: nil): {number}
		return {}
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

-- Split a digit into its low "d" digits and its high digits. For example, split_at(12345, 3) 
--will extract the 3 final digits, giving: high=12, low=345.
local function GetKaratsubaLower(int: BigInteger, n: number): BigInteger
	local new: {number} = {}
	local digits: {number} = int.digits
	
	for i: number = 1, #digits - n do
		tinsert(new, digits[i])
	end
	
	return BigInteger.new(new)
end

local function GetKaratsubaUpper(int: BigInteger, n: number): BigInteger
	-- select(#x - half, unpack(x)) this is faster, but unpack only works up to a certain degree. fml
	-- TODO: figure out that limit and implement this for numbers under that limit (limit is >1k for sure)

	local new: {number} = {}
	local digits: {number} = int.digits
	
	for i: number = #digits - n + 1, #digits do
		tinsert(new, digits[i])
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
	local result = z2:LeftShift(m2 * 2)
		:AddRaw(
			(z1:SubtractRaw(z2):SubtractRaw(z0)):LeftShift(m2)
		)
		:AddRaw(z0)
	
	print(x)
	print("low1", low1)
	print("high1", high1)

	if x:Sign() ~= y:Sign() then
		return result:Negate()
	end
	
	return result
end

local function StripLeadingZeros(bigint: BigInteger)
	local digits: {number} = bigint.digits
	while #bigint > 1 and digits[1] == 0 do
		tremove(digits, 1)
	end
end

-- ====================
--> METATABLE FUNCTIONS
-- ====================

function BigInteger.new(num: any): BigInteger
	return setmetatable({
		num = typeConstructors[typeof(num)](num),
		signum = -1,
	}, BigInteger) :: BigInteger
end

function BigInteger:Negate(): BigInteger
	local result: BigInteger = BigInteger.new(self)
	result.signum = -result.signum
	
	return result
end

-- =====================
--> ARITHMETIC FUNCTIONS
-- =====================

function BigInteger:AddRaw(summand: BigInteger): BigInteger
	local result: BigInteger = BigInteger.new()
	
	-- largest
	local digitsToAdd: number = (#(self :: BigInteger) > #summand and #(self :: BigInteger) or #summand)
	
	local digitsSummand: {number}, digitsSelf: {number} = summand.digits, self.digits
	
	--> from right to left
	local carry: number = 0
	for i: number = 1, digitsToAdd do
		local sum: number = (digitsSelf[i] :: number or 0) + (digitsSummand[i] :: number or 0) + carry

		if sum > 9 then
			carry = 1
			sum = sum - 10
		else
			carry = 0
		end
		
		result.digits[i] = sum
	end

	if carry > 0 then
		result.digits[digitsToAdd + 1] = carry
	end
	
	if self:Sign() == -1 and summand:Sign() == 1 then
		return result:Negate()
	end
	
	return result
end

function BigInteger:SubtractRaw(subrahend: BigInteger): BigInteger
	local result: BigInteger = BigInteger.new()
	
	local digitsSelf: {number}, digitsSubrahend: {number} = self.digits, subrahend.digits

	--> from right to left
	local borrow: number = 0
	for i: number, digit: number in digitsSelf do
		local diff: number = digit - (digitsSubrahend[i] :: number or 0) - borrow
	
		if diff < 0 then
			borrow = 1
			diff = diff + 10
		else
			borrow = 0
		end
		
		result.digits[i] = diff
	end
	
	StripLeadingZeros(result)

	return result
end

function BigInteger:MultiplyRaw(factor: BigInteger)
	local selfDigits: {number} = self.digits
	local factorDigits: {number} = factor.digits
	
	if #self > KARATSUBA_THRESHOLD or #factor > KARATSUBA_THRESHOLD then
		return MultiplyKaratsuba(self, factor)
	end

	local result: BigInteger = BigInteger.new()
	
	-- do normal o(n^2) multiplication
	for i: number, digit: number in selfDigits do
		local carry: number = 0
		local prependedZeros: number = i - 1
		
		local mulResult: BigInteger = BigInteger.new(tcreate(prependedZeros, 0)) -- prepend zeros
		
		for j: number, factorDigit: number in factorDigits do
			local mul: number = digit * factorDigit + carry
			
			if mul > 9 then
				carry = mul // 10
				mul = mul % 10
			else
				carry = 0
			end
			
			mulResult.digits[j + prependedZeros] = mul
		end
		
		while carry > 0 do
			local last: number? = mulResult.digits[#mulResult + 1]
			local sum: number = (last or 0) + carry
			
			if sum > 9 then
				carry = 1
				sum = sum - 10
			else
				carry = 0
			end
			
			mulResult.digits[#mulResult + 1] = sum
		end
		
		result = result:AddRaw(mulResult)
	end

	return result
end

function BigInteger:ToStringRaw(): string
	local str: string = ""

	--> from left to right
	for i: number = #self, 1, -1 do
		str ..= tostring(rawget(self, i))
	end

	return str
end

-- ==================
--> BOOLEAN FUNCTIONS
-- ==================

function BigInteger:LeftShift(digits: number)
	local result = BigInteger.new(self)
	
	local tbl: {number} = result.digits
	
	for i = 1, digits do
		tinsert(tbl, 1, 0)
	end
	
	return result
end

-- ============
--> METAMETHODS
-- ============
BigInteger.__unm = function(self: BigInteger): BigInteger
	return self:Negate()
end

BigInteger.__add = function(self: BigInteger, summand: number | BigInteger): BigInteger
	local bigint: BigInteger = ArgumentToBigInteger(summand, "add")
	
	return self:AddRaw(bigint)
end

BigInteger.__sub = function(self: BigInteger, subrahend: number | BigInteger): BigInteger
	local bigint: BigInteger = ArgumentToBigInteger(subrahend, "sub")

	return self:SubtractRaw(bigint)
end

BigInteger.__tostring = function(self: BigInteger): string
	return self:ToStringRaw()
end

BigInteger.__len = function(self: BigInteger): number
	return #self.digits
end

return table.freeze(BigInteger)
