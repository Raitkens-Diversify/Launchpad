/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Shared test data for notification framework tests.
 */
@IsTest
public class NotificationTestDataFactory {
  public class NotificationTestContext {
    public Account household;
    public User recipientUser;
  }

  public static NotificationTestContext createHouseholdWithRecipient() {
    NotificationTestContext context = new NotificationTestContext();

    System.runAs(runningUser()) {
      context.household = FscDataTestDataFactory.createHouseholdAccount(
        'Notification Test Household'
      );
    }

    context.recipientUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ context.recipientUser.Id }
    };

    return context;
  }

  public static NotificationTestContext createHouseholdWithStandardUserRecipient() {
    NotificationTestContext context = new NotificationTestContext();

    context.recipientUser = createStandardUser('notifrcpt');

    System.runAs(runningUser()) {
      context.household = FscDataTestDataFactory.createHouseholdAccount(
        'Notification Test Household'
      );
    }

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ context.recipientUser.Id }
    };

    return context;
  }

  public static void insertRecord(SObject record) {
    if (record == null) {
      return;
    }

    insertRecords(new List<SObject>{ record });
  }

  public static void insertRecords(List<SObject> records) {
    if (records == null || records.isEmpty()) {
      return;
    }

    System.runAs(runningUser()) {
      insert records;
    }
  }

  public static void updateRecord(SObject record) {
    if (record == null) {
      return;
    }

    updateRecords(new List<SObject>{ record });
  }

  public static void updateRecords(List<SObject> records) {
    if (records == null || records.isEmpty()) {
      return;
    }

    System.runAs(runningUser()) {
      update records;
    }
  }

  public static void clearTestOverrides() {
    NotificationRecipientService.testRecipientOverrides = null;
  }

  public static String defaultChannel() {
    return NotificationChannelService.getDefaultChannelApiName();
  }

  public static String channel(String apiName) {
    System.assert(
      NotificationChannelService.getActiveChannelApiNames().contains(apiName),
      'Expected active channel: ' + apiName
    );
    return apiName;
  }

  public static String alternateChannel() {
    String defaultChannel = defaultChannel();
    for (String channelApiName : NotificationChannelService.getActiveChannelApiNames()) {
      if (channelApiName != defaultChannel) {
        return channelApiName;
      }
    }

    return defaultChannel();
  }

  public static Notification_Rule__c createGlobalPreference(String objectType) {
    return createPreference(
      objectType,
      null,
      null,
      NotificationChannelService.getDefaultChannelApiName(),
      NotificationConstants.FREQUENCY_IMMEDIATE,
      0
    );
  }

  public static Notification_Rule__c createUserPreference(
    String objectType,
    Id userId,
    String channel,
    String frequency
  ) {
    return createPreference(objectType, userId, null, channel, frequency, 10);
  }

  public static Notification_Rule__c createUserPreference(
    String objectType,
    Id userId,
    List<String> channels,
    String frequency
  ) {
    return createPreference(
      objectType,
      userId,
      null,
      joinChannels(channels),
      frequency,
      10
    );
  }

  public static Notification_Rule__c createHouseholdPreference(
    String objectType,
    Id householdId,
    String channel,
    String frequency
  ) {
    return createPreference(objectType, null, householdId, channel, frequency, 10);
  }

  public static Notification_Rule__c createUserHouseholdPreference(
    String objectType,
    Id userId,
    Id householdId,
    List<String> channels,
    String frequency
  ) {
    return createPreference(
      objectType,
      userId,
      householdId,
      joinChannels(channels),
      frequency,
      20
    );
  }

  public static String joinChannels(List<String> channels) {
    if (channels == null || channels.isEmpty()) {
      return null;
    }

    List<String> normalizedChannels = new List<String>();
    for (String channel : channels) {
      if (!String.isBlank(channel)) {
        normalizedChannels.add(channel.trim());
      }
    }

    return normalizedChannels.isEmpty()
      ? null
      : String.join(normalizedChannels, ';');
  }

  public static Notification_Rule__c createUserHouseholdPreference(
    String objectType,
    Id userId,
    Id householdId,
    String channel,
    String frequency
  ) {
    return createPreference(objectType, userId, householdId, channel, frequency, 20);
  }

  @TestVisible
  public static Notification_Rule__c createPreference(
    String objectType,
    Id userId,
    Id householdId,
    String channel,
    String frequency,
    Decimal priority
  ) {
    Notification_Rule__c preference = new Notification_Rule__c(
      Object_Type__c = objectType,
      Channel__c = channel,
      Frequency__c = frequency,
      Is_Active__c = true,
      Is_System_Default__c = userId == null && householdId == null,
      Priority__c = priority,
      User__c = userId,
      Household__c = householdId
    );
    insertRecord(preference);
    return preference;
  }

  public static Notification_Log__c createSentInAppNotification(
    Id recipientId,
    Id householdId,
    String sourceType,
    String title,
    String body,
    Boolean isRead
  ) {
    Notification_Log__c notification = new Notification_Log__c(
      Recipient__c = recipientId,
      Household__c = householdId,
      Source_Type__c = sourceType,
      Channel__c = NotificationConstants.CHANNEL_IN_APP,
      Status__c = NotificationConstants.STATUS_SENT,
      Title__c = title,
      Body__c = body,
      Is_Read__c = isRead,
      Delivered_At__c = System.now()
    );
    insertRecord(notification);
    return notification;
  }

  public static Notification_Log__c createLogNotification(
    Id recipientId,
    Id householdId,
    String sourceType,
    String status,
    String channel,
    String frequency,
    String title,
    String suppressionReason,
    Id preferenceId
  ) {
    Notification_Log__c notification = new Notification_Log__c(
      Recipient__c = recipientId,
      Household__c = householdId,
      Source_Type__c = sourceType,
      Channel__c = channel,
      Status__c = status,
      Frequency__c = frequency,
      Title__c = title,
      Body__c = title,
      Suppression_Reason__c = suppressionReason,
      Notification_Rule__c = preferenceId,
      Delivered_At__c = status == NotificationConstants.STATUS_SENT
        ? System.now()
        : null
    );
    insertRecord(notification);
    return notification;
  }

  @TestVisible
  public static User createStandardUser(String aliasPrefix) {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    String uniqueSuffix = String.valueOf(System.currentTimeMillis());
    User testUser = new User(
      Alias = aliasPrefix.left(8),
      Email = aliasPrefix + '@example.com.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Notification Test User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasPrefix + uniqueSuffix + '@example.com.test'
    );
    insert testUser;
    stripAutomationPermissionSetAssignments(testUser.Id);
    return testUser;
  }

  @TestVisible
  public static User createProfileUser(String profileName, String aliasPrefix) {
    Profile profileRecord = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      LIMIT 1
    ];

    String uniqueSuffix = String.valueOf(System.currentTimeMillis());
    User testUser = new User(
      Alias = aliasPrefix.left(8),
      Email = aliasPrefix + '@example.com.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Notification Profile Test User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileRecord.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasPrefix + uniqueSuffix + '@example.com.test'
    );
    insert testUser;
    stripAutomationPermissionSetAssignments(testUser.Id);
    return testUser;
  }

  @TestVisible
  public static User runningUser() {
    return new User(Id = UserInfo.getUserId());
  }

  private static void stripAutomationPermissionSetAssignments(Id userId) {
    delete [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND (PermissionSetGroupId != NULL OR PermissionSet.IsOwnedByProfile = FALSE)
    ];
  }
}