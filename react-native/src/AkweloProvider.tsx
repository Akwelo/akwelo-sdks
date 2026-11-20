import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Modal, SafeAreaView, StyleSheet } from 'react-native';
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
    setPresenter((options, done) => {
      // Only one verification at a time; a superseded caller is told it was cancelled.
      activeRef.current?.done({ status: 'cancelled' });
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

  return (
    <>
      {children}
      <Modal visible={!!active} animationType="slide" presentationStyle="fullScreen" onRequestClose={() => finish({ status: 'cancelled' })}>
        <SafeAreaView style={styles.fill}>
          {active && <AkweloVerifyView key={active.options.sessionToken} {...active.options} onResult={finish} />}
        </SafeAreaView>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({ fill: { flex: 1 } });
