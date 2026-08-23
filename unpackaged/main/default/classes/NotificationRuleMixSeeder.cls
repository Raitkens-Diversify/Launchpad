/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Seeds a representative mix of user-defined Notification_Rule__c records
 * for Notification Center UI testing (Immediate + Email Digest, all object
 * types, global and household scopes).
 */
public without sharing class NotificationRuleMixSeeder {
  public static final String SEED_PREFIX = 'UI-RULE-MIX';

  public class SeedResult {
    public Id userId;
    public String username;
    public Id householdId;
    public String householdName;
    public List<NotificationCenterModels.RuleItem> createdRules = new List<NotificationCenterModels.RuleItem>();
    public Integer skippedCount = 0;
  }

  public class RuleDefinition {
    public String ruleName;
    public String category;
    public String objectType;
    public String frequency;
    public String digestFrequency;
    public String digestFrequencyHour;
    public List<String> channels;
    public Id householdId;

    public RuleDefinition(
      String ruleName,
      String category,
      String objectType,
      String frequency,
      List<String> channels
    ) {
      this.ruleName = ruleName;
      this.category = category;
      this.objectType = objectType;
      this.frequency = frequency;
      this.channels = channels;
    }

    public RuleDefinition withDigest(String cadence, String deliveryHour) {
      this.digestFrequency = cadence;
      this.digestFrequencyHour = deliveryHour;
      return this;
    }

    public RuleDefinition forHousehold(Id accountId) {
      this.householdId = accountId;
      return this;
    }
  }

  public static SeedResult seedForUser(String username, Id householdId) {
    if (String.isBlank(username)) {
      throw new IllegalArgumentException('username is required.');
    }

    User recipient = [
      SELECT Id, Username
      FROM User
      WHERE Username = :username AND IsActive = TRUE
      LIMIT 1
    ];

    Id resolvedHouseholdId = resolveHouseholdId(householdId);
    String householdName = null;

    if (resolvedHouseholdId != null) {
      householdName = [
        SELECT Name
        FROM Account
        WHERE Id = :resolvedHouseholdId
        LIMIT 1
      ]
      .Name;
    }

    String marker = SEED_PREFIX;
    List<RuleDefinition> definitions = buildDefinitions(marker, resolvedHouseholdId);
    Set<String> existingNames = loadExistingSeedRuleNames(recipient.Id);
    NotificationCenterService service = new NotificationCenterService();
    SeedResult result = new SeedResult();
    result.userId = recipient.Id;
    result.username = recipient.Username;
    result.householdId = resolvedHouseholdId;
    result.householdName = householdName;

    for (RuleDefinition definition : definitions) {
      if (existingNames.contains(definition.ruleName)) {
        result.skippedCount++;
        continue;
      }

      NotificationCenterModels.RuleInput input = toRuleInput(definition);
      input.isActive = true;
      result.createdRules.add(service.saveNotificationRule(recipient.Id, input));
    }

    return result;
  }

  public static SeedResult seedForRunningUser() {
    User runningUser = [
      SELECT Username
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    return seedForUser(runningUser.Username, SimpsonMapDemoDataSeeder.HOUSEHOLD_ID);
  }

  public static void logResult(SeedResult result) {
    System.debug('=== Notification Rule Mix Seeder ===');
    System.debug('User: ' + result.username + ' (' + result.userId + ')');

    if (result.householdId != null) {
      System.debug(
        'Household scope: ' + result.householdName + ' (' + result.householdId + ')'
      );
    }

    System.debug('Created rules: ' + result.createdRules.size());
    System.debug('Skipped existing seed rules: ' + result.skippedCount);

    for (NotificationCenterModels.RuleItem rule : result.createdRules) {
      System.debug(
        '  ' +
          rule.ruleName +
          ' | ' +
          rule.objectType +
          ' | ' +
          rule.frequency +
          formatDigest(rule) +
          ' | Channels: ' +
          String.join(rule.channels, ', ') +
          (rule.householdScoped ? ' | Household' : ' | Global')
      );
    }

    System.debug('Open Notification Center > Notification Rules > User Defined to review.');
  }

  private static String formatDigest(NotificationCenterModels.RuleItem rule) {
    if (rule.frequency != NotificationConstants.FREQUENCY_DIGEST) {
      return '';
    }

    String label = ' | Digest: ' + rule.digestFrequency;

    if (String.isNotBlank(rule.digestFrequencyHour)) {
      label += ' @ hour ' + rule.digestFrequencyHour;
    }

    return label;
  }

  private static List<RuleDefinition> buildDefinitions(String prefix, Id householdId) {
    List<RuleDefinition> definitions = new List<RuleDefinition>();

    definitions.add(
      new RuleDefinition(
        prefix + ' · Case Immediate In App',
        'Service',
        NotificationConstants.OBJECT_TYPE_CASE,
        NotificationConstants.FREQUENCY_IMMEDIATE,
        new List<String>{ NotificationConstants.CHANNEL_IN_APP }
      )
    );
    definitions.add(
      new RuleDefinition(
        prefix + ' · Case Immediate In App + Email',
        'Urgent',
        NotificationConstants.OBJECT_TYPE_CASE,
        NotificationConstants.FREQUENCY_IMMEDIATE,
        new List<String>{
          NotificationConstants.CHANNEL_IN_APP,
          NotificationConstants.CHANNEL_EMAIL
        }
      )
    );
    definitions.add(
      new RuleDefinition(
        prefix + ' · Task Immediate In App',
        'Service',
        NotificationConstants.OBJECT_TYPE_TASK,
        NotificationConstants.FREQUENCY_IMMEDIATE,
        new List<String>{ NotificationConstants.CHANNEL_IN_APP }
      )
    );
    definitions.add(
      new RuleDefinition(
        prefix + ' · Event Immediate In App + Email',
        'Info',
        NotificationConstants.OBJECT_TYPE_EVENT,
        NotificationConstants.FREQUENCY_IMMEDIATE,
        new List<String>{
          NotificationConstants.CHANNEL_IN_APP,
          NotificationConstants.CHANNEL_EMAIL
        }
      )
    );
    definitions.add(
      new RuleDefinition(
        prefix + ' · Case Email Digest Daily 9 AM',
        'Service',
        NotificationConstants.OBJECT_TYPE_CASE,
        NotificationConstants.FREQUENCY_DIGEST,
        new List<String>{ NotificationConstants.CHANNEL_EMAIL }
      )
        .withDigest(NotificationConstants.DIGEST_FREQUENCY_DAILY, '9')
    );
    definitions.add(
      new RuleDefinition(
        prefix + ' · Task Email Digest Weekly',
        'Info',
        NotificationConstants.OBJECT_TYPE_TASK,
        NotificationConstants.FREQUENCY_DIGEST,
        new List<String>{ NotificationConstants.CHANNEL_EMAIL }
      )
        .withDigest(NotificationConstants.DIGEST_FREQUENCY_WEEKLY, null)
    );
    definitions.add(
      new RuleDefinition(
        prefix + ' · Event Email Digest Hourly',
        'Service',
        NotificationConstants.OBJECT_TYPE_EVENT,
        NotificationConstants.FREQUENCY_DIGEST,
        new List<String>{ NotificationConstants.CHANNEL_EMAIL }
      )
        .withDigest(NotificationConstants.DIGEST_FREQUENCY_HOURLY, null)
    );

    if (householdId != null) {
      definitions.add(
        new RuleDefinition(
          prefix + ' · Case Email Digest Daily 6 PM (Household)',
          'Service',
          NotificationConstants.OBJECT_TYPE_CASE,
          NotificationConstants.FREQUENCY_DIGEST,
          new List<String>{ NotificationConstants.CHANNEL_EMAIL }
        )
          .withDigest(NotificationConstants.DIGEST_FREQUENCY_DAILY, '18')
          .forHousehold(householdId)
      );
      definitions.add(
        new RuleDefinition(
          prefix + ' · Task Immediate In App (Household)',
          'Urgent',
          NotificationConstants.OBJECT_TYPE_TASK,
          NotificationConstants.FREQUENCY_IMMEDIATE,
          new List<String>{ NotificationConstants.CHANNEL_IN_APP }
        )
          .forHousehold(householdId)
      );
      definitions.add(
        new RuleDefinition(
          prefix + ' · Event Email Digest Daily 12 PM (Household)',
          'Info',
          NotificationConstants.OBJECT_TYPE_EVENT,
          NotificationConstants.FREQUENCY_DIGEST,
          new List<String>{ NotificationConstants.CHANNEL_EMAIL }
        )
          .withDigest(NotificationConstants.DIGEST_FREQUENCY_DAILY, '12')
          .forHousehold(householdId)
      );
    }

    return definitions;
  }

  private static NotificationCenterModels.RuleInput toRuleInput(
    RuleDefinition definition
  ) {
    NotificationCenterModels.RuleInput input = new NotificationCenterModels.RuleInput();
    input.ruleName = definition.ruleName;
    input.category = definition.category;
    input.objectType = definition.objectType;
    input.frequency = definition.frequency;
    input.digestFrequency = definition.digestFrequency;
    input.digestFrequencyHour = definition.digestFrequencyHour;
    input.channels = definition.channels;
    input.householdId = definition.householdId;
    input.isActive = true;
    return input;
  }

  private static Set<String> loadExistingSeedRuleNames(Id userId) {
    Set<String> names = new Set<String>();

    for (Notification_Rule__c rule : [
      SELECT Rule_Name__c
      FROM Notification_Rule__c
      WHERE
        User__c = :userId
        AND Is_System_Default__c = FALSE
        AND Rule_Name__c LIKE :(SEED_PREFIX + '%')
    ]) {
      if (String.isNotBlank(rule.Rule_Name__c)) {
        names.add(rule.Rule_Name__c);
      }
    }

    return names;
  }

  private static Id resolveHouseholdId(Id householdId) {
    if (householdId != null) {
      return householdId;
    }

    return SimpsonMapDemoDataSeeder.HOUSEHOLD_ID;
  }
}