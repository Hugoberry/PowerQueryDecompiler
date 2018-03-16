let

handleExp = (x) =>
let
    kind = x[Kind],
    expr =  if (kind = "Invocation") then invocationExp(x) else
            if (kind = "ElementAccess") then elementAccessExp(x) else
            if (kind = "If") then ifExp(x) else
            if (kind = "Binary") then binaryExp(x) else
            if (kind = "FieldAccess") then fieldAccessExp(x) else
            if (kind = "Identifier") then identifierExp(x) else
            if (kind = "Constant") then constantExp(x) else
            Text.Format("Unkonw Kind: #{0}",{kind})
in
    expr,

invocationExp = (x) => 
let 
     f    = x[Function],
     args = x[Arguments],
     funcStr = handleExp(f),
     argsStr = Text.Combine(List.Transform(args, each try _[Name] otherwise _[MemberName]),",")
in
  Text.Format("#{0}(#{1})",{funcStr, argsStr}),


functionName = (x) => 
    try Value.Metadata(Value.Type(x))[Documentation.Name] 
        otherwise
        try Value.ResourceExpression(x)[Name] otherwise "function",

ifExp = (x) =>
let 
   cond = handleExp(x[Condition]),
   left = handleExp(x[TrueCase]),
   right = handleExp(x[FalseCase])
in 
   Text.Format("if(#{0}) then #{1} else #{2}", { cond, left, right }),


operatorExp = (x) => 
let op =
        if (x = "Equals") then "=" else
        if (x = "NotEquals") then "!=" else
        if (x = "GreaterThan") then ">" else
        if (x = "GreaterThanOrEquals") then ">=" else
        if (x = "LessThan") then "<" else
        if (x = "LessThanOrEquals") then "<=" else
        if (x = "And") then "and" else
        if (x = "Or") then "or" else
        if (x = "Not") then "not" else
        if (x = "Add") then "+" else
        if (x = "Subtract") then "-" else
        if (x = "Multiply") then "*" else
        if (x = "Divide") then "/" else
        if (x = "Concatenate") then "&" else
        x
in
    op,

identifierExp    = (x) => x[Name],

constantExp      = (x) => x[Value],

fieldAccessExp   = (x) => x[MemberName],

elementAccessExp = (x) => 
let
    refList = x[Collection][Value],
    idx = x[Key][Value]
in functionName(refList{idx}),


binaryExp = (x) => 
let
    op = operatorExp(x[Operator]),
    left = handleExp(x[Left]),
    right = handleExp(x[Right]),
    format = if (op = "&") then "#{0} & #{2}"    
        else "#{0} #{1} #{2}"
in 
    Text.Format(format, {left, op, right}),

decompile = (x)=>
let
    members = x[Members]
in 
    List.Transform(members,each Text.Format("#{0} = #{1}",{_[Name],handleExp(_[Value])})),

    AST = decompile(Value.ResourceExpression(List.Range)[Expression][Arguments]{0}[Function][Expression][Expression])
in
    AST