/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
@IsTest
private class NotificationCenterControllerTest {
  @IsTest
  static void getInboxReturnsSentInAppNotificationsForCurrentUser() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c unreadNotification = NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'Unread Case Alert',
      'Case 00001001 - Portfolio Review',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      'Read Task Alert',
      'Follow up call',
      true
    );

    System.runAs(context.recipientUser) {
      NotificationCenterModels.InboxPageResult result = NotificationCenterController.getInbox(
        'ALL',
        null,
        25,
        null,
        'newest'
      );

      System.assertEquals(2, result.items.size());
      System.assertEquals(1, result.stats.unreadCount);
      System.assertEquals(2, result.stats.totalCount);

      Set<Id> returnedIds = new Set<Id>();
      for (NotificationCenterModels.InboxItem item : result.items) {
        returnedIds.add(item.id);
      }
      System.assert(returnedIds.contains(unreadNotification.Id));
    }
  }

  @IsTest
  static void getInboxFiltersUnreadOnly() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'Unread only',
      'Body',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_EVENT,
      'Already read',
      'Body',
      true
    );

    System.runAs(context.recipientUser) {
      NotificationCenterModels.InboxPageResult result = NotificationCenterController.getInbox(
        'UNREAD',
        null,
        25,
        null,
        'newest'
      );

      System.assertEquals(1, result.items.size());
      System.assertEquals(false, result.items[0].isRead);
    }
  }

  @IsTest
  static void markAsReadUpdatesOnlyCurrentUserNotifications() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.NotificationTestContext otherContext = NotificationTestDataFactory.createHouseholdWithStandardUserRecipient();

    Notification_Log__c ownedNotification = NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'Owned notification',
      'Body',
      false
    );
    Notification_Log__c otherNotification = NotificationTestDataFactory.createSentInAppNotification(
      otherContext.recipientUser.Id,
      otherContext.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'Other user notification',
      'Body',
      false
    );

    System.runAs(context.recipientUser) {
      Integer updatedCount = NotificationCenterController.markAsRead(
        new List<Id>{ ownedNotification.Id, otherNotification.Id }
      );
      System.assertEquals(1, updatedCount);
    }

    ownedNotification = [
      SELECT Is_Read__c, Read_At__c
      FROM Notification_Log__c
      WHERE Id = :ownedNotification.Id
    ];
    otherNotification = [
      SELECT Is_Read__c
      FROM Notification_Log__c
      WHERE Id = :otherNotification.Id
    ];

    System.assertEquals(true, ownedNotification.Is_Read__c);
    System.assertNotEquals(null, ownedNotification.Read_At__c);
    System.assertEquals(false, otherNotification.Is_Read__c);
  }

  @IsTest
  static void markAllAsReadClearsUnreadCount() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'One',
      'Body',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      'Two',
      'Body',
      false
    );

    System.runAs(context.recipientUser) {
      System.assertEquals(2, NotificationCenterController.getUnreadCount());
      System.assertEquals(2, NotificationCenterController.markAllAsRead());
      System.assertEquals(0, NotificationCenterController.getUnreadCount());
    }
  }

  @IsTest
  static void getNotificationLogReturnsDeliveredSuppressedAndQueuedEntries() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c urgentPreference = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationTestDataFactory.channel('In_App'),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    urgentPreference.Priority__c = 50;
    NotificationTestDataFactory.updateRecord(urgentPreference);

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'New case was created for Thornton Estate',
      null,
      urgentPreference.Id
    );
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_SUPPRESSED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'New task was updated for Chen Family',
      'Quiet hours active — converted to Digest queue',
      null
    );
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'New event was created for Park & Associates',
      null,
      urgentPreference.Id
    );

    System.runAs(context.recipientUser) {
      NotificationCenterModels.LogPageResult result = NotificationCenterController.getNotificationLog(
        NotificationConstants.LOG_STATUS_ALL,
        NotificationConstants.LOG_CATEGORY_ALL,
        50,
        null,
        Date.today(),
        Date.today(),
        null,
        'ALL',
        null,
        null,
        false
      );

      System.assertEquals(3, result.items.size());
      System.assertEquals('Urgent', result.items[0].category);
    }
  }

  @IsTest
  static void getNotificationLogFiltersByStatus() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Delivered notification',
      null,
      null
    );
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_SUPPRESSED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Suppressed notification',
      'Info category disabled for this recipient',
      null
    );

    System.runAs(context.recipientUser) {
      NotificationCenterModels.LogPageResult result = NotificationCenterController.getNotificationLog(
        NotificationConstants.LOG_STATUS_SUPPRESSED,
        NotificationConstants.LOG_CATEGORY_ALL,
        50,
        null,
        null,
        null,
        null,
        'ALL',
        null,
        null,
        false
      );

      System.assertEquals(1, result.items.size());
      System.assertEquals(NotificationConstants.STATUS_SUPPRESSED, result.items[0].status);
    }
  }

  @IsTest
  static void getPresentationLogReturnsRowsMatchingChangeDateNotLogCreatedDate() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'Presentation log task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    Datetime todayChangedAt = System.now();
    Datetime oldChangedAt = todayChangedAt.addDays(-30);

    NotificationChangeModels.ChangeContext oldChangeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    oldChangeContext.changedAt = oldChangedAt.formatGmt(
      'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
    );

    Notification_Log__c oldLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Old change date task update',
      null,
      null
    );
    oldLog.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    oldLog.Change_Context__c = oldChangeContext.toJson();
    NotificationTestDataFactory.updateRecord(oldLog);

    NotificationChangeModels.ChangeContext todayChangeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    todayChangeContext.changedAt = todayChangedAt.formatGmt(
      'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
    );
    todayChangeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'OwnerId',
        'Assigned To',
        'Old Owner',
        'New Owner',
        'Old Owner',
        'New Owner'
      )
    );

    Notification_Log__c todayLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Today task owner update',
      null,
      null
    );
    todayLog.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    todayLog.Change_Context__c = todayChangeContext.toJson();
    NotificationTestDataFactory.updateRecord(todayLog);

    System.runAs(context.recipientUser) {
      NotificationCenterModels.LogPageResult result = NotificationCenterController.getNotificationLog(
        NotificationConstants.LOG_STATUS_ALL,
        NotificationConstants.LOG_CATEGORY_ALL,
        50,
        null,
        Date.today(),
        Date.today(),
        null,
        'ALL',
        null,
        null,
        true
      );

      System.assertEquals(
        1,
        result.items.size(),
        'Presentation log should filter by change date, not log created date'
      );
      System.assertEquals(
        1,
        result.filteredTotalCount,
        'Presentation log total should reflect deduplicated filtered rows'
      );
      System.assertEquals(todayLog.Id, result.items[0].id);
      System.assertNotEquals(
        null,
        result.householdOptions,
        'Presentation log should return household filter options'
      );
      System.assert(
        !result.householdOptions.isEmpty(),
        'Presentation log should include household options from matching records'
      );
    }
  }

  @IsTest
  static void getPresentationLogDeduplicatesMultiChannelLogsForSameChange() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Task taskRecord = new Task(
      Subject = 'test 2',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedAt = System.now().formatGmt(
      'yyyy-MM-dd\'T\'HH:mm:ss\'Z\''
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'OwnerId',
        'Assigned To',
        'Old Owner',
        'New Owner',
        'Old Owner',
        'New Owner'
      )
    );

    String baseCorrelationKey =
      String.valueOf(taskRecord.Id) +
      '-presentation-dedup';

    Notification_Log__c emailLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Task update email channel',
      null,
      null
    );
    emailLog.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    emailLog.Change_Context__c = changeContext.toJson();
    emailLog.Correlation_Key__c = baseCorrelationKey + '-Email';
    NotificationTestDataFactory.updateRecord(emailLog);

    Notification_Log__c inAppLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'Task update in-app channel',
      null,
      null
    );
    inAppLog.Source_Record_Id__c = String.valueOf(taskRecord.Id);
    inAppLog.Change_Context__c = changeContext.toJson();
    inAppLog.Correlation_Key__c = baseCorrelationKey + '-In_App';
    NotificationTestDataFactory.updateRecord(inAppLog);

    System.runAs(context.recipientUser) {
      NotificationCenterModels.LogPageResult result = NotificationCenterController.getNotificationLog(
        NotificationConstants.LOG_STATUS_ALL,
        NotificationConstants.LOG_CATEGORY_ALL,
        50,
        null,
        Date.today(),
        Date.today(),
        null,
        'ALL',
        null,
        null,
        true
      );

      System.assertEquals(
        1,
        result.items.size(),
        'Presentation log should show one row per change across delivery channels'
      );
      System.assertEquals(
        1,
        result.filteredTotalCount,
        'Presentation log total should deduplicate multi-channel rows'
      );
    }
  }

  @IsTest
  static void getUserDefaultPreferencesReturnsCurrentUserRecords() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationTestDataFactory.channel('In_App'),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    System.runAs(context.recipientUser) {
      List<Notification_Rule__c> preferences = NotificationCenterController.getUserDefaultPreferences();
      System.assertEquals(1, preferences.size());
      System.assertEquals(NotificationConstants.OBJECT_TYPE_CASE, preferences[0].Object_Type__c);
    }
  }

  @IsTest
  static void getDashboardReturnsStatsRecentEventsAndDigests() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'New case was created for Thornton Estate',
      null,
      null
    );
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_DIGEST,
      'Task updated for Chen Family',
      null,
      null
    );

    System.runAs(context.recipientUser) {
      NotificationCenterModels.DashboardResult result = NotificationCenterController.getDashboard();

      System.assertEquals(1, result.stats.deliveredTodayCount);
      System.assertEquals(1, result.stats.queuedCount);
      System.assertEquals(1, result.stats.activeHouseholdCount);
      System.assertEquals(2, result.recentEvents.size());
      System.assertEquals(2, result.channelDelivery.size());
      System.assertEquals(1, result.upcomingDigests.size());
      System.assertEquals(1, result.upcomingDigests[0].queuedCount);
    }
  }

  @IsTest
  static void getSystemDefaultRulesReturnsOrgDefaultsForAdmin() {
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.category = 'Service';
    input.objectType = NotificationConstants.OBJECT_TYPE_CASE;
    input.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    input.channels = new List<String>{ NotificationConstants.CHANNEL_IN_APP };
    input.isActive = true;

    NotificationCenterController.saveSystemDefaultRule(input);
    List<NotificationCenterModels.RuleItem> rules = NotificationCenterController.getSystemDefaultRules();

    System.assertEquals(1, rules.size());
    System.assertEquals(true, rules[0].isSystemDefault);
    System.assertEquals('Case', rules[0].objectType);
  }

  @IsTest
  static void deleteSystemDefaultRule_removesOrgDefaultForAdmin() {
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.category = 'Service';
    input.objectType = NotificationConstants.OBJECT_TYPE_TASK;
    input.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    input.channels = new List<String>{ NotificationConstants.CHANNEL_IN_APP };
    input.isActive = true;

    NotificationCenterModels.RuleItem savedRule = NotificationCenterController.saveSystemDefaultRule(
      input
    );

    NotificationCenterController.deleteSystemDefaultRule(savedRule.id);

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Notification_Rule__c
        WHERE Id = :savedRule.id
      ]
    );
  }

  @IsTest
  static void deleteNotificationRule_deletesUserOwnedRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    System.runAs(context.recipientUser) {
      NotificationCenterController.deleteNotificationRule(userRule.Id);
    }

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Notification_Rule__c
        WHERE Id = :userRule.Id
      ]
    );
  }

  @IsTest
  static void toggleNotificationRule_updatesUserOwnedRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    System.runAs(context.recipientUser) {
      NotificationCenterModels.RuleItem updatedRule = NotificationCenterController.toggleNotificationRule(
        userRule.Id,
        false
      );

      System.assertEquals(false, updatedRule.isActive);
    }

    System.assertEquals(false, [
      SELECT Is_Active__c
      FROM Notification_Rule__c
      WHERE Id = :userRule.Id
    ].Is_Active__c);
  }

  @IsTest
  static void getUnreadCount_returnsCountForCurrentUser() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'Controller unread',
      'Body',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      'Controller read',
      'Body',
      true
    );

    System.runAs(context.recipientUser) {
      System.assertEquals(1, NotificationCenterController.getUnreadCount());
    }
  }

  private static void assignAdminPermission(User user) {
    PermissionSet permissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Notification_Center_Admin'
      LIMIT 1
    ];

    insert new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = permissionSet.Id
    );
  }
}