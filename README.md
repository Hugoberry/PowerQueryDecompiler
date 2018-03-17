# Power Query Decompiler
This repository contains a proof of concept on decompiling Power Query (M) functions.
![Output](img/DecompileCall.PNG "Output")

## Structure

`AST.pq` - a deep call to `Value.ResourceExpression` in order to demo how the A Statement Tree (AST) looks for  `List.Range` 

`AST2json.pq` - serializing the output from `Value.ResourceExpression` to `JSON` 

`Decompile.pq` - function definition that translates an AST into an expression

`Expression.pq` - same code as `Decompile(x)` function exposed as an expression(query)
 