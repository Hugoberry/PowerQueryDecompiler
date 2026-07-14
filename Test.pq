// Runs Decompile over every function in #shared whose resource expression is
// decompilable, and reports success/failure per function. Requires a query
// named "Decompile" (Decompile.pq) in the same workbook/PBIX.
let
    candidates =
        List.Select(
            Record.FieldNames(#shared),
            each try Value.ResourceExpression(Record.Field(#shared, _))[Kind] = "Function"
                 otherwise false),

    results =
        List.Transform(
            candidates,
            each
                let
                    r = try Decompile(Record.Field(#shared, _))
                in
                    [
                        Name  = _,
                        Ok    = not r[HasError],
                        Code  = Record.FieldOrDefault(r, "Value", null),
                        Error = Record.FieldOrDefault(r, "Error", null)
                    ]),

    asTable = Table.FromRecords(results),
    sorted  = Table.Sort(asTable, {{"Ok", Order.Ascending}, {"Name", Order.Ascending}})
in
    sorted
