namespace PalworldLiveMap.Reader;

internal sealed record NestedObjectInspection(
    string Path,
    string ClassName,
    string ObjectName,
    string Address);

internal sealed record PropertySignalInspection(
    string Path,
    string RawHex,
    bool IsAllZero,
    byte FirstByte);

internal sealed record ActorInspection(
    string Id,
    string ClassName,
    string ObjectName,
    double? X,
    double? Y,
    double? Z,
    IReadOnlyList<string> Properties,
    IReadOnlyList<NestedObjectInspection> NestedObjects,
    IReadOnlyList<PropertySignalInspection> Signals);
