/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 */
@IsTest
private class NotificationCenterServiceTest {
  @IsTest
  static void getInboxReturnsSentInAppNotificationsForRecipient() {
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

    NotificationCenterService service = new NotificationCenterService();
    NotificationCenterModels.InboxPageResult result = service.getInbox(
      context.recipientUser.Id,
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

    NotificationCenterModels.DashboardResult result = new NotificationCenterService()
      .getDashboard(context.recipientUser.Id);

    System.assertEquals(1, result.stats.deliveredTodayCount);
    System.assertEquals(1, result.stats.queuedCount);
    System.assertEquals(1, result.stats.activeHouseholdCount);
    System.assertEquals(2, result.recentEvents.size());
    System.assertEquals(2, result.channelDelivery.size());
    System.assertEquals(1, result.upcomingDigests.size());
    System.assertEquals(1, result.upcomingDigests[0].queuedCount);
  }

  @IsTest
  static void getInboxRequiresRecipientId() {
    Boolean didThrow = false;

    try {
      new NotificationCenterService().getInbox(null, 'ALL', null, 25, null, 'newest');
    } catch (IllegalArgumentException expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void getNotificationRulesReturnsUserScopedRules() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    List<NotificationCenterModels.RuleItem> rules = new NotificationCenterService()
      .getNotificationRules(context.recipientUser.Id);

    System.assertEquals(1, rules.size());
    System.assertEquals('Case', rules[0].objectType);
    System.assertEquals('Service', rules[0].category);
  }

  @IsTest
  static void getNotificationRulesReturnsOnlyHouseholdScopedRules() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    List<NotificationCenterModels.RuleItem> householdRules = new NotificationCenterService()
      .getNotificationRules(context.recipientUser.Id, context.household.Id);

    System.assertEquals(1, householdRules.size());
    System.assertEquals('Task', householdRules[0].objectType);
    System.assertEquals(context.household.Id, householdRules[0].householdId);
  }

  @IsTest
  static void saveNotificationRuleCreatesUserDefaultRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.category = 'Urgent';
    input.objectType = NotificationConstants.OBJECT_TYPE_TASK;
    input.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    input.channels = new List<String>{ NotificationConstants.CHANNEL_IN_APP, 'Email' };
    input.isActive = true;

    System.runAs(context.recipientUser) {
      NotificationCenterModels.RuleItem savedRule = new NotificationCenterService()
        .saveNotificationRule(context.recipientUser.Id, input);

      System.assertNotEquals(null, savedRule.id);
      System.assertEquals('Urgent', savedRule.category);
      System.assertEquals('Task', savedRule.objectType);
      System.assertEquals(2, savedRule.channels.size());
    }
  }

  @IsTest
  static void saveNotificationRulePersistsDigestFrequency() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.category = 'Info';
    input.objectType = NotificationConstants.OBJECT_TYPE_CASE;
    input.frequency = NotificationConstants.FREQUENCY_DIGEST;
    input.digestFrequency = NotificationConstants.DIGEST_FREQUENCY_WEEKLY;
    input.channels = new List<String>{ NotificationConstants.CHANNEL_IN_APP };
    input.isActive = true;

    System.runAs(context.recipientUser) {
      NotificationCenterModels.RuleItem savedRule = new NotificationCenterService()
        .saveNotificationRule(context.recipientUser.Id, input);

      System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, savedRule.frequency);
      System.assertEquals(
        NotificationConstants.DIGEST_FREQUENCY_WEEKLY,
        savedRule.digestFrequency
      );
    }
  }

  @IsTest
  static void saveNotificationRulePersistsDailyDigestFrequencyHour() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.category = 'Info';
    input.objectType = NotificationConstants.OBJECT_TYPE_CASE;
    input.frequency = NotificationConstants.FREQUENCY_DIGEST;
    input.digestFrequency = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    input.digestFrequencyHour = '9';
    input.channels = new List<String>{ NotificationConstants.CHANNEL_EMAIL };
    input.isActive = true;

    System.runAs(context.recipientUser) {
      NotificationCenterModels.RuleItem savedRule = new NotificationCenterService()
        .saveNotificationRule(context.recipientUser.Id, input);

      System.assertEquals(
        NotificationConstants.DIGEST_FREQUENCY_DAILY,
        savedRule.digestFrequency
      );
      System.assertEquals('9', savedRule.digestFrequencyHour);
      System.assertEquals(
        new List<String>{ NotificationConstants.CHANNEL_EMAIL },
        savedRule.channels
      );
    }
  }

  @IsTest
  static void saveNotificationRulePersistsOptionalRuleName() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.category = 'Service';
    input.objectType = NotificationConstants.OBJECT_TYPE_CASE;
    input.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    input.channels = new List<String>{ NotificationConstants.CHANNEL_IN_APP };
    input.isActive = true;
    input.ruleName = 'Portfolio Review Alerts';

    System.runAs(context.recipientUser) {
      NotificationCenterModels.RuleItem savedRule = new NotificationCenterService()
        .saveNotificationRule(context.recipientUser.Id, input);

      System.assertEquals('Portfolio Review Alerts', savedRule.ruleName);
      System.assertEquals('Portfolio Review Alerts', savedRule.name);
    }
  }

  @IsTest
  static void getNotificationRulesMergesVisibleSystemDefaults() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_CASE);
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_TASK);
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    List<NotificationCenterModels.RuleItem> rules = new NotificationCenterService()
      .getNotificationRules(context.recipientUser.Id);

    System.assertEquals(3, rules.size());

    Map<String, NotificationCenterModels.RuleItem> rulesByObjectType = new Map<String, NotificationCenterModels.RuleItem>();
    for (NotificationCenterModels.RuleItem rule : rules) {
      rulesByObjectType.put(rule.objectType, rule);
    }

    System.assertEquals(true, rulesByObjectType.get('Case').isSystemDefault);
    System.assertEquals(true, rulesByObjectType.get('Case').isReadOnly);
    System.assertEquals(true, rulesByObjectType.get('Task').isSystemDefault);
    System.assertEquals(false, rulesByObjectType.get('Event').isSystemDefault);
  }

  @IsTest
  static void toggleSystemDefaultOffAllowedForAdmin() {
    Notification_Rule__c systemRule = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );
    NotificationCenterModels.RuleItem updatedRule = new NotificationCenterService()
      .toggleNotificationRule(UserInfo.getUserId(), systemRule.Id, false);

    System.assertEquals(false, updatedRule.isActive);
    System.assertEquals(false, [
      SELECT Is_Active__c
      FROM Notification_Rule__c
      WHERE Id = :systemRule.Id
    ].Is_Active__c);
  }

  @IsTest
  static void toggleSystemDefaultOffBlockedForNonAdmin() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithStandardUserRecipient();
    Notification_Rule__c systemRule = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );
    Boolean didThrow = false;

    Integer userRuleCountBefore = [
      SELECT COUNT()
      FROM Notification_Rule__c
      WHERE User__c = :context.recipientUser.Id
    ];

    System.runAs(context.recipientUser) {
      try {
        new NotificationCenterService()
          .toggleNotificationRule(context.recipientUser.Id, systemRule.Id, false);
      } catch (IllegalArgumentException expected) {
        didThrow = true;
      }
    }

    Integer userRuleCountAfter = [
      SELECT COUNT()
      FROM Notification_Rule__c
      WHERE User__c = :context.recipientUser.Id
    ];

    System.assertEquals(true, didThrow);
    System.assertEquals(userRuleCountBefore, userRuleCountAfter);
    System.assertEquals(true, [
      SELECT Is_Active__c
      FROM Notification_Rule__c
      WHERE Id = :systemRule.Id
    ].Is_Active__c);
  }

  @IsTest
  static void deleteNotificationRuleBlocksSystemDefaultRows() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c systemRule = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );
    Boolean didThrow = false;

    try {
      new NotificationCenterService()
        .deleteNotificationRule(context.recipientUser.Id, systemRule.Id);
    } catch (IllegalArgumentException expected) {
      didThrow = true;
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void getSystemDefaultRulesRequiresAdminPermission() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithStandardUserRecipient();
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_CASE);
    Boolean didThrow = false;

    System.runAs(context.recipientUser) {
      try {
        new NotificationCenterService().getSystemDefaultRules();
      } catch (AuraHandledException expected) {
        didThrow = true;
      }
    }

    System.assertEquals(true, didThrow);
  }

  @IsTest
  static void saveSystemDefaultRuleCreatesOrgDefaultForAdmin() {
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.category = 'Service';
    input.objectType = NotificationConstants.OBJECT_TYPE_CASE;
    input.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    input.channels = new List<String>{ NotificationConstants.CHANNEL_IN_APP };
    input.isActive = true;

    NotificationCenterModels.RuleItem savedRule = new NotificationCenterService()
      .saveSystemDefaultRule(input);

    System.assertNotEquals(null, savedRule.id);
    System.assertEquals(true, savedRule.isSystemDefault);
    System.assertEquals('Case', savedRule.objectType);
  }

  @IsTest
  static void saveNotificationRuleCreatesCopyWithoutOverridingExistingRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c existingRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    existingRule.Rule_Name__c = 'Original Case Alert';
    NotificationTestDataFactory.updateRecord(existingRule);

    NotificationCenterModels.RuleInput copyInput = new NotificationCenterModels.RuleInput();
    copyInput.category = 'Service';
    copyInput.objectType = NotificationConstants.OBJECT_TYPE_CASE;
    copyInput.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    copyInput.channels = new List<String>{ NotificationConstants.CHANNEL_IN_APP };
    copyInput.isActive = true;
    copyInput.ruleName = 'Copy of Original Case Alert';

    System.runAs(context.recipientUser) {
      NotificationCenterModels.RuleItem savedCopy = new NotificationCenterService()
        .saveNotificationRule(context.recipientUser.Id, copyInput);

      System.assertNotEquals(existingRule.Id, savedCopy.id);
      System.assertEquals('Copy of Original Case Alert', savedCopy.ruleName);

      List<Notification_Rule__c> userRules = [
        SELECT Id, Rule_Name__c
        FROM Notification_Rule__c
        WHERE
          User__c = :context.recipientUser.Id
          AND Object_Type__c = :NotificationConstants.OBJECT_TYPE_CASE
      ];

      System.assertEquals(2, userRules.size());

      Notification_Rule__c persistedOriginal = [
        SELECT Rule_Name__c
        FROM Notification_Rule__c
        WHERE Id = :existingRule.Id
      ];

      System.assertEquals('Original Case Alert', persistedOriginal.Rule_Name__c);
    }
  }

  @IsTest
  static void getNotificationLog_filtersByPendingStatus() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_PENDING,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Pending notification',
      null,
      null
    );
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Delivered notification',
      null,
      null
    );

    NotificationCenterModels.LogPageResult result = new NotificationCenterService()
      .getNotificationLog(
        context.recipientUser.Id,
        NotificationConstants.LOG_STATUS_PENDING,
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
    System.assertEquals(NotificationConstants.STATUS_PENDING, result.items[0].status);
  }

  @IsTest
  static void getNotificationLog_filtersByFailedStatus() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_FAILED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Failed notification',
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
      'Queued notification',
      null,
      null
    );

    NotificationCenterModels.LogPageResult result = new NotificationCenterService()
      .getNotificationLog(
        context.recipientUser.Id,
        NotificationConstants.LOG_STATUS_FAILED,
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
    System.assertEquals(NotificationConstants.STATUS_FAILED, result.items[0].status);
  }

  @IsTest
  static void markAsReadAndMarkAllAsRead_updateUnreadCounts() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c firstUnread = NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'First unread',
      'Body',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      'Second unread',
      'Body',
      false
    );

    NotificationCenterService service = new NotificationCenterService();
    System.assertEquals(2, service.getUnreadCount(context.recipientUser.Id));

    System.assertEquals(
      1,
      service.markAsRead(
        context.recipientUser.Id,
        new List<Id>{ firstUnread.Id }
      )
    );
    System.assertEquals(1, service.getUnreadCount(context.recipientUser.Id));

    System.assertEquals(1, service.markAllAsRead(context.recipientUser.Id));
    System.assertEquals(0, service.getUnreadCount(context.recipientUser.Id));
  }

  @IsTest
  static void deleteSystemDefaultRule_removesOrgDefault() {
    Notification_Rule__c systemRule = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    new NotificationCenterService().deleteSystemDefaultRule(systemRule.Id);

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Notification_Rule__c
        WHERE Id = :systemRule.Id
      ]
    );
  }

  @IsTest
  static void toggleNotificationRule_updatesUserOwnedRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationCenterModels.RuleItem updatedRule = new NotificationCenterService()
      .toggleNotificationRule(context.recipientUser.Id, userRule.Id, false);

    System.assertEquals(false, updatedRule.isActive);
    System.assertEquals(false, [
      SELECT Is_Active__c
      FROM Notification_Rule__c
      WHERE Id = :userRule.Id
    ].Is_Active__c);
  }

  @IsTest
  static void deleteNotificationRule_deletesUserOwnedRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    new NotificationCenterService().deleteNotificationRule(
      context.recipientUser.Id,
      userRule.Id
    );

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
  static void getUnreadCount_returnsUnreadTotal() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      'Unread one',
      'Body',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      'Unread two',
      'Body',
      false
    );
    NotificationTestDataFactory.createSentInAppNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_EVENT,
      'Read item',
      'Body',
      true
    );

    System.assertEquals(
      2,
      new NotificationCenterService().getUnreadCount(context.recipientUser.Id)
    );
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