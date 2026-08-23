/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
@IsTest
private class NotificationSourceContextServiceTest {
  @IsTest
  static void resolveCaseContextBuildsTitleAndDetail() {
    Account household = new Account(Name = 'Source Context Household');
    NotificationTestDataFactory.insertRecord(household);

    Case caseRecord = new Case(
      Subject = 'Portfolio Review',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationSourceContextService.ResolveResult result = NotificationSourceContextService.resolve(
      NotificationConstants.OBJECT_TYPE_CASE,
      String.valueOf(caseRecord.Id),
      household.Id
    );

    System.assertEquals('Source Context Household', result.householdName);
    System.assertEquals(String.valueOf(caseRecord.Id), result.targetRecordId);
    System.assertEquals('New case', result.title);
    System.assertEquals(
      'New case created for Source Context Household',
      result.body
    );
    System.assert(result.sourceDetail.contains('Portfolio Review'));
  }

  @IsTest
  static void resolveTaskContextUsesSubject() {
    Account household = new Account(Name = 'Task Household');
    NotificationTestDataFactory.insertRecord(household);

    Task taskRecord = new Task(
      Subject = 'Follow up call',
      WhatId = household.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationSourceContextService.ResolveResult result = NotificationSourceContextService.resolve(
      NotificationConstants.OBJECT_TYPE_TASK,
      String.valueOf(taskRecord.Id),
      household.Id
    );

    System.assertEquals('Follow up call', result.sourceDetail);
    System.assertEquals(String.valueOf(taskRecord.Id), result.targetRecordId);
    System.assertEquals('New task', result.title);
    System.assertEquals(
      'New task created for Task Household',
      result.body
    );
  }

  @IsTest
  static void resolveEventContextFallsBackToHouseholdTarget() {
    Account household = new Account(Name = 'Event Household');
    NotificationTestDataFactory.insertRecord(household);

    NotificationSourceContextService.ResolveResult result = NotificationSourceContextService.resolve(
      NotificationConstants.OBJECT_TYPE_EVENT,
      null,
      household.Id
    );

    System.assertEquals('Event details unavailable', result.sourceDetail);
    System.assertEquals(String.valueOf(household.Id), result.targetRecordId);
    System.assertEquals('Event Household', result.householdName);
    System.assertEquals('New event', result.title);
    System.assertEquals(
      'New event created for Event Household',
      result.body
    );
  }
}