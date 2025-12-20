<p align="center"><img src="https://github.com/fosterchild1/AptInt/blob/main/resources/text.png" width="659" height="288"></p>

## <p align="center">Luau implementation of BigInteger.</p>
It can support up to b × 2⁵³ digits before it loses precision.

Right now, b = 10⁷, which is around 90 sextillion digits.

# 💡 Getting the most performance out of it
You can make <b>AptInt</b> work better for your use case by:
- Changing it's "BASE" variable. By default, it is set to 7. If you know you aren't going to multiply or divide two numbers, it can go all the way up to 14, doubling it's performance.
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
Note that these were done on an i7-10750H CPU @ 2.60GHz.<br/>
The results are updated every time the performance gets improved.

| Digit count | Addition | Subtraction | Multiplication | Division |
| ---  | --- | --- | --- | --- |
| 1 | 1μs | 1μs | 6μs | 1s |
| 50 | 1μs | 3μs | 38μs | 4μs |
| 100 | 5μs | 7μs | 70μs | 13μs |
| 500 | 11μs | 9μs | 850μs | 479μs |
| 1,000 | 14μs | 59μs | 1ms | 1ms |
| 5,000 | 49μs | 65μs | 19ms | 25ms |
| 10,000 | 68μs | 80μs | 43ms | 71ms |
| 50,000 | 393μs | 375μs | 320ms | 2.6s |
| 100,000 | 551μs | 638μs | 693ms | 6s |
