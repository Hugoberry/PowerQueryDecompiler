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
