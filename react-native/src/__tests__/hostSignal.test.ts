import { buildVerifyUrl, encodeHostEnv, hostSignal, hostSignalScript, HostSignalState, watchScreenCapture } from '../core';

// Decoded the way the hosted page does (readHostEnv in apps/flow): base64url, padding optional.
const atob = (globalThis as unknown as { atob(s: string): string }).atob;
const decode = (v: string) => {
  const b64 = v.replace(/-/g, '+').replace(/_/g, '/');
  return JSON.parse(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4)));
};

describe('host signal (screen capture)', () => {
  it('builds the payload the hosted page expects', () => {
    expect(hostSignal(true)).toEqual({ screen_capture: 'active', source: 'react-native' });
    expect(hostSignal(false)).toEqual({ screen_capture: 'inactive', source: 'react-native' });
    expect(hostSignal(false, 'react-native', true)).toEqual({
      screen_capture: 'inactive',
      source: 'react-native',
      screen_capture_seen: true,
    });
  });
  it('encodes the first value as base64url JSON for the env= fragment', () => {
    const env = encodeHostEnv(true);
    expect(env).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(decode(env)).toEqual({ screen_capture: 'active', source: 'react-native' });
    expect(decode(encodeHostEnv(false, 'react-native', true))).toEqual({
      screen_capture: 'inactive',
      source: 'react-native',
      screen_capture_seen: true,
    });
    expect(buildVerifyUrl('https://flow.akwelo.com', 'abc', null, env)).toBe(
      `https://flow.akwelo.com/verify/selfie#token=abc&env=${env}`,
    );
    expect(buildVerifyUrl('https://flow.akwelo.com', 'abc', 'att', env)).toBe(
      `https://flow.akwelo.com/verify/selfie#token=abc&attest=att&env=${env}`,
    );
  });
  it('calls window.AkweloHost.signal with the payload, and never throws', () => {
    const script = hostSignalScript(false);
    expect(script).toBe(
      'try{window.AkweloHost&&window.AkweloHost.signal({"screen_capture":"inactive","source":"react-native"})}catch(e){} true;',
    );
    const signal = jest.fn();
    new Function('window', script)({ AkweloHost: { signal } });
    expect(signal).toHaveBeenCalledWith({ screen_capture: 'inactive', source: 'react-native' });
    expect(() => new Function('window', script)({})).not.toThrow();
    expect(() =>
      new Function('window', script)({
        AkweloHost: {
          signal() {
            throw new Error('page not ready');
          },
        },
      }),
    ).not.toThrow();
  });
  it('reports only changes', () => {
    const s = new HostSignalState();
    expect(s.active).toBeUndefined();
    expect(s.payload()).toBeNull();
    expect(s.set(false)).toBe(true);
    expect(s.set(false)).toBe(false);
    expect(s.payload()).toEqual({ screen_capture: 'inactive', source: 'react-native' });
    expect(s.set(true)).toBe(true);
    expect(s.active).toBe(true);
  });
  it('remembers a capture once seen, after it stops', () => {
    const s = new HostSignalState();
    s.set(false);
    expect(s.seen).toBe(false);
    s.set(true);
    s.set(false);
    expect(s.seen).toBe(true);
    expect(s.payload()).toEqual({ screen_capture: 'inactive', source: 'react-native', screen_capture_seen: true });
    expect(s.markSeen()).toBe(false); // already seen: nothing new to send
  });
  it('forwards a value, a subscription, or nothing', () => {
    const seen: boolean[] = [];
    watchScreenCapture(true, (a) => seen.push(a))();
    expect(seen).toEqual([true]);

    let emit: (a: boolean) => void = () => undefined;
    const unsubscribe = jest.fn();
    const stop = watchScreenCapture((cb) => {
      emit = cb;
      return unsubscribe;
    }, (a) => seen.push(a));
    emit(false);
    emit(true);
    stop();
    emit(false); // after stop: ignored
    expect(seen).toEqual([true, false, true]);
    expect(unsubscribe).toHaveBeenCalledTimes(1);

    const none = jest.fn();
    watchScreenCapture(undefined, none)();
    watchScreenCapture(() => {
      throw new Error('native module missing');
    }, none)();
    expect(none).not.toHaveBeenCalled();
  });
});
