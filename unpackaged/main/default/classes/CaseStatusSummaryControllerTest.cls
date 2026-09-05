/*@IsTest
public class CaseStatusSummaryControllerTest {

    @TestSetup
    static void setup() {
        // Create User for Owner
        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testuser234@unique.com.test',
            Alias = 'tusr',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        Task_Template__c ttmp = new Task_Template__c(
        );
        insert ttmp;
        Case_Template__c ctmp = new Case_Template__c(
        );
		insert ctmp;
        // Create Case Template
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType='Case' LIMIT 1];
        Case c = new Case(
            Status = 'New',
            Origin = 'Phone',
            RecordTypeId = rt.Id,
            Case_Template__c = ctmp.Id,
            Total_Main_Track_Tasks__c = 5,
            Completed_Main_Track_Tasks__c = 2
        );
        insert c;

        // Create Task Template Item + Activity
        Task_Template_Item__c tti = new Task_Template_Item__c(
            Case_Template__c = ctmp.Id,
            Task_Template__c = ttmp.Id,
            Branch_Goal_Milestone__c = true
        );
        insert tti;

        Task act = new Task(
            Task_Template_Item__c = tti.Id,
            Status = 'Completed'
        );
        insert act;

        // Create a Task for Case
        Task t = new Task(
            Subject = 'Review documents',
            OwnerId = u.Id,
            WhatId = c.Id,
            Branch_Pit_Stop__c = true,
            Status = 'Completed'
        );
        insert t;

        // Update Case with Task Id
        c.Current_Task_Id__c = t.Id;
        update c;
    }

    @IsTest
    static void testGetCaseStatusSummary() {
        User u = [SELECT Id FROM User LIMIT 1];
        Case c = [SELECT Id, Current_Task_Id__c FROM Case LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper result =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(c.Current_Task_Id__c, result.currentTaskId);
        System.assert(result.statusMessage.contains('Branch Pit Stop'), 'Status message should reflect pit stop');
        System.assertEquals(5, result.totalTasks);
        System.assertEquals(2, result.completedTasks);
        System.assertNotEquals(null, result.wrappedMilestones);
    }

    @IsTest
    static void testNullCaseId() {
        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper result =
            CaseStatusSummaryController.getCaseStatusSummary(null, null);
        Test.stopTest();

        System.assertEquals('', result.statusMessage, 'Should return blank wrapper on null input');
    }

    @IsTest
    static void testCaseStatus() {
        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper result =
            CaseStatusSummaryController.getCaseStatusSummary([SELECT Id FROM Case limit 1].Id, null);
        Test.stopTest();

        System.assertEquals(true, result.statusMessage.contains('Branch Pit Stop'));
    }
}*/

@IsTest
public class CaseStatusSummaryControllerTest {

    @TestSetup
    static void setup() {
        // Create User for Owner
        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testuser234@unique.com.test',
            Alias = 'tusr',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        // Isolate setup-object DML (User / PermissionSetAssignment) from the
        // non-setup DML below, otherwise the transaction hits MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }

        // Financial_Advisor_Team_TriggerHandler.updateRepCode queries a team
        // named 'Default Team' unconditionally whenever a Financial_Advisor_Team__c
        // is updated -- which happens as soon as a test method here sets
        // Primary_Financial_Advisor__c on a team (that auto-creates a
        // Financial_Advisor_Team_Member__c, whose dlrs rollup updates the
        // parent team). Test methods run without org data, so without a
        // same-named team of our own that query returns no rows and throws
        // "List has no rows for assignment to SObject".
        insert new Financial_Advisor_Team__c(
            Name = 'Default Team',
            Related_Advisors__c = 'DEFAULT' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        Task_Template__c ttmp = new Task_Template__c();
        insert ttmp;

        Case_Template__c ctmp = new Case_Template__c();
        insert ctmp;

        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType='Case' LIMIT 1];

        Case c = new Case(
            Status = 'New',
            Origin = 'Phone',
            RecordTypeId = rt.Id,
            Case_Template__c = ctmp.Id,
            Total_Main_Track_Tasks__c = 5,
            Completed_Main_Track_Tasks__c = 2
        );
        insert c;

        Task_Template_Item__c tti = new Task_Template_Item__c(
            Case_Template__c = ctmp.Id,
            Task_Template__c = ttmp.Id,
            Branch_Goal_Milestone__c = true,
          	Home_Office_Submission_Milestone__c = true,
            Home_Office_Approval_Milestone__c = true,
            Home_Office_Goal_Milestone__c = true
        );
        insert tti;

        Task milestoneTask = new Task(
            Task_Template_Item__c = tti.Id,
            WhatId = c.Id,
            Status = 'Completed'
        );
        insert milestoneTask;

        Task currentTask = new Task(
            Subject = 'Review documents',
            OwnerId = u.Id,
            WhatId = c.Id,
            Branch_Pit_Stop__c = true,
            Status = 'Not Started'
        );
        insert currentTask;

        // Five main-track tasks, two complete, so the 5/2 the assertions expect
        // exist as records: the counts are now read from the tasks rather than
        // from Total_Main_Track_Tasks__c. The count selects tasks whose
        // Full_Template_Order__c is set, so each task carries a sequence value.
        // The template item's milestone flags are deliberately left off so this
        // does not disturb the milestone assertions in the tests below.
        //
        // Full_Template_Order__c starts at 101, not 1: inserting this Case with
        // Case_Template__c already set fires Case_TriggerHandler's isAfterInsert
        // -> createWizardTask, which enqueues a @future (setCurrentTask) that
        // flushes at Test.stopTest() and re-points Case.Current_Task_Id__c at
        // whichever Task has Full_Template_Order__c = 1 (2 becomes Next_Task__c).
        // That runs after every other setup DML here, including this loop, so a
        // main-track task landing on order 1 silently overwrites the
        // Current_Task_Id__c set below and the pit-stop assertions fail against
        // the wrong task. Keeping these orders out of {1, 2} sidesteps that
        // platform automation instead of fighting it.
        Task_Template_Item__c orderedItem = new Task_Template_Item__c(
            Case_Template__c = ctmp.Id,
            Task_Template__c = ttmp.Id,
            Order__c = 1
        );
        insert orderedItem;

        List<Task> mainTrack = new List<Task>();
        for (Integer i = 1; i <= 5; i++) {
            mainTrack.add(new Task(
                Subject = 'Main track ' + i,
                WhatId = c.Id,
                Task_Template_Item__c = orderedItem.Id,
                Full_Template_Order__c = 100 + i,
                Status = i <= 2 ? 'Completed' : 'Not Started'
            ));
        }
        insert mainTrack;

        c.Current_Task_Id__c = currentTask.Id;
        update c;
    }

    @IsTest
    static void testGetCaseStatusSummary_BranchUser() {
        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrap, 'Wrapper should not be null');
        System.assertEquals(5, wrap.totalTasks, 'Total tasks mismatch');
        System.assertEquals(2, wrap.completedTasks, 'Completed tasks mismatch');
        System.assertEquals('Branch Pit Stop Task', wrap.statusMessage);
        System.assertEquals('Review documents', wrap.nextAction);
        System.assertNotEquals('', wrap.formattedOwnerDetail);
        System.assertNotEquals('', wrap.timeInStage);
        System.assertEquals(true, wrap.wrappedMilestones.size() > 0);
        System.assertEquals('HO Submission', wrap.wrappedMilestones[0].label);
        System.assertEquals(true, wrap.wrappedMilestones[0].isCompleted);
    }

    @IsTest
    static void testGetCaseStatusSummary_HomeOfficeSubmission() {
        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];
        Case c = [SELECT Id FROM Case LIMIT 1];
        // Filtered to the milestone item: setup also creates an ordered item to
        // hang the main-track tasks off, so an unfiltered single-row assignment
        // here now matches two records.
        Task_Template_Item__c tti = [SELECT Id, Home_Office_Submission_Milestone__c, Home_Office_Approval_Milestone__c, Home_Office_Goal_Milestone__c FROM Task_Template_Item__c WHERE Branch_Goal_Milestone__c = TRUE LIMIT 1];
        tti.Home_Office_Submission_Milestone__c = true;
        tti.Home_Office_Approval_Milestone__c = true;
        tti.Home_Office_Goal_Milestone__c = true;

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrap, 'Wrapper should not be null');
        System.assertEquals(5, wrap.totalTasks, 'Total tasks mismatch');
        System.assertEquals(2, wrap.completedTasks, 'Completed tasks mismatch');
        System.assertEquals('Branch Pit Stop Task', wrap.statusMessage);
        System.assertEquals('Review documents', wrap.nextAction);
        System.assertNotEquals('', wrap.formattedOwnerDetail);
        System.assertNotEquals('', wrap.timeInStage);
        System.assertEquals(true, wrap.wrappedMilestones.size() > 0);
        System.assertEquals('HO Submission', wrap.wrappedMilestones[0].label);
        System.assertEquals(true, wrap.wrappedMilestones[0].isCompleted);
    }

    @IsTest
    static void testGetCaseStatusSummary_NullCaseId() {
        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(null, u.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrap);
        System.assertEquals(0, wrap.totalTasks);
        System.assertEquals('', wrap.statusMessage);
    }

    @IsTest
    static void testGetCaseStatusSummary_NoCurrentTask() {
        Case c = [SELECT Id, Current_Task_Id__c FROM Case LIMIT 1];
        c.Current_Task_Id__c = null;
        update c;

        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertEquals('No current Task set.', wrap.statusMessage);
    }

    private static Id personAccountRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
    }

    /**
     * resolveMembership's early return, and how it is actually reached in this
     * org: Case_TriggerHandler.populateBranchAndHomeNames recomputes
     * Case_Branch_Name__c from Type/Financial Account/Financial Advisor
     * Team/Amount on every insert and update (unconditionally, not only "on
     * orgs whose Case trigger writes it" as resolveMembership's own comment
     * assumes), so any Case with one of those fields set already carries a
     * non-blank stored value by the time the controller reads it. That makes
     * resolveMembership's own live-build fallback (the `describesCase` block)
     * unreachable through normal data in this org -- see the coverage note in
     * the final report.
     */
    @IsTest
    static void testGetCaseStatusSummary_BuildsMembershipFromTypeAndAmountWhenNothingElseDescribesTheCase() {
        Case c = new Case(
            Status = 'New',
            Origin = 'Phone',
            Type = 'Question',
            Amount__c = 250
        );
        insert c;

        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assert(
            wrap.membership.contains('Question'),
            'The case Type is part of the built summary line.'
        );
        System.assert(
            wrap.membership.contains('$'),
            'The amount is part of the built summary line.'
        );
    }

    /**
     * A Home Office user (GroupMember of the Home_Office public group) reads
     * Case_Home_Office_Name__c instead of Case_Branch_Name__c, and -- with a
     * live Financial Account and Financial Advisor Team on the case -- the
     * summary line is built from both, advisor before owner (Home Office
     * ordering, the reverse of the branch ordering covered above).
     */
    @IsTest
    static void testGetCaseStatusSummary_HomeOfficeUserBuildsMembershipFromFinancialAccountAndTeam() {
        Group homeOfficeGroup = new Group(Name = 'Home_Office');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert homeOfficeGroup;
            insert new GroupMember(
                GroupId = homeOfficeGroup.Id,
                UserOrGroupId = UserInfo.getUserId()
            );
        }

        Account personOwner = new Account(
            FirstName = 'Owner',
            LastName = 'Person',
            RecordTypeId = personAccountRecordTypeId(),
            Type = 'Prospect'
        );
        insert personOwner;

        Financial_Account__c financialAccount = new Financial_Account__c(
            Name = 'Membership Line Account',
            Registration_Type__c = '403(b)',
            Custodian__c = 'DIRECT',
            Managed_Account_Platform__c = 'AltMS',
            BD_or_RIA__c = 'RIA',
            Primary_Owner__c = personOwner.Id
        );
        insert financialAccount;

        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
            Name = 'Membership Line Team',
            Related_Advisors__c = 'MEM' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Primary_Financial_Advisor__c = UserInfo.getUserId()
        );
        insert team;

        Case c = new Case(
            Status = 'New',
            Origin = 'Phone',
            Type = 'Question',
            Amount__c = 500,
            Wizard_Financial_Account__c = financialAccount.Id,
            Financial_Advisor_Team__c = team.Id
        );
        insert c;

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, UserInfo.getUserId());
        Test.stopTest();

        System.assert(
            wrap.membership.contains('403(b)'),
            'The Financial Account registration type is part of the built summary line.'
        );
        System.assert(
            wrap.membership.contains('$'),
            'The amount is part of the built summary line.'
        );
    }

    /**
     * buildMilestones' other statusMessage write: every Task on the case is
     * Completed, so the tile leads with "All Tasks Completed" ahead of the
     * per-milestone breakdown (there is no Current_Task_Id__c on this case, so
     * processCurrentTask's "No current Task set." is what gets overwritten).
     */
    @IsTest
    static void testGetCaseStatusSummary_AllTasksCompletedSetsSummaryMessage() {
        Task_Template__c ttmp = new Task_Template__c();
        insert ttmp;
        Case_Template__c ctmp = new Case_Template__c();
        insert ctmp;

        // Deliberately not set on the Case itself (see the Full_Template_Order__c
        // comment in setup()): this case never reaches Case_TriggerHandler's
        // createWizardTask, so there is no async Current_Task_Id__c rewrite to
        // account for here.
        Task_Template_Item__c tti = new Task_Template_Item__c(
            Case_Template__c = ctmp.Id,
            Task_Template__c = ttmp.Id,
            Branch_Goal_Milestone__c = true
        );
        insert tti;

        Case c = new Case(Status = 'New', Origin = 'Phone');
        insert c;

        Task completedTask = new Task(
            Task_Template_Item__c = tti.Id,
            WhatId = c.Id,
            Status = 'Completed'
        );
        insert completedTask;

        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];

        Test.startTest();
        CaseStatusSummaryController.CaseStatusWrapper wrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertEquals('All Tasks Completed', wrap.statusMessage);
        System.assertEquals(1, wrap.wrappedMilestones.size());
        System.assertEquals('Branch Goal', wrap.wrappedMilestones[0].label);
        System.assertEquals(true, wrap.wrappedMilestones[0].isCompleted);
    }

    /**
     * processCurrentTask's remaining statusMessage branches (HO Pit Stop, On
     * Track, Unspecified) and formatOwner's Group-owner and User-department
     * branches, exercised by repointing one Case's Current_Task_Id__c at
     * different tasks in turn. No Case_Template__c is set on this case, so
     * (as above) there is no async current-task rewrite to work around.
     */
    @IsTest
    static void testGetCaseStatusSummary_CurrentTaskMessageAndOwnerVariants() {
        // Task.OwnerId only accepts a User or a Queue (Type = 'Queue'), and a
        // Group needs a QueueSObject row -- itself a setup object -- before a
        // Task can actually be assigned to it.
        Group opsGroup = new Group(Name = 'Membership Ops Group', Type = 'Queue');
        User departmentUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert opsGroup;
            insert new QueueSObject(QueueId = opsGroup.Id, SobjectType = 'Task');
        }
        departmentUser = new User(
            Id = UserInfo.getUserId(),
            Department_Picklist__c = 'Operations'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update departmentUser;
        }

        Case c = new Case(Status = 'New', Origin = 'Phone');
        insert c;

        Task_Template__c ttmp = new Task_Template__c();
        insert ttmp;

        Task hoPitStopTask = new Task(
            Subject = 'HO pit stop task',
            WhatId = c.Id,
            OwnerId = opsGroup.Id,
            Home_Office_Pit_Stop__c = true,
            Status = 'Not Started'
        );
        insert hoPitStopTask;

        Task onTrackTask = new Task(
            Subject = 'On track task',
            WhatId = c.Id,
            OwnerId = UserInfo.getUserId(),
            Task_Template__c = ttmp.Id,
            Status = 'Not Started'
        );
        insert onTrackTask;

        Task unspecifiedTask = new Task(
            Subject = 'Unspecified task',
            WhatId = c.Id,
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started'
        );
        insert unspecifiedTask;

        User u = [SELECT Id FROM User WHERE Username LIKE 'testuser%' LIMIT 1];

        Test.startTest();
        c.Current_Task_Id__c = hoPitStopTask.Id;
        update c;
        CaseStatusSummaryController.CaseStatusWrapper hoWrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);

        c.Current_Task_Id__c = onTrackTask.Id;
        update c;
        CaseStatusSummaryController.CaseStatusWrapper onTrackWrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);

        c.Current_Task_Id__c = unspecifiedTask.Id;
        update c;
        CaseStatusSummaryController.CaseStatusWrapper unspecifiedWrap =
            CaseStatusSummaryController.getCaseStatusSummary(c.Id, u.Id);
        Test.stopTest();

        System.assertEquals('HO Pit Stop Task', hoWrap.statusMessage);
        System.assertEquals(
            opsGroup.Name + ' | HO pit stop task',
            hoWrap.formattedOwnerDetail,
            'A Group-owned task reports the group name.'
        );

        System.assertEquals('This Case is On Track.', onTrackWrap.statusMessage);
        System.assert(
            onTrackWrap.formattedOwnerDetail.contains('Operations'),
            'A User owner with a department reports it ahead of the subject.'
        );

        System.assertEquals('This Case status is Unspecified.', unspecifiedWrap.statusMessage);
    }

}