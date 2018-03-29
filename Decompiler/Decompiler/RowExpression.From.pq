(fn, depth)=>
let
    Value.FixType = (value, optional depth) =>
        let
            nextDepth = if depth = null then 3 else depth - 1,
            result = if depth = 0 then null
                else if value is type then TextType(value)
                else if value is table then Table.TransformColumns(value, {}, @Value.FixType)
                else if value is list then List.Transform(value, each @Value.FixType(_, nextDepth))
                else if value is record then
                    Record.FromList(List.Transform(Record.ToList(value), each @Value.FixType(_, nextDepth)), Record.FieldNames(value))
                else if value is function then "<function>"
                else value
        in
            result,

    TextType = (t as type) as text => 
        let
            nonNullableType = Type.NonNullable(t),
            TypeDescription = if Type.Is(nonNullableType, type binary) then "binary"
            else if Type.Is(nonNullableType, type date) then "date"
            else if Type.Is(nonNullableType, type datetime) then "datetime"
            else if Type.Is(nonNullableType, type datetimezone) then "datetimezone"
            else if Type.Is(nonNullableType, type duration) then "duration"
            else if Type.Is(nonNullableType, type function) then "function"
            else if Type.Is(nonNullableType, type list) then "list"
            else if Type.Is(nonNullableType, type logical) then "logical"
            else if Type.Is(nonNullableType, type none) then "none"
            else if Type.Is(nonNullableType, type null) then "null"
            else if Type.Is(nonNullableType, type number) then "number"
            else if Type.Is(nonNullableType, type record) then "record"
            else if Type.Is(nonNullableType, type table) then "table"
            else if Type.Is(nonNullableType, type text) then "text"
            else if Type.Is(nonNullableType, type time) then "time"
            else if Type.Is(nonNullableType, type type) then "type"
            else if Type.Is(nonNullableType, type action) then "action"
            else if Type.Is(type anynonnull, nonNullableType) then "any"
            else error "Unknown type",
            TypeString = if TypeDescription = "any" then 
                             if Type.IsNullable(t) then 
                                 "any" else "anynonnull"
                             else if Type.IsNullable(t) then 
                                 "nullable " & TypeDescription 
                             else TypeDescription
        in
            TypeString,

    FunctionSignature = (functionType as type) =>
        let
            Parameters = Record.ToTable(Type.FunctionParameters(functionType)), // Name, Value
            WithIndex = Table.AddIndexColumn(Parameters, "Required"),
            MinParameters = Type.FunctionRequiredParameters(functionType),
            WithRequired = Table.TransformColumns(WithIndex, {{"Required", (index) => index < MinParameters}}),
            WithNullable = Table.AddColumn(WithRequired, "Nullable", each Type.IsNullable([Value])),
            WithMetadata = Table.AddColumn(WithNullable, "Metadata", each Value.Metadata([Value])),
            WithDocumentation = Table.ExpandRecordColumn(WithMetadata, "Metadata",
                {"Documentation.FieldCaption", "Documentation.FieldDescription", "Documentation.SampleValues", "Documentation.AllowedValues", "Documentation.DefaultValue"},
                {"fieldCaption", "fieldDescription", "sampleValues", "allowedValue", "defaultValue"}),
            // TODO: Add documentation to the allowed values
            Renamed = Table.RenameColumns(WithDocumentation,
            {
                {"Name", "name"},
                {"Value", "parameterType"},
                {"Required", "isRequired"},
                {"Nullable", "isNullable"}
            })
        in
            Renamed,

    Value.ToJsonText = (x,d) => Text.FromBinary(Json.FromValue(Value.FixType(x, d))),
    Result = Value.ToJsonText(fn,depth)
in
    Result