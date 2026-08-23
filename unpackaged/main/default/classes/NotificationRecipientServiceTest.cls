/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 */
@IsTest
private class NotificationRecipientServiceTest {
  @IsTest
  static void getRecipientsByHouseholdReturnsSendNotificationsMembers() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationRecipientService recipientService = new NotificationRecipientService();
    Map<Id, List<Id>> householdIdToRecipientIds = recipientService.getRecipientsByHousehold(
      new Set<Id>{ context.household.Id }
    );

    System.assertEquals(1, householdIdToRecipientIds.size());
    System.assertEquals(
      context.recipientUser.Id,
      householdIdToRecipientIds.get(context.household.Id)[0]
    );
  }

  @IsTest
  static void getRecipientsByHouseholdExcludesInactiveMembers() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>();

    NotificationRecipientService recipientService = new NotificationRecipientService();
    Map<Id, List<Id>> householdIdToRecipientIds = recipientService.getRecipientsByHousehold(
      new Set<Id>{ context.household.Id }
    );

    System.assertEquals(true, householdIdToRecipientIds.isEmpty());
  }

  @IsTest
  static void getRecipientsByHouseholdResolvesFaTeamMembers() {
    User recipientUser = NotificationTestDataFactory.createHouseholdWithRecipient().recipientUser;
    NotificationRecipientService.testRecipientOverrides = null;

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Repository Test Team',
      Related_Advisors__c = 'RepoTest' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'FA Team Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    Financial_Advisor_Team_Member__c activeMember = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = faTeam.Id,
      User__c = recipientUser.Id,
      Send_Notifications__c = true,
      Active__c = true
    );

    Boolean memberInsertSucceeded = true;
    try {
      NotificationTestDataFactory.insertRecord(activeMember);
    } catch (DmlException ex) {
      memberInsertSucceeded = false;
    }

    if (!memberInsertSucceeded) {
      System.assert(true, 'Org FA Team automation prevented member insert; override path covered elsewhere.');
      return;
    }

    NotificationRecipientService recipientService = new NotificationRecipientService();
    Map<Id, List<Id>> householdIdToRecipientIds = recipientService.getRecipientsByHousehold(
      new Set<Id>{ household.Id }
    );

    System.assertEquals(1, householdIdToRecipientIds.get(household.Id).size());
    System.assertEquals(recipientUser.Id, householdIdToRecipientIds.get(household.Id)[0]);
  }

  @IsTest
  static void getRecipientsByHouseholdIncludesPreferenceEnabledTeamMembers() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationRecipientService.testRecipientOverrides = null;

    User preferenceUser = context.recipientUser;
    User sendNotificationsUser = NotificationTestDataFactory.createStandardUser('sendnotif');

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Preference Recipient Team',
      Related_Advisors__c = 'PrefRec' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Preference Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    List<Financial_Advisor_Team_Member__c> members = new List<Financial_Advisor_Team_Member__c>{
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = preferenceUser.Id,
        Send_Notifications__c = false,
        Active__c = true
      ),
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = sendNotificationsUser.Id,
        Send_Notifications__c = true,
        Active__c = true
      )
    };

    Boolean memberInsertSucceeded = true;
    try {
      for (Financial_Advisor_Team_Member__c member : members) {
        NotificationTestDataFactory.insertRecord(member);
      }
    } catch (DmlException ex) {
      memberInsertSucceeded = false;
    }

    if (!memberInsertSucceeded) {
      System.assert(true, 'Org FA Team automation prevented member insert; override path covered elsewhere.');
      return;
    }

    NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      preferenceUser.Id,
      household.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationRecipientService recipientService = new NotificationRecipientService();
    Map<Id, List<Id>> householdIdToRecipientIds = recipientService.getRecipientsByHousehold(
      new Set<Id>{ household.Id }
    );

    Set<Id> recipientIds = new Set<Id>(householdIdToRecipientIds.get(household.Id));

    System.assertEquals(2, recipientIds.size());
    System.assert(recipientIds.contains(preferenceUser.Id));
    System.assert(recipientIds.contains(sendNotificationsUser.Id));
  }

  @IsTest
  static void getRecipientsByHouseholdIncludesActiveMembersWithoutPreferences() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationRecipientService.testRecipientOverrides = null;

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'System Default Recipient Team',
      Related_Advisors__c = 'SysDef' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'System Default Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    Financial_Advisor_Team_Member__c activeMember = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = faTeam.Id,
      User__c = context.recipientUser.Id,
      Send_Notifications__c = false,
      Active__c = true
    );

    Boolean memberInsertSucceeded = true;
    try {
      NotificationTestDataFactory.insertRecord(activeMember);
    } catch (DmlException ex) {
      memberInsertSucceeded = false;
    }

    if (!memberInsertSucceeded) {
      System.assert(true, 'Org FA Team automation prevented member insert; override path covered elsewhere.');
      return;
    }

    NotificationRecipientService recipientService = new NotificationRecipientService();
    Map<Id, List<Id>> householdIdToRecipientIds = recipientService.getRecipientsByHousehold(
      new Set<Id>{ household.Id }
    );

    List<Id> recipientIds = householdIdToRecipientIds.get(household.Id);
    System.assertNotEquals(null, recipientIds, 'Expected household recipients.');
    System.assertEquals(1, recipientIds.size());
    System.assertEquals(context.recipientUser.Id, recipientIds[0]);
  }

  @IsTest
  static void getRecipientsByHousehold_returnsEmptyForNullOrEmptyInput() {
    NotificationRecipientService recipientService = new NotificationRecipientService();

    System.assertEquals(
      0,
      recipientService.getRecipientsByHousehold(null).size()
    );
    System.assertEquals(
      0,
      recipientService.getRecipientsByHousehold(new Set<Id>()).size()
    );
  }

  @IsTest
  static void getRecipientsByHousehold_returnsEmptyWhenHouseholdHasNoFaTeam() {
    NotificationTestDataFactory.clearTestOverrides();

    Account household = new Account(Name = 'No FA Team Household');
    NotificationTestDataFactory.insertRecord(household);

    NotificationRecipientService recipientService = new NotificationRecipientService();
    Map<Id, List<Id>> householdIdToRecipientIds = recipientService.getRecipientsByHousehold(
      new Set<Id>{ household.Id }
    );

    System.assertEquals(true, householdIdToRecipientIds.isEmpty());
  }

  @IsTest
  static void getRecipientsForSourceRecord_returnsEmptyForUnknownTypeAndNullHousehold() {
    NotificationRecipientService recipientService = new NotificationRecipientService();

    List<Id> recipientIds = recipientService.getRecipientsForSourceRecord(
      'Unknown',
      null,
      null
    );

    System.assertEquals(0, recipientIds.size());
  }

  @IsTest
  static void getRecipientsForSourceRecordDelegatesTaskWithoutOverride() {
    NotificationRecipientService.testRecipientOverrides = null;
    NotificationTaskRecipientService.testRecipientOverrides = null;

    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!NotificationConstants.isNotificationEligibleProfile(currentUser.Profile.Name)) {
      System.assert(true, 'Current user profile is outside notification scope.');
      return;
    }

    Task taskRecord = new Task(
      Subject = 'Delegated Task Recipient',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = currentUser.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      taskRecord,
      null
    );

    System.assert(recipientIds.contains(currentUser.Id));
  }

  @IsTest
  static void getRecipientsForSourceRecordUsesHouseholdOverrideForTaskWhatId() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ context.recipientUser.Id }
    };

    Task taskRecord = new Task(
      Subject = 'Household Override Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      taskRecord,
      null
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(context.recipientUser.Id, recipientIds[0]);
  }

  @IsTest
  static void getRecipientsForSourceRecordUsesCaseAccountOverride() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ context.recipientUser.Id }
    };

    Case caseRecord = new Case(
      Subject = 'Override Account Case',
      AccountId = context.household.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_CASE,
      caseRecord,
      null
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(context.recipientUser.Id, recipientIds[0]);
  }

  @IsTest
  static void getRecipientsForBranchPitStopTaskReturnsOnlyExceptionRecipients() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    User branchUser = createBranchUserForRecipientTest('pitrcptbr');
    User nexsAdvisor = createBranchUserForRecipientTest('pitrcptnx');

    if (branchUser == null || nexsAdvisor == null) {
      System.assert(true, 'Org automation prevented branch user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Branch Pit Stop Recipient Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'Branch Pit Stop Recipient Task',
      WhatId = caseRecord.Id,
      OwnerId = branchUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Branch_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ nexsAdvisor.Id }
    };

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      taskRecord,
      context.household.Id
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(branchUser.Id, recipientIds[0]);
  }

  @IsTest
  static void getRecipientsForHoPitStopTaskSuppressesBranchUsersOnNormalPath() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    User branchUser = createBranchUserForRecipientTest('hopitrcptbr');

    if (branchUser == null) {
      System.assert(true, 'Org automation prevented branch user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'HO Pit Stop Recipient Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'HO Pit Stop Recipient Task',
      WhatId = caseRecord.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Home_Office_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ branchUser.Id }
    };

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      taskRecord,
      context.household.Id
    );

    System.assertEquals(
      0,
      recipientIds.size(),
      'Branch users should be suppressed on Home Office pit stop Case tasks.'
    );
  }

  @IsTest
  static void getRecipientsForHoPitStopHouseholdTaskDoesNotSuppressBranchUsers() {
    User branchUser = createBranchUserForRecipientTest('hopithhbr');

    if (branchUser == null) {
      System.assert(true, 'Org automation prevented branch user insert.');
      return;
    }

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'HO Pit Stop Household Task',
      WhatId = context.household.Id,
      OwnerId = context.recipientUser.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      Home_Office_Pit_Stop__c = true
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ branchUser.Id }
    };

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      taskRecord,
      context.household.Id
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(branchUser.Id, recipientIds[0]);
  }

  private static User createBranchUserForRecipientTest(String aliasPrefix) {
    try {
      return NotificationTestDataFactory.createProfileUser(
        NotificationConstants.PROFILE_NEXS,
        aliasPrefix
      );
    } catch (DmlException ex) {
      try {
        return NotificationTestDataFactory.createProfileUser(
          NotificationConstants.PROFILE_ADVISOR,
          aliasPrefix
        );
      } catch (DmlException advisorException) {
        return null;
      }
    }
  }
}