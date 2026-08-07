# Changelog

## 0.1.0 - 2026-07-23

- Initial KeepWorking release.
- Preserves toggle-based manual work through alt-tab focus loss and in-game windows.
- Uses event-driven interaction hooks with no player or UObject polling.
- Keeps the frequent UI-hook path allocation-free and silent unless action is required.
- Samples foreground state every 100 ms through a minimal native helper.
