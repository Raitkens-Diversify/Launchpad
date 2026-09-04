import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/**
 * messageUtil — the one place Apex errors become user-facing strings and
 * toasts (the envelopeFormSchema pattern: pure, dependency-light helpers
 * shared by import instead of copy-paste; this module replaced ~20 private
 * messageFrom()/toast() twins across the admin console and UAT surfaces).
 *
 * Kept intentionally tiny: AuraHandledException messages arrive on
 * error.body.message; everything else collapses to the fallback.
 */

const DEFAULT_MESSAGE = 'Something went wrong. Refresh and try again.';

/** User-facing message from an Apex/wire error, with an optional fallback. */
export function messageFrom(error, fallback = DEFAULT_MESSAGE) {
    return (error && error.body && error.body.message) || fallback;
}

/**
 * Any error's real text: Apex first, then a plain JS Error's own message.
 *
 * messageFrom reads body.message ONLY, which is correct for a wire error and
 * destructive for a client-side one — a TypeError carries no .body, so it
 * collapsed to DEFAULT_MESSAGE and the true cause became unrecoverable. That is
 * what hid the Cycle Report's broken export: a generic toast, nothing logged,
 * and no way to tell a dead vendor bundle from a dead download.
 *
 * Deliberately a SECOND function rather than a change to messageFrom: 23
 * components import that one, and a raw exception message is not a string to
 * start showing users by default.
 */
export function detailOf(error, fallback = DEFAULT_MESSAGE) {
    return (error && error.body && error.body.message) || (error && error.message) || fallback;
}

/** The error object itself — message AND stack — under a bundle-tagged prefix,
 *  matching the bookOfBusinessChart convention. */
export function logError(bundle, operation, error) {
    // eslint-disable-next-line no-console
    console.error(`[${bundle}] ${operation} failed`, error);
}

/**
 * What a catch should call when a bare toast would hide a real defect: the
 * console keeps the whole error, and the toast names the operation, so
 * "Export failed: …" is actionable instead of ambient.
 */
export function reportError(cmp, bundle, operation, error) {
    logError(bundle, operation, error);
    toast(cmp, 'error', `${operation} failed: ${detailOf(error)}`);
}

/**
 * Title per toast variant. Every variant the platform accepts needs an entry:
 * the derivation used to be a single error/success ternary, so a `warning`
 * toast rendered under a "Success" heading — the exact contradiction a warning
 * exists to avoid (found 2026-08-14, wiring the runner's incomplete-submit
 * toast). Anything unrecognized still falls back to Success.
 */
const VARIANT_TITLE = {
    error: 'Error',
    warning: 'Warning',
    info: 'Info',
    success: 'Success'
};

/**
 * Dispatch the house-style toast from a component: title derives from the
 * variant unless given. Usage: toast(this, 'error', messageFrom(e)).
 */
export function toast(cmp, variant, message, title) {
    cmp.dispatchEvent(
        new ShowToastEvent({
            title: title || VARIANT_TITLE[variant] || 'Success',
            message,
            variant
        })
    );
}