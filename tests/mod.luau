--!native
--!optimize 2

local aptint = require(game.ReplicatedStorage.AptInt)

local random = math.random

local function testRandomModulo()
	--> init vars
	local int1: string = random(1, 2) == 1 and "-" or ""
	local int2: string = random(1, 2) == 1 and "-" or ""

	for i = 1, math.random(1, 7) do
		int1 ..= random(1, 9)
	end
	
	for i = 1, math.random(1, 14) do
		int2 ..= random(1, 9)
	end

	local bint1: aptint.AptInt = aptint.new(int1)
	local bint2: aptint.AptInt = aptint.new(int2)
	local b: aptint.AptInt = bint1:ModRaw(bint2)
	
	assert(
		tonumber(int1) % tonumber(int2) == b:ToNumber(),
		`modulo test failed: term1: {int1}, term2: {int2}, expected: {tonumber(int1) % tonumber(int2)}, got {b}`
	)
end

for i = 1, 10000 do
	testRandomModulo()
end
