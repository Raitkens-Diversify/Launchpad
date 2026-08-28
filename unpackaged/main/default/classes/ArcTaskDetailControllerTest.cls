@IsTest
private class ArcTaskDetailControllerTest {
  @IsTest
  static void getTaskContextReturnsWhatWhoOwnerAndParentCaseFlag() {
    Case parentCase = new Case(Subject = 'Parent Case', Status = 'New');
    insert parentCase;

    Task record = new Task(
      Subject = 'Confirm Rep Change is Complete',
      Status = 'Not Started',
      WhatId = parentCase.Id
    );
    insert record;

    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(parentCase.Id, context.whatId);
    Assert.areEqual(UserInfo.getUserId(), context.ownerId, 'defaults to the inserting user');
    Assert.areEqual('Not Started', context.status);
    Assert.areEqual('Confirm Rep Change is Complete', context.subject);
    Assert.isTrue(context.isParentCase);
    Assert.areEqual('Case', context.whatObjectApiName);

    Case insertedCase = [SELECT CaseNumber FROM Case WHERE Id = :parentCase.Id];
    Assert.areEqual(insertedCase.CaseNumber, context.whatName, 'What is a Case, so its display name is the case number');
  }

  @IsTest
  static void getTaskContextIsFalseForParentCaseWhenWhatIdBlank() {
    Task record = new Task(Subject = 'Standalone task', Status = 'Not Started');
    insert record;

    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      record.Id
    );
    Test.stopTest();

    Assert.isNull(context.whatId);
    Assert.isFalse(context.isParentCase);
  }

  @IsTest
  static void getTaskContextReturnsBlankContextForNullId() {
    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      null
    );
    Test.stopTest();

    Assert.isNull(context.whatId);
    Assert.isNull(context.subject);
    Assert.isFalse(context.isParentCase);
  }

  @IsTest
  static void getOpenActivitiesForParentCaseReturnsOnlyOpenSiblingTasks() {
    Case parentCase = new Case(Subject = 'Rep Change Case', Status = 'New');
    insert parentCase;

    Task currentTask = new Task(
      Subject = 'Confirm Rep Change is Complete',
      Status = 'Not Started',
      WhatId = parentCase.Id
    );
    Task siblingOpenTask = new Task(
      Subject = 'Submit Applicable Rep Change Docs',
      Status = 'Not Started',
      WhatId = parentCase.Id
    );
    Task siblingClosedTask = new Task(
      Subject = 'Already handled',
      Status = 'Completed',
      WhatId = parentCase.Id
    );
    insert new List<Task>{ currentTask, siblingOpenTask, siblingClosedTask };

    Test.startTest();
    List<ArcCaseDetailController.TaskInfo> results = ArcTaskDetailController.getOpenActivitiesForParentCase(
      currentTask.Id
    );
    Test.stopTest();

    Assert.areEqual(2, results.size(), 'only the two open tasks should surface');
    Set<Id> resultIds = new Set<Id>();
    for (ArcCaseDetailController.TaskInfo info : results) {
      resultIds.add(info.id);
    }
    Assert.isTrue(resultIds.contains(currentTask.Id), 'the current task itself should be included when open');
    Assert.isTrue(resultIds.contains(siblingOpenTask.Id));
    Assert.isFalse(resultIds.contains(siblingClosedTask.Id));
  }

  @IsTest
  static void getOpenActivitiesForParentCaseReturnsEmptyWhenNoParentCase() {
    Task record = new Task(Subject = 'No parent case', Status = 'Not Started');
    insert record;

    Test.startTest();
    List<ArcCaseDetailController.TaskInfo> results = ArcTaskDetailController.getOpenActivitiesForParentCase(
      record.Id
    );
    Test.stopTest();

    Assert.isTrue(results.isEmpty());
  }

  @IsTest
  static void getOpenActivitiesForParentCaseReturnsEmptyForNullId() {
    Test.startTest();
    List<ArcCaseDetailController.TaskInfo> results = ArcTaskDetailController.getOpenActivitiesForParentCase(
      null
    );
    Test.stopTest();

    Assert.isTrue(results.isEmpty());
  }

  // A "task's household has open case siblings" test would need
  // Case.FinServ__Household__c to survive insert, which -- per
  // ArcCaseDetailControllerTest's own documented findings for the
  // structurally identical getRelatedHouseholdCases -- this org's automation
  // clears specifically in Apex test context. The no-household path below
  // (the actual query's early-exit branch) is the reliable part to cover;
  // the row-mapping loop is otherwise identical in structure to the
  // equally-tested getOpenActivitiesForParentCase loop.
  @IsTest
  static void getOpenCasesForHouseholdReturnsEmptyWhenTaskHasNoHousehold() {
    Task record = new Task(Subject = 'No household task', Status = 'Not Started');
    insert record;

    Test.startTest();
    List<ArcCaseDetailController.RelatedCaseInfo> results = ArcTaskDetailController.getOpenCasesForHousehold(
      record.Id
    );
    Test.stopTest();

    Assert.isTrue(results.isEmpty());
  }

  @IsTest
  static void getOpenCasesForHouseholdReturnsEmptyForNullId() {
    Test.startTest();
    List<ArcCaseDetailController.RelatedCaseInfo> results = ArcTaskDetailController.getOpenCasesForHousehold(
      null
    );
    Test.stopTest();

    Assert.isTrue(results.isEmpty());
  }
}