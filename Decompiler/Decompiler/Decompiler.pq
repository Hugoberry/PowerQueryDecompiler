// This file contains your Data Connector logic
section Decompiler;

[DataSource.Kind="Decompiler", Publish="Decompiler.Publish"]
shared Decompiler.Contents = (optional message as text) =>
    let
        _message = if (message <> null) then message else "(no message)",
        a = "Hello from Decompiler: " & _message
    in
        a;

// Data Source Kind description
Decompiler = [
    Authentication = [
        // Key = [],
        // UsernamePassword = [],
        // Windows = [],
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
Decompiler.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = Decompiler.Icons,
    SourceTypeImage = Decompiler.Icons
];

Decompiler.Icons = [
    Icon16 = { Extension.Contents("Decompiler16.png"), Extension.Contents("Decompiler20.png"), Extension.Contents("Decompiler24.png"), Extension.Contents("Decompiler32.png") },
    Icon32 = { Extension.Contents("Decompiler32.png"), Extension.Contents("Decompiler40.png"), Extension.Contents("Decompiler48.png"), Extension.Contents("Decompiler64.png") }
];


// Utils


Extension.LoadFunction = (name as text) =>
    let
        binary = Extension.Contents(name),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

RowExpression.From = Extension.LoadFunction("RowExpression.From.pq");

Diagnostics = Extension.LoadFunction("Diagnostics.pq");

Diagnostics.LogValue = Diagnostics[LogValue];
Diagnostics.LogValue2 = Diagnostics[LogValue2];
Diagnostics.LogFailure = Diagnostics[LogFailure];
Diagnostics.WrapFunctionResult = Diagnostics[WrapFunctionResult];
Diagnostics.WrapHandlers = Diagnostics[WrapHandlers];

Value.IfNull = (a, b) => if a <> null then a else b;

Value.ToText = (value, optional depth) =>
        let
            nextDepth = if depth = null then 3 else depth - 1,
            result = if depth = 0 then "..."
                else if value is null then "<null>"
                else if value is function then "<function>"
                else if value is table then "#table({" & Text.Combine(Table.ColumnNames(value), ",") & "},{" & Text.Combine(
                    List.Transform(Table.ToRows(Table.FirstN(value, 2)), each @Value.ToText(_, nextDepth)), "},#(cr)#(lf){") & "})"
                    //& "Row Count (" & Number.ToText(Table.RowCount(value)) & ")"
                else if value is list then "{" & Text.Combine(List.Transform(List.FirstN(value, 10), each @Value.ToText(_, nextDepth)), ",") & "}"
                else if value is record then "[" & Text.Combine(List.Transform(Record.FieldNames(value), each _ & "=" & @Value.ToText(Record.Field(value, _), nextDepth)), ",") & "]"
                else if value is type then List.First(Table.Schema(#table({"type"}, {{value}}))[TypeName], "<type>")
                else Text.From(value)
        in
            try result otherwise "<error>";