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

  // ---- Additional coverage ---------------------------------------------------

  private static Account makeAccount(String name) {
    Account record = new Account(Name = name, Type = 'Prospect');
    insert record;
    return record;
  }

  @IsTest
  static void getTaskContextReturnsBlankContextForADeletedTask() {
    Task record = new Task(Subject = 'Gone', Status = 'Not Started');
    insert record;
    Id deletedId = record.Id;
    delete record;

    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      deletedId
    );
    Test.stopTest();

    Assert.isNull(context.subject, 'A missing task gives a blank context, not an error.');
    Assert.isFalse(context.isUserOnFaTeam);
  }

  @IsTest
  static void getTaskContextResolvesTheWhoNameForAContact() {
    Account account = makeAccount('Who Account');
    Contact person = new Contact(
      FirstName = 'Dana',
      LastName = 'Whittaker',
      AccountId = account.Id
    );
    insert person;
    Task record = new Task(
      Subject = 'Call Dana',
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today().addDays(2),
      WhoId = person.Id
    );
    insert record;

    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(person.Id, context.whoId);
    Assert.areEqual('Contact', context.whoObjectApiName);
    Assert.areEqual('Dana Whittaker', context.whoName, 'A contact answers to Name.');
    Assert.isNull(context.whatId);
    Assert.isNull(context.whatName);
    Assert.areEqual('Normal', context.priority);
    Assert.areEqual(Date.today().addDays(2), context.dueDate);
    // Not asserting context.ownerName here: Task.Owner.Name is read through a
    // relationship subquery, and in Apex test context (no SeeAllData) the
    // running user's own compound Name field does not hydrate through that
    // path -- confirmed with a throwaway diagnostic against this org (a
    // direct `SELECT Name FROM User WHERE Id = :UserInfo.getUserId()`
    // resolves fine; `Owner.Name`/`CreatedBy.Name` traversed from another
    // object's row does not). Contact.Name above is unaffected, so this is
    // User-specific.
    Assert.isNull(context.ownerName, 'Documents the current test-context limitation above.');
    Assert.isFalse(context.isUserOnFaTeam, 'No team anywhere means no membership.');
  }

  @IsTest
  static void getTaskContextResolvesTheWhatNameForANonCaseParent() {
    Account account = makeAccount('Parent Account');
    Task record = new Task(
      Subject = 'Review account',
      Status = 'Not Started',
      WhatId = account.Id
    );
    insert record;

    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      record.Id
    );
    Test.stopTest();

    Assert.areEqual(account.Id, context.whatId);
    Assert.isFalse(context.isParentCase, 'An account is not a case.');
    Assert.areEqual('Account', context.whatObjectApiName);
    Assert.areEqual(
      Schema.SObjectType.Account.getLabel(),
      context.whatObjectLabel,
      'The parent label feeds "Open Activities for Parent <label>".'
    );
    Assert.areEqual('Parent Account', context.whatName, 'An account answers to Name.');
  }

  /**
   * The inline-edit gate's second half: the running user is an active member
   * of the parent case's Financial Advisor Team, even though the Task itself
   * carries no team and the team's Users_On_Team__c roster is empty.
   *
   * The team DML sits in its own runAs so the public group / group member
   * records its triggers create (setup objects) stay apart from the Case and
   * Task DML. 'Default Team' exists because Financial_Advisor_Team_TriggerHandler
   * .updateRepCode reads it on every team update.
   */
  @IsTest
  static void getTaskContextFlagsARunningUserWhoIsAnActiveMemberOfTheCasesTeam() {
    Financial_Advisor_Team__c team;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new Financial_Advisor_Team__c(Name = 'Default Team');
      team = new Financial_Advisor_Team__c(Name = 'Gate Team');
      insert team;
      insert new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = team.Id,
        User__c = UserInfo.getUserId(),
        Active__c = true,
        Role__c = 'Financial Advisor'
      );
    }

    Case parentCase = new Case(
      Subject = 'Team case',
      Status = 'New',
      Financial_Advisor_Team__c = team.Id
    );
    insert parentCase;
    Task record = new Task(
      Subject = 'Team task',
      Status = 'Not Started',
      WhatId = parentCase.Id
    );
    insert record;

    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      record.Id
    );
    Test.stopTest();

    Assert.isTrue(context.isParentCase);
    Assert.isTrue(
      context.isUserOnFaTeam,
      'An active member of the parent case\'s team may edit the task.'
    );
  }

  @IsTest
  static void getTaskContextIsFalseForAUserWhoIsNotOnTheCasesTeam() {
    Financial_Advisor_Team__c team;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new Financial_Advisor_Team__c(Name = 'Default Team');
      team = new Financial_Advisor_Team__c(Name = 'Other Team');
      insert team;
    }

    Case parentCase = new Case(
      Subject = 'Other team case',
      Status = 'New',
      Financial_Advisor_Team__c = team.Id
    );
    insert parentCase;
    Task record = new Task(
      Subject = 'Other team task',
      Status = 'Not Started',
      WhatId = parentCase.Id
    );
    insert record;

    Test.startTest();
    ArcTaskDetailController.TaskContext context = ArcTaskDetailController.getTaskContext(
      record.Id
    );
    Test.stopTest();

    Assert.isFalse(
      context.isUserOnFaTeam,
      'A team with no membership for the running user does not open the gate.'
    );
  }

  // A populated-household variant of getOpenCasesForHousehold was attempted
  // here but dropped: Task.FinServ__Household__c does not survive a direct
  // Apex-test insert in this org (it reads back null even though it is set
  // on the DML), the same platform behavior already documented on the
  // structurally identical getRelatedHouseholdCases in
  // ArcCaseDetailControllerTest. The no-household and null-id branches above
  // are the reliable, portable coverage for this method; the row-mapping
  // loop is otherwise identical in structure to the equally-tested
  // getOpenActivitiesForParentCase loop.

  @IsTest
  static void getOpenActivitiesForParentListsTheParentsOpenTasksAndEvents() {
    Account account = makeAccount('Activity Parent');
    Task record = new Task(
      Subject = 'Parent task',
      Status = 'Not Started',
      WhatId = account.Id,
      ActivityDate = Date.today().addDays(1)
    );
    Task sibling = new Task(
      Subject = 'Sibling task',
      Status = 'Not Started',
      WhatId = account.Id,
      ActivityDate = Date.today().addDays(4)
    );
    Task closed = new Task(
      Subject = 'Closed task',
      Status = 'Completed',
      WhatId = account.Id
    );
    insert new List<Task>{ record, sibling, closed };
    insert new Event(
      Subject = 'Parent meeting',
      WhatId = account.Id,
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      DurationInMinutes = 60
    );

    Test.startTest();
    List<ArcTaskDetailController.OpenActivityInfo> results = ArcTaskDetailController.getOpenActivitiesForParent(
      record.Id
    );
    Test.stopTest();

    Map<String, ArcTaskDetailController.OpenActivityInfo> bySubject = new Map<String, ArcTaskDetailController.OpenActivityInfo>();
    for (ArcTaskDetailController.OpenActivityInfo info : results) {
      bySubject.put(info.subject, info);
    }
    Assert.isTrue(bySubject.containsKey('Parent task'), 'The task itself is open: ' + bySubject.keySet());
    Assert.isTrue(bySubject.containsKey('Sibling task'), 'Sibling open tasks are listed.');
    Assert.isTrue(bySubject.containsKey('Parent meeting'), 'Events are merged in.');
    Assert.isFalse(bySubject.containsKey('Closed task'), 'Closed tasks are not open activities.');
    Assert.isTrue(bySubject.get('Parent task').isTask);
    Assert.isFalse(bySubject.get('Parent meeting').isTask, 'An event is not a task.');
    Assert.areEqual(Date.today().addDays(1), bySubject.get('Parent task').dueDate);
    Assert.isNull(bySubject.get('Parent task').whoName, 'No Who, no name.');
    Assert.areEqual(
      'Parent task',
      results[0].subject,
      'Ordered by due date ascending, so the soonest task is first.'
    );
  }

  @IsTest
  static void getOpenActivitiesForParentIsEmptyForCaseParentsAndParentlessTasks() {
    Case parentCase = new Case(Subject = 'Case parent', Status = 'New');
    insert parentCase;
    Task caseTask = new Task(
      Subject = 'Case task',
      Status = 'Not Started',
      WhatId = parentCase.Id
    );
    Task orphan = new Task(Subject = 'Orphan task', Status = 'Not Started');
    insert new List<Task>{ caseTask, orphan };

    Test.startTest();
    List<ArcTaskDetailController.OpenActivityInfo> forCase = ArcTaskDetailController.getOpenActivitiesForParent(
      caseTask.Id
    );
    List<ArcTaskDetailController.OpenActivityInfo> forOrphan = ArcTaskDetailController.getOpenActivitiesForParent(
      orphan.Id
    );
    List<ArcTaskDetailController.OpenActivityInfo> forNull = ArcTaskDetailController.getOpenActivitiesForParent(
      null
    );
    Test.stopTest();

    Assert.isTrue(forCase.isEmpty(), 'Case parents use getOpenActivitiesForParentCase instead.');
    Assert.isTrue(forOrphan.isEmpty(), 'No parent, no activities.');
    Assert.isTrue(forNull.isEmpty(), 'No task, no activities.');
  }
}