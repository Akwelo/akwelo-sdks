import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';
import {
  BRIDGE_SHIM,
  DEFAULT_BASE_URL,
  buildVerifyUrl,
  isTrustedUrl,
  originOf,
  parseResult,
  resolveAttestation,
  type VerifyOptions,
  type VerifyResult,
} from './core';

export interface AkweloVerifyViewProps extends VerifyOptions {
  onResult: (result: VerifyResult) => void;
}

/** Embeddable capture view. Most apps use `Akwelo.verify()` with `<AkweloProvider>` instead. */
export function AkweloVerifyView({ sessionToken, baseUrl = DEFAULT_BASE_URL, attestationToken, onResult }: AkweloVerifyViewProps) {
  const [uri, setUri] = useState<string | null>(null);
  const done = useRef(false);
  const finish = (r: VerifyResult) => {
    if (done.current) return;
    done.current = true;
    onResult(r);
  };

  useEffect(() => {
    let alive = true;
    resolveAttestation(attestationToken).then((attest) => {
      if (!alive) return;
      try {
        setUri(buildVerifyUrl(baseUrl, sessionToken, attest));
      } catch (e) {
        finish({ status: 'error', error: (e as Error).message });
      }
    });
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionToken, baseUrl]);

  if (!uri) {
    return (
      <View style={styles.center}>
        <ActivityIndicator />
      </View>
    );
  }

  const origin = originOf(baseUrl) ?? baseUrl;
  return (
    <WebView
      source={{ uri }}
      style={styles.fill}
      originWhitelist={[origin]}
      javaScriptEnabled
      domStorageEnabled
      allowsInlineMediaPlayback
      mediaPlaybackRequiresUserAction={false}
      mediaCapturePermissionGrantType="grantIfSameHostElsePrompt"
      injectedJavaScriptBeforeContentLoaded={BRIDGE_SHIM}
      // Keep the top-level document on the Akwelo origin; no other site gets the bridge.
      onShouldStartLoadWithRequest={(req) => req.isTopFrame === false || isTrustedUrl(req.url, baseUrl)}
      setSupportMultipleWindows={false}
      onMessage={(e: WebViewMessageEvent) => {
        if (!isTrustedUrl(e.nativeEvent.url, baseUrl)) return;
        const r = parseResult(e.nativeEvent.data);
        if (r) finish(r);
      }}
      onError={(e) => finish({ status: 'error', error: e.nativeEvent.description || 'load_failed' })}
    />
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
