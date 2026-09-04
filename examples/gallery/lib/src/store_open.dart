/// Picks the store the platform can offer.
///
/// Resolved at compile time, the same arrangement the runtime packages use, so
/// a web build never references `dart:io` beyond the stub and a native build
/// never carries the in-memory one.
library;

export 'store_io.dart' if (dart.library.js_interop) 'store_web.dart'
    show openStore;
