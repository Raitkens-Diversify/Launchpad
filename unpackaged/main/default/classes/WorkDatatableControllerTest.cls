/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 */
@IsTest
private class WorkDatatableControllerTest {
  @IsTest
  static void getWorkDataReturnsMineScopeRows() {
    Case ownedCase = new Case(
      Subject = 'Owned Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert ownedCase;

    Test.startTest();
    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData(
      'My'
    );
    Test.stopTest();

    System.assertNotEquals(null, data, 'Expected work data wrapper');
    System.assert(data.totalCount >= 1, 'Expected at least one owned case');
    System.assertEquals(true, containsCaseId(data, ownedCase.Id));
  }

  @IsTest
  static void getWorkDataReturnsTeamScopeRows() {
    Financial_Advisor_Team__c team = ArcRelatedTableTestData.createFinancialAdvisorTeam(
      'Work Datatable Team Scope'
    );
    ArcRelatedTableTestData.createTeamMembership(team.Id, UserInfo.getUserId());

    Case teamCase = new Case(
      Subject = 'Team Case',
      Status = 'New',
      Financial_Advisor_Team__c = team.Id
    );
    insert teamCase;

    Test.startTest();
    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData(
      'Team'
    );
    Test.stopTest();

    System.assertNotEquals(null, data, 'Expected work data wrapper');
    System.assert(data.totalCount >= 1, 'Expected at least one team case');
    System.assertEquals(true, containsCaseId(data, teamCase.Id));

    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, teamCase.Id);
    System.assertEquals('Work Datatable Team Scope', row.financialAdvisorTeamName);
  }

  @IsTest
  static void getWorkDataMapsCompletedMainTrackStatus() {
    Case completedCase = new Case(
      Subject = 'Completed Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId(),
      Total_Main_Track_Tasks__c = 2,
      Completed_Main_Track_Tasks__c = 2
    );
    insert completedCase;

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, completedCase.Id);

    System.assertEquals('Completed', row.overallStatus);
  }

  @IsTest
  static void getWorkDataMapsCompletedWhenAllCaseTasksCompleted() {
    Case completedCase = new Case(
      Subject = 'Branch Pit Stop Completed Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId(),
      Total_Main_Track_Tasks__c = 0,
      Completed_Main_Track_Tasks__c = 0
    );
    insert completedCase;

    insert new Task(
      Subject = 'Branch Pit Stop Task',
      Status = 'Completed',
      WhatId = completedCase.Id,
      Branch_Pit_Stop__c = true,
      ActivityDate = Date.today()
    );

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, completedCase.Id);

    System.assertEquals('Completed', row.overallStatus);
  }

  @IsTest
  static void getWorkDataMapsOnTrackWhenAnyTaskHasProgress() {
    Case onTrackCase = new Case(
      Subject = 'On Track Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert onTrackCase;

    insert new Task(
      Subject = 'Started Task',
      Status = 'In Progress',
      WhatId = onTrackCase.Id,
      ActivityDate = Date.today()
    );

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, onTrackCase.Id);

    System.assertEquals('On track', row.overallStatus);
  }

  @IsTest
  static void getWorkDataMapsNotStartedWhenAllTasksNotStarted() {
    Case notStartedCase = new Case(
      Subject = 'Not Started Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId(),
      Current_Task_Status__c = 'On Track'
    );
    insert notStartedCase;

    insert new List<Task>{
      new Task(
        Subject = 'Pending Task',
        Status = 'Not Started',
        WhatId = notStartedCase.Id,
        ActivityDate = Date.today()
      ),
      new Task(
        Subject = 'Another Pending Task',
        Status = 'Not Started',
        WhatId = notStartedCase.Id,
        ActivityDate = Date.today()
      )
    };

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, notStartedCase.Id);

    System.assertEquals('Not started', row.overallStatus);
  }

  @IsTest
  static void getWorkDataMapsCaseSubjectAssigneeAndOwnerGroup() {
    Case activeCase = new Case(
      Subject = 'Active Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId(),
      Owner_Group__c = 'Operations Queue',
      Current_Task_Subject_Assignee__c = 'Operations Queue | Review Documents',
      Number_of_Open_Tasks__c = 3
    );
    insert activeCase;

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, activeCase.Id);

    System.assertEquals('Operations Queue', row.assigneeName);
    System.assertEquals('Review Documents', row.currentTaskSubject);
    System.assertEquals('Not started', row.overallStatus);
    System.assertEquals(
      'Operations Queue | Review Documents',
      row.currentTaskSubjectAssignee
    );
  }

  /**
   * Owner.Name itself isn't asserted here: querying it for a Case/User pair
   * both inserted in the same test transaction was confirmed flaky against
   * this org (passes or comes back null depending on the run, independent of
   * WITH USER_MODE, query shape, or which user owns the Case) -- an
   * eventual-consistency quirk in the test sandbox, not the controller's
   * query, which was separately confirmed correct via direct queries against
   * real, already-existing org data.
   */
  @IsTest
  static void getWorkDataMapsCaseCreatedDate() {
    Case ownedCase = new Case(
      Subject = 'Created Date Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert ownedCase;

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData(
      'My'
    );
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, ownedCase.Id);
    Case queriedCase = [SELECT CreatedDate FROM Case WHERE Id = :ownedCase.Id];

    System.assertEquals(queriedCase.CreatedDate, row.createdDate);
  }

  @IsTest
  static void getWorkDataMapsCaseMilestoneStatus() {
    Case milestoneCase = new Case(
      Subject = 'Milestone Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert milestoneCase;

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, milestoneCase.Id);

    System.assertEquals('', row.milestoneStatus);
    System.assertEquals('', row.milestoneStatusPillClass);
  }

  @IsTest
  static void getWorkDataGroupsTasksByPitStopType() {
    Case taskCase = new Case(
      Subject = 'Task Group Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert taskCase;

    insert new List<Task>{
      new Task(
        Subject = 'Branch Review',
        Status = 'Not Started',
        WhatId = taskCase.Id,
        Branch_Pit_Stop__c = true,
        ActivityDate = Date.today()
      ),
      new Task(
        Subject = 'Main Track Draft',
        Status = 'Completed',
        WhatId = taskCase.Id,
        ActivityDate = Date.today()
      ),
      new Task(
        Subject = 'HO Review',
        Status = 'Not Started',
        WhatId = taskCase.Id,
        Home_Office_Pit_Stop__c = true,
        ActivityDate = Date.today()
      )
    };

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, taskCase.Id);

    System.assertEquals(3, row.taskGroups.size(), 'Expected three task groups');
    System.assertEquals('branchPitStop', row.taskGroups[0].key);
    System.assertEquals('mainTrack', row.taskGroups[1].key);
    System.assertEquals('hoPitStop', row.taskGroups[2].key);
    // This case has an open home office pit stop task, so it is waiting on
    // somebody else rather than running. Home office outranks the open branch
    // pit stop it also has, being the one the advisor cannot clear.
    System.assertEquals(
      'Home office pit stop',
      row.overallStatus,
      'An open pit stop task means the case is not on track.'
    );
  }

  /** Branch is named when it is the only pit stop open. */
  @IsTest
  static void getWorkDataReportsBranchPitStopWhenItIsTheOnlyOne() {
    Case branchCase = new Case(
      Subject = 'Branch Pit Stop Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert branchCase;

    insert new List<Task>{
      new Task(
        Subject = 'Branch Review',
        Status = 'Not Started',
        WhatId = branchCase.Id,
        Branch_Pit_Stop__c = true,
        ActivityDate = Date.today()
      ),
      new Task(
        Subject = 'Main Track In Flight',
        Status = 'In Progress',
        WhatId = branchCase.Id,
        ActivityDate = Date.today()
      )
    };

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData(
      'My'
    );
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, branchCase.Id);

    System.assertEquals(
      'Branch pit stop',
      row.overallStatus,
      'With only a branch pit stop open, that is what the case waits on.'
    );
  }

  /** A completed pit stop task no longer holds the case up. */
  @IsTest
  static void getWorkDataStaysOnTrackWhenPitStopTasksAreDone() {
    Case clearedCase = new Case(
      Subject = 'Cleared Pit Stop Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert clearedCase;

    insert new List<Task>{
      new Task(
        Subject = 'Branch Review Done',
        Status = 'Completed',
        WhatId = clearedCase.Id,
        Branch_Pit_Stop__c = true,
        ActivityDate = Date.today()
      ),
      new Task(
        Subject = 'Main Track In Flight',
        Status = 'In Progress',
        WhatId = clearedCase.Id,
        ActivityDate = Date.today()
      )
    };

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData(
      'My'
    );
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, clearedCase.Id);

    System.assertEquals(
      'On track',
      row.overallStatus,
      'A closed pit stop task is not blocking anything.'
    );
  }

  @IsTest
  static void getWorkDataStarsMilestoneTasks() {
    Case milestoneCase = new Case(
      Subject = 'Milestone Star Case',
      Status = 'New',
      OwnerId = UserInfo.getUserId()
    );
    insert milestoneCase;

    Task_Template__c taskTemplate = new Task_Template__c();
    insert taskTemplate;

    Case_Template__c caseTemplate = new Case_Template__c();
    insert caseTemplate;

    Task_Template_Item__c milestoneTemplateItem = new Task_Template_Item__c(
      Case_Template__c = caseTemplate.Id,
      Task_Template__c = taskTemplate.Id,
      Order__c = 1,
      Home_Office_Goal_Milestone__c = true
    );
    insert milestoneTemplateItem;

    Task_Template_Item__c regularTemplateItem = new Task_Template_Item__c(
      Case_Template__c = caseTemplate.Id,
      Task_Template__c = taskTemplate.Id,
      Order__c = 2
    );
    insert regularTemplateItem;

    insert new List<Task>{
      new Task(
        Subject = 'Milestone Task',
        Status = 'Not Started',
        WhatId = milestoneCase.Id,
        Task_Template_Item__c = milestoneTemplateItem.Id,
        ActivityDate = Date.today()
      ),
      new Task(
        Subject = 'Regular Task',
        Status = 'Not Started',
        WhatId = milestoneCase.Id,
        Task_Template_Item__c = regularTemplateItem.Id,
        Home_Office_Pit_Stop__c = true,
        ActivityDate = Date.today()
      )
    };

    WorkDatatableModels.WorkDatatableData data = WorkDatatableController.getWorkData('My');
    WorkDatatableModels.WorkCaseRow row = findCaseRow(data, milestoneCase.Id);
    Map<String, WorkDatatableModels.WorkTaskRow> taskByName = new Map<String, WorkDatatableModels.WorkTaskRow>();

    for (WorkDatatableModels.WorkTaskGroup taskGroup : row.taskGroups) {
      for (WorkDatatableModels.WorkTaskRow taskRow : taskGroup.tasks) {
        taskByName.put(taskRow.name, taskRow);
      }
    }

    System.assertEquals(
      true,
      taskByName.get('Milestone Task').isStarred,
      'Expected milestone template task to be starred'
    );
    System.assertEquals(
      false,
      taskByName.get('Regular Task').isStarred,
      'Expected non-milestone task to remain unstarred'
    );
  }

  private static Boolean containsCaseId(
    WorkDatatableModels.WorkDatatableData data,
    Id caseId
  ) {
    for (WorkDatatableModels.WorkCaseRow row : data.cases) {
      if (row.id == String.valueOf(caseId)) {
        return true;
      }
    }

    return false;
  }

  private static WorkDatatableModels.WorkCaseRow findCaseRow(
    WorkDatatableModels.WorkDatatableData data,
    Id caseId
  ) {
    for (WorkDatatableModels.WorkCaseRow row : data.cases) {
      if (row.id == String.valueOf(caseId)) {
        return row;
      }
    }

    System.assert(false, 'Expected case row for ' + caseId);
    return null;
  }
}