<p align="center"><img src="https://github.com/fosterchild1/AptInt/blob/main/resources/text.png" width="659" height="288"></p>

## <p align="center">The most performant Luau implementation of BigInteger.</p>
It can support up to b × 2⁵³ digits before it loses precision.

Right now, b = 10⁷, which is around 90 sextillion digits.

# 💡 Getting the most performance out of it
You can make <b>AptInt</b> work better for your use case by:
- Changing it's "BASE" variable. By default, it is set to 7. If you know you aren't going to multiply or divide two numbers, it can go all the way up to 14, doubling its performance.
- Only constructing using number tables. Avoid parsing from strings or numbers if possible.
- Using the raw methods instead of metamethods. This avoids additional overhead created by verifying the arguments.

# 💡 Extensions
Extending the module is very easy. Just call `AptInt.Extend(func)`. For example,

```luau
AptInt.Extend(function(tbl: typeof(AptInt) | any)
	function tbl:IsEven(): boolean
		return (self :: AptInt).digits[1] % 2 == 0
	end
end)
```

# 💡 Benchmarks
Note that these were done on an i7-10750H CPU.<br/>
The results are updated every time the performance gets improved.

| Digit count | Addition | Subtraction | Multiplication | Division |
| ---  | --- | --- | --- | --- |
| 1 | 1μs | 1μs | 2μs | 6μs |
| 50 | 1μs | 3μs | 9μs | 24μs |
| 100 | 1μs | 7μs | 13μs | 31μs |
| 500 | 2μs | 9μs | 220μs | 114μs |
| 1,000 | 19μs | 13μs | 659μs | 353μs |
| 5,000 | 42μs | 30μs | 10ms | 7ms |
| 10,000 | 59μs | 74μs | 42ms | 31ms |
| 50,000 | 258μs | 286μs | 503ms | 634ms |
| 100,000 | 515μs | 558μs | 984ms | 2.5s |
