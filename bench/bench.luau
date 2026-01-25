--!native
--!optimize 2

local aptint = require(game.ReplicatedStorage.AptInt)

type AptInt = aptint.AptInt

local clock: () -> number = os.clock
local random: (number?, number?) -> number = math.random
local insert = table.insert

local MAX: number = 2^26-1
local LOG2_10: number = 3.32192809489

local digits: {number} = {1, 50, 100, 500, 1_000, 5_000, 10_000, 50_000, 100_000}
--local digits: {number} = {100_000}

local function BuildRandomNum(digitCount: number): AptInt
	local len: number = digitCount * LOG2_10/26
	if digitCount <= 1 then
		return aptint.new({random(1, 9.99999999^digitCount)})
	end
	
	local tbl: {number} = {}
	
	for i: number = 1, len do
		if i == len then -- avoid leading zeros
			insert(tbl, random(1, MAX))
			continue
		end
		
		insert(tbl, random(0, MAX))
	end
	
	return aptint.new(tbl)
end

local function BenchFunc(name: string, fn: (AptInt, AptInt) -> ()): ()
	local start: number

	--> division takes more the smaller the divisor is.
	local isDiv: boolean = (name == "divBench")
	
	--> sqrt requires non-negative number.
	local isSqrt: boolean = (name == "sqrtBench")

	for _: number, digitCount: number in digits do
		local int1: AptInt = BuildRandomNum(digitCount)
		local int2: AptInt = BuildRandomNum(isDiv and digitCount/2+1 or digitCount)
		
		if isSqrt then
			int1.signum = 1
		end

		start = clock()
		fn(int1, int2)
		print(`Took {clock()-start} to run {name} with {digitCount} digits`)

		task.wait(0.25)
	end
end

BenchFunc("addBench", function(int1: AptInt, int2: AptInt)
	int1:AddRaw(int2)
end)

BenchFunc("subBench", function(int1: AptInt, int2: AptInt)
	int1:SubtractRaw(int2)
end)

BenchFunc("mulBench", function(int1: AptInt, int2: AptInt)
	int1:MultiplyRaw(int2)
end)

BenchFunc("divBench", function(int1: AptInt, int2: AptInt)
	int1:DivideRaw(int2)
end)

BenchFunc("sqrtBench", function(int1: AptInt, int2: AptInt)
	int1:sqrt()
end)
