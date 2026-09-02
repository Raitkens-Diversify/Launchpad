/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 *
 * Intensive household vs global preference isolation scenarios.
 */
@IsTest
private class NotificationPrefHouseholdScenarioTest {
  @IsTest
  static void householdOverrideDoesNotAffectGlobalRuleOnOtherHouseholds() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account otherHousehold = FscDataTestDataFactory.createHouseholdAccount(
      'Scenario Other Household'
    );

    Notification_Rule__c globalRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      },
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    Notification_Rule__c householdRule = NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Map<String, NotificationPreferenceService.ResolveResult> scopedResults = preferenceService.resolveForRecipientsByChannel(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ context.recipientUser.Id },
      context.household.Id
    ).get(context.recipientUser.Id);
    Map<String, NotificationPreferenceService.ResolveResult> otherResults = preferenceService.resolveForRecipientsByChannel(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ context.recipientUser.Id },
      otherHousehold.Id
    ).get(context.recipientUser.Id);

    System.assertEquals(1, scopedResults.size());
    System.assertEquals(
      householdRule.Id,
      scopedResults.get(NotificationConstants.CHANNEL_IN_APP).preference.Id
    );
    System.assertEquals(
      'USER_HOUSEHOLD_OVERRIDE',
      scopedResults.get(NotificationConstants.CHANNEL_IN_APP).resolvedScope
    );
    System.assertEquals(false, scopedResults.containsKey(NotificationConstants.CHANNEL_EMAIL));

    System.assertEquals(2, otherResults.size());
    System.assertEquals(
      globalRule.Id,
      otherResults.get(NotificationConstants.CHANNEL_EMAIL).preference.Id
    );
    System.assertEquals(
      globalRule.Id,
      otherResults.get(NotificationConstants.CHANNEL_IN_APP).preference.Id
    );
    System.assertEquals(
      'USER_DEFAULT',
      otherResults.get(NotificationConstants.CHANNEL_EMAIL).resolvedScope
    );
  }

  @IsTest
  static void householdDigestLogsDoNotCrossHouseholdBoundaries() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account otherHousehold = FscDataTestDataFactory.createHouseholdAccount(
      'Scenario Digest Household'
    );
    Notification_Rule__c digestRule = NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    digestRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_HOURLY;
    NotificationTestDataFactory.updateRecord(digestRule);

    Notification_Log__c matchingLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Matching digest',
      null,
      digestRule.Id
    );
    NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      otherHousehold.Id,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Other digest',
      null,
      digestRule.Id
    );

    List<Notification_Log__c> scopedLogs = new NotificationLogRepository()
      .selectQueuedLogsForRules(new Set<Id>{ digestRule.Id });

    System.assertEquals(1, scopedLogs.size());
    System.assertEquals(matchingLog.Id, scopedLogs[0].Id);
  }

  @IsTest
  static void appOnlyGlobalRuleDoesNotBackfillEmailFromSystemDefault() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_EVENT
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Map<String, NotificationPreferenceService.ResolveResult> channelResults = preferenceService.resolveForRecipientsByChannel(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new List<Id>{ context.recipientUser.Id },
      context.household.Id
    ).get(context.recipientUser.Id);

    System.assertEquals(1, channelResults.size());
    System.assertEquals(
      NotificationConstants.CHANNEL_IN_APP,
      new List<String>(channelResults.keySet())[0]
    );
  }

  @IsTest
  static void householdSettingDoesNotApplyOnDifferentHousehold() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account otherHousehold = FscDataTestDataFactory.createHouseholdAccount(
      'Scenario Household Setting B'
    );
    NotificationTestDataFactory.createHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.household.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    Notification_Rule__c globalUserRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Map<String, NotificationPreferenceService.ResolveResult> otherResults = preferenceService.resolveForRecipientsByChannel(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Id>{ context.recipientUser.Id },
      otherHousehold.Id
    ).get(context.recipientUser.Id);

    System.assertEquals(1, otherResults.size());
    System.assertEquals(
      globalUserRule.Id,
      otherResults.get(NotificationConstants.CHANNEL_IN_APP).preference.Id
    );
    System.assertEquals(
      'USER_DEFAULT',
      otherResults.get(NotificationConstants.CHANNEL_IN_APP).resolvedScope
    );
  }

  @IsTest
  static void resolveForCurrentUserScenarioMatrix() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Account householdTwo = FscDataTestDataFactory.createHouseholdAccount(
      'Scenario Matrix Household Two'
    );
    Account householdThree = FscDataTestDataFactory.createHouseholdAccount(
      'Scenario Matrix Household Three'
    );

    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      },
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      householdTwo.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    List<Id> households = new List<Id>{
      context.household.Id,
      householdTwo.Id,
      householdThree.Id
    };
    List<String> objectTypes = new List<String>{
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.OBJECT_TYPE_EVENT
    };

    for (Id householdId : households) {
      for (String objectType : objectTypes) {
        Map<String, NotificationPreferenceService.ResolveResult> channelResults = preferenceService.resolveForRecipientsByChannel(
          objectType,
          new List<Id>{ context.recipientUser.Id },
          householdId
        ).get(context.recipientUser.Id);

        if (channelResults == null) {
          continue;
        }

        for (String channelName : channelResults.keySet()) {
          NotificationPreferenceService.ResolveResult result = channelResults.get(
            channelName
          );

          if (result.preference.Household__c != null) {
            System.assertEquals(
              householdId,
              result.preference.Household__c,
              'Household rule must match event household'
            );
          }
        }
      }
    }
  }
}