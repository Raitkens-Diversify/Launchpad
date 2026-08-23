/**
 * uatTitleUtil — the two client-side halves of the Case_ID__c slug contract.
 *
 * humanizeCaseCode() reads a slug BACKWARD: cards headline with
 * Test_Case__c.Title__c, and when it's blank the raw slug
 * ("wizard-wizard_testers-household_creation_&_account_opening-v1.0-1001")
 * is not a title, it's an identifier — this derives a readable fallback,
 * "Household creation & account opening". The real fix is always filling
 * Title__c; this only keeps blank ones from shouting slugs at testers.
 *
 * buildCaseCode() writes one FORWARD, for previewing the Case ID a pick will
 * produce (New Case modal, and the module-move preview on the case detail
 * page). Both mirror the Case_ID__c formula, which stays the truth — a
 * taxonomy or format change has to touch the formula and this file together
 * (docs/ui-standards.md).
 */

// Words that should stay uppercase after sentence-casing.
const ABBREVIATIONS = new Set(['uat', 'api', 'id', 'fsc', 'crm', 'ui', 'ux', 'sla', 'pdf']);

// Case_ID__c formula shape: system_code-module_group-module-version-sequence
// (5+ dash segments; the version segment looks like v1.0 / v12.3).
const VERSION_SEGMENT = /^v\d+(\.\d+)*$/;
const NUMERIC_SEGMENT = /^\d+$/;

function sentenceCase(words) {
    return words
        .map((word, i) => {
            if (ABBREVIATIONS.has(word)) {
                return word.toUpperCase();
            }
            if (i === 0) {
                return word.charAt(0).toUpperCase() + word.slice(1);
            }
            return word;
        })
        .join(' ');
}

/**
 * Forward mirror of the Case_ID__c formula:
 *   LOWER(system_code) - LOWER(SUBSTITUTE(group,' ','_'))
 *   - LOWER(SUBSTITUTE(module,' ','_')) - LOWER(version) - sequence
 *
 * Note the asymmetry, which is the formula's and not a slip: the system code
 * and version are only lowercased, while the two taxonomy NAMES also get
 * their spaces underscored. Anything not yet picked renders as '…' so a
 * partial selection still previews.
 */
export function buildCaseCode({ systemCode, groupName, moduleName, version, sequence } = {}) {
    const lower = (v) => (v ? String(v).toLowerCase() : '…');
    const slug = (v) => (v ? String(v).toLowerCase().replace(/ /g, '_') : '…');
    const seq = sequence === null || sequence === undefined || sequence === ''
        ? '…'
        : String(sequence);
    return [lower(systemCode), slug(groupName), slug(moduleName), lower(version), seq].join('-');
}

/** Short scannable ref for a case slug: humanized module plus the sequence —
 *  "Households · 1001". humanizeCaseCode alone trims the sequence, which is
 *  right for a headline fallback and wrong for a reference column: findings
 *  on cases 1001 and 1002 of one module must not read identically. Callers
 *  put the raw slug in the tooltip; this is only the visible text. */
export function shortCaseRef(code) {
    if (!code) {
        return '';
    }
    const segments = String(code).split('-');
    const tail = segments[segments.length - 1];
    const sequence = segments.length > 1 && NUMERIC_SEGMENT.test(tail) ? tail : null;
    const head = humanizeCaseCode(code);
    return sequence ? `${head} · ${sequence}` : head;
}

export function humanizeCaseCode(code) {
    if (!code) {
        return '';
    }
    let segments = String(code).split('-');

    // Trim the identifier tail: trailing sequence number, then version.
    if (segments.length > 1 && NUMERIC_SEGMENT.test(segments[segments.length - 1])) {
        segments = segments.slice(0, -1);
    }
    if (segments.length > 1 && VERSION_SEGMENT.test(segments[segments.length - 1])) {
        segments = segments.slice(0, -1);
    }
    // Trim the taxonomy head (system code + module group) when the full
    // 5-segment shape was present; shorter strings keep everything.
    if (segments.length >= 3) {
        segments = segments.slice(2);
    }

    const words = segments
        .join(' ')
        .replace(/_/g, ' ')
        .toLowerCase()
        .split(/\s+/)
        .filter(Boolean);

    return words.length ? sentenceCase(words) : String(code);
}