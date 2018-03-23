let
    //  Entry point for routing the calls for various AST node "Kind"s 
    // TODO: throw
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
                if (kind = "Record") then recordExp(x) else
                if (kind = "Unary") then unaryExp(x) else
                if (kind = "Throw") then throwExp(x) else
                if (kind = "Function") then funcExp(x) else
                Text.Format("Unkonw Kind: #{0}",{kind})
    in
        expr,
    
    // Handle records
    recordExp = (x) =>
    let 
        members = x[Members],
        lines   = List.Transform(members,
                        each Text.Format("#{0} = #{1}",
                                        {_[Name],handleExp(_[Value])})
                        )
    in
        Text.Combine(lines,"#(cr)#(lf)"),

    // Handle Unary expressions
    unaryExp = (x) => 
    let 
        op = x[Operator],
        inExp = x[Expression],
        kind = inExp[Kind],
        exp = if (op = "Not") then "not (" & handleExp(inExp) & ")" else 
               if (op = "Negative") then "-(" & handleExp(inExp) & ")" else
                   handleExp(inExp)
    in 
        exp,

    // Throw
    throwExp = (x) =>Text.Format("error #{0}", handleExp(x[Expression])),

    // Function kind
    funcExp = (x) =>"[function]",

    // "Invocation" node handling
    invocationExp = (x) => 
    let 
        f    = x[Function],
        args = x[Arguments],
        funcStr = handleExp(f),
        argsStr = Text.Combine(List.Transform(args, each handleExp(_)),",")
    in
    Text.Format("#{0}(#{1})",{funcStr, argsStr}),

    // Get function name from a handle
    // TODO: have a peek at #shared first as docs are missleading
    functionName = (x) => 
        //try getting the name from the associated meta Documentation
        try Value.Metadata(Value.Type(x))[Documentation.Name] 
            otherwise
            // or "ResourceExpression"
            try Value.ResourceExpression(x)[Name] otherwise "function",
            
    // "If" node handling
    ifExp = (x) =>
    let 
        cond = handleExp(x[Condition]),
        left = handleExp(x[TrueCase]),
        right = handleExp(x[FalseCase])
    in 
        Text.Format("if(#{0}) then #{1} else #{2}", { cond, left, right }),

    // "Operator" node handling
    operatorExp = (x) => 
    let 
        op =
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
    // "Identifier" node handling
    identifierExp    = (x) => x[Name],
    // "Constnt" node handling
    constantExp      = (x) => x[Value],
    // "FieldAccess" node handling
    fieldAccessExp   = (x) => x[MemberName],

    // "ElementAccess" node handling
    elementAccessExp = (x) => 
    let
        refList = x[Collection][Value],
        idx = x[Key][Value]
    in functionName(refList{idx}),

    // Handles node of a "Binary" expression
    binaryExp = (x) => 
    let
        op = operatorExp(x[Operator]),
        left = handleExp(x[Left]),
        right = handleExp(x[Right]),
        format = if (op = "&") then "#{0} & #{2}"    
            else "#{0} #{1} #{2}"
    in 
        Text.Format(format, {left, op, right}),

    // Looping through the Members of a shallow AST and calls expression->text function:handleExp(x)
    run = (x)=>
    let
        members = x[Members]
    in 
        List.Transform(members,
                        each Text.Format("#{0} = #{1}",
                                        {_[Name],handleExp(_[Value])})
                        ),
    
    // Function to decompile
    fn = List.Range,
    // Getting a "shalow" view on the AST
    // TODO: replace with a search
    AST = 
    try Value.ResourceExpression(fn)[Expression][Function][Expression] otherwise 
            Value.ResourceExpression(fn)[Expression][Arguments]{0}[Function][Expression][Expression],
    // Start
    expression = run(AST)
in
    expression