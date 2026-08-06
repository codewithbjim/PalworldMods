namespace PalworldLiveMap.Reader;

internal readonly record struct PlayerSnapshot(
    DateTimeOffset CapturedAt,
    long PawnAddress,
    double X,
    double Y,
    double Z,
    double Pitch,
    double Yaw,
    double Roll);
