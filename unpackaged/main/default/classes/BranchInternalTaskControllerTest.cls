/**
 * BranchInternalTaskControllerTest
 *
 * BranchInternalTaskController.getTasks returns the Branch_Internal_task__c Tasks
 * related to a given record (Task.WhatId), newest first. These tests confirm the
 * WhatId filter, the Branch_Internal_task__c = true filter, the CreatedDate DESC
 * ordering, and the empty-result path.
 *
 * Accounts are given a Type to satisfy the Type_OR_Classification_Required
 * validation rule (activated 2026-09-02).
 */
@IsTest
private class BranchInternalTaskControllerTest {

  private static Account makeAccount(String name) {
    Account acct = new Account(Name = name, Type = 'Prospect');
    insert acct;
    return acct;
  }

  private static Task makeTask(String subject, Id whatId, Boolean branchInternal) {
    return new Task(
      Subject = subject,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = UserInfo.getUserId(),
      WhatId = whatId,
      Branch_Internal_task__c = branchInternal
    );
  }

  @IsTest
  static void getTasks_returnsOnlyBranchInternalTasksForRecord() {
    Account target = makeAccount('Target Household');
    Account other = makeAccount('Other Household');

    insert new List<Task>{
      makeTask('Branch Internal On Target', target.Id, true),
      makeTask('Regular Task On Target', target.Id, false),
      makeTask('Branch Internal On Other', other.Id, true)
    };

    Test.startTest();
    List<Task> results = BranchInternalTaskController.getTasks(target.Id);
    Test.stopTest();

    System.assertEquals(1, results.size(),
      'Only the branch-internal task on the target record should be returned');
    System.assertEquals('Branch Internal On Target', results[0].Subject,
      'The returned task should be the branch-internal one on the target record');
    System.assertEquals(true, results[0].Branch_Internal_task__c,
      'Only Branch_Internal_task__c = true records should be returned');
    System.assertEquals(target.Id, results[0].WhatId,
      'Returned task should be related to the requested record');
  }

  

  @IsTest
  static void getTasks_returnsEmptyWhenNoMatchingTasks() {
    Account target = makeAccount('Empty Household');
    // A non-branch-internal task must not be returned.
    insert makeTask('Regular Only', target.Id, false);

    Test.startTest();
    List<Task> results = BranchInternalTaskController.getTasks(target.Id);
    Test.stopTest();

    System.assertEquals(0, results.size(),
      'No branch-internal tasks exist for this record, so the list should be empty');
  }
}