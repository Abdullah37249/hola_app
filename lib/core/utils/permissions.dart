import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// The phone permissions HOLA asks for, each with the job it does.
enum AppPermission { notifications, location, photos }

enum PermState { granted, denied, blocked }

/// Thin wrapper over permission_handler so screens never talk to the plugin.
class Permissions {
  static List<Permission> _of(AppPermission p) => switch (p) {
    AppPermission.notifications => [Permission.notification],
    AppPermission.location => [Permission.locationWhenInUse],
    // Android 13+ asks for photos; older Android for storage.
    AppPermission.photos => [Permission.photos, Permission.storage],
  };

  static PermState _merge(List<PermissionStatus> xs) {
    if (xs.any((s) => s.isGranted || s.isLimited)) return PermState.granted;
    if (xs.any((s) => s.isPermanentlyDenied || s.isRestricted)) return PermState.blocked;
    return PermState.denied;
  }

  static Future<PermState> status(AppPermission p) async {
    try {
      return _merge([for (final x in _of(p)) await x.status]);
    } on MissingPluginException {
      return PermState.denied;
    } on PlatformException {
      return PermState.denied;
    }
  }

  static Future<PermState> request(AppPermission p) async {
    try {
      final r = await _of(p).request();
      return _merge(r.values.toList());
    } on MissingPluginException {
      return PermState.denied;
    } on PlatformException {
      return PermState.denied;
    }
  }

  /// Opens the system settings page for HOLA (for permissions refused for good).
  static Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }
}
