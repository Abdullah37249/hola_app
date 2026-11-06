import 'dart:io' show Platform;

import 'package:local_auth/local_auth.dart';

/// iPhone with Face ID (true) or Touch ID (false); unknown until [Biometrics.available] runs.
bool? _iosFace;

/// Icon for the biometric button: a face for Face ID, else a fingerprint.
String get bioIcon => Platform.isIOS && (_iosFace ?? true) ? 'faceid' : 'finger';

/// Fingerprint wording (already translated), said the iPhone way: Android
/// keeps it as is; iPhone gets Face ID ("look at your iPhone") or Touch ID.
String bio(String text) {
  if (!Platform.isIOS) return text;
  final face = _iosFace ?? true;
  final name = face ? 'Face ID' : 'Touch ID';
  var t = text;
  if (face) {
    t = t
        .replaceAll('Touch the fingerprint sensor', 'Look at your iPhone')
        .replaceAll('touch the fingerprint sensor', 'look at your iPhone')
        .replaceAll('فنگر پرنٹ سینسر کو چھوئیں', 'اپنے iPhone کی طرف دیکھیں');
  }
  return t.replaceAll('your fingerprint', name).replaceAll('fingerprint', name).replaceAll('Fingerprint', name).replaceAll('فنگر پرنٹ', name);
}

/// How a fingerprint check ended.
enum BioResult {
  ok,

  /// The person closed the prompt (or the phone did): say nothing.
  cancelled,

  /// Fingerprint not recognised.
  failed,

  /// Too many tries: Android has paused fingerprint for a while.
  lockedOut,

  /// No fingerprint set up on this phone (or no sensor).
  unavailable,
}

/// The phone's fingerprint (or other strong biometric) check, via Android's
/// own prompt. The fingerprint itself never leaves the phone's secure chip.
class Biometrics {
  final _auth = LocalAuthentication();

  /// The phone has a sensor and a fingerprint is enrolled.
  Future<bool> available() async {
    try {
      // Never let this hold up start-up (some phones and tests don't answer).
      return await (() async {
        final types = await _auth.getAvailableBiometrics();
        if (Platform.isIOS) _iosFace = types.contains(BiometricType.face) || !types.contains(BiometricType.fingerprint);
        return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics && types.isNotEmpty;
      })().timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (_) {
      return false; // no plugin (tests) or no hardware
    }
  }

  Future<BioResult> verify(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true, persistAcrossBackgrounding: true) ? BioResult.ok : BioResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress ||
        LocalAuthExceptionCode.uiUnavailable => BioResult.cancelled,
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => BioResult.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable => BioResult.unavailable,
        _ => BioResult.failed,
      };
    } catch (_) {
      return BioResult.failed;
    }
  }
}
