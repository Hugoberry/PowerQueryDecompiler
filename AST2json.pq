(placeholder) =>
let 
    resource = Value.ResourceExpression(placeholder),
    func = (_) => try Value.Metadata(Value.Type(_))[Documentation.Name] otherwise
                  try Value.ResourceExpression(_)[Name] otherwise "function",
    trace = (_) => if _ is function then func(_)
        else if _ is type then "type"
        else if _ is null then "null"
        else if _ is list then List.Accumulate(_,{},(s,c)=>s&{@trace(c)})
        else if _ is record then List.Accumulate(Record.FieldNames(_),[],(s,c)=>Record.AddField(s,c,@trace(Record.Field(_,c))))
        else Text.From(_)
in Json.FromValue(trace(resource))