## 0.2.0

- **BREAKING**: Replaced `build_runner` with standalone `package:analyzer`. No longer requires `build_runner`, `source_gen`, or `build.yaml`.
- `ClassCollector.collect()` now takes a `String packageRoot` instead of a `BuildStep`.
- Removed `IntentionsBuilder` and `intentionsBuilder()` factory.
- Designed for use with [Dart build hooks](https://dart.dev/tools/hooks) (`hook/build.dart`).

## 0.1.0

- Initial release.
