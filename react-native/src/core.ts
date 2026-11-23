export const DEFAULT_BASE_URL = 'https://flow.akwelo.com';
export const RESULT_MESSAGE_TYPE = 'akwelo.verify.result';

/** Capture outcome. `submitted` means capture finished; the decision is delivered to your backend. */
export type VerifyStatus = 'submitted' | 'cancelled' | 'error';

export interface VerifyResult {
  status: VerifyStatus;
  sessionId?: string;
  /** Stable error code when `status` is `error`, for example `camera_unavailable`. See README. */
  error?: string;
  /** Text for a person, in the page's language when the page reported the error. */
  errorMessage?: string;
}

export interface VerifyOptions {
  /** Short-lived token your backend got when creating the session. */
  sessionToken: string;
  /** Hosted capture origin. Defaults to https://flow.akwelo.com. Must be https (or localhost). */
  baseUrl?: string;
  /**
   * Optional device attestation token (Play Integrity / App Attest), or a function returning one.
   * Obtain it with a native module; see README. Passed to the page as `attest=`. A function that
   * throws or takes longer than 5 seconds is skipped: capture never waits on attestation.
   */
  attestationToken?: string | (() => Promise<string | undefined | null>);
  /**
   * Whether the screen is being recorded, mirrored or shared, from your own native module (React
   * Native cannot see it; see README). A boolean, or a function that receives a callback to call
   * with every change and may return an unsubscribe function. Forwarded to the page, which sends
   * it to Akwelo as evidence. Absent: nothing is sent and Akwelo records `unknown`.
   */
  screenCaptureActive?: ScreenCaptureOption;
}

export type ScreenCaptureOption = boolean | ((onChange: (active: boolean) => void) => (() => void) | void);

/** How long capture waits for an attestation token before starting without one. */
export const ATTESTATION_TIMEOUT_MS = 5000;

/** An SDK-side failure, in the same shape as one the page reports. */
export function sdkError(code: string, message: string): VerifyResult {
  return { status: 'error', error: code, errorMessage: message };
}

const STATUSES: ReadonlySet<string> = new Set(['submitted', 'cancelled', 'error']);

/**
 * Builds `{baseUrl}/verify/selfie#token=...[&attest=...][&env=...]`. Secrets stay in the URL
 * fragment. `env` is the first screen capture report, from `encodeHostEnv`.
 */
export function buildVerifyUrl(
  baseUrl: string,
  sessionToken: string,
  attestationToken?: string | null,
  env?: string | null,
): string {
  if (!sessionToken || !sessionToken.trim()) throw new Error('Akwelo: sessionToken must not be blank');
  const base = baseUrl.replace(/\/+$/, '');
  let url = `${base}/verify/selfie#token=${encodeURIComponent(sessionToken)}`;
  if (attestationToken) url += `&attest=${encodeURIComponent(attestationToken)}`;
  if (env) url += `&env=${encodeURIComponent(env)}`;
  return url;
}

/** Which SDK reports the capture environment. */
export type HostSource = 'ios' | 'android' | 'react-native' | 'flutter';

/**
 * The report the hosted page receives through `window.AkweloHost.signal(...)` and `env=`.
 * `screen_capture_seen` is present (true) once any capture was seen since the screen opened.
 */
export function hostSignal(active: boolean, source: HostSource = 'react-native', seen = false) {
  const report: { screen_capture: 'active' | 'inactive'; source: HostSource; screen_capture_seen?: true } = {
    screen_capture: active ? 'active' : 'inactive',
    source,
  };
  if (seen) report.screen_capture_seen = true;
  return report;
}

const B64URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** The report as base64url JSON without padding, for the `env=` fragment value. */
export function encodeHostEnv(active: boolean, source: HostSource = 'react-native', seen = false): string {
  // The JSON is ASCII (fixed keys and values), so each char is one byte. No btoa: not every engine has it.
  const json = JSON.stringify(hostSignal(active, source, seen));
  let out = '';
  for (let i = 0; i < json.length; i += 3) {
    const n = (json.charCodeAt(i) << 16) | ((json.charCodeAt(i + 1) || 0) << 8) | (json.charCodeAt(i + 2) || 0);
    const chars = Math.min(4, Math.ceil(((json.length - i) * 8) / 6));
    for (let k = 0; k < chars; k++) out += B64URL[(n >> (18 - 6 * k)) & 63];
  }
  return out;
}

/** JavaScript that hands the report to the page; it never throws, whatever state the page is in. */
export function hostSignalScript(active: boolean, source: HostSource = 'react-native', seen = false): string {
  const payload = JSON.stringify(hostSignal(active, source, seen));
  return `try{window.AkweloHost&&window.AkweloHost.signal(${payload})}catch(e){} true;`;
}

/** Screen capture as last reported, and whether any was seen since the screen opened. */
export class HostSignalState {
  active: boolean | undefined;
  seen = false;
  /** Records a report; answers whether what the page should hear changed. */
  set(active: boolean): boolean {
    const changed = this.active !== active || (active && !this.seen);
    this.active = active;
    if (active) this.seen = true;
    return changed;
  }
  /** A capture happened without changing the current state; answers whether that is news. */
  markSeen(): boolean {
    if (this.seen) return false;
    this.seen = true;
    return true;
  }
  /** The report to send, or null before the host app reported anything. */
  payload(source: HostSource = 'react-native') {
    return this.active === undefined ? null : hostSignal(this.active, source, this.seen);
  }
}

/**
 * Feeds `onChange` from the `screenCaptureActive` option: once for a boolean, on every report for a
 * subscription, never when absent or when the host's function throws. Returns a stop function.
 */
export function watchScreenCapture(opt: ScreenCaptureOption | undefined, onChange: (active: boolean) => void): () => void {
  if (typeof opt === 'boolean') {
    onChange(opt);
    return () => undefined;
  }
  if (typeof opt !== 'function') return () => undefined;
  let live = true;
  let unsubscribe: (() => void) | void;
  try {
    unsubscribe = opt((active) => {
      if (live && typeof active === 'boolean') onChange(active);
    });
  } catch {
    // The host's native module failed: send nothing, the server records `unknown`.
  }
  return () => {
    live = false;
    try {
      if (typeof unsubscribe === 'function') unsubscribe();
    } catch {
      // ignore
    }
  };
}

/** `scheme://host[:port]`, lower-cased, default ports dropped. Null without a host or with userinfo. */
export function originOf(url: string | null | undefined): string | null {
  const m = /^([a-z][a-z0-9+.-]*):\/\/([^/?#]*)/i.exec((url ?? '').trim());
  if (!m || !m[2] || m[2].includes('@')) return null;
  const scheme = m[1]!.toLowerCase();
  let host = m[2].toLowerCase();
  if ((scheme === 'https' && host.endsWith(':443')) || (scheme === 'http' && host.endsWith(':80'))) {
    host = host.slice(0, host.lastIndexOf(':'));
  }
  return `${scheme}://${host}`;
}

/** True only when `url` is on exactly the same origin as `baseUrl`. */
export function isTrustedUrl(url: string | null | undefined, baseUrl: string): boolean {
  const o = originOf(url);
  return o !== null && o === originOf(baseUrl);
}

const LOCAL_HOSTS: ReadonlySet<string> = new Set(['localhost', '127.0.0.1', '10.0.2.2', '[::1]']);

/**
 * The origin of a usable `baseUrl`, or null. The page handles a camera and a session token, so
 * it must be https; plain http is accepted only for a development server on this machine.
 */
export function validBaseOrigin(baseUrl: string | null | undefined): string | null {
  const origin = originOf(baseUrl);
  if (!origin) return null;
  if (origin.startsWith('https://')) return origin;
  const host = origin.slice('http://'.length).replace(/:\d+$/, '');
  return origin.startsWith('http://') && LOCAL_HOSTS.has(host) ? origin : null;
}

/**
 * Parses a bridge message (string or object). Returns null for anything that is not an Akwelo
 * result. The page sends `error` as `{ code, message }`; a bare string is read as the code.
 */
export function parseResult(data: unknown): VerifyResult | null {
  let obj: unknown = data;
  if (typeof data === 'string') {
    try {
      obj = JSON.parse(data);
    } catch {
      return null;
    }
  }
  if (!obj || typeof obj !== 'object') return null;
  const m = obj as Record<string, unknown>;
  if (m.type !== RESULT_MESSAGE_TYPE || typeof m.status !== 'string' || !STATUSES.has(m.status)) return null;
  const result: VerifyResult = { status: m.status as VerifyStatus };
  if (typeof m.sessionId === 'string' && m.sessionId) result.sessionId = m.sessionId;
  if (typeof m.error === 'string' && m.error) {
    result.error = m.error;
  } else if (m.error && typeof m.error === 'object') {
    const e = m.error as Record<string, unknown>;
    if (typeof e.code === 'string' && e.code) result.error = e.code;
    if (typeof e.message === 'string' && e.message) result.errorMessage = e.message;
  }
  // An error always carries a code, so callers can switch on it.
  if (result.status === 'error' && !result.error) result.error = 'unknown_error';
  return result;
}

/** The attestation token, or undefined when there is none, it failed, or it took too long. */
export async function resolveAttestation(
  opt: VerifyOptions['attestationToken'],
  timeoutMs: number = ATTESTATION_TIMEOUT_MS,
): Promise<string | undefined> {
  if (!opt) return undefined;
  if (typeof opt === 'string') return opt;
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const late = new Promise<undefined>((resolve) => {
      timer = setTimeout(() => resolve(undefined), timeoutMs);
    });
    return (await Promise.race([opt(), late])) ?? undefined;
  } catch {
    return undefined; // best-effort: load without attestation
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

/** Gives the page the same `AkweloBridge.postMessage(json)` API it uses on native SDKs. */
export const BRIDGE_SHIM = `(function(){
  if (window.AkweloBridge) return;
  window.AkweloBridge = { postMessage: function (m) {
    window.ReactNativeWebView.postMessage(typeof m === 'string' ? m : JSON.stringify(m));
  } };
})(); true;`;

/** The provider registers itself as the presenter behind `Akwelo.verify()`. */
export type Presenter = (options: VerifyOptions, done: (r: VerifyResult) => void) => void;

let presenter: Presenter | null = null;
let inFlight = false;

export function setPresenter(p: Presenter | null): void {
  presenter = p;
}

export const Akwelo = {
  /**
   * Opens the capture page and resolves with the outcome; it never rejects. Requires
   * `<AkweloProvider>` near the app root. One capture at a time: a call made while another is
   * open resolves at once with `already_in_progress` and leaves the open one untouched.
   */
  verify(options: VerifyOptions): Promise<VerifyResult> {
    return new Promise((resolve) => {
      if (!presenter) {
        resolve(sdkError('provider_not_mounted', 'AkweloProvider is not mounted'));
        return;
      }
      if (typeof options?.sessionToken !== 'string' || !options.sessionToken.trim()) {
        resolve(sdkError('invalid_session_token', 'sessionToken must not be blank'));
        return;
      }
      if (!validBaseOrigin(options.baseUrl ?? DEFAULT_BASE_URL)) {
        resolve(sdkError('invalid_base_url', 'baseUrl must be an https URL'));
        return;
      }
      if (inFlight) {
        resolve(sdkError('already_in_progress', 'A verification is already open'));
        return;
      }
      inFlight = true;
      let settled = false;
      const done = (r: VerifyResult) => {
        if (settled) return;
        settled = true;
        inFlight = false;
        resolve(r);
      };
      try {
        presenter(options, done);
      } catch (e) {
        done(sdkError('presentation_failed', (e as Error)?.message ?? 'Could not open the capture screen'));
      }
    });
  },
};
