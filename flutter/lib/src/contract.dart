import 'dart:convert';

const String kDefaultBaseUrl = 'https://flow.akwelo.com';
const String kResultMessageType = 'akwelo.verify.result';

/// How long capture waits for an attestation token before starting without one.
const Duration kAttestationTimeout = Duration(seconds: 5);

/// Capture outcome. `submitted` means capture finished; the decision is delivered to your backend.
enum VerifyStatus { submitted, cancelled, error }

class VerifyResult {
  const VerifyResult(this.status, {this.sessionId, this.error, this.errorMessage});

  /// An SDK-side failure, in the same shape as one the page reports.
  const VerifyResult.failure(String code, String message)
      : status = VerifyStatus.error,
        sessionId = null,
        error = code,
        errorMessage = message;

  final VerifyStatus status;
  final String? sessionId;

  /// Stable error code when [status] is [VerifyStatus.error], for example `camera_unavailable`.
  final String? error;

  /// Text for a person, in the page's language when the page reported the error.
  final String? errorMessage;

  static const cancelled = VerifyResult(VerifyStatus.cancelled);

  /// Parses a bridge message. Returns null for anything that is not an Akwelo result.
  /// The page sends `error` as `{code, message}`; a bare string is read as the code.
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
    String? code;
    String? text;
    if (err is String && err.isNotEmpty) {
      code = err;
    } else if (err is Map) {
      final c = err['code'];
      final m = err['message'];
      if (c is String && c.isNotEmpty) code = c;
      if (m is String && m.isNotEmpty) text = m;
    }
    // An error always carries a code, so callers can switch on it.
    if (status == VerifyStatus.error) code ??= 'unknown_error';
    return VerifyResult(
      status,
      sessionId: sid is String && sid.isNotEmpty ? sid : null,
      error: code,
      errorMessage: text,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VerifyResult &&
      other.status == status &&
      other.sessionId == sessionId &&
      other.error == error &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(status, sessionId, error, errorMessage);

  @override
  String toString() =>
      'VerifyResult($status, sessionId: $sessionId, error: $error, errorMessage: $errorMessage)';
}

/// Subscribes to screen capture reports from the host app's own native code: call `onChange` with
/// every change (and the current value, if known); return a function that stops the subscription.
typedef ScreenCaptureWatcher = void Function() Function(void Function(bool active) onChange);

class AkweloOptions {
  const AkweloOptions({
    this.baseUrl = kDefaultBaseUrl,
    this.attestationToken,
    this.screenCaptureActive,
    this.watchScreenCapture,
  });

  /// Hosted capture origin. Override for staging or self-hosted deployments. Must be https
  /// (plain http is accepted only for a development server on this machine).
  final String baseUrl;

  /// Optional device attestation token provider (Play Integrity / App Attest), passed as `attest=`.
  /// A provider that throws or takes longer than [kAttestationTimeout] is skipped: capture
  /// never waits on attestation.
  /// TODO(akwelo): a native helper is planned once real Google and Apple accounts exist.
  final Future<String?> Function()? attestationToken;

  /// Whether the screen is being recorded, mirrored or shared, as your app's native code sees it
  /// (Flutter cannot; see README). Forwarded to the page, which sends it to Akwelo as evidence.
  /// Use [watchScreenCapture] instead to report changes while the capture page is open. With
  /// neither, nothing is sent and Akwelo records `unknown`.
  final bool? screenCaptureActive;

  /// Live variant of [screenCaptureActive]; takes precedence over it.
  final ScreenCaptureWatcher? watchScreenCapture;
}

/// Which SDK reports the capture environment.
const String kHostSource = 'flutter';

/// The report the hosted page receives through `window.AkweloHost.signal(...)` and `env=`.
/// `screen_capture_seen` is present (true) once any capture was seen since the page opened.
Map<String, Object> hostSignal(bool active, {bool seen = false, String source = kHostSource}) => {
      'screen_capture': active ? 'active' : 'inactive',
      'source': source,
      if (seen) 'screen_capture_seen': true,
    };

/// The report as base64url JSON without padding, for the `env=` fragment value.
String encodeHostEnv(bool active, {bool seen = false, String source = kHostSource}) =>
    base64Url.encode(utf8.encode(jsonEncode(hostSignal(active, seen: seen, source: source)))).replaceAll('=', '');

/// JavaScript that hands the report to the page; it never throws, whatever state the page is in.
String hostSignalScript(bool active, {bool seen = false, String source = kHostSource}) =>
    'try{window.AkweloHost&&window.AkweloHost.signal(${jsonEncode(hostSignal(active, seen: seen, source: source))})}catch(e){}';

/// Screen capture as last reported, and whether any was seen since the page opened.
class HostSignalState {
  bool? active;
  bool seen = false;

  /// Records a report; answers whether what the page should hear changed.
  bool set(bool value) {
    final changed = active != value || (value && !seen);
    active = value;
    if (value) seen = true;
    return changed;
  }

  /// A capture happened without changing the current state; answers whether that is news.
  bool markSeen() {
    if (seen) return false;
    seen = true;
    return true;
  }

  /// The report to send, or null before anything was reported.
  Map<String, Object>? payload() {
    final a = active;
    return a == null ? null : hostSignal(a, seen: seen);
  }

  String? script() {
    final a = active;
    return a == null ? null : hostSignalScript(a, seen: seen);
  }

  String? env() {
    final a = active;
    return a == null ? null : encodeHostEnv(a, seen: seen);
  }
}

/// Builds `{baseUrl}/verify/selfie#token=...[&attest=...][&env=...]`. Secrets stay in the URL
/// fragment. `env` is the first screen capture report, from [encodeHostEnv].
Uri buildVerifyUrl(String baseUrl, String sessionToken, {String? attestation, String? env}) {
  if (sessionToken.trim().isEmpty) {
    throw ArgumentError.value(sessionToken, 'sessionToken', 'must not be blank');
  }
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  var fragment = 'token=${Uri.encodeComponent(sessionToken)}';
  if (attestation != null && attestation.isNotEmpty) {
    fragment += '&attest=${Uri.encodeComponent(attestation)}';
  }
  if (env != null && env.isNotEmpty) fragment += '&env=${Uri.encodeComponent(env)}';
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

const Set<String> _localHosts = {'localhost', '127.0.0.1', '10.0.2.2', '::1'};

/// The origin of a usable `baseUrl`, or null. The page handles a camera and a session token, so
/// it must be https; plain http is accepted only for a development server on this machine.
String? validBaseOrigin(String? baseUrl) {
  final origin = originOf(baseUrl);
  if (origin == null) return null;
  if (origin.startsWith('https://')) return origin;
  if (!origin.startsWith('http://')) return null;
  return _localHosts.contains(Uri.parse(origin).host) ? origin : null;
}

/// The attestation token, or null when there is none, it failed, or it took too long.
Future<String?> resolveAttestation(
  Future<String?> Function()? provider, {
  Duration timeout = kAttestationTimeout,
}) async {
  if (provider == null) return null;
  try {
    // Widened first: a provider typed Future<String> rejects a null onTimeout at run time.
    return await provider().then<String?>((v) => v).timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null; // best-effort: load without attestation
  }
}
