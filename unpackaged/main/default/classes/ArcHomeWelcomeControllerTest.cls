/**
 * ArcHomeWelcomeControllerTest
 *
 * No @seeAllData — the running user's own preference row is created and read
 * back entirely within the test.
 */
@IsTest
private class ArcHomeWelcomeControllerTest {
  @IsTest
  static void defaultsToNotSeenWhenNoPreferenceExists() {
    Test.startTest();
    Boolean seen = ArcHomeWelcomeController.getHasSeenWelcome();
    Test.stopTest();

    Assert.isFalse(
      seen,
      'A user with no preference row has not seen the welcome yet'
    );
  }

  @IsTest
  static void fetchHasSeenWelcomeAgreesWithTheCacheableRead() {
    // fetchHasSeenWelcome exists only so the client can bypass the
    // cacheable read's client-side cache after markWelcomeSeen writes; it
    // must report the exact same thing the cacheable version does, just
    // without being cached.
    ArcHomeWelcomeController.markWelcomeSeen();

    Test.startTest();
    Boolean seen = ArcHomeWelcomeController.fetchHasSeenWelcome();
    Test.stopTest();

    Assert.isTrue(
      seen,
      'fetchHasSeenWelcome should see the same flag getHasSeenWelcome does'
    );
  }

  @IsTest
  static void markingSeenPersistsAndIsReadBack() {
    Test.startTest();
    ArcHomeWelcomeController.markWelcomeSeen();
    Boolean seen = ArcHomeWelcomeController.getHasSeenWelcome();
    Test.stopTest();

    Assert.isTrue(
      seen,
      'The flag should read back true after being marked seen'
    );
  }

  @IsTest
  static void doesNotCollideWithTheHelpCenterWelcomeFlag() {
    // The Help Center flow's own flag lives on User.Has_Seen_Welcome__c and
    // is untouched by this controller — this is the assertion that fails if
    // the two welcome experiences are ever accidentally wired to the same
    // piece of state.
    Test.startTest();
    ArcHomeWelcomeController.markWelcomeSeen();
    Test.stopTest();

    User u = [
      SELECT Has_Seen_Welcome__c
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ];
    Assert.isFalse(
      u.Has_Seen_Welcome__c,
      'Marking the ARC home welcome seen must not touch the Help Center flag'
    );
  }

  @IsTest
  static void isScopedToTheRunningUserOnly() {
    User_Preference__c stored;

    Test.startTest();
    ArcHomeWelcomeController.markWelcomeSeen();
    Test.stopTest();

    stored = [
      SELECT User__c, Application_Name__c
      FROM User_Preference__c
      WHERE Application_Name__c = :ArcHomeWelcomeController.APPLICATION_NAME
    ];
    Assert.areEqual(
      UserInfo.getUserId(),
      stored.User__c,
      'The preference row must belong to the running user'
    );
  }
}