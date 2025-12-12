--!optimize 2
--!native
--!strict

local BigInteger = {}
BigInteger.__index = BigInteger

export type BigInteger = setmetatable<{number} & {
	read __add: (self: BigInteger, toAdd: BigInteger | number) -> BigInteger,
	read __tostring: (self: BigInteger) -> string,

	read AddRaw: (self: BigInteger, adder: BigInteger) -> BigInteger,
	read ToString: (self: BigInteger) -> string
}, typeof(BigInteger)>

local log10: (number) -> number = math.log10
local floor: (number) -> number = math.floor
local ceil: (number) -> number = math.ceil

local tcreate = table.create

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

	["nil"] = function(_: nil): {number}
		return {0}
	end,
}

--> HELPER FUNCTIONS
local function ArgumentToBigInteger(num: number | BigInteger, errContext: string): BigInteger
	local bigint: BigInteger;

	--> make sure toAdd is correct
	if typeof(num) == "number" then
		assert(num < 2^53, "[BigInteger]: non-BigInteger number should be lower than 2^53.")

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

function BigInteger.new(num: any): BigInteger
	return setmetatable(typeConstructors[typeof(num)](num), BigInteger) :: BigInteger
end

function BigInteger:Sign()
	return self[1] > 0 and 1 or 1
end

--> ARITHMETIC OPERATIONS
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

	local digitsSelf: number, digitsSubrahend: number = #self, #subrahend
	local digitsToSubtract: number = (digitsSelf > digitsSubrahend and digitsSubrahend or digitsSelf) -- smallest

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

	if borrow > 0 then
		local Next: number = digitsToSubtract + 1
		result[Next] = (if result[Next] == 1 then nil else result[Next] - borrow) -- remove if 0
	end

	return result
end

function BigInteger:ToString(): string
	local str: string = ""

	--> from left to right
	for i: number = #self, 1, -1 do
		str ..= tostring(rawget(self, i))
	end

	return str
end

--> METAMETHODS
BigInteger.__add = function(self: BigInteger, summand: number | BigInteger): BigInteger
	local bigint: BigInteger = ArgumentToBigInteger(summand, "add")
	
	return self:AddRaw(bigint)
end

BigInteger.__sub = function(self: BigInteger, subrahend: number | BigInteger): BigInteger
	local bigint: BigInteger = ArgumentToBigInteger(subrahend, "sub")

	return self:SubtractRaw(bigint)
end

BigInteger.__tostring = function(self: BigInteger): string
	return self:ToString()
end

return table.freeze(BigInteger)
