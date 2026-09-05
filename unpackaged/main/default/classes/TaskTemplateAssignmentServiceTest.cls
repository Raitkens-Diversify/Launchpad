/**
 * Author: Claude
 * Date: 2026-09-04
 *
 * TaskTemplateAssignmentService lives only in the org (not in git); this test
 * is deployed against the org's copy. It exercises assignOwners' branches:
 * null/empty input, the Queue path (including the Queue -> Approval Task
 * record-type special case for Compliance/Principal Review), the FA Team
 * Permission path, and the no-team fallback that leaves a task untouched.
 */
@IsTest
private class TaskTemplateAssignmentServiceTest {
  @TestSetup
  static void setup() {
    // Isolate setup-object DML (User) from the non-setup DML below, otherwise
    // the transaction hits MIXED_DML_OPERATION.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      ArcRelatedTableTestData.createStandardUser('ttas');
    }

    // Financial_Advisor_Team_TriggerHandler.updateRepCode queries a team named
    // 'Default Team' unconditionally whenever a Financial_Advisor_Team__c is
    // updated -- which happens here through the dlrs rollup trigger fired by
    // inserting a Financial_Advisor_Team_Member__c. Test methods run without
    // org data, so without a same-named team of our own that query returns no
    // rows and throws "List has no rows for assignment to SObject".
    insert new Financial_Advisor_Team__c(
      Name = 'Default Team',
      Related_Advisors__c = 'DEFAULT' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
    );
  }

  private static User operationsUser() {
    return [
      SELECT Id
      FROM User
      WHERE Username LIKE 'ttas%@relatedtable.example.com'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static Id approvalTaskRecordTypeId() {
    return Schema.SObjectType.Task.getRecordTypeInfosByName()
      .get('Approval Task')
      .getRecordTypeId();
  }

  private static List<Task> loadForAssignment(Id taskId) {
    return [
      SELECT
        Id,
        WhatId,
        OwnerId,
        RecordTypeId,
        Task_Template__r.Assigned_To__c,
        Task_Template__r.Queue__c,
        Task_Template__r.FA_Team_Permission__c
      FROM Task
      WHERE Id = :taskId
    ];
  }

  @IsTest
  static void assignOwnersDoesNothingForNullList() {
    Test.startTest();
    TaskTemplateAssignmentService.assignOwners(null);
    Test.stopTest();
    // No exception is the assertion: a null list is a no-op.
  }

  @IsTest
  static void assignOwnersDoesNothingForEmptyList() {
    Test.startTest();
    TaskTemplateAssignmentService.assignOwners(new List<Task>());
    Test.stopTest();
    // No exception is the assertion: an empty list is a no-op.
  }

  @IsTest
  static void assignOwnersRoutesBackOfficeOperationsQueueToOperationsGroup() {
    Group operationsQueue = new Group(Name = 'Operations', Type = 'Queue');
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert operationsQueue;
    }

    Task_Template__c template = new Task_Template__c(
      Assigned_To__c = 'Queue',
      Queue__c = 'Back Office Operations'
    );
    insert template;

    Case caseRecord = new Case(Status = 'New', Origin = 'Phone');
    insert caseRecord;

    Task task = new Task(
      Subject = 'Route to ops',
      WhatId = caseRecord.Id,
      Task_Template__c = template.Id,
      Status = 'Not Started'
    );
    insert task;

    List<Task> tasksToAssign = loadForAssignment(task.Id);

    Test.startTest();
    TaskTemplateAssignmentService.assignOwners(tasksToAssign);
    Test.stopTest();

    Assert.areEqual(
      operationsQueue.Id,
      tasksToAssign[0].OwnerId,
      'Back Office Operations is a special case that maps onto the Operations queue.'
    );
  }

  @IsTest
  static void assignOwnersSetsApprovalRecordTypeForComplianceQueue() {
    Group complianceQueue = new Group(Name = 'Compliance', Type = 'Queue');
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert complianceQueue;
    }

    Task_Template__c template = new Task_Template__c(
      Assigned_To__c = 'Queue',
      Queue__c = 'Compliance'
    );
    insert template;

    Case caseRecord = new Case(Status = 'New', Origin = 'Phone');
    insert caseRecord;

    Task task = new Task(
      Subject = 'Needs compliance approval',
      WhatId = caseRecord.Id,
      Task_Template__c = template.Id,
      Status = 'Not Started'
    );
    insert task;

    List<Task> tasksToAssign = loadForAssignment(task.Id);

    Test.startTest();
    TaskTemplateAssignmentService.assignOwners(tasksToAssign);
    Test.stopTest();

    Assert.areEqual(
      complianceQueue.Id,
      tasksToAssign[0].OwnerId,
      'The Compliance queue owns the task.'
    );
    Assert.areEqual(
      approvalTaskRecordTypeId(),
      tasksToAssign[0].RecordTypeId,
      'Compliance and Principal Review route through the Approval Task record type.'
    );
  }

  @IsTest
  static void assignOwnersUsesFaTeamMemberOverCaseOwner() {
    User advisorMember = operationsUser();

    Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
      Name = 'Assignment Team',
      Related_Advisors__c = 'AT' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
    );
    insert team;

    // FA_Team_Permission__c's picklist (git metadata) offers Trading, Draft
    // Paperwork, Review Paperwork, Send Notifications, CSA, Associate Advisor
    // and Advisor -- there is no active 'Operation' value, even though
    // TaskTemplateAssignmentService.fatMemberFieldFor and the org's own
    // Case_TriggerHandler/Task_TriggerHandler both special-case it to
    // Operations__c. That branch is currently unreachable through the UI in
    // this org; 'Advisor' (-> Primary__c) exercises the same lookup logic
    // with a value the field actually accepts.
    insert new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = team.Id,
      User__c = advisorMember.Id,
      Active__c = true,
      Primary__c = true
    );

    Case caseRecord = new Case(
      Status = 'New',
      Origin = 'Phone',
      Financial_Advisor_Team__c = team.Id,
      OwnerId = UserInfo.getUserId()
    );
    insert caseRecord;

    Task_Template__c template = new Task_Template__c(
      Assigned_To__c = 'FA Team Permission',
      FA_Team_Permission__c = 'Advisor'
    );
    insert template;

    Task task = new Task(
      Subject = 'Advisor review',
      WhatId = caseRecord.Id,
      Task_Template__c = template.Id,
      Status = 'Not Started',
      OwnerId = UserInfo.getUserId()
    );
    insert task;

    List<Task> tasksToAssign = loadForAssignment(task.Id);

    Test.startTest();
    TaskTemplateAssignmentService.assignOwners(tasksToAssign);
    Test.stopTest();

    Assert.areEqual(
      advisorMember.Id,
      tasksToAssign[0].OwnerId,
      'The FA team member with the Primary flag owns the task.'
    );
    Assert.areNotEqual(
      UserInfo.getUserId(),
      tasksToAssign[0].OwnerId,
      'Confirms the FA-team-member path fired rather than leaving the running user (the case owner) in place.'
    );
  }

  @IsTest
  static void assignOwnersLeavesTaskUntouchedWhenCaseHasNoTeam() {
    Case caseRecord = new Case(Status = 'New', Origin = 'Phone');
    insert caseRecord;

    Task_Template__c template = new Task_Template__c(
      Assigned_To__c = 'FA Team Permission',
      FA_Team_Permission__c = 'Advisor'
    );
    insert template;

    Task task = new Task(
      Subject = 'No team on case',
      WhatId = caseRecord.Id,
      Task_Template__c = template.Id,
      Status = 'Not Started',
      OwnerId = UserInfo.getUserId()
    );
    insert task;

    List<Task> tasksToAssign = loadForAssignment(task.Id);

    Test.startTest();
    TaskTemplateAssignmentService.assignOwners(tasksToAssign);
    Test.stopTest();

    Assert.areEqual(
      UserInfo.getUserId(),
      tasksToAssign[0].OwnerId,
      'No team on the case means the FA Team Permission branch is skipped, leaving the owner unchanged.'
    );
  }
}