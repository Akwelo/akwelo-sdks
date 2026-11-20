import { Akwelo, buildVerifyUrl, isTrustedUrl, parseResult, resolveAttestation, setPresenter } from '../core';

describe('buildVerifyUrl', () => {
  it('builds the default URL with the token in the fragment', () => {
    expect(buildVerifyUrl('https://flow.akwelo.com', 'abc')).toBe('https://flow.akwelo.com/verify/selfie#token=abc');
  });
  it('trims trailing slashes and encodes values', () => {
    expect(buildVerifyUrl('https://staging.example//', 'a+b=', 'x y')).toBe(
      'https://staging.example/verify/selfie#token=a%2Bb%3D&attest=x%20y',
    );
  });
  it('rejects blank tokens', () => {
    expect(() => buildVerifyUrl('https://x', ' ')).toThrow();
  });
});

describe('parseResult', () => {
  it('parses string and object payloads', () => {
    expect(parseResult('{"type":"akwelo.verify.result","sessionId":"s_1","status":"submitted"}')).toEqual({
      status: 'submitted',
      sessionId: 's_1',
    });
    expect(parseResult({ type: 'akwelo.verify.result', status: 'error', error: 'camera_denied' })).toEqual({
      status: 'error',
      error: 'camera_denied',
    });
  });
  it('ignores foreign and malformed messages', () => {
    expect(parseResult('{"type":"other","status":"submitted"}')).toBeNull();
    expect(parseResult('{"type":"akwelo.verify.result","status":"approved"}')).toBeNull();
    expect(parseResult('not json')).toBeNull();
    expect(parseResult(null)).toBeNull();
  });
});

describe('resolveAttestation', () => {
  it('accepts strings, functions, and swallows failures', async () => {
    expect(await resolveAttestation('t')).toBe('t');
    expect(await resolveAttestation(async () => 'f')).toBe('f');
    expect(await resolveAttestation(async () => { throw new Error('no'); })).toBeUndefined();
    expect(await resolveAttestation(undefined)).toBeUndefined();
  });
});

describe('Akwelo.verify', () => {
  afterEach(() => setPresenter(null));
  it('errors when no provider is mounted', async () => {
    expect(await Akwelo.verify({ sessionToken: 't' })).toEqual({ status: 'error', error: 'AkweloProvider is not mounted' });
  });
  it('delegates to the presenter and resolves with its result', async () => {
    setPresenter((opts, done) => done({ status: 'submitted', sessionId: opts.sessionToken }));
    expect(await Akwelo.verify({ sessionToken: 's_9' })).toEqual({ status: 'submitted', sessionId: 's_9' });
  });
});

describe('isTrustedUrl', () => {
  const base = 'https://flow.akwelo.com';
  it('accepts the exact origin', () => {
    expect(isTrustedUrl('https://flow.akwelo.com/verify/selfie#token=x', base)).toBe(true);
    expect(isTrustedUrl('https://FLOW.akwelo.com:443/', `${base}/`)).toBe(true);
  });
  it('rejects look-alikes and other origins', () => {
    for (const u of [
      'https://flow.akwelo.com.evil.com/',
      'https://flow.akwelo.com@evil.com/',
      'http://flow.akwelo.com/',
      'https://flow.akwelo.com:8443/',
      'about:blank',
      undefined,
    ]) {
      expect(isTrustedUrl(u, base)).toBe(false);
    }
  });
});
