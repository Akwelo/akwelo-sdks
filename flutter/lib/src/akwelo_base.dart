import 'package:flutter/material.dart';

import 'contract.dart';
import 'verify_page.dart';

/// Entry point.
///
/// ```dart
/// final result = await Akwelo.verify(context, sessionToken: token);
/// ```
class Akwelo {
  Akwelo._();

  static Future<VerifyResult> verify(
    BuildContext context, {
    required String sessionToken,
    AkweloOptions options = const AkweloOptions(),
  }) async {
    final Uri url;
    try {
      String? attest;
      if (options.attestationToken != null) {
        try {
          attest = await options.attestationToken!();
        } catch (_) {
          attest = null; // best-effort
        }
      }
      url = buildVerifyUrl(options.baseUrl, sessionToken, attestation: attest);
    } on ArgumentError catch (e) {
      return VerifyResult(VerifyStatus.error, error: e.message?.toString());
    }
    if (!context.mounted) return VerifyResult.cancelled;
    final result = await Navigator.of(context).push<VerifyResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => AkweloVerifyPage(url: url)),
    );
    return result ?? VerifyResult.cancelled;
  }
}
