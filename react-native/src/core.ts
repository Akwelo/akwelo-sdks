export const DEFAULT_BASE_URL = 'https://flow.akwelo.com';
export const RESULT_MESSAGE_TYPE = 'akwelo.verify.result';

/** Capture outcome. `submitted` means capture finished; the decision is delivered to your backend. */
export type VerifyStatus = 'submitted' | 'cancelled' | 'error';

export interface VerifyResult {
  status: VerifyStatus;
  sessionId?: string;
  error?: string;
}

export interface VerifyOptions {
  /** Short-lived token your backend got when creating the session. */
  sessionToken: string;
  /** Hosted capture origin. Defaults to https://flow.akwelo.com. */
  baseUrl?: string;
  /**
   * Optional device attestation token (Play Integrity / App Attest), or a function returning one.
   * Obtain it with a native module; see README. Passed to the page as `attest=`.
   */
  attestationToken?: string | (() => Promise<string | undefined | null>);
}

const STATUSES: ReadonlySet<string> = new Set(['submitted', 'cancelled', 'error']);

/** Builds `{baseUrl}/verify/selfie#token=...[&attest=...]`. Secrets stay in the URL fragment. */
export function buildVerifyUrl(baseUrl: string, sessionToken: string, attestationToken?: string | null): string {
  if (!sessionToken || !sessionToken.trim()) throw new Error('Akwelo: sessionToken must not be blank');
  const base = baseUrl.replace(/\/+$/, '');
  let url = `${base}/verify/selfie#token=${encodeURIComponent(sessionToken)}`;
  if (attestationToken) url += `&attest=${encodeURIComponent(attestationToken)}`;
  return url;
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

/** Parses a bridge message (string or object). Returns null for anything that is not an Akwelo result. */
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
  if (typeof m.error === 'string') result.error = m.error;
  return result;
}

export async function resolveAttestation(opt: VerifyOptions['attestationToken']): Promise<string | undefined> {
  if (!opt) return undefined;
  if (typeof opt === 'string') return opt;
  try {
    return (await opt()) ?? undefined;
  } catch {
    return undefined; // best-effort: load without attestation
  }
}

/** Gives the page the same `AkweloBridge.postMessage(json)` API it uses on native SDKs. */
export const BRIDGE_SHIM = `(function(){
  if (window.AkweloBridge) return;
  window.AkweloBridge = { postMessage: function (m) {
    window.ReactNativeWebView.postMessage(typeof m === 'string' ? m : JSON.stringify(m));
  } };
})(); true;`;

/** Single-flight coordinator behind `Akwelo.verify()`; the provider registers itself as the presenter. */
export type Presenter = (options: VerifyOptions, done: (r: VerifyResult) => void) => void;

let presenter: Presenter | null = null;

export function setPresenter(p: Presenter | null): void {
  presenter = p;
}

export const Akwelo = {
  /** Opens the capture page and resolves with the outcome. Requires `<AkweloProvider>` near the app root. */
  verify(options: VerifyOptions): Promise<VerifyResult> {
    return new Promise((resolve) => {
      if (!presenter) {
        resolve({ status: 'error', error: 'AkweloProvider is not mounted' });
        return;
      }
      if (!options?.sessionToken?.trim()) {
        resolve({ status: 'error', error: 'sessionToken must not be blank' });
        return;
      }
      presenter(options, resolve);
    });
  },
};
