--!native
--!optimize 2

local aptint = require(game.ReplicatedStorage.AptInt)

type AptInt = aptint.AptInt

local clock: () -> number = os.clock
local random: (number?, number?) -> number = math.random

local digits: {number} = {1, 50, 100, 500, 1000, 5000, 10000, 50000, 100000}

local function BuildRandomNum(digitCount: number): AptInt
	local n: string = random(1, 2) == 1 and "-" or ""
	for i = 1, digitCount do
		n ..= random(1, 9)
	end

	return aptint.new(n)
end

local function BenchFunc(name: string, fn: (AptInt, AptInt) -> ()): ()
	local start: number

	--> division takes more the smaller the divisor is.
	local isDiv: boolean = (name == "divBench")

	for _: number, digitCount: number in digits do
		local int1: AptInt = BuildRandomNum(digitCount)
		local int2: AptInt = BuildRandomNum(isDiv and digitCount/2+1 or digitCount)

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
