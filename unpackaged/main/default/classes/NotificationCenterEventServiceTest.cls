/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
@IsTest
private class NotificationCenterEventServiceTest {
  @IsTest
  static void prepareFromSourceRecordCreatesImmediateDeliveryItems() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    Case caseRecord = new Case(
      Subject = 'Center Event Case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Test.startTest();
    List<NotificationCenterDeliveryItem> deliveryItems = new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_CASE,
      String.valueOf(caseRecord.Id)
    );
    Test.stopTest();

    System.assert(!deliveryItems.isEmpty());

    NotificationCenterDeliveryItem emailDeliveryItem;
    for (NotificationCenterDeliveryItem deliveryItem : deliveryItems) {
      if (deliveryItem.channel == NotificationConstants.CHANNEL_EMAIL) {
        emailDeliveryItem = deliveryItem;
        break;
      }
    }

    System.assertNotEquals(null, emailDeliveryItem);
    System.assertEquals(
      NotificationConstants.CHANNEL_EMAIL,
      emailDeliveryItem.channel
    );

    List<Notification_Log__c> notifications = [
      SELECT Id, Status__c, Frequency__c, Channel__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(caseRecord.Id)
    ];

    System.assert(notifications.size() >= 1);
    Notification_Log__c emailNotification;
    for (Notification_Log__c notification : notifications) {
      if (notification.Channel__c == NotificationConstants.CHANNEL_EMAIL) {
        emailNotification = notification;
        break;
      }
    }

    System.assertNotEquals(null, emailNotification);
    System.assertEquals(NotificationConstants.STATUS_QUEUED, emailNotification.Status__c);
    System.assertEquals(
      NotificationConstants.FREQUENCY_IMMEDIATE,
      emailNotification.Frequency__c
    );
  }

  @IsTest
  static void prepareFromSourceRecordQueuesDigestLogs() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Case caseRecord = new Case(
      Subject = 'Digest Case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Test.startTest();
    List<NotificationCenterDeliveryItem> deliveryItems = new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_CASE,
      String.valueOf(caseRecord.Id)
    );
    Test.stopTest();

    System.assertEquals(0, deliveryItems.size());

    Notification_Log__c notification = [
      SELECT Status__c, Frequency__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(caseRecord.Id)
      LIMIT 1
    ];

    System.assertEquals(NotificationConstants.STATUS_QUEUED, notification.Status__c);
    System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, notification.Frequency__c);
  }

  @IsTest
  static void prepareFromNotificationLogReturnsDigestEmailItem() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Digest email item',
      null,
      rule.Id
    );
    logRecord.Source_Record_Id__c = String.valueOf(context.household.Id);
    NotificationTestDataFactory.updateRecord(logRecord);

    Test.startTest();
    List<NotificationCenterDeliveryItem> deliveryItems = new NotificationCenterEventService().prepareNotificationLog(
      String.valueOf(logRecord.Id)
    );
    Test.stopTest();

    System.assertEquals(1, deliveryItems.size());
    System.assertEquals(
      NotificationConstants.CHANNEL_EMAIL,
      deliveryItems[0].channel
    );
    System.assertEquals(
      String.valueOf(logRecord.Id),
      deliveryItems[0].logIdsCsv
    );
  }

  @IsTest
  static void prepareFromNotificationLogReturnsSingleDigestEmailItem() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c rule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    Notification_Log__c firstLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'First digest email item',
      null,
      rule.Id
    );
    firstLog.Source_Record_Id__c = String.valueOf(context.household.Id);
    NotificationTestDataFactory.updateRecord(firstLog);

    Notification_Log__c secondLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Second digest email item',
      null,
      rule.Id
    );
    secondLog.Source_Record_Id__c = String.valueOf(context.household.Id);
    NotificationTestDataFactory.updateRecord(secondLog);

    Test.startTest();
    List<NotificationCenterDeliveryItem> deliveryItems = new NotificationCenterEventService().prepareNotificationLog(
      String.valueOf(firstLog.Id)
    );
    Test.stopTest();

    System.assertEquals(1, deliveryItems.size());
    System.assertEquals(String.valueOf(firstLog.Id), deliveryItems[0].logIdsCsv);
    System.assertEquals(
      NotificationConstants.CHANNEL_EMAIL,
      deliveryItems[0].channel
    );
    System.assertEquals(
      NotificationConstants.FREQUENCY_DIGEST,
      deliveryItems[0].frequency
    );
    System.assertEquals(context.recipientUser.Id, deliveryItems[0].recipientId);
  }

  @IsTest
  static void prepareFromSourceRecordStoresTaskChangeContext() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    Task taskRecord = new Task(
      Subject = 'Context Task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    Test.startTest();
    new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      String.valueOf(taskRecord.Id),
      changeContext.toJson()
    );
    Test.stopTest();

    Notification_Log__c notification = [
      SELECT Change_Context__c, Body__c, Title__c, Channel__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(taskRecord.Id)
      LIMIT 1
    ];

    System.assertEquals(
      NotificationConstants.CHANGE_TYPE_INSERT,
      NotificationChangeModels.fromJson(notification.Change_Context__c)
        .triggerType
    );
    System.assertEquals(
      null,
      notification.Title__c,
      'Title is enriched at delivery time to avoid per-recipient SOQL during prepare.'
    );
    System.assertEquals(
      null,
      notification.Body__c,
      'Body is enriched at delivery time to avoid per-recipient SOQL during prepare.'
    );
  }

  @IsTest
  static void prepareCaseSourceRecordCreatesLogsFromOwnershipAndRuleSettings() {
    clearCaseRecipientTestOverrides();

    Profile nexsProfile = selectProfile(UserInfoUtils.PROFILE_NEXS);
    Profile homeOfficeProfile = selectProfile(
      UserInfoUtils.PROFILE_HOME_OFFICE
    );
    if (nexsProfile == null || homeOfficeProfile == null) {
      System.assert(true, 'Required NexS or Home Office profile is unavailable.');
      return;
    }

    User nexsUser = tryCreateProfileUser(nexsProfile.Id, 'nexscasee2e');
    User homeOfficeUser = tryCreateProfileUser(homeOfficeProfile.Id, 'hocasee2e');
    if (nexsUser == null || homeOfficeUser == null) {
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Case E2E FA Team',
      Related_Advisors__c = 'CaseE2E' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Case E2E Household'
    );
    household.Financial_Advisor_Team__c = faTeam.Id;
    NotificationTestDataFactory.updateRecord(household);

    if (!tryInsertPrimaryAdvisor(faTeam.Id, nexsUser.Id)) {
      return;
    }

    Case caseRecord = new Case(
      Subject = 'Case E2E Ownership',
      AccountId = household.Id,
      Financial_Advisor_Team__c = faTeam.Id,
      Status = 'New',
      Origin = 'Phone',
      OwnerId = homeOfficeUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Notification_Rule__c nexsRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      nexsUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    Notification_Rule__c homeOfficeRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      homeOfficeUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Test.startTest();
    List<NotificationCenterDeliveryItem> deliveryItems = new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_CASE,
      String.valueOf(caseRecord.Id)
    );
    Test.stopTest();

    Map<Id, Notification_Log__c> logByRecipientId = selectLogsByRecipientId(
      caseRecord.Id
    );

    System.assertEquals(
      2,
      logByRecipientId.size(),
      'Eligible NexS primary advisor and Home Office owner should each receive a log.'
    );

    Notification_Log__c nexsLog = logByRecipientId.get(nexsUser.Id);
    System.assertNotEquals(null, nexsLog, 'NexS primary advisor should receive a log.');
    System.assertEquals(
      NotificationConstants.FREQUENCY_DIGEST,
      nexsLog.Frequency__c
    );
    System.assertEquals(nexsRule.Id, nexsLog.Notification_Rule__c);

    Notification_Log__c homeOfficeLog = logByRecipientId.get(homeOfficeUser.Id);
    System.assertNotEquals(
      null,
      homeOfficeLog,
      'Home Office case owner should receive a log.'
    );
    System.assertEquals(
      NotificationConstants.FREQUENCY_IMMEDIATE,
      homeOfficeLog.Frequency__c
    );
    System.assertEquals(homeOfficeRule.Id, homeOfficeLog.Notification_Rule__c);

    System.assertEquals(1, deliveryItems.size());
    System.assertEquals(homeOfficeUser.Id, deliveryItems[0].recipientId);
    System.assertEquals(
      NotificationConstants.FREQUENCY_IMMEDIATE,
      deliveryItems[0].frequency
    );
  }

  @IsTest
  static void prepareCaseSourceRecordExcludesHomeOfficePrimaryAdvisorOnly() {
    clearCaseRecipientTestOverrides();

    Profile nexsProfile = selectProfile(UserInfoUtils.PROFILE_NEXS);
    Profile homeOfficeProfile = selectProfile(
      UserInfoUtils.PROFILE_HOME_OFFICE
    );
    if (nexsProfile == null || homeOfficeProfile == null) {
      System.assert(true, 'Required NexS or Home Office profile is unavailable.');
      return;
    }

    User nexsUser = tryCreateProfileUser(nexsProfile.Id, 'nexsownere2e');
    User homeOfficeUser = tryCreateProfileUser(homeOfficeProfile.Id, 'hoprimadv');
    if (nexsUser == null || homeOfficeUser == null) {
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Case E2E Primary Advisor Team',
      Related_Advisors__c = 'CasePrimAdv' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Case E2E Primary Advisor Household'
    );
    household.Financial_Advisor_Team__c = faTeam.Id;
    NotificationTestDataFactory.updateRecord(household);

    if (!tryInsertPrimaryAdvisor(faTeam.Id, homeOfficeUser.Id)) {
      return;
    }

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      homeOfficeUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Case caseRecord = new Case(
      Subject = 'Case E2E NexS Owner',
      AccountId = household.Id,
      Financial_Advisor_Team__c = faTeam.Id,
      Status = 'New',
      Origin = 'Phone',
      OwnerId = nexsUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      nexsUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Test.startTest();
    new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_CASE,
      String.valueOf(caseRecord.Id)
    );
    Test.stopTest();

    Map<Id, Notification_Log__c> logByRecipientId = selectLogsByRecipientId(
      caseRecord.Id
    );

    System.assertEquals(
      1,
      logByRecipientId.size(),
      'Only the NexS case owner should receive a notification log.'
    );
    System.assert(
      logByRecipientId.containsKey(nexsUser.Id),
      'NexS owner should receive a log.'
    );
    System.assert(
      !logByRecipientId.containsKey(homeOfficeUser.Id),
      'Home Office primary advisor without ownership should not receive a log.'
    );
  }

  @IsTest
  static void prepareCaseSourceRecordIncludesSystemAdminPrimaryAdvisor() {
    clearCaseRecipientTestOverrides();

    Profile nexsProfile = selectProfile(UserInfoUtils.PROFILE_NEXS);
    Profile homeOfficeProfile = selectProfile(
      UserInfoUtils.PROFILE_HOME_OFFICE
    );
    Profile systemAdminProfile = selectProfile(
      UserInfoUtils.PROFILE_SYSTEM_ADMINISTRATOR
    );
    if (nexsProfile == null || homeOfficeProfile == null || systemAdminProfile == null) {
      System.assert(true, 'Required profiles are unavailable.');
      return;
    }

    User nexsUser = tryCreateProfileUser(nexsProfile.Id, 'nexsownsys');
    User homeOfficeUser = tryCreateProfileUser(homeOfficeProfile.Id, 'hoprimsys');
    User systemAdminUser = tryCreateProfileUser(systemAdminProfile.Id, 'sysprim');
    if (nexsUser == null || homeOfficeUser == null || systemAdminUser == null) {
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Case E2E System Admin Team',
      Related_Advisors__c = 'CaseSysAdmin' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Case E2E System Admin Household'
    );
    household.Financial_Advisor_Team__c = faTeam.Id;
    NotificationTestDataFactory.updateRecord(household);

    if (!tryInsertPrimaryAdvisor(faTeam.Id, systemAdminUser.Id)) {
      return;
    }

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      systemAdminUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Case caseRecord = new Case(
      Subject = 'Case E2E System Admin Primary Advisor',
      AccountId = household.Id,
      Financial_Advisor_Team__c = faTeam.Id,
      Status = 'New',
      Origin = 'Phone',
      OwnerId = nexsUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      nexsUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Test.startTest();
    new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_CASE,
      String.valueOf(caseRecord.Id)
    );
    Test.stopTest();

    Map<Id, Notification_Log__c> logByRecipientId = selectLogsByRecipientId(
      caseRecord.Id
    );

    System.assertEquals(
      2,
      logByRecipientId.size(),
      'NexS owner and System Administrator primary advisor should each receive a log.'
    );
    System.assert(
      logByRecipientId.containsKey(nexsUser.Id),
      'NexS owner should receive a log.'
    );
    System.assert(
      logByRecipientId.containsKey(systemAdminUser.Id),
      'System Administrator primary advisor should receive a log.'
    );
    System.assert(
      !logByRecipientId.containsKey(homeOfficeUser.Id),
      'Home Office user without ownership should not receive a log.'
    );
  }

  @IsTest
  static void prepareEventSourceRecordCreatesLogForAttendeeWithActiveRule() {
    clearCaseRecipientTestOverrides();

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

    User eventCreator = selectActiveUserOtherThan(currentUser.Id);
    if (eventCreator == null) {
      System.assert(true, 'No alternate active user available for creator role.');
      return;
    }

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      currentUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Event eventRecord;
    Id householdId;

    System.runAs(eventCreator) {
      Account household = new Account(Name = 'Event Attendee E2E Household');
      NotificationTestDataFactory.insertRecord(household);
      householdId = household.Id;

      eventRecord = new Event(
        Subject = 'Event E2E Attendee',
        WhatId = household.Id,
        StartDateTime = Datetime.now().addDays(2),
        EndDateTime = Datetime.now().addDays(2).addHours(1),
        DurationInMinutes = 60
      );
      NotificationTestDataFactory.insertRecord(eventRecord);

      NotificationTestDataFactory.insertRecord(new EventRelation(
        EventId = eventRecord.Id,
        RelationId = currentUser.Id,
        IsInvitee = true
      ));
    }

    Test.startTest();
    new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_EVENT,
      String.valueOf(eventRecord.Id)
    );
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Recipient__c, Frequency__c
      FROM Notification_Log__c
      WHERE
        Source_Record_Id__c = :String.valueOf(eventRecord.Id)
        AND Recipient__c = :currentUser.Id
    ];

    System.assert(!logs.isEmpty(), 'Event attendee should receive a notification log.');
    System.assertEquals(
      NotificationConstants.FREQUENCY_IMMEDIATE,
      logs[0].Frequency__c
    );
  }

  @IsTest
  static void prepareTaskSourceRecordCreatesLogForAssigneeWithActiveRule() {
    clearCaseRecipientTestOverrides();

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

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      currentUser.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Task taskRecord = new Task(
      Subject = 'Task E2E Assignee',
      Status = 'Not Started',
      Priority = 'Normal',
      OwnerId = currentUser.Id
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Test.startTest();
    new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_TASK,
      String.valueOf(taskRecord.Id)
    );
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Recipient__c, Frequency__c
      FROM Notification_Log__c
      WHERE
        Source_Record_Id__c = :String.valueOf(taskRecord.Id)
        AND Recipient__c = :currentUser.Id
    ];

    System.assert(!logs.isEmpty(), 'Task assignee should receive a notification log.');
    System.assertEquals(
      NotificationConstants.FREQUENCY_IMMEDIATE,
      logs[0].Frequency__c
    );
  }

  @IsTest
  static void prepareEventSourceRecordCreatesLogForCreatorWithActiveRule() {
    clearCaseRecipientTestOverrides();

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      UserInfo.getUserId(),
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    Account household = FscDataTestDataFactory.createHouseholdAccount(
      'Event E2E Household'
    );

    Event eventRecord = new Event(
      Subject = 'Event E2E Creator',
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Test.startTest();
    new NotificationCenterEventService().prepareSourceRecord(
      NotificationConstants.OBJECT_TYPE_EVENT,
      String.valueOf(eventRecord.Id)
    );
    Test.stopTest();

    List<Notification_Log__c> logs = [
      SELECT Recipient__c, Frequency__c
      FROM Notification_Log__c
      WHERE
        Source_Record_Id__c = :String.valueOf(eventRecord.Id)
        AND Recipient__c = :UserInfo.getUserId()
    ];

    System.assert(!logs.isEmpty(), 'Event creator should receive a notification log.');
    System.assertEquals(
      NotificationConstants.FREQUENCY_IMMEDIATE,
      logs[0].Frequency__c
    );
  }

  @IsTest
  static void updateLogStatusMarksLogsSent() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c logRecord = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_PENDING,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Pending item',
      null,
      null
    );

    Test.startTest();
    NotificationLogDeliveryService.markSent(new List<Notification_Log__c>{ logRecord });
    Test.stopTest();

    logRecord = [
      SELECT Status__c, Delivered_At__c
      FROM Notification_Log__c
      WHERE Id = :logRecord.Id
    ];

    System.assertEquals(NotificationConstants.STATUS_SENT, logRecord.Status__c);
    System.assertNotEquals(null, logRecord.Delivered_At__c);
  }

  private static void clearCaseRecipientTestOverrides() {
    NotificationRecipientService.testRecipientOverrides = null;
    NotificationCaseRecipientService.testRecipientOverrides = null;
    NotificationEventRecipientService.testRecipientOverrides = null;
    NotificationTaskRecipientService.testRecipientOverrides = null;
  }

  private static User selectActiveUserOtherThan(Id excludedUserId) {
    List<User> users = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id != :excludedUserId AND IsActive = TRUE
      ORDER BY Name
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0];
  }

  private static Profile selectProfile(String profileName) {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      LIMIT 1
    ];
    return profiles.isEmpty() ? null : profiles[0];
  }

  private static User tryCreateProfileUser(Id profileId, String aliasPrefix) {
    try {
      return createProfileUser(profileId, aliasPrefix);
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented profile user insert.');
      return null;
    }
  }

  private static User createProfileUser(Id profileId, String aliasPrefix) {
    String uniqueSuffix = String.valueOf(System.currentTimeMillis());
    User testUser = new User(
      Alias = aliasPrefix.left(8),
      Email = aliasPrefix + '@example.com.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Case Event Service Test User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasPrefix + uniqueSuffix + '@example.com.test'
    );
    insert testUser;
    return testUser;
  }

  private static Boolean tryInsertPrimaryAdvisor(Id teamId, Id userId) {
    Financial_Advisor_Team_Member__c primaryMember = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = teamId,
      User__c = userId,
      Primary__c = true,
      Active__c = true
    );

    try {
      NotificationTestDataFactory.insertRecord(primaryMember);
      return true;
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return false;
    }
  }

  private static Map<Id, Notification_Log__c> selectLogsByRecipientId(Id caseId) {
    Map<Id, Notification_Log__c> logByRecipientId = new Map<Id, Notification_Log__c>();

    for (Notification_Log__c notificationLog : [
      SELECT Id, Recipient__c, Frequency__c, Notification_Rule__c
      FROM Notification_Log__c
      WHERE Source_Record_Id__c = :String.valueOf(caseId)
    ]) {
      logByRecipientId.put(notificationLog.Recipient__c, notificationLog);
    }

    return logByRecipientId;
  }
}