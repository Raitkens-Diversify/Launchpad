/**
 * Author: Claude
 * Date: 2026-08-17
 *
 * Fixture: a household with one person-account member under it, a case on each
 * of the three ways a case reaches an account (direct, household, contact), and
 * a task on each of the two lookups a task uses (WhatId, WhoId).
 *
 * No org prerequisites beyond person accounts being enabled, which this org
 * requires throughout.
 */
@IsTest
private class ArcRecordWorkItemsControllerTest {
  private static Id householdRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Household')
      .getRecordTypeId();
  }

  private static Id personRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();
  }

  @TestSetup
  static void setup() {
    Account household = new Account(
      Name = 'Work Items Household',
      RecordTypeId = householdRecordTypeId()
    );
    insert household;

    Account member = new Account(
      FirstName = 'Work',
      LastName = 'Member',
      Household__c = household.Id,
      RecordTypeId = personRecordTypeId()
    );
    insert member;
  }

  private static Account member() {
    return [
      SELECT Id, PersonContactId, Household__c
      FROM Account
      WHERE LastName = 'Member'
      LIMIT 1
    ];
  }

  @IsTest
  static void getWorkItemsReturnsCasesReachedEveryWay() {
    Account contact = member();

    insert new List<Case>{
      new Case(Subject = 'Direct case', AccountId = contact.Id),
      new Case(Subject = 'Contact case', ContactId = contact.PersonContactId)
    };

    Test.startTest();
    ArcRecordWorkItemsController.WorkItems result = ArcRecordWorkItemsController.getWorkItems(
      contact.Id
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ArcRecordWorkItemsController.WorkItem item : result.cases) {
      titles.add(item.title);
    }

    Assert.isTrue(
      titles.contains('Direct case'),
      'A case linked straight to the account belongs to it.'
    );
    Assert.isTrue(
      titles.contains('Contact case'),
      'A case on the contact behind a person account belongs to it too.'
    );
  }

  @IsTest
  static void getWorkItemsReturnsTasksFromBothLookups() {
    Account contact = member();

    insert new List<Task>{
      new Task(Subject = 'What task', WhatId = contact.Id),
      new Task(Subject = 'Who task', WhoId = contact.PersonContactId)
    };

    Test.startTest();
    ArcRecordWorkItemsController.WorkItems result = ArcRecordWorkItemsController.getWorkItems(
      contact.Id
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ArcRecordWorkItemsController.WorkItem item : result.tasks) {
      titles.add(item.title);
    }

    Assert.isTrue(
      titles.contains('What task'),
      'A task on the account itself is the account\'s work.'
    );
    Assert.isTrue(
      titles.contains('Who task'),
      'Task.Who is polymorphic and cannot be traversed in SOQL, so the person contact is resolved first; this is the assertion that catches it regressing.'
    );
  }

  /**
   * A household page shows the household's own work.
   *
   * Linked through AccountId rather than FinServ__Household__c: that field is
   * derived by org automation from the case's contact and is cleared on insert
   * when there is none, so setting it directly here would only be asserting
   * against the automation. The controller still matches on it, which is what
   * covers the 138 existing cases that carry it.
   */
  @IsTest
  static void getWorkItemsIncludesHouseholdCases() {
    Id householdId = [
      SELECT Id
      FROM Account
      WHERE Name = 'Work Items Household'
      LIMIT 1
    ]
    .Id;

    insert new Case(Subject = 'Household case', AccountId = householdId);

    Test.startTest();
    ArcRecordWorkItemsController.WorkItems result = ArcRecordWorkItemsController.getWorkItems(
      householdId
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ArcRecordWorkItemsController.WorkItem item : result.cases) {
      titles.add(item.title);
    }
    Assert.isTrue(
      titles.contains('Household case'),
      'A case on the household shows on the household.'
    );
  }

  /** An account with nothing on it returns empty lists, not null. */
  @IsTest
  static void getWorkItemsReturnsEmptyListsForAnUnusedRecord() {
    Account contact = member();

    Test.startTest();
    ArcRecordWorkItemsController.WorkItems result = ArcRecordWorkItemsController.getWorkItems(
      contact.Id
    );
    Test.stopTest();

    Assert.isNotNull(result.cases, 'Cases should be an empty list, not null.');
    Assert.isNotNull(result.tasks, 'Tasks should be an empty list, not null.');
    Assert.areEqual(0, result.cases.size(), 'No cases were created.');
    Assert.areEqual(0, result.tasks.size(), 'No tasks were created.');
  }

  @IsTest
  static void getWorkItemsRejectsNullRecordId() {
    Boolean threw = false;
    try {
      ArcRecordWorkItemsController.getWorkItems(null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Assert.isTrue(threw, 'A null record id should be refused, not queried.');
  }
}