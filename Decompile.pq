// Decompiles a Power Query (M) function into M source text by walking the
// undocumented AST returned by Value.ResourceExpression.
//
// AST facts this version relies on (verified against List.Range,
// List.FindText and a large user-defined function):
//  * `let` desugars to FieldAccess(result, Record(Identifier = selfId, Members)),
//    and binding references appear as selfId[name]. A reference to the member
//    currently being defined is recursion and must render as @name.
//  * A runtime type-checking harness wraps everything: invocations of
//    constant-held harness functions - wrapper(value) / wrapper(value,
//    typeInfo) - plus immediate lambda applications whose arguments are
//    exactly the lambda's own parameters (possibly themselves wrapped).
//    The wrapper handle is either unnamed or reference-equal to Value.As
//    in #shared (newer engines). Both patterns are stripped (the latter
//    beta-reduced), but funcExp first harvests the typeInfo they carry to
//    re-emit `as` ascriptions on function signatures.
//  * Function parameters live in FunctionType[Parameters][Identifier]; Min
//    gives the count of required parameters (rest render as `optional`).
//  * `try a otherwise b` compiles to TryCatch [Try, ExceptionCase[Variable,
//    Expression]].
//  * `{a .. b}` compiles to Binary Operator = "Range"; `x meta y` to
//    Binary Operator = "MetadataAdd".
//  * Library references are ElementAccess into a constant pool that holds
//    function handles AND plain values (enum numbers like Occurrence.Last = 1,
//    TextEncoding.Unicode = 1200, and opaque type values).
(fn as function) =>
let
    // ============================ helpers ============================

    keywords = {"and","as","each","else","error","false","if","in","is","let",
                "meta","not","null","or","otherwise","section","shared","then",
                "true","try","type","catch"},

    quoteIdentifier = (name as text) as text =>
    let
        allowed   = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._",
        plainBody = List.MatchesAll(Text.ToList(name), each Text.Contains(allowed, _)),
        startsOk  = name <> "" and not List.Contains({"0".."9"}, Text.Start(name, 1)),
        isPlain   = plainBody and startsOk and not List.Contains(keywords, name)
    in
        if isPlain then name
        else "#""" & Text.Replace(name, """", """""") & """",

    // Intrinsics like #binary / #table must not be re-quoted
    functionRef = (name as text) as text =>
        if Text.StartsWith(name, "#") then name else quoteIdentifier(name),

    // NB: "#(" starts an escape sequence inside M text literals, so neither
    // the search string "#(" nor replacements like "#(cr)" can be written
    // directly as literals - build them by concatenation instead.
    escapeText = (t as text) as text =>
    let
        hash = "#",
        a = Text.Replace(t, hash & "(", hash & "(" & hash & ")" & "("),
        b = Text.Replace(a, """", """"""),
        c = Text.Replace(b, Character.FromNumber(13), hash & "(cr)"),
        d = Text.Replace(c, Character.FromNumber(10), hash & "(lf)"),
        e = Text.Replace(d, Character.FromNumber(9),  hash & "(tab)")
    in
        e,

    // Best-effort name for a function handle:
    //   1. reverse lookup in #shared
    //   2. Documentation.Name metadata
    //   3. Value.ResourceExpression name
    functionName = (f as function) as text =>
    let
        sharedName =
            try List.First(
                    List.Select(
                        Record.FieldNames(#shared),
                        (n) => try Record.Field(#shared, n) = f otherwise false),
                    null)
            otherwise null,
        docName = try Value.Metadata(Value.Type(f))[Documentation.Name] otherwise null,
        resName = try Value.ResourceExpression(f)[Name] otherwise null
    in
        List.First(List.RemoveNulls({sharedName, docName, resName}), "function"),

    // Classify a runtime type value into its primitive kind via Type.Is.
    // Structure (list item types, record fields, function signatures) is
    // still unrecoverable, but the primitive kind + nullability is enough
    // for `as` ascriptions, which only allow nullable primitive types.
    typeName = (t as type) as text =>
    let
        prims = {
            [P = type null,         N = "null"],
            [P = type logical,      N = "logical"],
            [P = type number,       N = "number"],
            [P = type text,         N = "text"],
            [P = type binary,       N = "binary"],
            [P = type date,         N = "date"],
            [P = type time,         N = "time"],
            [P = type datetime,     N = "datetime"],
            [P = type datetimezone, N = "datetimezone"],
            [P = type duration,     N = "duration"],
            [P = type list,         N = "list"],
            [P = type record,       N = "record"],
            [P = type table,        N = "table"],
            [P = type function,     N = "function"],
            [P = type type,         N = "type"]
        },
        hit = List.First(
                  List.Select(prims, (p) => try Type.Is(t, p[P]) otherwise false),
                  null)
    in
        if hit = null then "any" else hit[N],

    // Render a runtime type value as a type expression: `type nullable text`
    typeText = (t as type) as text =>
    let
        base = typeName(try Type.NonNullable(t) otherwise t),
        nn   = (try Type.IsNullable(t) otherwise false) and base <> "any"
    in
        "type " & (if nn then "nullable " else "") & base,

    // " as ..." ascription for a harvested type value; "" when unknown or
    // `any`. `optional` parameters are implicitly nullable, so the nullable
    // prefix is dropped there.
    ascription = (t, forOptional as logical) as text =>
        if t = null then ""
        else
        let
            base = typeName(try Type.NonNullable(t) otherwise t),
            nn   = (try Type.IsNullable(t) otherwise false)
                   and not forOptional and base <> "any"
        in
            if base = "any" then ""
            else " as " & (if nn then "nullable " else "") & base,

    // Render a plain M value (not an AST node) as an M source literal
    literal = (v) as text =>
        if v = null then "null"
        else if v is logical then (if v then "true" else "false")
        else if v is number then Number.ToText(v)
        else if v is text then """" & escapeText(v) & """"
        else if v is list then
            "{" & Text.Combine(List.Transform(v, @literal), ", ") & "}"
        else if v is record then
            "[" & Text.Combine(
                      List.Transform(
                          Record.FieldNames(v),
                          (n) => quoteIdentifier(n) & " = " & @literal(Record.Field(v, n))),
                      ", ")
                & "]"
        else if v is function then functionRef(functionName(v))
        else if v is type then typeText(v)  // primitive kind only; structure is lost
        else Text.From(v),

    // ==================== operators and precedence ====================

    operatorInfo = (op as text) as record =>
        Record.FieldOrDefault(
            [
                Or                  = [Symbol = "or",   Prec = 1],
                And                 = [Symbol = "and",  Prec = 2],
                Equals              = [Symbol = "=",    Prec = 3],
                NotEquals           = [Symbol = "<>",   Prec = 3],
                GreaterThan         = [Symbol = ">",    Prec = 4],
                GreaterThanOrEquals = [Symbol = ">=",   Prec = 4],
                LessThan            = [Symbol = "<",    Prec = 4],
                LessThanOrEquals    = [Symbol = "<=",   Prec = 4],
                Add                 = [Symbol = "+",    Prec = 5],
                Subtract            = [Symbol = "-",    Prec = 5],
                Concatenate         = [Symbol = "&",    Prec = 5],
                Multiply            = [Symbol = "*",    Prec = 6],
                Divide              = [Symbol = "/",    Prec = 6],
                MetadataAdd         = [Symbol = "meta", Prec = 6.5]
            ],
            op,
            [Symbol = op, Prec = 3]),

    // A FieldAccess over a self-identified Record node is a desugared `let`
    isDesugaredLet = (x) as logical =>
        (try x[Kind] otherwise null) = "FieldAccess"
        and (try x[Expression][Kind] otherwise null) = "Record"
        and (try Record.HasFields(x[Expression], "Identifier") otherwise false),

    // Precedence of a rendered node, used to decide parenthesisation.
    //   0  = statement-like (if / function / try / error): always wrap when nested
    //   10 = primary (identifier, constant, invocation, accesses, {a..b})
    nodePrec = (x) as number =>
    let
        kind = try x[Kind] otherwise null
    in
        if isDesugaredLet(x) then 0
        else if kind = "Binary" then
            (if x[Operator] = "Range" then 10 else operatorInfo(x[Operator])[Prec])
        else if kind = "Unary" then 7
        else if kind = "If" or kind = "Function" or kind = "Throw"
                or kind = "TryCatch" or kind = "Let" then 0
        else 10,

    // ===================== harness normalisation ======================

    // Is f a Constant node holding a compiler harness function handle?
    // Two observed variants: a genuinely unnamed handle (functionName gives
    // the "function" sentinel) and, on newer engines, a handle that is
    // reference-equal to Value.As in #shared. Safe either way: real library
    // references compile to ElementAccess into the constant pool, never to
    // a Constant-held handle, so user code cannot match this test.
    isHarnessFn = (f) =>
        (try f[Kind] otherwise null) = "Constant"
        and (try f[Value] is function otherwise false)
        and List.Contains({"function", "Value.As"},
                          try functionName(f[Value]) otherwise "?"),

    // Extract the runtime type value out of a harness typeInfo argument.
    // Observed packagings: Constant(type), List{Constant(type)}, and either
    // of those wrapped in a further 1-arg harness invocation (normalize
    // removes that layer). Returns null when the shape is not recognised.
    typeFromInfo = (node) =>
    let
        n     = normalize(node),
        kind  = try n[Kind] otherwise null,
        inner = if kind = "List" and List.Count(n[Members]) = 1
                then normalize(n[Members]{0})
                else n
    in
        if (try inner[Kind] otherwise null) = "Constant"
           and (try inner[Value] is type otherwise false)
        then inner[Value]
        else null,

    // Strip the runtime type-checking harness before rendering a node:
    //  * wrapper(value) / wrapper(value, typeInfo) -> value, where wrapper is
    //    a harness invocation (see isHarnessFn)
    //  * (p1, .., pn) => body applied to exactly (p1, .., pn) -> body
    //    (the arguments may themselves be harness-wrapped: they are
    //    normalized before comparison)
    // Both patterns are produced only by the compiler; named library calls go
    // through ElementAccess, so real code is not affected.
    normalize = (x) =>
    let
        kind = try x[Kind] otherwise null
    in
        if kind <> "Invocation" then x
        else
        let
            f     = x[Function],
            fKind = try f[Kind] otherwise null,
            args  = x[Arguments],
            isWrapper =
                isHarnessFn(f)
                and (List.Count(args) = 1 or List.Count(args) = 2),
            betaBody =
                if fKind <> "Function" then null
                else
                let
                    params   = try List.Transform(f[FunctionType][Parameters],
                                                  each [Identifier])
                               otherwise null,
                    argNames = List.Transform(
                                   args,
                                   (a) => let n = @normalize(a)
                                          in  if (try n[Kind] otherwise null) = "Identifier"
                                              then n[Name] else null)
                in
                    if params <> null
                       and List.Count(params) = List.Count(argNames)
                       and List.MatchesAll(
                               List.Positions(params),
                               (i) => argNames{i} <> null and argNames{i} = params{i})
                    then f[Expression]
                    else null
        in
            if isWrapper then @normalize(args{0})
            else if betaBody <> null then @normalize(betaBody)
            else x,

    // Render a child expression, wrapping it in parentheses when its
    // precedence is lower than the context that contains it.
    // env = [Selves = {[Id, Member]}, Depth = indent level]
    child = (x, contextPrec as number, env as record) as text =>
    let
        n = normalize(x),
        s = handleExp(n, env)
    in
        if nodePrec(n) < contextPrec then "(" & s & ")" else s,

    // ========================= node handlers =========================

    identifierExp = (x, env) => quoteIdentifier(x[Name]),

    constantExp = (x, env) => literal(x[Value]),

    invocationExp = (x, env) =>
    let
        funcStr = child(x[Function], 10, env),
        args    = x[Arguments],
        n       = List.Count(args),
        // the last argument may be an unparenthesised `each`/lambda;
        // earlier arguments get wrapped so commas parse unambiguously
        argStrs = List.Transform(
                      List.Positions(args),
                      (i) => if i = n - 1
                             then handleExp(normalize(args{i}), env)
                             else child(args{i}, 1, env))
    in
        funcStr & "(" & Text.Combine(argStrs, ", ") & ")",

    ifExp = (x, env) =>
        "if " & handleExp(normalize(x[Condition]), env)
        & " then " & handleExp(normalize(x[TrueCase]), env)
        & " else " & handleExp(normalize(x[FalseCase]), env),

    unaryExp = (x, env) =>
    let
        op    = x[Operator],
        inner = child(x[Expression], 7, env)
    in
        if op = "Not" then "not " & inner
        else if op = "Negative" then "-" & inner
        else if op = "Positive" then "+" & inner
        else inner,

    binaryExp = (x, env) =>
        if x[Operator] = "Range" then
            // `{a .. b}` compiles to a bare Range node; braces restore it
            "{" & handleExp(normalize(x[Left]), env)
                & " .. "
                & handleExp(normalize(x[Right]), env) & "}"
        else
        let
            info   = operatorInfo(x[Operator]),
            p      = info[Prec],
            left   = child(x[Left], p, env),
            // right operand of non-associative operators needs parentheses
            // even at equal precedence: a - (b - c), a / (b / c)
            rightP = if info[Symbol] = "-" or info[Symbol] = "/" then p + 1 else p,
            right  = child(x[Right], rightP, env)
        in
            left & " " & info[Symbol] & " " & right,

    fieldAccessExp = (x, env) =>
    let
        target  = try x[Expression] otherwise null,
        tKind   = try target[Kind] otherwise null,
        opt     = if (try x[IsOptional] otherwise false) = true then "?" else "",
        member  = x[MemberName],
        // reference to a let binding through the record self-id?
        selfHit = if tKind = "Identifier"
                  then List.First(
                           List.Select(env[Selves], each [Id] = target[Name]),
                           null)
                  else null
    in
        // desugared let: [bindings][result] -> let ... in result
        if isDesugaredLet(x) then letFromRecord(target, member, env)
        // selfId[x] -> x; if x is the member being defined, it's recursion -> @x
        else if selfHit <> null then
            (if selfHit[Member] = member then "@" else "") & quoteIdentifier(member)
        else if target = null then "[" & quoteIdentifier(member) & "]" & opt
        else child(target, 10, env) & "[" & quoteIdentifier(member) & "]" & opt,

    elementAccessExp = (x, env) =>
    let
        coll = x[Collection],
        key  = x[Key],
        opt  = if (try x[IsOptional] otherwise false) = true then "?" else "",
        // Library references index into a constant pool of function handles
        // and plain values (enum numbers, opaque types) - inline them.
        resolved =
            try
                let item = coll[Value]{key[Value]}
                in  if item is function then functionRef(functionName(item))
                    else if item is type then typeText(item)
                    else literal(item)
            otherwise null
    in
        if resolved <> null then resolved
        else child(coll, 10, env) & "{" & handleExp(normalize(key), env) & "}" & opt,

    listExp = (x, env) =>
    let
        items = List.Transform(
                    x[Members],
                    (m) => if (try m[Kind] otherwise null) = "Binary"
                              and (try m[Operator] otherwise null) = "Range"
                           then handleExp(normalize(m[Left]), env)
                                & " .. "
                                & handleExp(normalize(m[Right]), env)
                           else handleExp(normalize(m), env))
    in
        "{" & Text.Combine(items, ", ") & "}",

    recordExp = (x, env) =>
    let
        // record literals also carry a self-identifier so fields can
        // reference each other; bring it into scope per field
        selfId = try x[Identifier] otherwise null,
        fields = List.Transform(
                     x[Members],
                     (m) => quoteIdentifier(m[Name]) & " = "
                            & handleExp(
                                  normalize(m[Value]),
                                  if selfId = null then env
                                  else [Selves = {[Id = selfId, Member = m[Name]]}
                                                 & env[Selves],
                                        Depth = env[Depth]]))
    in
        "[" & Text.Combine(fields, ", ") & "]",

    // Re-sugar FieldAccess(Record(...)) back into a let expression
    letFromRecord = (rec, resultName as text, env as record) as text =>
    let
        selfId   = rec[Identifier],
        depth1   = env[Depth] + 1,
        pad      = Text.Repeat("    ", depth1),
        pad0     = Text.Repeat("    ", env[Depth]),
        bindings = List.Transform(
                       rec[Members],
                       (m) => pad & quoteIdentifier(m[Name]) & " = "
                              & handleExp(
                                    normalize(m[Value]),
                                    [Selves = {[Id = selfId, Member = m[Name]]}
                                              & env[Selves],
                                     Depth = depth1]))
    in
        "let#(cr,lf)"
        & Text.Combine(bindings, ",#(cr,lf)")
        & "#(cr,lf)" & pad0 & "in#(cr,lf)"
        & pad & quoteIdentifier(resultName),

    throwExp = (x, env) => "error " & child(x[Expression], 1, env),

    tryCatchExp = (x, env) =>
    let
        tryPart   = child(x[Try], 1, env),
        exc       = try x[ExceptionCase] otherwise null,
        varName   = try exc[Variable] otherwise null,
        catchPart = if exc = null then null
                    else handleExp(normalize(exc[Expression]), env),
        // `try a otherwise b` discards the exception variable; only use the
        // catch form when the variable is actually referenced
        usesVar   = varName <> null and catchPart <> null
                    and Text.Contains(catchPart, varName)
    in
        if exc = null then "try " & tryPart
        else if usesVar then
            "try " & tryPart & " catch (" & quoteIdentifier(varName) & ") => " & catchPart
        else "try " & tryPart & " otherwise " & catchPart,

    funcExp = (x, env) =>
    let
        ft      = try x[FunctionType] otherwise null,
        params  = if ft <> null then ft[Parameters] else {},
        min     = try Number.From(ft[Min]) otherwise List.Count(params),
        rawBody = x[Expression],

        // Harvest type ascriptions from the harness before normalize strips
        // it. Full shape:
        //   wrapper(((p1..pn) => body)(wrapper(p1, t1), .., wrapper(pn, tn)),
        //           tRet)
        // Every piece is optional; unrecognised shapes just yield nulls and
        // the signature renders untyped, exactly as before.
        outerArgN =
            if (try rawBody[Kind] otherwise null) = "Invocation"
               and isHarnessFn(try rawBody[Function] otherwise null)
            then List.Count(rawBody[Arguments])
            else 0,
        outerIsWrapper = outerArgN = 1 or outerArgN = 2,
        returnT   = if outerArgN = 2 then typeFromInfo(rawBody[Arguments]{1})
                    else null,
        innerApp  = if outerIsWrapper then rawBody[Arguments]{0} else rawBody,
        innerArgs = try innerApp[Arguments] otherwise null,
        paramTs   =
            if (try innerApp[Kind] otherwise null) = "Invocation"
               and (try innerApp[Function][Kind] otherwise null) = "Function"
               and innerArgs <> null
               and List.Count(innerArgs) = List.Count(params)
            then List.Transform(
                     List.Positions(params),
                     (i) => let a = innerArgs{i}
                            in  if (try a[Kind] otherwise null) = "Invocation"
                                   and isHarnessFn(try a[Function] otherwise null)
                                   and List.Count(a[Arguments]) = 2
                                then typeFromInfo(a[Arguments]{1})
                                else null)
            else List.Transform(params, each null),

        names  = List.Transform(
                     List.Positions(params),
                     (i) => (if i >= min then "optional " else "")
                            & quoteIdentifier(params{i}[Identifier])
                            & ascription(paramTs{i}, i >= min)),
        retAsc = ascription(returnT, false),
        body0  = normalize(rawBody),
        body   = handleExp(body0, env),
        isEach = List.Count(params) = 1 and min = 1
                 and params{0}[Identifier] = "_"
    in
        if isEach then "each " & body
        else if isDesugaredLet(body0)
             then "(" & Text.Combine(names, ", ") & ")" & retAsc & " =>#(cr,lf)" & body
        else "(" & Text.Combine(names, ", ") & ")" & retAsc & " => " & body,

    // ========================== dispatcher ===========================

    handlers = [
        Invocation    = invocationExp,
        ElementAccess = elementAccessExp,
        If            = ifExp,
        Binary        = binaryExp,
        Unary         = unaryExp,
        FieldAccess   = fieldAccessExp,
        Identifier    = identifierExp,
        Constant      = constantExp,
        Record        = recordExp,
        List          = listExp,
        Throw         = throwExp,
        TryCatch      = tryCatchExp,
        Function      = funcExp
    ],

    handleExp = (x, env as record) as text =>
    let
        x2   = normalize(x),
        kind = try x2[Kind]
               otherwise error Error.Record(
                             "Decompile.BadNode",
                             "AST node has no Kind field",
                             [Node = x2]),
        handler = Record.FieldOrDefault(handlers, kind, null)
    in
        if handler <> null then handler(x2, env)
        else error Error.Record(
                 "Decompile.UnknownKind",
                 "Unhandled AST node kind: " & kind,
                 [Kind = kind, Node = x2]),

    // ========================== entry point ==========================

    root = Value.ResourceExpression(fn),
    env0 = [Selves = {}, Depth = 0],

    expression =
        if root is record and Record.HasFields(root, "Kind")
             then handleExp(root, env0)
        else if root is record and Record.HasFields(root, "Expression")
             then handleExp(root[Expression], env0)
        else error Error.Record(
                 "Decompile.NoAst",
                 "Value.ResourceExpression output contains no decompilable expression node.",
                 [Root = root])
in
    expression
