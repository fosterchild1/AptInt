--!native
--!strict
--!optimize 2

--> THIS IS VERY UGLY CODE!!! I ONLY USE THIS FOR WHEN BENCHMARKING ALGORITHM THRESHOLDS

local aptint = require(game.ReplicatedStorage.AptInt.AptInt)

type AptInt = aptint.AptInt

local clock: () -> number = os.clock
local random: (number?, number?) -> number = math.random
local insert = table.insert

local MAX: number = 2^24-1
local LOG2_10: number = 3.32192809489

local function BuildRandomNum(digitCount: number): AptInt
	if digitCount <= 1 then
		return aptint.new({random(1, MAX)})
	end

	local len: number = digitCount * LOG2_10/24
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

local function bench(fn: () -> (), runs: number)
	local start = os.clock()
	for i = 1, runs do
		fn()
	end
	
	return (os.clock() - start)/runs
end

local inarow=0
local best = 0
for i = 1, 1000, 7 do
	local int1 = BuildRandomNum(i)
	local int2 = BuildRandomNum(i)
	
	local Atime = bench(function()
		
	end, 30)
	local Btime = bench(function()
		
	end, 30)

	if Atime < Btime then
		inarow+=1
		continue
	end
	
	if inarow >= best then
		print("NEW BEST! "..inarow)

		best=inarow
		inarow=0

		continue
	end
	
	inarow = 0
	task.wait()
end
