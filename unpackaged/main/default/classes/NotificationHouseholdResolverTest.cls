/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 */
@IsTest
private class NotificationHouseholdResolverTest {
  @IsTest
  static void resolveHouseholdsFromCaseUsesAccountId() {
    Account household = new Account(Name = 'Case Household');
    NotificationTestDataFactory.insertRecord(household);

    Case caseRecord = new Case(
      Subject = 'Notification Case',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationHouseholdResolver resolver = new NotificationHouseholdResolver();
    Map<Id, Id> recordIdToHouseholdId = resolver.resolveHouseholds(
      new List<SObject>{ caseRecord },
      NotificationConstants.OBJECT_TYPE_CASE
    );

    System.assertEquals(
      household.Id,
      recordIdToHouseholdId.get(caseRecord.Id),
      'Case AccountId should resolve to household'
    );
  }

  @IsTest
  static void resolveHouseholdsFromTaskUsesAccountWhatId() {
    Account household = new Account(Name = 'Task Household');
    NotificationTestDataFactory.insertRecord(household);

    Task taskRecord = new Task(
      Subject = 'Notification Task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationHouseholdResolver resolver = new NotificationHouseholdResolver();
    Map<Id, Id> recordIdToHouseholdId = resolver.resolveHouseholds(
      new List<SObject>{ taskRecord },
      NotificationConstants.OBJECT_TYPE_TASK
    );

    System.assertEquals(
      household.Id,
      recordIdToHouseholdId.get(taskRecord.Id),
      'Task WhatId Account should resolve to household'
    );
  }

  @IsTest
  static void resolveHouseholdsFromTaskUsesCaseAccount() {
    Account household = new Account(Name = 'Case Linked Household');
    NotificationTestDataFactory.insertRecord(household);

    Case caseRecord = new Case(
      Subject = 'Linked Case',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'Case Task',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationHouseholdResolver resolver = new NotificationHouseholdResolver();
    Map<Id, Id> recordIdToHouseholdId = resolver.resolveHouseholds(
      new List<SObject>{ taskRecord },
      NotificationConstants.OBJECT_TYPE_TASK
    );

    System.assertEquals(
      household.Id,
      recordIdToHouseholdId.get(taskRecord.Id),
      'Task linked to Case should resolve Case AccountId'
    );
  }

  @IsTest
  static void resolveHouseholdsReturnsEmptyForNullOrEmptyInput() {
    NotificationHouseholdResolver resolver = new NotificationHouseholdResolver();

    System.assertEquals(
      0,
      resolver.resolveHouseholds(null, NotificationConstants.OBJECT_TYPE_CASE)
        .size()
    );
    System.assertEquals(
      0,
      resolver.resolveHouseholds(
          new List<SObject>(),
          NotificationConstants.OBJECT_TYPE_TASK
        )
        .size()
    );
  }

  @IsTest
  static void resolveHouseholdsFromTaskUsesOpportunityAccount() {
    Account household = new Account(Name = 'Opportunity Household');
    NotificationTestDataFactory.insertRecord(household);

    Opportunity opportunityRecord = new Opportunity(
      Name = 'Notification Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(opportunityRecord);

    Task taskRecord = new Task(
      Subject = 'Opportunity Task',
      WhatId = opportunityRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationHouseholdResolver resolver = new NotificationHouseholdResolver();
    Map<Id, Id> recordIdToHouseholdId = resolver.resolveHouseholds(
      new List<SObject>{ taskRecord },
      NotificationConstants.OBJECT_TYPE_TASK
    );

    System.assertEquals(
      household.Id,
      recordIdToHouseholdId.get(taskRecord.Id),
      'Task linked to Opportunity should resolve Opportunity Account household'
    );
  }
}