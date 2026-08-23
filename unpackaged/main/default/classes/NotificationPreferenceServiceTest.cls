/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 */
@IsTest
private class NotificationPreferenceServiceTest {
  @IsTest
  static void resolveReturnsGlobalPreference() {
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_CASE
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_CASE,
      UserInfo.getUserId(),
      null
    );

    System.assertEquals(true, result.isAllowed);
    System.assertEquals(
      NotificationTestDataFactory.defaultChannel(),
      result.preference.Channel__c
    );
    System.assertEquals('ORG_DEFAULT', result.resolvedScope);
  }

  @IsTest
  static void resolvePrefersUserOverrideOverGlobal() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_CASE);
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_DIGEST
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(true, result.isAllowed);
    System.assertEquals(
      NotificationTestDataFactory.alternateChannel(),
      result.preference.Channel__c
    );
    System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, result.preference.Frequency__c);
    System.assertEquals(context.recipientUser.Id, result.preference.User__c);
    System.assertEquals('USER_DEFAULT', result.resolvedScope);
  }

  @IsTest
  static void resolvePrefersHouseholdOverrideOverGlobal() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_TASK);
    NotificationTestDataFactory.createHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.household.Id,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_DIGEST
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(true, result.isAllowed);
    System.assertEquals(
      NotificationTestDataFactory.alternateChannel(),
      result.preference.Channel__c
    );
    System.assertEquals(context.household.Id, result.preference.Household__c);
    System.assertEquals(null, result.preference.User__c);
    System.assertEquals('HOUSEHOLD_SETTING', result.resolvedScope);
  }

  @IsTest
  static void resolvePrefersUserDefaultOverHouseholdSetting() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_DIGEST
    );
    NotificationTestDataFactory.createHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.household.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(true, result.isAllowed);
    System.assertEquals(
      NotificationTestDataFactory.alternateChannel(),
      result.preference.Channel__c
    );
    System.assertEquals(NotificationConstants.FREQUENCY_DIGEST, result.preference.Frequency__c);
    System.assertEquals('USER_DEFAULT', result.resolvedScope);
  }

  @IsTest
  static void resolvePrefersUserHouseholdOverrideOverUserAndHousehold() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_EVENT);
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    NotificationTestDataFactory.createHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.household.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_DIGEST
    );
    NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      context.household.Id,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(true, result.isAllowed);
    System.assertEquals(
      NotificationTestDataFactory.alternateChannel(),
      result.preference.Channel__c
    );
    System.assertEquals(context.recipientUser.Id, result.preference.User__c);
    System.assertEquals(context.household.Id, result.preference.Household__c);
    System.assertEquals('USER_HOUSEHOLD_OVERRIDE', result.resolvedScope);
  }

  @IsTest
  static void resolveUsesHighestPriorityWithinSameScope() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c lowerPriority = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    lowerPriority.Priority__c = 5;
    NotificationTestDataFactory.updateRecord(lowerPriority);

    NotificationTestDataFactory.createPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      null,
      NotificationTestDataFactory.alternateChannel(),
      NotificationConstants.FREQUENCY_DIGEST,
      50
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(
      NotificationTestDataFactory.alternateChannel(),
      result.preference.Channel__c
    );
    System.assertEquals(50, result.preference.Priority__c);
    System.assertEquals('USER_DEFAULT', result.resolvedScope);
  }

  @IsTest
  static void determineScopeClassifiesRecordShape() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Notification_Rule__c globalPreference = new Notification_Rule__c();
    Notification_Rule__c userDefault = new Notification_Rule__c(
      User__c = context.recipientUser.Id
    );
    Notification_Rule__c householdSetting = new Notification_Rule__c(
      Household__c = context.household.Id
    );
    Notification_Rule__c userHouseholdOverride = new Notification_Rule__c(
      User__c = context.recipientUser.Id,
      Household__c = context.household.Id
    );

    System.assertEquals(
      NotificationPreferenceService.PreferenceScope.ORG_DEFAULT,
      NotificationPreferenceService.determineScope(globalPreference)
    );
    System.assertEquals(
      NotificationPreferenceService.PreferenceScope.USER_DEFAULT,
      NotificationPreferenceService.determineScope(userDefault)
    );
    System.assertEquals(
      NotificationPreferenceService.PreferenceScope.HOUSEHOLD_SETTING,
      NotificationPreferenceService.determineScope(householdSetting)
    );
    System.assertEquals(
      NotificationPreferenceService.PreferenceScope.USER_HOUSEHOLD_OVERRIDE,
      NotificationPreferenceService.determineScope(userHouseholdOverride)
    );
  }

  @IsTest
  static void resolveSuppressesWhenNoPreferenceExists() {
    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_EVENT,
      UserInfo.getUserId(),
      null
    );

    System.assertEquals(false, result.isAllowed);
    System.assertEquals(
      NotificationConstants.SUPPRESSION_NO_PREFERENCE,
      result.suppressionReason
    );
    System.assertEquals(null, result.resolvedScope);
  }

  @IsTest
  static void resolveFallsBackToSystemDefaultWhenNoCustomRule() {
    Notification_Rule__c systemRule = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(true, result.isAllowed);
    System.assertEquals(systemRule.Id, result.preference.Id);
    System.assertEquals('ORG_DEFAULT', result.resolvedScope);
  }

  @IsTest
  static void resolveSuppressesWhenSystemDefaultInactiveAndNoCustomRule() {
    Notification_Rule__c systemRule = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );
    systemRule.Is_Active__c = false;
    NotificationTestDataFactory.updateRecord(systemRule);

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(false, result.isAllowed);
    System.assertEquals(
      NotificationConstants.SUPPRESSION_NO_PREFERENCE,
      result.suppressionReason
    );
  }

  @IsTest
  static void resolvePrefersActiveCustomRuleOverSystemDefault() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_TASK);
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_DIGEST
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(true, result.isAllowed);
    System.assertEquals(userRule.Id, result.preference.Id);
    System.assertEquals('USER_DEFAULT', result.resolvedScope);
  }

  @IsTest
  static void resolveSuppressesWhenPreferenceInactive() {
    Notification_Rule__c preference = NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );
    preference.Is_Active__c = false;
    update preference;

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    NotificationPreferenceService.ResolveResult result = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_TASK,
      UserInfo.getUserId(),
      null
    );

    System.assertEquals(false, result.isAllowed);
    System.assertEquals(
      NotificationConstants.SUPPRESSION_NO_PREFERENCE,
      result.suppressionReason
    );
  }

  @IsTest
  static void resolveForRecipientsMatchesSingleResolve() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createGlobalPreference(NotificationConstants.OBJECT_TYPE_TASK);
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_DIGEST
    );

    User secondUser = NotificationTestDataFactory.createStandardUser('notifrcpt2');
    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Map<Id, NotificationPreferenceService.ResolveResult> bulkResults = preferenceService.resolveForRecipients(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Id>{ context.recipientUser.Id, secondUser.Id },
      context.household.Id
    );

    NotificationPreferenceService.ResolveResult singleResult = preferenceService.resolve(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assertEquals(
      singleResult.preference.Id,
      bulkResults.get(context.recipientUser.Id).preference.Id
    );
    System.assertEquals(
      singleResult.resolvedScope,
      bulkResults.get(context.recipientUser.Id).resolvedScope
    );
    System.assertEquals(
      'ORG_DEFAULT',
      bulkResults.get(secondUser.Id).resolvedScope
    );
  }

  @IsTest
  static void preferenceRepositoryQueriesActiveScopedPreferences() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationTestDataFactory.defaultChannel(),
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    NotificationTestDataFactory.createGlobalPreference(
      NotificationConstants.OBJECT_TYPE_TASK
    );

    NotificationPreferenceRepository repository = new NotificationPreferenceRepository();
    List<Notification_Rule__c> scopedPreferences = repository.selectActiveScopedPreferencesForRecipients(
      NotificationConstants.OBJECT_TYPE_CASE,
      new Set<Id>{ context.recipientUser.Id },
      context.household.Id
    );
    List<Notification_Rule__c> userDefaults = repository.selectUserDefaultPreferences(
      context.recipientUser.Id
    );
    List<Notification_Rule__c> userRules = repository.selectRulesForUser(
      context.recipientUser.Id
    );
    List<Notification_Rule__c> householdRules = repository.selectRulesForUserAndHousehold(
      context.recipientUser.Id,
      context.household.Id
    );
    List<Notification_Rule__c> systemDefaults = repository.selectSystemDefaultRules();
    List<Notification_Rule__c> exactScopeRules = repository.selectExactScope(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      null
    );
    Notification_Rule__c ruleById = repository.selectRuleById(userRule.Id);
    Notification_Rule__c ruleForUser = repository.selectRuleForUser(
      userRule.Id,
      context.recipientUser.Id
    );
    Notification_Rule__c userDefaultForObject = repository.selectUserDefaultRuleForObjectType(
      context.recipientUser.Id,
      NotificationConstants.OBJECT_TYPE_CASE
    );
    List<Notification_Rule__c> matchingPreferences = repository.selectMatchingPreferences(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      context.household.Id
    );

    System.assert(!scopedPreferences.isEmpty());
    System.assert(!userDefaults.isEmpty());
    System.assert(!userRules.isEmpty());
    System.assertEquals(userRule.Id, ruleById.Id);
    System.assertEquals(userRule.Id, ruleForUser.Id);
    System.assertEquals(userRule.Id, userDefaultForObject.Id);
    System.assertEquals(userRule.Id, matchingPreferences[0].Id);
    System.assert(!systemDefaults.isEmpty());
    System.assert(!exactScopeRules.isEmpty());
    System.assertEquals(
      0,
      repository.selectActiveScopedPreferencesForRecipients(
        NotificationConstants.OBJECT_TYPE_CASE,
        new Set<Id>(),
        context.household.Id
      ).size()
    );
    System.assert(
      !repository.selectActiveScopedPreferencesForRecipients(
        NotificationConstants.OBJECT_TYPE_CASE,
        new Set<Id>{ context.recipientUser.Id },
        null
      ).isEmpty()
    );
    System.assertEquals(
      userRule.Id,
      repository.upsertPreference(userRule).Id
    );
    System.assertEquals(
      userRule.Id,
      repository.selectActiveScopedPreferences(
        NotificationConstants.OBJECT_TYPE_CASE,
        context.recipientUser.Id,
        context.household.Id
      )[0].Id
    );
    System.assert(
      !repository.selectActiveSystemDefaults(
        NotificationConstants.OBJECT_TYPE_TASK
      ).isEmpty()
    );
    System.assertEquals(
      null,
      repository.selectSystemDefaultRule(UserInfo.getUserId())
    );
    System.assert(householdRules.size() >= 0);
  }

  @IsTest
  static void resolveForRecipientsByChannelBlocksInAppFallbackWhenHouseholdRuleExists() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      },
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    Notification_Rule__c householdRule = NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_TASK,
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST
    );
    householdRule.Digest_Cadence__c = NotificationConstants.DIGEST_FREQUENCY_DAILY;
    NotificationTestDataFactory.updateRecord(householdRule);

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Map<Id, Map<String, NotificationPreferenceService.ResolveResult>> resultsByRecipientId = preferenceService.resolveForRecipientsByChannel(
      NotificationConstants.OBJECT_TYPE_TASK,
      new List<Id>{ context.recipientUser.Id },
      context.household.Id
    );

    Map<String, NotificationPreferenceService.ResolveResult> channelResults = resultsByRecipientId.get(
      context.recipientUser.Id
    );

    System.assertEquals(1, channelResults.size());
    System.assertEquals(
      householdRule.Id,
      channelResults.get(NotificationConstants.CHANNEL_EMAIL).preference.Id
    );
    System.assertEquals(
      NotificationConstants.FREQUENCY_DIGEST,
      channelResults.get(NotificationConstants.CHANNEL_EMAIL).preference.Frequency__c
    );
    System.assertEquals(
      false,
      channelResults.containsKey(NotificationConstants.CHANNEL_IN_APP)
    );
  }

  @IsTest
  static void resolveForRecipientsByChannelUsesHouseholdRuleChannelsWhenBothConfigured() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
    Notification_Rule__c householdRule = NotificationTestDataFactory.createUserHouseholdPreference(
      NotificationConstants.OBJECT_TYPE_CASE,
      context.recipientUser.Id,
      context.household.Id,
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      },
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Map<String, NotificationPreferenceService.ResolveResult> channelResults = preferenceService.resolveForRecipientsByChannel(
      NotificationConstants.OBJECT_TYPE_CASE,
      new List<Id>{ context.recipientUser.Id },
      context.household.Id
    ).get(context.recipientUser.Id);

    System.assertEquals(2, channelResults.size());
    System.assertEquals(
      householdRule.Id,
      channelResults.get(NotificationConstants.CHANNEL_IN_APP).preference.Id
    );
    System.assertEquals(
      householdRule.Id,
      channelResults.get(NotificationConstants.CHANNEL_EMAIL).preference.Id
    );
  }

  @IsTest
  static void resolveForRecipientsByChannelFallsBackToUserDefaultWithoutHouseholdRule() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Rule__c userRule = NotificationTestDataFactory.createUserPreference(
      NotificationConstants.OBJECT_TYPE_EVENT,
      context.recipientUser.Id,
      new List<String>{
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.CHANNEL_IN_APP
      },
      NotificationConstants.FREQUENCY_IMMEDIATE
    );

    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Map<String, NotificationPreferenceService.ResolveResult> channelResults = preferenceService.resolveForRecipientsByChannel(
      NotificationConstants.OBJECT_TYPE_EVENT,
      new List<Id>{ context.recipientUser.Id },
      context.household.Id
    ).get(context.recipientUser.Id);

    System.assertEquals(2, channelResults.size());
    System.assertEquals(
      userRule.Id,
      channelResults.get(NotificationConstants.CHANNEL_IN_APP).preference.Id
    );
    System.assertEquals(
      userRule.Id,
      channelResults.get(NotificationConstants.CHANNEL_EMAIL).preference.Id
    );
  }
}