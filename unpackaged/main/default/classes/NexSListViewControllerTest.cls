/**
 * Fixture note: ListView is not createable through DML, so these tests cannot
 * seed a saved view and then find it. What they can pin down is the contract
 * the component depends on — a list is always returned, never null; a blank or
 * unknown object name yields nothing rather than throwing; and the query is
 * scoped to the running user, which is asserted by running as a freshly
 * inserted user who cannot have created any view in this org.
 *
 * Org prerequisite: none. The class only reads ListView.
 */
@IsTest
private class NexSListViewControllerTest {
  @TestSetup
  static void setup() {
    insert buildUser('nexslistview');
  }

  /** A user who has created no list views sees an empty strip, not an error. */
  @IsTest
  static void getMySavedListViewNamesReturnsNothingForANewUser() {
    User runner = [
      SELECT Id
      FROM User
      WHERE Username LIKE 'nexslistview%'
      LIMIT 1
    ];

    List<String> names;
    Test.startTest();
    System.runAs(runner) {
      names = NexSListViewController.getMySavedListViewNames('Case');
    }
    Test.stopTest();

    Assert.isNotNull(
      names,
      'The component iterates the result, so it must never be null.'
    );
    Assert.areEqual(
      0,
      names.size(),
      'A user who has created no views on Case owns no saved views.'
    );
  }

  /** No object, no query — the component calls this before it knows the object. */
  @IsTest
  static void getMySavedListViewNamesHandlesABlankObject() {
    Test.startTest();
    List<String> blank = NexSListViewController.getMySavedListViewNames('');
    List<String> nothing = NexSListViewController.getMySavedListViewNames(null);
    Test.stopTest();

    Assert.areEqual(0, blank.size(), 'A blank object name selects nothing.');
    Assert.areEqual(0, nothing.size(), 'A null object name selects nothing.');
  }

  /** A name that matches no object is empty rather than an error. */
  @IsTest
  static void getMySavedListViewNamesHandlesAnUnknownObject() {
    Test.startTest();
    List<String> names = NexSListViewController.getMySavedListViewNames(
      'Not_An_Object__c'
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      names.size(),
      'An object nobody has views on returns an empty list.'
    );
  }

  /** The running user owns the answer — a second user sees their own set. */
  @IsTest
  static void getMySavedListViewNamesIsScopedToTheRunningUser() {
    User other = buildUser('nexsotheruser');
    insert other;

    List<String> names;
    Test.startTest();
    System.runAs(other) {
      names = NexSListViewController.getMySavedListViewNames('Task');
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      names.size(),
      'Views created by anyone else must not tab up for this user.'
    );
  }

  // ---- Fixture helpers ---------------------------------------------------

  private static User buildUser(String prefix) {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    return new User(
      Alias = 'nxsl',
      Email = prefix + '@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Tester',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'America/New_York',
      Username = prefix + System.now().getTime() + '@example.invalid'
    );
  }
}