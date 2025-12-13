--!optimize 2
--!native
--!strict

-- INSPO: https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/math/BigInteger.java

local BigInteger = {}
BigInteger.__index = BigInteger

export type BigInteger = setmetatable<{number} & {
	read __add: (self: BigInteger, summand: BigInteger | number) -> BigInteger,
	read __sub: (self: BigInteger, subrahend: BigInteger | number) -> BigInteger,
	read __tostring: (self: BigInteger) -> string,
	
	read Sign: (self: BigInteger) -> number,
	read Negate: (self: BigInteger) -> BigInteger,
	
	read ShiftLeft: (self: BigInteger, bits: number) -> BigInteger,
	
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
local tinsert: <V>({V}, V) -> () = table.insert

local KARATSUBA_THRESHOLD: number = 80 -- in digits
local MAX_LOSSLESS_POW: number = 53
local MAX_BIT32_POW: number = 30 -- Bit32 only works from -2^31 to 2^31, anything over that and it overflows

--> CONSTRUCTOR
local typeConstructors: {[string]: (any) -> {number}} = {
	["string"] = function(str: string): {number}
		local len: number = #str
		local arr: {number} = tcreate(len, 0)

		for i: number = 1, len do
			arr[len - i + 1] = tonumber(str:sub(i, i))
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

local function GetKaratsubaLower(int: BigInteger, n: number): BigInteger
	-- select(#x - half, unpack(x)) this is faster, but unpack only works up to a certain degree. fml
	-- TODO: figure out that limit and implement this for numbers under that limit (limit is >1k for sure)
	
	local new: {number} = {}
	local limit: number = #int - n
	
	for i: number, v: number in int do
		if i < limit then continue end
		tinsert(new, v)
	end
	
	return BigInteger.new(new)
end

local function GetKaratsubaUpper(int: BigInteger, n: number): BigInteger
	local new: {number} = {}
	local limit: number = #int - n

	for i: number, v: number in int do
		if i > limit then continue end
		tinsert(new, v)
	end

	return BigInteger.new(new)
end

local function MultiplyKaratsuba(x: BigInteger, y: BigInteger): BigInteger
	local half: number = (max(#x, #y)+1)//2

	local xl: BigInteger, yl: BigInteger = GetKaratsubaLower(x, half), GetKaratsubaLower(y, half)
	local xh: BigInteger, yh: BigInteger = GetKaratsubaUpper(x, half), GetKaratsubaUpper(y, half)
	
	local p1: BigInteger, p2: BigInteger = xh:MultiplyRaw(yh), xl:MultiplyRaw(yl)
	local p3: BigInteger = xh:AddRaw(xl):MultiplyRaw(yh:AddRaw(yl))
	
	local result: BigInteger = p1:LeftShift(MAX_BIT32_POW * half):AddRaw(p3:SubtractRaw(p1):
		SubtractRaw(p2)):LeftShift(MAX_BIT32_POW * half):AddRaw(p2)
	
	if x:Sign() ~= y:Sign() then
		return result:Negate()
	end
	
	return result
end

local function StripLeadingZeros(bigint: BigInteger)
	while #bigint > 1 and bigint[1] == 0 do
		table.remove(bigint, 1)
	end
end

-- ====================
--> METATABLE FUNCTIONS
-- ====================

function BigInteger.new(num: any): BigInteger
	return setmetatable(typeConstructors[typeof(num)](num), BigInteger) :: BigInteger
end

function BigInteger:Sign(): number
	return self[#self :: BigInteger] > 0 and 1 or -1
end

function BigInteger:Negate(): BigInteger
	self[#self :: BigInteger] = -(self :: BigInteger):Sign()
	return self
end

-- =====================
--> ARITHMETIC FUNCTIONS
-- =====================

function BigInteger:AddRaw(summand: BigInteger): BigInteger
	local result: BigInteger = BigInteger.new()

	local digitsSelf: number, digitsAdder: number = #self, #summand
	local digitsToAdd: number = (digitsSelf > digitsAdder and digitsSelf or digitsAdder) -- largest

	--> from right to left
	local carry: number = 0
	for i: number = 1, digitsToAdd do
		local sum: number = (self[i] :: number or 0) + (summand[i] :: number or 0) + carry

		if sum > 9 then
			carry = 1
			sum = sum - 10
		else
			carry = 0
		end
		
		result[i] = sum
	end

	if carry > 0 then
		result[digitsToAdd + 1] = carry
	end

	return result
end

function BigInteger:SubtractRaw(subrahend: BigInteger): BigInteger
	local result: BigInteger = BigInteger.new()
	local digitsToSubtract: number = #self

	--> from right to left
	local borrow: number = 0
	for i: number = 1, digitsToSubtract do
		local diff: number = (self[i] :: number or 0) - (subrahend[i] :: number or 0) - borrow
	
		if diff < 0 then
			borrow = 1
			diff = diff + 10
		else
			borrow = 0
		end
		
		result[i] = diff
	end
	
	StripLeadingZeros(result)

	return result
end

function BigInteger:MultiplyRaw(factor: BigInteger)
	local selfDigits: number = #self
	local factorDigits: number = #factor
	
	if selfDigits > KARATSUBA_THRESHOLD or factorDigits > KARATSUBA_THRESHOLD then
		return MultiplyKaratsuba(self, factor)
	end

	local result: BigInteger = BigInteger.new()
	
	-- do normal o(n^2) multiplication
	for i: number = 1, selfDigits do
		local digit: number = self[i]
		local carry: number = 0
		local prependedZeros: number = i - 1
		
		local mulResult: BigInteger = BigInteger.new(tcreate(prependedZeros, 0)) -- prepend zeros
		
		for j: number = 1, factorDigits do
			local factorDigit: number = factor[j]
			local mul: number = digit * factorDigit + carry
			
			if mul > 9 then
				carry = mul // 10
				mul = mul % 10
			else
				carry = 0
			end
			
			mulResult[j + prependedZeros] = mul
		end
		
		if carry > 0 then
			local last: number? = mulResult[#mulResult + 1]
			mulResult[#mulResult + 1] = (last and last + carry or carry)
		end
		
		result += mulResult
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

function BigInteger:LeftShift(bits: number): BigInteger
	local nInts: number = bits // MAX_BIT32_POW
	local nBits: number = bits % MAX_BIT32_POW
	local digits: number = #(self :: BigInteger)
	
	local result: BigInteger = BigInteger.new()
	
	if nBits == 0 then
		return self
	end
	
	local i: number = 0
	local highBits: number = rshift(result[1], MAX_BIT32_POW - nBits)
	local numIter: number = digits - 1

	local shiftCount: number = MAX_BIT32_POW - nBits;
	
	if highBits ~= 0 then
		i = 1
		result[1] = highBits
	end
	
	local oldIndex: number = 0
	while oldIndex < numIter do
		i += 1; oldIndex += 1
		result[i] = bor(lshift(self[oldIndex], nBits), rshift(self[oldIndex], shiftCount))
	end
	
	result[numIter + i] = lshift(self[numIter], nBits)
	
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

return table.freeze(BigInteger)
