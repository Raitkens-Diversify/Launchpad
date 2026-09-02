/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 *
 * Live preference scenario runner for the current user. Creates temporary
 * rules/logs, validates resolution, then cleans up.
 */
public without sharing class NotificationPrefScenarioRunner {
  public class ScenarioRunnerException extends Exception {
  }

  public class ScenarioResult {
    public Integer passCount { get; private set; }
    public Integer failCount { get; private set; }
    public List<String> failures { get; private set; }
    public Id userId { get; private set; }

    private ScenarioResult(Id userId) {
      this.userId = userId;
      this.passCount = 0;
      this.failCount = 0;
      this.failures = new List<String>();
    }

    private void recordPass(String label) {
      passCount++;
      System.debug('PASS: ' + label);
    }

    private void recordFail(String label) {
      failCount++;
      failures.add(label);
      System.debug('FAIL: ' + label);
    }
  }

  private static final Integer SCENARIO_RULE_PRIORITY = 99999;

  public static ScenarioResult runForCurrentUser() {
    return runForUser(UserInfo.getUserId());
  }

  public static ScenarioResult runForUser(Id userId) {
    ScenarioResult result = new ScenarioResult(userId);
    NotificationPreferenceService preferenceService = new NotificationPreferenceService();
    Account householdA;
    Account householdB;
    Notification_Rule__c globalRule;
    Notification_Rule__c householdRuleA;
    List<Notification_Log__c> logsToDelete = new List<Notification_Log__c>();
    List<Notification_Rule__c> rulesToDelete = new List<Notification_Rule__c>();

    try {
      householdA = createScenarioHousehold('Pref Scenario Household A');
      householdB = createScenarioHousehold('Pref Scenario Household B');

      globalRule = buildRule(
        NotificationConstants.OBJECT_TYPE_CASE,
        userId,
        null,
        NotificationConstants.CHANNEL_EMAIL +
          ';' +
          NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_IMMEDIATE,
        SCENARIO_RULE_PRIORITY,
        false,
        null
      );
      householdRuleA = buildRule(
        NotificationConstants.OBJECT_TYPE_CASE,
        userId,
        householdA.Id,
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_IMMEDIATE,
        SCENARIO_RULE_PRIORITY,
        false,
        null
      );
      insertRecords(new List<Notification_Rule__c>{ globalRule, householdRuleA });
      rulesToDelete.add(globalRule);
      rulesToDelete.add(householdRuleA);

      NotificationPreferenceService.clearSystemDefaultCache();

      Map<String, NotificationPreferenceService.ResolveResult> householdAResults = preferenceService
        .resolveForRecipientsByChannel(
          NotificationConstants.OBJECT_TYPE_CASE,
          new List<Id>{ userId },
          householdA.Id
        )
        .get(userId);

      assertCondition(
        result,
        householdAResults.size() == 1,
        'Household A exposes one channel'
      );
      assertCondition(
        result,
        householdAResults.containsKey(NotificationConstants.CHANNEL_IN_APP),
        'Household A includes In-App'
      );
      assertCondition(
        result,
        !householdAResults.containsKey(NotificationConstants.CHANNEL_EMAIL),
        'Household A excludes Email'
      );
      assertCondition(
        result,
        householdAResults.get(NotificationConstants.CHANNEL_IN_APP)
          .resolvedScope == 'USER_HOUSEHOLD_OVERRIDE',
        'Household A scope is USER_HOUSEHOLD_OVERRIDE'
      );
      assertCondition(
        result,
        householdAResults.get(NotificationConstants.CHANNEL_IN_APP).preference
          .Household__c == householdA.Id,
        'Household A In-App preference is household-scoped'
      );
      assertCondition(
        result,
        householdAResults.get(NotificationConstants.CHANNEL_IN_APP).preference
          .User__c == userId,
        'Household A In-App preference belongs to current user'
      );

      Map<String, NotificationPreferenceService.ResolveResult> householdBResults = preferenceService
        .resolveForRecipientsByChannel(
          NotificationConstants.OBJECT_TYPE_CASE,
          new List<Id>{ userId },
          householdB.Id
        )
        .get(userId);

      assertCondition(
        result,
        householdBResults.size() == 2,
        'Household B exposes both channels (actual=' +
          householdBResults.size() +
          ')'
      );
      assertCondition(
        result,
        householdBResults.get(NotificationConstants.CHANNEL_EMAIL).resolvedScope ==
        'USER_DEFAULT',
        'Household B Email scope is USER_DEFAULT'
      );
      assertCondition(
        result,
        householdBResults.get(NotificationConstants.CHANNEL_IN_APP).resolvedScope ==
        'USER_DEFAULT',
        'Household B In-App scope is USER_DEFAULT'
      );
      assertCondition(
        result,
        isUserGlobalPreference(
          householdBResults.get(NotificationConstants.CHANNEL_EMAIL).preference,
          userId
        ),
        'Household B Email uses a user global preference'
      );
      assertCondition(
        result,
        isUserGlobalPreference(
          householdBResults.get(NotificationConstants.CHANNEL_IN_APP).preference,
          userId
        ),
        'Household B In-App uses a user global preference'
      );

      NotificationPreferenceService.ResolveResult householdBSingle = preferenceService.resolve(
        NotificationConstants.OBJECT_TYPE_CASE,
        userId,
        householdB.Id
      );
      assertCondition(
        result,
        householdBSingle.isAllowed &&
          householdBSingle.resolvedScope == 'USER_DEFAULT',
        'Household B single resolve uses USER_DEFAULT'
      );

      NotificationPreferenceService.ResolveResult householdASingle = preferenceService.resolve(
        NotificationConstants.OBJECT_TYPE_CASE,
        userId,
        householdA.Id
      );
      assertCondition(
        result,
        householdASingle.isAllowed &&
          householdASingle.resolvedScope == 'USER_HOUSEHOLD_OVERRIDE',
        'Household A single resolve uses USER_HOUSEHOLD_OVERRIDE'
      );

      Notification_Rule__c digestRuleA = buildRule(
        NotificationConstants.OBJECT_TYPE_TASK,
        userId,
        householdA.Id,
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.FREQUENCY_DIGEST,
        SCENARIO_RULE_PRIORITY,
        false,
        NotificationConstants.DIGEST_FREQUENCY_HOURLY
      );
      insertRecords(new List<Notification_Rule__c>{ digestRuleA });
      rulesToDelete.add(digestRuleA);

      Notification_Log__c logOnA = buildLog(
        userId,
        householdA.Id,
        NotificationConstants.OBJECT_TYPE_TASK,
        digestRuleA.Id,
        'Scenario log A'
      );
      Notification_Log__c logOnB = buildLog(
        userId,
        householdB.Id,
        NotificationConstants.OBJECT_TYPE_TASK,
        digestRuleA.Id,
        'Scenario log B'
      );
      insertRecords(new List<Notification_Log__c>{ logOnA, logOnB });
      logsToDelete.add(logOnA);
      logsToDelete.add(logOnB);

      List<Notification_Log__c> scopedQueued = new NotificationLogRepository()
        .selectQueuedLogsForRules(new Set<Id>{ digestRuleA.Id });
      assertCondition(
        result,
        scopedQueued.size() == 1 && scopedQueued[0].Id == logOnA.Id,
        'Digest batch keeps household A log only'
      );

      Notification_Rule__c appOnlyGlobal = buildRule(
        NotificationConstants.OBJECT_TYPE_EVENT,
        userId,
        null,
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_IMMEDIATE,
        SCENARIO_RULE_PRIORITY,
        false,
        null
      );
      insertRecords(new List<Notification_Rule__c>{ appOnlyGlobal });
      rulesToDelete.add(appOnlyGlobal);

      List<Notification_Rule__c> existingSystem = querySystemDefaultRules(
        NotificationConstants.OBJECT_TYPE_EVENT
      );
      if (existingSystem.isEmpty()) {
        Notification_Rule__c systemEvent = buildRule(
          NotificationConstants.OBJECT_TYPE_EVENT,
          null,
          null,
          NotificationConstants.CHANNEL_EMAIL +
            ';' +
            NotificationConstants.CHANNEL_IN_APP,
          NotificationConstants.FREQUENCY_IMMEDIATE,
          0,
          true,
          null
        );
        insertRecords(new List<Notification_Rule__c>{ systemEvent });
        rulesToDelete.add(systemEvent);
      }

      NotificationPreferenceService.clearSystemDefaultCache();
      Map<String, NotificationPreferenceService.ResolveResult> appOnlyResults = preferenceService
        .resolveForRecipientsByChannel(
          NotificationConstants.OBJECT_TYPE_EVENT,
          new List<Id>{ userId },
          householdB.Id
        )
        .get(userId);

      assertCondition(
        result,
        appOnlyResults.size() == 1,
        'App-only global exposes one channel'
      );
      assertCondition(
        result,
        !appOnlyResults.containsKey(NotificationConstants.CHANNEL_EMAIL),
        'App-only global does not backfill Email'
      );
    } finally {
      if (!logsToDelete.isEmpty()) {
        deleteRecords(logsToDelete);
      }
      if (!rulesToDelete.isEmpty()) {
        deleteRecords(rulesToDelete);
      }
      if (householdA != null && householdB != null) {
        deleteRecords(new List<Account>{ householdA, householdB });
      }
    }

    System.debug(
      'SCENARIO_SUMMARY userId=' +
        userId +
        ' pass=' +
        result.passCount +
        ' fail=' +
        result.failCount
    );
    if (!result.failures.isEmpty()) {
      for (String failure : result.failures) {
        System.debug('SCENARIO_FAILURE ' + failure);
      }
      throw new ScenarioRunnerException(
        'Preference scenario failures: ' + String.join(result.failures, ' | ')
      );
    }

    return result;
  }

  private static void assertCondition(
    ScenarioResult result,
    Boolean condition,
    String label
  ) {
    if (condition) {
      result.recordPass(label);
    } else {
      result.recordFail(label);
    }
  }

  private static Account createScenarioHousehold(String name) {
    Id householdRecordTypeId = FscRelAccountRepository.selectHouseholdRecordTypeId();
    Account householdAccount = new Account(Name = name);
    if (householdRecordTypeId != null) {
      householdAccount.RecordTypeId = householdRecordTypeId;
    }
    insertRecords(new List<Account>{ householdAccount });
    return householdAccount;
  }

  private static Boolean isUserGlobalPreference(
    Notification_Rule__c preference,
    Id userId
  ) {
    return preference != null &&
      preference.User__c == userId &&
      preference.Household__c == null;
  }

  private static List<Notification_Rule__c> querySystemDefaultRules(
    String objectType
  ) {
    return Database.queryWithBinds(
      'SELECT Id FROM Notification_Rule__c WHERE Object_Type__c = :objectType AND Is_System_Default__c = TRUE AND User__c = NULL AND Household__c = NULL LIMIT 1',
      new Map<String, Object>{ 'objectType' => objectType },
      AccessLevel.SYSTEM_MODE
    );
  }

  private static void insertRecords(List<SObject> records) {
    Database.insert(records, AccessLevel.SYSTEM_MODE);
  }

  private static void deleteRecords(List<SObject> records) {
    Database.delete(records, AccessLevel.SYSTEM_MODE);
  }

  private static Notification_Rule__c buildRule(
    String objectType,
    Id userId,
    Id householdId,
    String channels,
    String frequency,
    Integer priority,
    Boolean isSystemDefault,
    String digestCadence
  ) {
    Notification_Rule__c rule = new Notification_Rule__c(
      Object_Type__c = objectType,
      User__c = userId,
      Household__c = householdId,
      Channel__c = channels,
      Frequency__c = frequency,
      Is_Active__c = true,
      Priority__c = priority,
      Is_System_Default__c = isSystemDefault
    );
    if (digestCadence != null) {
      rule.Digest_Cadence__c = digestCadence;
    }
    return rule;
  }

  private static Notification_Log__c buildLog(
    Id recipientId,
    Id householdId,
    String sourceType,
    Id ruleId,
    String title
  ) {
    return new Notification_Log__c(
      Recipient__c = recipientId,
      Household__c = householdId,
      Source_Type__c = sourceType,
      Channel__c = NotificationConstants.CHANNEL_EMAIL,
      Frequency__c = NotificationConstants.FREQUENCY_DIGEST,
      Status__c = NotificationConstants.STATUS_QUEUED,
      Title__c = title,
      Body__c = title,
      Notification_Rule__c = ruleId
    );
  }
}