/**
 * arcNavigationGuard — lets a page-specific component (currently only the envelope wizard)
 * register a check that runs before arcNavigation completes an in-app navigation, so an open
 * interview with unsaved changes prompts the same way whether the user tries to leave via the
 * wizard's own controls or via the site's own sidebar nav (Cases, Tasks, anything else).
 *
 * A Set, not a single overwritable slot: a page transition where the outgoing and incoming
 * page-specific components are briefly both mounted can't have one registration silently
 * clobber another's.
 *
 * Registering nothing costs nothing: confirmNavigationAllowed() resolves true immediately with
 * no guards registered, so every ARC page other than the envelope wizard is unaffected, and the
 * envelope wizard itself only blocks when a registered guard actually says no (i.e. there's a
 * dirty interview) — see envelopeApp's registration, which delegates to the shell's
 * confirmExit() and is only in place while envelopeApp itself is mounted.
 */

const guards = new Set();

export function registerNavigationGuard(guardFn) {
  guards.add(guardFn);
}

export function unregisterNavigationGuard(guardFn) {
  guards.delete(guardFn);
}

export async function confirmNavigationAllowed() {
  if (guards.size === 0) {
    return true;
  }
  for (const guardFn of guards) {
    // eslint-disable-next-line no-await-in-loop
    const allowed = await guardFn();
    if (allowed === false) {
      return false;
    }
  }
  return true;
}