--!native
--!strict
--!optimize 2

local Radix = {}

local Add = require("./Add")
local Mul = require("./Mul")

local tcreate: (number, {number}) -> {{number}} = table.create
local tinsert: ({number}, number) -> () = table.insert

local ceil: (number) -> number = math.ceil

function Radix.fromString(str: string): ({number}, number)
	--> Algorithm 1.25: FastIntegerInput
	--> https://maths-people.anu.edu.au/~brent/pd/mca-cup-0.5.9.pdf
	if str == "0" then return {}, 0 end
	--> KEEP IN MIND: l = bigint array, b = also bigint
	
	
	local isNegative: boolean = str:sub(1, 1) == "-"
	if isNegative then
		str = str:sub(2, #str)
	end
	
	--> l = [val(s_0), val(s_1) ... val(s_m-1)]
	local digits: {string} = str:split("")
	local digitCount = #digits
	local l: {{number}} = tcreate(digitCount, {0})
	
	for i: number, digit: string in digits do
		l[digitCount - i + 1] = {tonumber(digit) or 0}
	end
	
	local b: {number}, k: number = {10}, #l -- (b, k) <- (B, m)
	
	while k > 1 do
		local lIdx: number = 1
		local new: {{number}} = {}
		for i: number = 1, k - 1, 2 do
			local bli1: {number} = Mul.MulLimbs(l[i + 1], b)
			new[lIdx] = Add.AddLimbs(l[i], bli1) -- [l_x + bl_x+1, ... ,l_k-2 + bl_k-1]
			lIdx += 1
		end
		
		--> if l odd l[k-1] = unchanged
		if k % 2 == 1 then
			new[lIdx] = l[k]
		end
		
		l = new
		b = Mul.MulLimbs(b, b)
		
		k = ceil(k/2)
	end
	
	return l[1], isNegative and -1 or 1
end

return Radix