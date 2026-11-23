import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Modal, Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { AkweloVerifyView } from './AkweloVerifyView';
import { setPresenter, type VerifyOptions, type VerifyResult } from './core';

interface Active {
  options: VerifyOptions;
  done: (r: VerifyResult) => void;
}

/**
 * Mount once near the app root. Hosts the full-screen capture modal used by `Akwelo.verify()`.
 * Camera permission: Android needs `android.permission.CAMERA` in the app manifest;
 * iOS needs `NSCameraUsageDescription` in Info.plist.
 */
export function AkweloProvider({ children }: { children?: ReactNode }) {
  const [active, setActive] = useState<Active | null>(null);
  const activeRef = useRef<Active | null>(null);

  useEffect(() => {
    // `Akwelo.verify` lets one capture through at a time, so there is never one to replace here.
    setPresenter((options, done) => {
      const next = { options, done };
      activeRef.current = next;
      setActive(next);
    });
    return () => {
      setPresenter(null);
      // Provider unmounted mid-flow: settle the pending promise instead of leaving it hanging.
      const cur = activeRef.current;
      activeRef.current = null;
      cur?.done({ status: 'cancelled' });
    };
  }, []);

  const finish = (r: VerifyResult) => {
    const cur = activeRef.current;
    activeRef.current = null;
    setActive(null);
    cur?.done(r);
  };
  const cancel = () => finish({ status: 'cancelled' });

  return (
    <>
      {children}
      <Modal visible={!!active} animationType="slide" presentationStyle="fullScreen" onRequestClose={cancel}>
        <SafeAreaView style={styles.fill}>
          {/* Always there, so a page that fails to draw can never trap the person (iOS has no back button). */}
          <View style={styles.bar}>
            <Pressable onPress={cancel} hitSlop={12} accessibilityRole="button" accessibilityLabel="Close">
              <Text style={styles.close}>{'✕'}</Text>
            </Pressable>
          </View>
          {active && <AkweloVerifyView key={active.options.sessionToken} {...active.options} onResult={finish} />}
        </SafeAreaView>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: '#fff' },
  bar: { height: 44, paddingHorizontal: 16, alignItems: 'flex-end', justifyContent: 'center' },
  close: { fontSize: 20, color: '#111' },
});
