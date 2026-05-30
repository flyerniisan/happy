import * as React from 'react';
import { useRouter } from 'expo-router';
import { CameraView } from 'expo-camera';

type ScannerMode = 'account' | 'terminal';

function isScannerCancelled(error: unknown): boolean {
    const message = error instanceof Error ? error.message : String(error ?? '');
    return message.toLowerCase().includes('cancel');
}

export function useScannerLauncher(mode: ScannerMode) {
    const router = useRouter();
    const openFallbackScanner = React.useCallback(() => {
        router.push({
            pathname: '/scanner',
            params: { mode },
        } as never);
    }, [mode, router]);

    return React.useCallback(async () => {
        if (!CameraView.isModernBarcodeScannerAvailable) {
            openFallbackScanner();
            return;
        }

        try {
            await CameraView.launchScanner({
                barcodeTypes: ['qr']
            });
        } catch (error) {
            if (isScannerCancelled(error)) {
                return;
            }

            console.warn(`[scanner] Failed to launch ${mode} scanner, falling back to embedded camera`, error);
            openFallbackScanner();
        }
    }, [mode, openFallbackScanner]);
}
