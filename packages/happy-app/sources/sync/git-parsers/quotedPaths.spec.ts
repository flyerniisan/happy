import { describe, expect, it } from 'vitest';
import { parseNumStat } from './parseDiff';
import { parseStatusSummaryV2 } from './parseStatusV2';

describe('git quoted path parsing', () => {
    it('decodes quoted paths from porcelain v2 status output', () => {
        const summary = parseStatusSummaryV2(
            [
                '# branch.oid abcdef1234567890',
                '# branch.head main',
                '1 .M N... 100644 100644 100644 abcdef1 abcdef2 "docs/\\347\\254\\254\\344\\270\\200\\347\\253\\240.md"',
                '? "docs/\\344\\270\\255\\346\\226\\207.md"',
                '2 R. N... 100644 100644 100644 abcdef1 abcdef2 R100 "docs/\\346\\227\\247\\346\\226\\207\\344\\273\\266.md"\t"docs/\\346\\226\\260\\346\\226\\207\\344\\273\\266.md"',
            ].join('\n'),
        );

        expect(summary.files[0]?.path).toBe('docs/\u7b2c\u4e00\u7ae0.md');
        expect(summary.not_added).toEqual(['docs/\u4e2d\u6587.md']);
        expect(summary.files[1]?.from).toBe('docs/\u65e7\u6587\u4ef6.md');
        expect(summary.files[1]?.path).toBe('docs/\u65b0\u6587\u4ef6.md');
    });

    it('decodes quoted paths from numstat output', () => {
        const summary = parseNumStat('12\t3\t"docs/\\344\\270\\255\\346\\226\\207.md"');

        expect(summary.files).toEqual([
            {
                file: 'docs/\u4e2d\u6587.md',
                changes: 15,
                insertions: 12,
                deletions: 3,
                binary: false,
            },
        ]);
    });
});
