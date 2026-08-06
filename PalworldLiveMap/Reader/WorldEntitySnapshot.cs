namespace PalworldLiveMap.Reader;

internal readonly record struct WorldEntitySnapshot(
    string Id,
    string Layer,
    string Name,
    string ClassName,
    string? CharacterId,
    bool IsTamed,
    double X,
    double Y,
    double Z);
