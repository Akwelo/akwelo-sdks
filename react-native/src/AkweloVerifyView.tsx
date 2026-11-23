import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';
import {
  BRIDGE_SHIM,
  DEFAULT_BASE_URL,
  buildVerifyUrl,
  isTrustedUrl,
  parseResult,
  resolveAttestation,
  sdkError,
  validBaseOrigin,
  type VerifyOptions,
  type VerifyResult,
} from './core';

export interface AkweloVerifyViewProps extends VerifyOptions {
  /** Called exactly once, with the outcome or with an SDK error (see README for the codes). */
  onResult: (result: VerifyResult) => void;
}

const Loading = () => (
  <View style={styles.center}>
    <ActivityIndicator />
  </View>
);

/**
 * Embeddable capture view. Most apps use `Akwelo.verify()` with `<AkweloProvider>` instead.
 * When you embed it, give the person a way to leave: the view cannot close itself.
 */
export function AkweloVerifyView({ sessionToken, baseUrl = DEFAULT_BASE_URL, attestationToken, onResult }: AkweloVerifyViewProps) {
  const [uri, setUri] = useState<string | null>(null);
  const done = useRef(false);
  const finish = (r: VerifyResult) => {
    if (done.current) return;
    done.current = true;
    onResult(r);
  };
  const origin = validBaseOrigin(baseUrl);

  useEffect(() => {
    if (!origin) {
      finish(sdkError('invalid_base_url', 'baseUrl must be an https URL'));
      return;
    }
    let alive = true;
    resolveAttestation(attestationToken).then((attest) => {
      if (!alive) return;
      try {
        setUri(buildVerifyUrl(baseUrl, sessionToken, attest));
      } catch (e) {
        finish(sdkError('invalid_session_token', (e as Error).message));
      }
    });
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionToken, baseUrl]);

  if (!uri || !origin) return <Loading />;

  // The capture page itself failed. A failure on another URL (a link the person tapped) is not ours.
  const pageFailed = (url: string | undefined, detail: string) => {
    if (url && !isTrustedUrl(url, baseUrl)) return;
    finish(sdkError('page_load_failed', detail));
  };

  return (
    <WebView
      source={{ uri }}
      style={styles.fill}
      // Other origins never load here; react-native-webview hands them to the system browser.
      originWhitelist={[origin]}
      javaScriptEnabled
      domStorageEnabled
      allowsInlineMediaPlayback
      mediaPlaybackRequiresUserAction={false}
      mediaCapturePermissionGrantType="grantIfSameHostElsePrompt"
      injectedJavaScriptBeforeContentLoaded={BRIDGE_SHIM}
      startInLoadingState
      renderLoading={() => (
        <View style={styles.cover}>
          <ActivityIndicator />
        </View>
      )}
      // Keep the top-level document on the Akwelo origin; no other site gets the bridge.
      onShouldStartLoadWithRequest={(req) => req.isTopFrame === false || isTrustedUrl(req.url, baseUrl)}
      setSupportMultipleWindows={false}
      onMessage={(e: WebViewMessageEvent) => {
        if (!isTrustedUrl(e.nativeEvent.url, baseUrl)) return;
        const r = parseResult(e.nativeEvent.data);
        if (r) finish(r);
      }}
      onError={(e) => pageFailed(e.nativeEvent.url, e.nativeEvent.description || 'The capture page did not load')}
      onHttpError={(e) => pageFailed(e.nativeEvent.url, `The capture page answered HTTP ${e.nativeEvent.statusCode}`)}
      // The web process died (low memory is the usual cause). The view is blank from here on.
      onRenderProcessGone={() => finish(sdkError('webview_crashed', 'The capture page stopped unexpectedly'))}
      onContentProcessDidTerminate={() => finish(sdkError('webview_crashed', 'The capture page stopped unexpectedly'))}
    />
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  cover: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', backgroundColor: '#fff' },
});
