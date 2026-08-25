/**
 * arcSession
 *
 * Anonymous, per-tab correlation key for search analytics. It lets the server
 * stitch a search to the click(s) that followed it WITHOUT identifying anyone:
 * the key is random, lives only in sessionStorage (gone when the tab closes),
 * and is never derived from any user attribute. Safe for guest sessions — it is
 * deliberately NOT a user id.
 */
const STORAGE_KEY = 'arc.sessionKey';
let memoryKey; // fallback when sessionStorage is unavailable (private mode / Locker)

function randomKey() {
    try {
        if (typeof crypto !== 'undefined' && crypto.randomUUID) {
            return crypto.randomUUID();
        }
        if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
            const buf = new Uint32Array(4);
            crypto.getRandomValues(buf);
            return Array.from(buf, (n) => n.toString(16).padStart(8, '0')).join('');
        }
    } catch (e) {
        // fall through to a non-crypto key
    }
    return 's' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
}

/**
 * The current tab's anonymous session key, created once and reused across every
 * search and click. At most 36 chars (well under Session_Key__c's 64).
 */
export function getSessionKey() {
    try {
        const existing = sessionStorage.getItem(STORAGE_KEY);
        if (existing) {
            return existing;
        }
        const key = randomKey();
        sessionStorage.setItem(STORAGE_KEY, key);
        return key;
    } catch (e) {
        // sessionStorage blocked — keep a stable key in memory for this instance.
        if (!memoryKey) {
            memoryKey = randomKey();
        }
        return memoryKey;
    }
}