import * as React from 'react';
import { ActivityIndicator, Platform, View } from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { Text } from '@/components/StyledText';
import { Typography } from '@/constants/Typography';
import { useConnectAccount } from '@/hooks/useConnectAccount';
import { useConnectTerminal } from '@/hooks/useConnectTerminal';
import { Modal } from '@/modal';
import { t } from '@/text';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

type ScannerMode = 'account' | 'terminal';

const stylesheet = StyleSheet.create((theme) => ({
    page: {
        flex: 1,
        backgroundColor: theme.colors.surface,
    },
    hero: {
        paddingHorizontal: 16,
        paddingTop: 12,
        paddingBottom: 16,
        alignItems: 'center',
    },
    iconWrap: {
        width: 56,
        height: 56,
        borderRadius: 28,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.colors.surfaceHigh,
        marginBottom: 12,
    },
    title: {
        ...Typography.default('semiBold'),
        fontSize: 20,
        color: theme.colors.text,
        textAlign: 'center',
        marginBottom: 8,
    },
    subtitle: {
        ...Typography.default(),
        fontSize: 14,
        lineHeight: 20,
        color: theme.colors.textSecondary,
        textAlign: 'center',
        maxWidth: 420,
    },
    cameraCard: {
        overflow: 'hidden',
        borderRadius: 20,
        marginHorizontal: 16,
        marginBottom: 16,
        backgroundColor: '#000',
        minHeight: 360,
    },
    camera: {
        minHeight: 360,
        width: '100%',
        aspectRatio: 1,
    },
    overlay: {
        ...StyleSheet.absoluteFillObject,
        justifyContent: 'center',
        alignItems: 'center',
        padding: 24,
    },
    finder: {
        width: '78%',
        aspectRatio: 1,
        borderRadius: 24,
        borderWidth: 2,
        borderColor: 'rgba(255,255,255,0.95)',
        backgroundColor: 'transparent',
    },
    helperChip: {
        position: 'absolute',
        bottom: 20,
        left: 20,
        right: 20,
        borderRadius: 14,
        backgroundColor: 'rgba(0,0,0,0.56)',
        paddingHorizontal: 14,
        paddingVertical: 12,
    },
    helperText: {
        ...Typography.default(),
        fontSize: 13,
        lineHeight: 18,
        color: '#fff',
        textAlign: 'center',
    },
    loadingWrap: {
        ...StyleSheet.absoluteFillObject,
        justifyContent: 'center',
        alignItems: 'center',
        gap: 12,
    },
    loadingText: {
        ...Typography.default(),
        fontSize: 14,
        color: '#fff',
    },
}));

function normalizeMode(value: string | string[] | undefined): ScannerMode {
    const raw = Array.isArray(value) ? value[0] : value;
    return raw === 'terminal' ? 'terminal' : 'account';
}

export default function ScannerScreen() {
    const { theme } = useUnistyles();
    const styles = stylesheet;
    const router = useRouter();
    const params = useLocalSearchParams<{ mode?: string | string[] }>();
    const mode = normalizeMode(params.mode);
    const [permission, requestPermission] = useCameraPermissions();
    const [askingPermission, setAskingPermission] = React.useState(false);
    const [scanLocked, setScanLocked] = React.useState(false);

    const { processAuthUrl: processAccountUrl, isLoading: accountLoading } = useConnectAccount({
        onSuccess: () => router.back(),
        onError: () => setScanLocked(false),
    });
    const { processAuthUrl: processTerminalUrl, isLoading: terminalLoading } = useConnectTerminal({
        onSuccess: () => router.back(),
        onError: () => setScanLocked(false),
    });

    const isLoading = accountLoading || terminalLoading;
    const processAuthUrl = React.useMemo(
        () => (mode === 'terminal' ? processTerminalUrl : processAccountUrl),
        [mode, processAccountUrl, processTerminalUrl]
    );
    const expectedPrefix = mode === 'terminal' ? 'happy://terminal?' : 'happy:///account?';

    React.useEffect(() => {
        if (Platform.OS === 'android') {
            // Embedded scanner fallback always needs camera permission on Android.
            if (!permission?.granted && !askingPermission) {
                setAskingPermission(true);
                requestPermission()
                    .catch((error) => {
                        console.warn('[scanner] Failed to request embedded camera permission', error);
                    })
                    .finally(() => {
                        setAskingPermission(false);
                    });
            }
        }
    }, [askingPermission, permission?.granted, requestPermission]);

    const handleBarcodeScanned = React.useCallback(async ({ data }: { data: string }) => {
        if (scanLocked || isLoading) {
            return;
        }

        if (!data.startsWith(expectedPrefix)) {
            return;
        }

        setScanLocked(true);
        const success = await processAuthUrl(data);
        if (!success) {
            setScanLocked(false);
        }
    }, [expectedPrefix, isLoading, processAuthUrl, scanLocked]);

    const handleOpenManualFallback = React.useCallback(async () => {
        const placeholder = mode === 'terminal' ? 'happy://terminal?...' : 'happy:///account?...';
        const promptTitle = mode === 'terminal'
            ? t('modals.authenticateTerminal')
            : t('navigation.linkNewDevice');
        const promptMessage = mode === 'terminal'
            ? t('modals.pasteUrlFromTerminal')
            : t('modals.pasteUrlFromDevice');
        const url = await Modal.prompt(promptTitle, promptMessage, {
            placeholder,
            confirmText: t('common.authenticate'),
        });
        if (!url?.trim()) {
            return;
        }

        setScanLocked(true);
        const success = await processAuthUrl(url.trim());
        if (!success) {
            setScanLocked(false);
        }
    }, [mode, processAuthUrl]);

    const showPermissionNotice = permission?.granted === false;

    return (
        <>
            <Stack.Screen
                options={{
                    headerTitle: mode === 'terminal' ? t('navigation.connectTerminal') : t('navigation.linkNewDevice'),
                }}
            />
            <ItemList style={styles.page}>
                <View style={styles.hero}>
                    <View style={styles.iconWrap}>
                        <Ionicons
                            name={mode === 'terminal' ? 'qr-code-outline' : 'phone-portrait-outline'}
                            size={28}
                            color={theme.colors.radio.active}
                        />
                    </View>
                    <Text style={styles.title}>
                        {mode === 'terminal' ? t('settings.scanQrCodeToAuthenticate') : t('settingsAccount.linkNewDevice')}
                    </Text>
                    <Text style={styles.subtitle}>
                        {mode === 'terminal' ? t('scanner.terminalSubtitle') : t('settingsAccount.linkNewDeviceSubtitle')}
                    </Text>
                </View>

                <View style={styles.cameraCard}>
                    {!showPermissionNotice && (
                        <CameraView
                            style={styles.camera}
                            facing="back"
                            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
                            onBarcodeScanned={handleBarcodeScanned}
                        />
                    )}

                    <View pointerEvents="none" style={styles.overlay}>
                        {!showPermissionNotice && <View style={styles.finder} />}
                        <View style={styles.helperChip}>
                            <Text style={styles.helperText}>
                                {t('scanner.centerQrCode')}
                            </Text>
                        </View>
                    </View>

                    {(askingPermission || isLoading) && (
                        <View style={styles.loadingWrap}>
                            <ActivityIndicator size="small" color="#fff" />
                            <Text style={styles.loadingText}>
                                {askingPermission ? t('scanner.requestingCameraPermission') : t('common.scanning')}
                            </Text>
                        </View>
                    )}
                </View>

                {showPermissionNotice && (
                    <ItemGroup>
                        <Item
                            title={t('scanner.cameraPermissionRequired')}
                            subtitle={t('scanner.cameraPermissionDescription')}
                            icon={<Ionicons name="camera-outline" size={29} color={theme.colors.textSecondary} />}
                            showChevron={false}
                        />
                    </ItemGroup>
                )}

                <ItemGroup>
                    {showPermissionNotice && (
                        <Item
                            title={t('scanner.grantCameraAccess')}
                            icon={<Ionicons name="checkmark-circle-outline" size={29} color={theme.colors.success} />}
                            onPress={async () => {
                                setAskingPermission(true);
                                try {
                                    await requestPermission();
                                } finally {
                                    setAskingPermission(false);
                                }
                            }}
                            loading={askingPermission}
                            showChevron={false}
                        />
                    )}
                    <Item
                        title={t('connect.enterUrlManually')}
                        subtitle={mode === 'terminal' ? t('modals.pasteUrlFromTerminal') : t('modals.pasteUrlFromDevice')}
                        icon={<Ionicons name="link-outline" size={29} color={theme.colors.radio.active} />}
                        onPress={() => {
                            void handleOpenManualFallback();
                        }}
                        showChevron={false}
                    />
                </ItemGroup>
            </ItemList>
        </>
    );
}
