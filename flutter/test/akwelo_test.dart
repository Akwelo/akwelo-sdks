import 'package:akwelo/akwelo.dart';
import 'dart:convert';

import 'package:akwelo/src/contract.dart'
    show
        HostSignalState,
        encodeHostEnv,
        hostSignal,
        hostSignalScript,
        kResultMessageType,
        originOf,
        resolveAttestation,
        validBaseOrigin;
import 'package:akwelo/src/verify_page.dart' show isPageRequest, resultForLoadError;
import 'package:flutter_test/flutter_test.dart';

/// Decoded the way the hosted page does (readHostEnv in apps/flow): base64url, padding optional.
Object? _decodeEnv(String v) => jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(v))));

void main() {
  group('host signal (screen capture)', () {
    test('payload the hosted page expects', () {
      expect(hostSignal(true), {'screen_capture': 'active', 'source': 'flutter'});
      expect(hostSignal(false, seen: true),
          {'screen_capture': 'inactive', 'source': 'flutter', 'screen_capture_seen': true});
    });
    test('env= value is base64url JSON without padding', () {
      final env = encodeHostEnv(true);
      expect(env, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(_decodeEnv(env), {'screen_capture': 'active', 'source': 'flutter'});
      expect(buildVerifyUrl(kDefaultBaseUrl, 'abc', attestation: 'a', env: env).toString(),
          'https://flow.akwelo.com/verify/selfie#token=abc&attest=a&env=$env');
    });
    test('the script never throws in the page', () {
      expect(hostSignalScript(false),
          'try{window.AkweloHost&&window.AkweloHost.signal({"screen_capture":"inactive","source":"flutter"})}catch(e){}');
    });
    test('reports changes only, and remembers a capture once seen', () {
      final s = HostSignalState();
      expect(s.payload(), isNull);
      expect(s.set(false), isTrue);
      expect(s.set(false), isFalse);
      expect(s.seen, isFalse);
      expect(s.set(true), isTrue);
      expect(s.set(false), isTrue);
      expect(s.payload(), {'screen_capture': 'inactive', 'source': 'flutter', 'screen_capture_seen': true});
      expect(s.markSeen(), isFalse);
    });
  });

  group('buildVerifyUrl', () {
    test('default URL keeps the token in the fragment', () {
      expect(buildVerifyUrl(kDefaultBaseUrl, 'abc').toString(),
          'https://flow.akwelo.com/verify/selfie#token=abc');
    });
    test('trims slashes and encodes', () {
      expect(buildVerifyUrl('https://staging.example//', 'a+b=', attestation: 'x y').toString(),
          'https://staging.example/verify/selfie#token=a%2Bb%3D&attest=x%20y');
    });
    test('rejects blank token', () {
      expect(() => buildVerifyUrl(kDefaultBaseUrl, ' '), throwsArgumentError);
    });
  });

  group('VerifyResult.parse', () {
    test('parses results', () {
      expect(VerifyResult.parse('{"type":"$kResultMessageType","sessionId":"s_1","status":"submitted"}'),
          const VerifyResult(VerifyStatus.submitted, sessionId: 's_1'));
      expect(VerifyResult.parse('{"type":"$kResultMessageType","status":"error","error":"camera_denied"}')?.error,
          'camera_denied');
    });
    test('reads the error the hosted page sends: an object with a code and a message', () {
      // Exactly what apps/flow postVerifyResult sends for a denied camera.
      const fromPage = '{"type":"$kResultMessageType","sessionId":null,"status":"error",'
          '"error":{"code":"camera_unavailable","message":"We could not use your camera."}}';
      expect(
        VerifyResult.parse(fromPage),
        const VerifyResult(VerifyStatus.error,
            error: 'camera_unavailable', errorMessage: 'We could not use your camera.'),
      );
    });
    test('always gives an error result a code', () {
      expect(VerifyResult.parse('{"type":"$kResultMessageType","status":"error"}')?.error, 'unknown_error');
      expect(VerifyResult.parse('{"type":"$kResultMessageType","status":"cancelled","sessionId":null}'),
          VerifyResult.cancelled);
    });
    test('ignores foreign and malformed', () {
      expect(VerifyResult.parse('{"type":"other","status":"submitted"}'), isNull);
      expect(VerifyResult.parse('{"type":"$kResultMessageType","status":"approved"}'), isNull);
      expect(VerifyResult.parse('nope'), isNull);
      expect(VerifyResult.parse(null), isNull);
    });
  });

  test('originOf matches only the exact origin', () {
    const base = 'https://flow.akwelo.com';
    expect(originOf('https://FLOW.akwelo.com:443/verify/selfie#token=x'), originOf(base));
    for (final u in [
      'https://flow.akwelo.com.evil.com/',
      'https://flow.akwelo.com@evil.com/',
      'http://flow.akwelo.com/',
      'https://flow.akwelo.com:8443/',
      null,
    ]) {
      expect(originOf(u) == originOf(base), isFalse, reason: '$u');
    }
  });

  group('validBaseOrigin', () {
    test('accepts https, and http only on this machine', () {
      expect(validBaseOrigin('https://flow.akwelo.com/'), 'https://flow.akwelo.com');
      expect(validBaseOrigin('https://staging.example:8443'), 'https://staging.example:8443');
      expect(validBaseOrigin('http://localhost:5173'), 'http://localhost:5173');
      expect(validBaseOrigin('http://10.0.2.2:5173/'), 'http://10.0.2.2:5173');
    });
    test('rejects anything a capture page cannot safely run on', () {
      for (final u in [
        'http://flow.akwelo.com',
        'http://192.168.1.20:5173',
        'flow.akwelo.com',
        'ftp://x',
        'https://u:p@x.com',
        '',
        null,
      ]) {
        expect(validBaseOrigin(u), isNull, reason: '$u');
      }
    });
  });

  group('resolveAttestation', () {
    test('returns the token, and null when the provider fails', () async {
      expect(await resolveAttestation(null), isNull);
      expect(await resolveAttestation(() async => 't'), 't');
      // The usual way an app writes it: a provider that returns a non-null String.
      Future<String> typed() async => 'typed';
      expect(await resolveAttestation(typed), 'typed');
      expect(await resolveAttestation(() async => throw StateError('no')), isNull);
    });
    test('does not wait on a provider that never answers', () async {
      final never = Future<String?>.delayed(const Duration(hours: 1), () => 'late');
      expect(await resolveAttestation(() => never, timeout: const Duration(milliseconds: 20)), isNull);
    });
  });

  group('load failures', () {
    const page = 'https://flow.akwelo.com';
    VerifyResult? err({
      String? url,
      bool main = true,
      bool terminated = false,
      int code = -2,
      String description = 'net::ERR_INTERNET_DISCONNECTED',
    }) =>
        resultForLoadError(
          pageOrigin: page,
          failingUrl: url,
          isForMainFrame: main,
          processTerminated: terminated,
          errorCode: code,
          description: description,
        );

    test('the capture page failing to load is an error result', () {
      expect(err(url: '$page/verify/selfie')?.error, 'page_load_failed');
      expect(err()?.error, 'page_load_failed'); // platforms that give no URL
      expect(err(description: '')?.errorMessage, isNotEmpty);
    });
    test('a dead web process is an error result', () {
      expect(err(terminated: true, main: false)?.error, 'webview_crashed');
    });
    test('resources, tapped links and cancelled navigations are not', () {
      expect(err(main: false), isNull);
      expect(err(url: 'https://akwelo.com/privacy'), isNull);
      expect(err(code: -999), isNull);
      expect(err(code: 102), isNull);
    });
    test('an HTTP error counts only for the page itself', () {
      final url = Uri.parse('$page/verify/selfie#token=t');
      expect(isPageRequest(url, Uri.parse('$page/verify/selfie')), isTrue);
      expect(isPageRequest(url, Uri.parse('$page/favicon.ico')), isFalse);
      expect(isPageRequest(url, Uri.parse('https://cdn.example/verify/selfie')), isFalse);
      expect(isPageRequest(url, null), isFalse);
    });
  });
}
