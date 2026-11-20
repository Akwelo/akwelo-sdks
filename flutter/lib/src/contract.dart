import 'dart:convert';

const String kDefaultBaseUrl = 'https://flow.akwelo.com';
const String kResultMessageType = 'akwelo.verify.result';

/// Capture outcome. `submitted` means capture finished; the decision is delivered to your backend.
enum VerifyStatus { submitted, cancelled, error }

class VerifyResult {
  const VerifyResult(this.status, {this.sessionId, this.error});

  final VerifyStatus status;
  final String? sessionId;
  final String? error;

  static const cancelled = VerifyResult(VerifyStatus.cancelled);

  /// Parses a bridge message. Returns null for anything that is not an Akwelo result.
  static VerifyResult? parse(String? message) {
    if (message == null || message.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return null;
    }
    if (decoded is! Map || decoded['type'] != kResultMessageType) return null;
    final status = switch (decoded['status']) {
      'submitted' => VerifyStatus.submitted,
      'cancelled' => VerifyStatus.cancelled,
      'error' => VerifyStatus.error,
      _ => null,
    };
    if (status == null) return null;
    final sid = decoded['sessionId'];
    final err = decoded['error'];
    return VerifyResult(
      status,
      sessionId: sid is String && sid.isNotEmpty ? sid : null,
      error: err is String ? err : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VerifyResult &&
      other.status == status &&
      other.sessionId == sessionId &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, sessionId, error);

  @override
  String toString() => 'VerifyResult($status, sessionId: $sessionId, error: $error)';
}

class AkweloOptions {
  const AkweloOptions({this.baseUrl = kDefaultBaseUrl, this.attestationToken});

  /// Hosted capture origin. Override for staging or self-hosted deployments.
  final String baseUrl;

  /// Optional device attestation token provider (Play Integrity / App Attest), passed as `attest=`.
  /// TODO(akwelo): a native helper is planned once real Google and Apple accounts exist.
  final Future<String?> Function()? attestationToken;
}

/// Builds `{baseUrl}/verify/selfie#token=...[&attest=...]`. Secrets stay in the URL fragment.
Uri buildVerifyUrl(String baseUrl, String sessionToken, {String? attestation}) {
  if (sessionToken.trim().isEmpty) {
    throw ArgumentError.value(sessionToken, 'sessionToken', 'must not be blank');
  }
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  var fragment = 'token=${Uri.encodeComponent(sessionToken)}';
  if (attestation != null && attestation.isNotEmpty) {
    fragment += '&attest=${Uri.encodeComponent(attestation)}';
  }
  return Uri.parse('$base/verify/selfie#$fragment');
}

/// `scheme://host[:port]`, lower-cased, default ports dropped. Null without a host or with userinfo.
String? originOf(String? url) {
  if (url == null) return null;
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty || u.userInfo.isNotEmpty || u.scheme.isEmpty) return null;
  final scheme = u.scheme.toLowerCase();
  final host = u.host.toLowerCase();
  final isDefault = !u.hasPort || (scheme == 'https' && u.port == 443) || (scheme == 'http' && u.port == 80);
  return isDefault ? '$scheme://$host' : '$scheme://$host:${u.port}';
}
