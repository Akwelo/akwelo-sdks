import 'package:akwelo/akwelo.dart';
import 'package:akwelo/src/contract.dart' show kResultMessageType, originOf;
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
