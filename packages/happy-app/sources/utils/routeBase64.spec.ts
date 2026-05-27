import { describe, expect, it } from 'vitest';
import { decodeRoutePath, encodeRoutePath } from './routeBase64';

describe('routeBase64', () => {
    it('round-trips unicode paths', () => {
        const path = 'docs/\u4e2d\u6587/\u7b2c\u4e00\u7ae0.md';

        const encoded = encodeRoutePath(path);
        const decoded = decodeRoutePath(encoded);

        expect(decoded).toBe(path);
    });
});
