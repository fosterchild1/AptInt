AptInt is a luau implementation of BigInteger. It uses base 10^7 to store numbers and it can go up to 90 sextillion digits before it starts losing precision.

# Construction

You can construct an AptInt in four ways:

```luau
AptInt.new() -- equal to AptInt.new({0})
AptInt.new("123") -- O(n)
AptInt.new(123) -- O(n)
AptInt.new({123}) -- O(1)
```

# Methods
Each method has their arguments and their types listed, alongside their computational complexity.<br/>
Metamethods are also supported, but they have added overhead compared to the raw functions.

In the computational complexity, we use a couple of terms that may be unknown to some. Their meanings are listed below:
- n - the size of the input
- M(n) - computational complexity of multiplying the input - O(n^2), O(n^1.565) or O(n^1.465) depending on input size.
- D(n) - computational complexity of dividing the input - O(n^2) or O(n log n) depending on input size.

```luau
clone(n: AptInt) -> Aptint -- O(n)
Negate(n: AptInt, inPlace: boolean) -> Aptint -- O(1) for inPlace, O(n) otherwise
```

### Arithmetic
```luau
AddRaw: (term: AptInt, term: AptInt, inPlace: AptInt) -> Aptint -- O(n), inPlace modifies self in-place.
SubtractRaw: (term: AptInt, term: AptInt, inPlace: AptInt) -> Aptint -- O(n), inPlace modifies self in-place.
MultiplyRaw: (factor: AptInt, factor: AptInt) -> Aptint -- M(n)
DivideRaw: (dividend: AptInt, divisor: AptInt) -> (AptInt, AptInt) -- D(n)
ModRaw: (n: AptInt, div: AptInt) -> Aptint -- D(n)
PowRaw: (n: AptInt, pow: AptInt) -> AptInt -- M(n) * O(log n)
sqrt: (n: AptInt) -> AptInt -- O(n^2 log n) for Newton-Heron, fast O(n log n) for Karatsuba square root
```

### Comparison
```luau
EqualsRaw: (x: AptInt, y: AptInt) -> boolean -- O(n)
LowerThanRaw: (x: AptInt, y: AptInt) -> boolean -- O(n)
LowerOrEqualToRaw: (x: AptInt, y: AptInt) -> boolean -- O(n)
```

### Other
```luau
LeftShift: (n: AptInt, amount: number) -> AptInt -- O(n)
RightShift: (n: AptInt, amount: number0 -> AptInt -- O(n)
```

### Conversion
```luau
ToString: (n: AptInt) -> string -- O(n)
ToNumber: (n: AptInt) -> number -- O(n)
```

# Extensions
Extensions are extra methods/variables added with the `Extend` function. Currently, the official extensions are:

```luau
Abs: (n: AptInt, inPlace: boolean) -> AptInt, -- O(1) for inPlace, O(n) otherwise
IsEven: (n: AptInt) -> boolean, -- O(1)
Min: (...AptInt) -> boolean, -- O(n)
Max: (...AptInt) -> boolean, -- O(n)
Clamp: (n: AptInt, min: AptInt, max: AptInt) -> AptInt, -- O(n)
ModPow: (n: AptInt, mod: AptInt, exp: AptInt) -> AptIntm -- M(N) * O(log n)
```

# Syntax
You can use an AptInt in two ways:
1. Calling the raw functions - this is the faster way. You can only pass in AptInts and not other data types, with the exception of `LeftShift` and `RightShift`.
2. Using arithmetic operators directly - AptInt supports operators such as `+`, `-`, `*`, `/`, `^`, `%`, and they also allow you to use other data types like numbers or strings directly, at the cost of performance.

# Example Usage
Below is example usage of almost all functions provided by Aptint.luau and Extensions.luau. It is also timed and usually finishes in a millisecond, with most of the time being spent on exponentiation.
```luau
local aptint = require(game.ReplicatedStorage.AptInt)
require(game.ReplicatedStorage.AptInt.Extensions)

type AptInt = aptint.AptInt -- optional

local start: number = os.clock()

local x: AptInt = aptint.new("189234913413490")
local y: AptInt = aptint.new("9012349012343490119034")
local z: AptInt = aptint.new(12193)
local w: AptInt = aptint.new({56})

print(x:ToString(), y:ToString(), z:ToString(), w:ToString()) -- 189234913413490, 9012349012343490119034, 12193, 56
print(x:ToNumber(), y:ToNumber(), z:ToNumber(), w:ToNumber()) -- won't match :ToString() results due to double precision

--> negation
print(-x, -y) -- -189234913413490, -9012349012343490119034
print(-x == x:Negate(), -y == y:Negate()) -- true, true

--> addition
print(x + y) -- 9012349201578403532524
print(x + y == x:AddRaw(y)) -- true

--> subtraction
print(x - y) -- -9012348823108576705544
print(x - y == x:SubtractRaw(y)) -- true

--> multiplication
print(x * y) -- 1705451085002972471905668363361368660
print(x * y == x:MultiplyRaw(y)) -- true

--> division
print(x / y, y / x) -- 0, 47625191
print(x / y == x:DivideRaw(y), y / x == y:DivideRaw(x)) -- true, true

--> modulo
print(x % z, y % x) -- 6501, 117157566892444
print(x % z < x:ModRaw(z), y % x > y:ModRaw(x)) -- false, false

--> exponentiation
print(x ^ w) -- 32514036223443818658666570820773897187131153144315156149796159889594110235088130815486702658418689303967322551776061233110733856666188520606046203541487526744978697268624908930891991692677194433039757018952689791349889558362298065381765020144225256562503576779807721417275236547177622338980771070805187332601074109411066979379416928975392909324458659310591619674434891034337428433851093726569936220342131949259425917664234626052601806328228079886484005517894641978810310456199692440073854572204955477598194457596242817389098299760810308800031756375052331751488986937507305703604948452437651836947695048811539858617086040404708980301226604335294410391579875203623659207743316274004917715589113056535037465902146148814089582712158693559047903440100000000000000000000000000000000000000000000000000000000
print(x ^ w ~= x:PowRaw(w)) -- false

--> EXTENSIONS
print(aptint.new(0) == aptint.zero) -- true

print((-x):Abs()) -- 189234913413490
print(x:Max(y, z, w)) -- 9012349012343490119034

print(os.clock() - start) -- usually finishes in 1ms
```
