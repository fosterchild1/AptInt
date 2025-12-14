### BigInteger.luau: Luau implementation of BigInteger with added typechecking

# Extensions
Extending the module is very easy. Just call `BigInteger.Extend(func: typeof(BigInteger) -> ())`. For example,
```luau
BigInteger.Extend(function(tbl: typeof(BigInteger) | any)
	function tbl:IsEven(): boolean
		return (self :: BigInteger).digits[1] % 2 == 0
	end
end)
```
