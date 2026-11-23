import 'package:flutter/widgets.dart';

import 'contract.dart';
import 'verify_page.dart';

/// Entry point.
///
/// ```dart
/// final result = await Akwelo.verify(context, sessionToken: token);
/// ```
class Akwelo {
  Akwelo._();

  static bool _open = false;

  /// Opens the capture page and completes with the outcome; it never throws. One capture at a
  /// time: a call made while another is open completes at once with `already_in_progress` and
  /// leaves the open one untouched.
  static Future<VerifyResult> verify(
    BuildContext context, {
    required String sessionToken,
    AkweloOptions options = const AkweloOptions(),
  }) async {
    if (sessionToken.trim().isEmpty) {
      return const VerifyResult.failure('invalid_session_token', 'sessionToken must not be blank');
    }
    if (validBaseOrigin(options.baseUrl) == null) {
      return const VerifyResult.failure('invalid_base_url', 'baseUrl must be an https URL');
    }
    if (_open) {
      return const VerifyResult.failure('already_in_progress', 'A verification is already open');
    }
    _open = true;
    try {
      final attest = await resolveAttestation(options.attestationToken);
      final url = buildVerifyUrl(options.baseUrl, sessionToken, attestation: attest);
      if (!context.mounted) return VerifyResult.cancelled;
      final result = await Navigator.of(context).push<VerifyResult>(
        PageRouteBuilder<VerifyResult>(
          fullscreenDialog: true,
          pageBuilder: (_, __, ___) => AkweloVerifyPage(
            url: url,
            screenCaptureActive: options.screenCaptureActive,
            watchScreenCapture: options.watchScreenCapture,
          ),
        ),
      );
      return result ?? VerifyResult.cancelled;
    } catch (e) {
      return VerifyResult.failure('presentation_failed', e.toString());
    } finally {
      _open = false;
    }
  }
}
