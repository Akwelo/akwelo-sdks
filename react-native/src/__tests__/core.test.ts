import {
  Akwelo,
  buildVerifyUrl,
  isTrustedUrl,
  parseResult,
  resolveAttestation,
  setPresenter,
  validBaseOrigin,
  type VerifyResult,
} from '../core';

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
  it('reads the error the hosted page sends: an object with a code and a message', () => {
    // Exactly what apps/flow postVerifyResult sends for a denied camera.
    const fromPage = {
      type: 'akwelo.verify.result',
      sessionId: null,
      status: 'error',
      error: { code: 'camera_unavailable', message: 'We could not use your camera.' },
    };
    const want = { status: 'error', error: 'camera_unavailable', errorMessage: 'We could not use your camera.' };
    expect(parseResult(fromPage)).toEqual(want);
    expect(parseResult(JSON.stringify(fromPage))).toEqual(want);
  });
  it('always gives an error result a code', () => {
    expect(parseResult({ type: 'akwelo.verify.result', status: 'error' })).toEqual({ status: 'error', error: 'unknown_error' });
    expect(parseResult({ type: 'akwelo.verify.result', status: 'error', error: { message: 'm' } })).toEqual({
      status: 'error',
      error: 'unknown_error',
      errorMessage: 'm',
    });
    expect(parseResult({ type: 'akwelo.verify.result', status: 'cancelled', sessionId: null })).toEqual({ status: 'cancelled' });
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
  it('does not wait on a provider that never answers', async () => {
    const never = () => new Promise<string>(() => undefined);
    const started = Date.now();
    expect(await resolveAttestation(never, 30)).toBeUndefined();
    expect(Date.now() - started).toBeLessThan(1000);
  });
});

describe('validBaseOrigin', () => {
  it('accepts https, and http only on this machine', () => {
    expect(validBaseOrigin('https://flow.akwelo.com/')).toBe('https://flow.akwelo.com');
    expect(validBaseOrigin('https://staging.example:8443')).toBe('https://staging.example:8443');
    expect(validBaseOrigin('http://localhost:5173')).toBe('http://localhost:5173');
    expect(validBaseOrigin('http://10.0.2.2:5173/')).toBe('http://10.0.2.2:5173');
  });
  it('rejects anything a capture page cannot safely run on', () => {
    for (const u of ['http://flow.akwelo.com', 'http://192.168.1.20:5173', 'flow.akwelo.com', 'ftp://x', 'https://u:p@x.com', '', undefined]) {
      expect(validBaseOrigin(u)).toBeNull();
    }
  });
});

describe('Akwelo.verify', () => {
  afterEach(() => setPresenter(null));
  it('errors when no provider is mounted', async () => {
    expect(await Akwelo.verify({ sessionToken: 't' })).toMatchObject({ status: 'error', error: 'provider_not_mounted' });
  });
  it('refuses a blank token or an unusable baseUrl before opening anything', async () => {
    const opened = jest.fn();
    setPresenter(opened);
    expect(await Akwelo.verify({ sessionToken: ' ' })).toMatchObject({ status: 'error', error: 'invalid_session_token' });
    expect(await Akwelo.verify({ sessionToken: 't', baseUrl: 'http://flow.akwelo.com' })).toMatchObject({
      status: 'error',
      error: 'invalid_base_url',
    });
    expect(opened).not.toHaveBeenCalled();
  });
  it('lets one capture through at a time and leaves the open one untouched', async () => {
    let finishFirst: (r: VerifyResult) => void = () => undefined;
    const opened = jest.fn((_opts, done) => {
      finishFirst = done;
    });
    setPresenter(opened);
    const first = Akwelo.verify({ sessionToken: 'a' });
    expect(await Akwelo.verify({ sessionToken: 'b' })).toMatchObject({ status: 'error', error: 'already_in_progress' });
    expect(opened).toHaveBeenCalledTimes(1);
    finishFirst({ status: 'submitted', sessionId: 's_a' });
    finishFirst({ status: 'cancelled' }); // a second report is ignored
    expect(await first).toEqual({ status: 'submitted', sessionId: 's_a' });
    // The next one opens normally.
    setPresenter((_opts, done) => done({ status: 'cancelled' }));
    expect(await Akwelo.verify({ sessionToken: 'c' })).toEqual({ status: 'cancelled' });
  });
  it('settles when the presenter throws', async () => {
    setPresenter(() => {
      throw new Error('boom');
    });
    expect(await Akwelo.verify({ sessionToken: 't' })).toMatchObject({ status: 'error', error: 'presentation_failed' });
    setPresenter((_opts, done) => done({ status: 'cancelled' }));
    expect(await Akwelo.verify({ sessionToken: 't' })).toEqual({ status: 'cancelled' });
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
