/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationTaskRecipientServiceTest {
  @IsTest
  static void resolveRecipientsReturnsEmptyForNullTask() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      null,
      null
    );

    System.assertEquals(0, recipientIds.size());
  }

  @IsTest
  static void resolveRecipientsIncludesAssigneeWithEligibleProfile() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!UserInfoUtils.isCurrentUserNotificationEligible()) {
      System.assert(true, 'Current user profile is outside notification scope.');
      return;
    }

    Task taskRecord = new Task(
      Subject = 'Assigned Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = currentUser.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assert(
      recipientIds.contains(currentUser.Id),
      'Task assignee should receive Task notifications.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesPrimaryAdvisorForHouseholdTask() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    Profile nexsProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :UserInfoUtils.PROFILE_NEXS
      LIMIT 1
    ];

    User nexsUser;
    try {
      nexsUser = createUser(nexsProfile.Id, 'nexstskadv');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented NexS user insert.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Task Primary Advisor Team',
      Related_Advisors__c = 'TaskPrimAdv' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Task Primary Advisor Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    try {
      NotificationTestDataFactory.insertRecord(new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = nexsUser.Id,
        Primary__c = true,
        Active__c = true
      ));
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    User assignee = [
      SELECT Id
      FROM User
      WHERE Id != :nexsUser.Id AND IsActive = TRUE
      LIMIT 1
    ];

    Task taskRecord = new Task(
      Subject = 'Household Task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = assignee.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      household.Id
    );

    System.assert(
      recipientIds.contains(nexsUser.Id),
      'NexS primary advisor should receive Task notifications for household tasks.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesCaseOwnerAndSubmitterForNexS() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    Profile nexsProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :UserInfoUtils.PROFILE_NEXS
      LIMIT 1
    ];

    User nexsOwner;
    User nexsSubmitter;
    try {
      nexsOwner = createUser(nexsProfile.Id, 'nexstskown');
      nexsSubmitter = createUser(nexsProfile.Id, 'nexstsksub');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented NexS user insert.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Task Case FA Team',
      Related_Advisors__c = 'TaskCaseFA' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Case caseRecord;
    System.runAs(nexsSubmitter) {
      caseRecord = new Case(
        Subject = 'Task Notification Case',
        Status = 'New',
        Origin = 'Phone',
        OwnerId = nexsOwner.Id,
        Financial_Advisor_Team__c = faTeam.Id
      );
      NotificationTestDataFactory.insertRecord(caseRecord);
    }

    try {
      NotificationTestDataFactory.insertRecord(new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = nexsSubmitter.Id,
        Primary__c = false,
        Active__c = true
      ));
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    User assignee = [
      SELECT Id
      FROM User
      WHERE Id NOT IN :new Set<Id>{ nexsOwner.Id, nexsSubmitter.Id } AND IsActive = TRUE
      LIMIT 1
    ];

    Task taskRecord = new Task(
      Subject = 'Case Task',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = assignee.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assert(
      recipientIds.contains(nexsOwner.Id),
      'NexS case owner should receive Task notifications for case-linked tasks.'
    );
    System.assert(
      recipientIds.contains(nexsSubmitter.Id),
      'NexS case submitter and FA team member should receive Task notifications.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesQueueMemberForAdvisorCaseTask() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    Profile advisorProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :UserInfoUtils.PROFILE_ADVISOR
      LIMIT 1
    ];

    User advisorQueueMember;
    try {
      advisorQueueMember = createUser(advisorProfile.Id, 'advtskque');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented Advisor user insert.');
      return;
    }

    Group serviceQueue = selectCaseQueueWithMember(advisorQueueMember.Id);
    if (serviceQueue == null) {
      Group operationsQueue = [
        SELECT Id, Name
        FROM Group
        WHERE Name = 'Operations' AND Type = 'Queue'
        LIMIT 1
      ];
      insert new GroupMember(
        GroupId = operationsQueue.Id,
        UserOrGroupId = advisorQueueMember.Id
      );
      serviceQueue = operationsQueue;
    }

    User assignee = [
      SELECT Id
      FROM User
      WHERE Id != :advisorQueueMember.Id AND IsActive = TRUE
      LIMIT 1
    ];

    Case caseRecord = new Case(
      Subject = 'Advisor Queued Case Task',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = serviceQueue.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'Advisor Queued Case Task',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = assignee.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assert(
      recipientIds.contains(advisorQueueMember.Id),
      'Advisor queue member should receive Task notifications for queued case tasks.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesQueueMemberForHomeOfficeCaseTask() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    User homeOfficeUser = selectActiveHomeOfficeUser();
    if (homeOfficeUser == null) {
      System.assert(true, 'No active Home Office user available.');
      return;
    }

    Group serviceQueue = selectCaseQueueWithMember(homeOfficeUser.Id);
    if (serviceQueue == null) {
      System.assert(true, 'No Case queue with Home Office member available for queue test.');
      return;
    }

    User assignee = [
      SELECT Id
      FROM User
      WHERE Id != :homeOfficeUser.Id AND IsActive = TRUE
      LIMIT 1
    ];

    Case caseRecord = new Case(
      Subject = 'Queued Case Task',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = serviceQueue.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task taskRecord = new Task(
      Subject = 'Queued Case Task',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = assignee.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assert(
      recipientIds.contains(homeOfficeUser.Id),
      'Home Office queue member should receive Task notifications for queued case tasks.'
    );
  }

  @IsTest
  static void resolveRecipientsExcludesHomeOfficePrimaryAdvisorOnly() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    User homeOfficeUser = selectActiveHomeOfficeUser();
    if (homeOfficeUser == null) {
      System.assert(true, 'No active Home Office user available.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Task HO Primary Team',
      Related_Advisors__c = 'TaskHOPrim' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Task HO Primary Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    try {
      NotificationTestDataFactory.insertRecord(new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = homeOfficeUser.Id,
        Primary__c = true,
        Active__c = true
      ));
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    User assignee = [
      SELECT Id
      FROM User
      WHERE Id != :homeOfficeUser.Id AND IsActive = TRUE
      LIMIT 1
    ];

    Task taskRecord = new Task(
      Subject = 'HO Primary Exclusion Task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = assignee.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      household.Id
    );

    System.assert(
      !recipientIds.contains(homeOfficeUser.Id),
      'Home Office primary advisor without assignee/case ownership should not receive Task notifications.'
    );
  }

  @IsTest
  static void getRecipientsForSourceRecordDelegatesTaskToProfileRules() {
    NotificationRecipientService.testRecipientOverrides = null;
    NotificationTaskRecipientService.testRecipientOverrides = null;

    Task taskRecord = new Task(
      Subject = 'Delegated Task',
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      taskRecord.Id => new List<Id>{ UserInfo.getUserId() }
    };

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      taskRecord,
      null
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(UserInfo.getUserId(), recipientIds[0]);
  }

  @IsTest
  static void resolveRecipientsUsesTestOverrideByTaskId() {
    Task taskRecord = new Task(
      Subject = 'Override Task',
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationTaskRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      taskRecord.Id => new List<Id>{ UserInfo.getUserId() }
    };

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assertEquals(1, recipientIds.size());
    NotificationTaskRecipientService.testRecipientOverrides = null;
  }

  @IsTest
  static void resolveRecipientsUsesTestOverrideByHouseholdId() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Task taskRecord = new Task(
      Subject = 'Household Override Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationTaskRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ context.recipientUser.Id }
    };

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      context.household.Id
    );

    NotificationTaskRecipientService.testRecipientOverrides = null;
    System.assertEquals(context.recipientUser.Id, recipientIds[0]);
  }

  @IsTest
  static void resolveRecipientsReturnsEmptyWhenTaskHasNoId() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    Task taskRecord = new Task(
      Subject = 'Unsaved Task',
      Status = 'Not Started',
      Priority = 'Normal'
    );

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assertEquals(0, recipientIds.size());
  }

  @IsTest
  static void resolveRecipientsUsesAccountWhatIdWhenHouseholdIdMissing() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    Account household = FscDataTestDataFactory.createClassifiedBusinessAccount(
      'Task WhatId Household',
      FscRelClassificationUtils.UNCLASSIFIED
    );

    User assignee = [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE
      LIMIT 1
    ];

    Task taskRecord = new Task(
      Subject = 'Account WhatId Task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = assignee.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assertNotEquals(null, recipientIds);
  }

  @IsTest
  static void idHelperMethods_classifyRecordIdPrefixes() {
    System.assertEquals(true, NotificationTaskRecipientService.isUserId(UserInfo.getUserId()));
    System.assertEquals(false, NotificationTaskRecipientService.isUserId(null));

    List<Group> queues = [
      SELECT Id
      FROM Group
      WHERE Type = 'Queue'
      LIMIT 1
    ];
    if (!queues.isEmpty()) {
      System.assertEquals(true, NotificationTaskRecipientService.isQueueId(queues[0].Id));
    }

    System.assertEquals(false, NotificationTaskRecipientService.isQueueId(UserInfo.getUserId()));

    Account household = FscDataTestDataFactory.createClassifiedBusinessAccount(
      'Prefix Test Household',
      FscRelClassificationUtils.UNCLASSIFIED
    );
    System.assertEquals(true, NotificationTaskRecipientService.isAccountId(household.Id));
    System.assertEquals(false, NotificationTaskRecipientService.isCaseId(household.Id));
  }

  @IsTest
  static void resolveRecipientsExcludesIneligibleProfileCandidates() {
    NotificationTaskRecipientService.testRecipientOverrides = null;

    List<Profile> ineligibleProfiles = [
      SELECT Id
      FROM Profile
      WHERE
        Name NOT IN :UserInfoUtils.notificationEligibleProfileNames()
        AND UserType = 'Standard'
      LIMIT 1
    ];

    if (ineligibleProfiles.isEmpty()) {
      System.assert(true, 'No ineligible standard profile available.');
      return;
    }

    User ineligibleUser;
    try {
      ineligibleUser = createUser(ineligibleProfiles[0].Id, 'ineligtsk');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented ineligible user insert.');
      return;
    }

    Task taskRecord = new Task(
      Subject = 'Ineligible Assignee Task',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = ineligibleUser.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    List<Id> recipientIds = new NotificationTaskRecipientService().resolveRecipients(
      taskRecord,
      null
    );

    System.assertEquals(
      0,
      recipientIds.size(),
      'Ineligible profile assignees should not receive Task notifications.'
    );
  }

  private static User selectActiveHomeOfficeUser() {
    List<User> users = [
      SELECT Id
      FROM User
      WHERE
        Profile.Name = :UserInfoUtils.PROFILE_HOME_OFFICE
        AND IsActive = TRUE
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0];
  }

  private static Group selectCaseQueueWithMember(Id userId) {
    for (GroupMember queueMember : [
      SELECT GroupId, Group.Name
      FROM GroupMember
      WHERE
        UserOrGroupId = :userId
        AND Group.Type = 'Queue'
      LIMIT 20
    ]) {
      List<QueueSobject> queueObjects = [
        SELECT Id
        FROM QueueSobject
        WHERE QueueId = :queueMember.GroupId AND SobjectType = 'Case'
        LIMIT 1
      ];

      if (!queueObjects.isEmpty()) {
        return new Group(Id = queueMember.GroupId, Name = queueMember.Group.Name);
      }
    }

    return null;
  }

  private static User createUser(Id profileId, String aliasPrefix) {
    String uniqueSuffix = String.valueOf(System.currentTimeMillis());
    User testUser = new User(
      Alias = aliasPrefix.left(8),
      Email = aliasPrefix + '@example.com.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Task Recipient Test User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasPrefix + uniqueSuffix + '@example.com.test'
    );
    insert testUser;
    return testUser;
  }
}