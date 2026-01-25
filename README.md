<p align="center"><img src="https://github.com/fosterchild1/AptInt/blob/main/resources/text.png" width="659" height="288"></p>

## <p align="center">The most performant Luau implementation of BigInteger.</p>
# About
AptInt is the fastest luau implementation of BigInteger. It uses base 10^7 to store numbers and uses asymptotically faster algorithms designed for working with numbers over 10,000 digits long.

# What makes it so fast?
AptInt uses the Karatsuba and Toom-Cook3 algorithms for multiplication, Knuths algorithm D for division, Karatsuba sqrt for finding the square root and more. Alongside these algorithms, it uses many techniques to shave off hundreds of milliseconds of computing time.

It also utilizes the full power of native code generation to get even faster results.

# Extensions
AptInt comes with a couple of official extensions made to help you. They are functions deemed too unimportant to be put in the main script, and so they can be found in a seperate `Extensions.luau` file to keep the codebase tidier.<br/>

The extensions are designed for ease of use, and you can use them as such:
```luau
local aptint = require("AptInt")
local ext = require("AptInt/Extensions")

type ExtendedApt = ext.ExtendedApt
```

# Benchmarks
Note that these were done on an i7-10750H CPU. The benchmark script can be found in [/bench/](https://github.com/fosterchild1/AptInt/blob/main/bench/bench.luau).<br/>
The results are updated every time the performance gets improved. They are also generally ~1.3x faster if running on the server.

| Digit count | Addition | Subtraction | Multiplication | Division | Square root |
| ---  | --- | --- | --- | --- | --- |
| 1 | 1μs | 1μs | 1μs | 6μs | 7μs |
| 50 | 1μs | 3μs | 9μs | 24μs | 40μs |
| 100 | 1μs | 7μs | 12μs | 31μs | 322μs |
| 500 | 2μs | 9μs | 120μs | 114μs | 737μs |
| 1,000 | 10μs | 13μs | 406μs | 326μs | 1ms |
| 5,000 | 37μs | 30μs | 4ms | 7ms | 4ms |
| 10,000 | 57μs | 74μs | 14ms | 14ms | 18ms |
| 50,000 | 229μs | 243μs | 128ms | 170ms | 141ms |
| 100,000 | 439μs | 470μs | 397ms | 404ms | 322ms |
