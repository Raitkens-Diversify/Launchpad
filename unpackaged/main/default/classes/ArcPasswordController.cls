/**
 * ArcPasswordController
 *
 * Backs the Password tab of the Arc settings surface. Changes the *running*
 * user's own password and nothing else.
 *
 * Conventions:
 * - The running user is the only subject. No user id crosses the wire, so this
 *   entry point cannot be pointed at somebody else's account.
 * - Site.changePassword is the self-service API: it verifies the old password
 *   before accepting the new one and enforces the org's own password policy
 *   (length, complexity, reuse history). System.setPassword is deliberately not
 *   used — it skips both of those checks and needs an admin permission the
 *   advisors running this site do not have.
 * - Failure is read from thrown exceptions and the return value, NOT from
 *   ApexPages. Site.changePassword is a Visualforce-era API and its documented
 *   way of reporting a refusal is to add an ApexPages message, but
 *   ApexPages.getMessages() throws "can only be called from a Visualforce page"
 *   when called from an @AuraEnabled method — and because that throw happened
 *   inside the catch block, it replaced every real failure reason with that
 *   error. Verified against the live site: the API instead *throws*, carrying
 *   the specific reason ("Your old password is invalid."), so the exception
 *   message is what to surface. The null-PageReference check is kept as a
 *   backstop for a refusal that somehow does not throw.
 * - The old password is never logged, echoed back, or stored.
 */
public with sharing class ArcPasswordController {
  /** Matches the shortest password any Salesforce password policy allows. */
  private static final Integer MIN_LENGTH = 8;

  /**
   * Fallback for a refusal that arrives without an exception to explain it.
   * In practice Site.changePassword throws and that message is more specific
   * than this, so this is the backstop rather than the usual text — hence it
   * names both plausible causes instead of guessing at one.
   */
  @TestVisible
  private static final String GENERIC_REFUSAL =
    'Your password could not be changed. Check that your current password is' +
    ' correct and that your new password meets your organization\'s password' +
    ' policy.';

  /**
   * Platform exception messages arrive prefixed with "Error: " (seen on the
   * live site as "Error: Your old password is invalid."). The banner already
   * reads as an error, so the prefix is redundant noise in the UI.
   *
   * Held without the trailing space: the message is trimmed before the prefix
   * is matched, and "Error: " trims down to "Error:", which would then fail a
   * startsWith check that expected the space.
   */
  private static final String PLATFORM_ERROR_PREFIX = 'Error:';

  /**
   * Change the running user's password.
   *
   * @param oldPassword     the user's current password
   * @param newPassword     the requested new password
   * @param confirmPassword newPassword typed a second time
   */
  @AuraEnabled
  public static void changePassword(
    String oldPassword,
    String newPassword,
    String confirmPassword
  ) {
    validate(oldPassword, newPassword, confirmPassword);

    // Site.changePassword only exists inside a Site/Experience Cloud
    // request. Called from anywhere else it cannot verify the old password,
    // so refuse plainly instead of failing in a way that reads like a
    // wrong-password error.
    if (Site.getSiteId() == null) {
      throw refusal('Your password can only be changed from the ARC site.');
    }

    PageReference destination;
    try {
      destination = Site.changePassword(
        newPassword,
        confirmPassword,
        oldPassword
      );
    } catch (Exception e) {
      // The platform's own wording is more specific than anything that
      // could be substituted here, so it is passed through.
      throw refusal(withoutErrorPrefix(e.getMessage()));
    }

    assertAccepted(destination);
  }

  /**
   * Decide whether the Site.changePassword call above actually succeeded.
   *
   * Split out from changePassword because Site.changePassword needs a live
   * Site request and so cannot run under test, while this — the part that
   * decides what the user is told — is the part worth testing. Kept
   * @TestVisible so the tests exercise it directly.
   *
   * @param destination what Site.changePassword returned; null means refused
   */
  @TestVisible
  private static void assertAccepted(PageReference destination) {
    if (destination == null) {
      throw refusal(GENERIC_REFUSAL);
    }
  }

  // ---- Validation ------------------------------------------------------

  /**
   * The checks worth making before spending a round trip on
   * Site.changePassword. The org's real policy is still the authority — it is
   * enforced server-side, and anything it refuses comes back through
   * GENERIC_REFUSAL.
   */
  private static void validate(
    String oldPassword,
    String newPassword,
    String confirmPassword
  ) {
    if (String.isBlank(oldPassword)) {
      throw refusal('Enter your current password.');
    }
    if (String.isBlank(newPassword)) {
      throw refusal('Enter a new password.');
    }
    if (newPassword != confirmPassword) {
      throw refusal('The new passwords do not match.');
    }
    if (newPassword.length() < MIN_LENGTH) {
      throw refusal(
        'Your new password must be at least ' + MIN_LENGTH + ' characters.'
      );
    }
    if (newPassword == oldPassword) {
      throw refusal(
        'Your new password must be different from your current one.'
      );
    }
  }

  /**
   * Strips the platform's redundant "Error: " prefix, leaving the sentence
   * that actually tells the user what went wrong.
   */
  @TestVisible
  private static String withoutErrorPrefix(String message) {
    if (String.isBlank(message)) {
      return GENERIC_REFUSAL;
    }
    String trimmed = message.trim();
    if (trimmed.startsWith(PLATFORM_ERROR_PREFIX)) {
      trimmed = trimmed.substring(PLATFORM_ERROR_PREFIX.length()).trim();
    }
    // A prefix with nothing after it says nothing to the user.
    return String.isBlank(trimmed) ? GENERIC_REFUSAL : trimmed;
  }

  /**
   * Builds an AuraHandledException carrying `message`.
   *
   * AuraHandledException.getMessage() does not return the text passed to its
   * constructor — it answers the generic "Script-thrown exception" unless
   * setMessage() is called explicitly first. Every refusal in this class goes
   * through here so that never gets missed, and so this class's own tests
   * (which read getMessage() in plain Apex, without the Aura/LWC boundary
   * that would otherwise supply the real text) see the actual message too.
   */
  private static AuraHandledException refusal(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}