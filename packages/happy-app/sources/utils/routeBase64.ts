import { encodeBase64, decodeBase64 } from '@/encryption/base64';

export function encodeRoutePath(path: string): string {
    return encodeBase64(new TextEncoder().encode(path), 'base64url');
}

export function decodeRoutePath(encodedPath: string): string {
    return new TextDecoder().decode(decodeBase64(encodedPath, 'base64url'));
}
