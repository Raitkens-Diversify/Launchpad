/**
 * Tests for ArcPasswordController.
 *
 * Site.changePassword needs a live Site/Experience Cloud request, which a test
 * context does not have — Site.getSiteId() is null under Test — so the real
 * credential change cannot be exercised here, and deliberately is not: a test
 * that actually rotated a password would be changing a real user's login.
 *
 * What is covered is everything the class decides on its own: each rejection in
 * validate(), and the guard that turns a missing Site context into a plain
 * message rather than something that reads like a wrong-password error. The
 * validation order matters (it is what the user sees first), so it is asserted
 * rather than assumed.
 */
@IsTest
private class ArcPasswordControllerTest {
  /** Long enough to clear the class's own MIN_LENGTH check. */
  private static final String VALID_NEW = 'ArcPassw0rd!2026';

  /**
   * Calls changePassword and returns the message it refused with, failing the
   * test if it did not refuse at all.
   */
  private static String refusalFor(
    String oldPassword,
    String newPassword,
    String confirmPassword
  ) {
    try {
      ArcPasswordController.changePassword(
        oldPassword,
        newPassword,
        confirmPassword
      );
      Assert.fail('Expected changePassword to refuse this input.');
    } catch (AuraHandledException e) {
      // AuraHandledException.getMessage() is the text handed to the LWC.
      return e.getMessage();
    }
    return null;
  }

  @IsTest
  static void blankCurrentPasswordIsRefused() {
    Test.startTest();
    String message = refusalFor('', VALID_NEW, VALID_NEW);
    Test.stopTest();

    Assert.isTrue(
      message.contains('current password'),
      'A blank current password should be named as the problem, got: ' + message
    );
  }

  @IsTest
  static void blankNewPasswordIsRefused() {
    Test.startTest();
    String message = refusalFor('OldPassw0rd!', '', '');
    Test.stopTest();

    Assert.isTrue(
      message.contains('new password'),
      'A blank new password should be named as the problem, got: ' + message
    );
  }

  @IsTest
  static void mismatchedConfirmationIsRefused() {
    Test.startTest();
    String message = refusalFor('OldPassw0rd!', VALID_NEW, 'ArcPassw0rd!2027');
    Test.stopTest();

    Assert.isTrue(
      message.contains('do not match'),
      'A mistyped confirmation should be reported as a mismatch, got: ' +
      message
    );
  }

  /** Checked before the org's own policy so the user gets the cheap answer first. */
  @IsTest
  static void shortNewPasswordIsRefused() {
    Test.startTest();
    String message = refusalFor('OldPassw0rd!', 'Arc1!', 'Arc1!');
    Test.stopTest();

    Assert.isTrue(
      message.contains('at least 8 characters'),
      'A short new password should state the minimum length, got: ' + message
    );
  }

  @IsTest
  static void reusingTheCurrentPasswordIsRefused() {
    Test.startTest();
    String message = refusalFor(VALID_NEW, VALID_NEW, VALID_NEW);
    Test.stopTest();

    Assert.isTrue(
      message.contains('different from your current'),
      'Re-submitting the current password should be refused, got: ' + message
    );
  }

  /**
   * With every validation satisfied the call reaches the Site guard. Outside a
   * Site request that is where it stops, and the message must say so rather
   * than blaming the password the user typed.
   */
  @IsTest
  static void validInputOutsideSiteContextIsRefusedClearly() {
    Assert.isNull(
      Site.getSiteId(),
      'A test context has no Site, which is what this case relies on.'
    );

    Test.startTest();
    String message = refusalFor('OldPassw0rd!', VALID_NEW, VALID_NEW);
    Test.stopTest();

    Assert.isTrue(
      message.contains('ARC site'),
      'Missing Site context should be named as the reason, got: ' + message
    );
  }

  // ---- Outcome interpretation -------------------------------------------
  // Site.changePassword itself cannot run under test, so these drive
  // assertAccepted directly with the two outcomes it produces.

  /**
   * A null PageReference is how Site.changePassword signals a refusal that
   * survives the Aura boundary. It is the *only* such signal: the API's
   * documented ApexPages messages cannot be read from an @AuraEnabled method
   * (ApexPages.getMessages() throws "can only be called from a Visualforce
   * page" there), which is why this null check carries the whole decision.
   */
  @IsTest
  static void nullDestinationIsTreatedAsFailure() {
    Test.startTest();
    try {
      ArcPasswordController.assertAccepted(null);
      Assert.fail('A null PageReference means the change did not happen.');
    } catch (AuraHandledException e) {
      Assert.areEqual(
        ArcPasswordController.GENERIC_REFUSAL,
        e.getMessage(),
        'A refusal should use the message that names both causes.'
      );
    }
    Test.stopTest();
  }

  /** A real PageReference back means the platform accepted the change. */
  @IsTest
  static void destinationMeansAccepted() {
    Test.startTest();
    ArcPasswordController.assertAccepted(new PageReference('/ARC/settings'));
    Test.stopTest();
    // Reaching here without an exception is the assertion.
    Assert.isTrue(true, 'An accepted change should not raise.');
  }

  /**
   * The fallback message has to name both the wrong-current-password case and
   * a policy rejection, since it is used precisely when nothing said which.
   */
  @IsTest
  static void refusalMessageNamesBothLikelyCauses() {
    String message = ArcPasswordController.GENERIC_REFUSAL;

    Assert.isTrue(
      message.contains('current password'),
      'The refusal should mention the current password, got: ' + message
    );
    Assert.isTrue(
      message.contains('password policy'),
      'The refusal should mention the password policy, got: ' + message
    );
  }

  // ---- Platform message tidying -----------------------------------------

  /**
   * The exact string the live site returned for a wrong current password. The
   * sentence must survive; only the redundant prefix goes.
   */
  @IsTest
  static void errorPrefixIsStrippedFromPlatformMessages() {
    Test.startTest();
    String cleaned = ArcPasswordController.withoutErrorPrefix(
      'Error: Your old password is invalid.'
    );
    Test.stopTest();

    Assert.areEqual(
      'Your old password is invalid.',
      cleaned,
      'The "Error: " prefix should be dropped and the sentence kept.'
    );
  }

  @IsTest
  static void messageWithoutThePrefixIsLeftAlone() {
    Test.startTest();
    String cleaned = ArcPasswordController.withoutErrorPrefix(
      'Your new password must not repeat a recent one.'
    );
    Test.stopTest();

    Assert.areEqual(
      'Your new password must not repeat a recent one.',
      cleaned,
      'A message with no prefix should pass through unchanged.'
    );
  }

  /** An exception with no usable text must still say something actionable. */
  @IsTest
  static void blankMessageFallsBackToTheGenericRefusal() {
    Test.startTest();
    String fromNull = ArcPasswordController.withoutErrorPrefix(null);
    String fromPrefixOnly = ArcPasswordController.withoutErrorPrefix('Error: ');
    Test.stopTest();

    Assert.areEqual(
      ArcPasswordController.GENERIC_REFUSAL,
      fromNull,
      'A null message should fall back rather than surface nothing.'
    );
    Assert.areEqual(
      ArcPasswordController.GENERIC_REFUSAL,
      fromPrefixOnly,
      'A prefix with no sentence after it should fall back too.'
    );
  }
}