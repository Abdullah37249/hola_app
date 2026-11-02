import 'package:flutter/foundation.dart';

/// Whether the app can reach the HOLA servers. The network client sets this
/// when requests fail or recover; on-device data never changes it.
abstract final class NetworkStatus {
  static final online = ValueNotifier<bool>(true);
}
