/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Shared constants for the household notification framework.
 */
public class NotificationConstants {
  public static final String OBJECT_TYPE_CASE = 'Case';
  public static final String OBJECT_TYPE_TASK = 'Task';
  public static final String OBJECT_TYPE_EVENT = 'Event';
  public static final String OBJECT_TYPE_NOTIFICATION_LOG = 'Notification_Log';

  public static final String CHANGE_TYPE_INSERT = 'Insert';
  public static final String CHANGE_TYPE_UPDATE = 'Update';

  public static final String FREQUENCY_IMMEDIATE = 'Immediate';
  public static final String FREQUENCY_DIGEST = 'Digest';

  public static final String DIGEST_FREQUENCY_DAILY = 'Daily';
  public static final String DIGEST_FREQUENCY_WEEKLY = 'Weekly';
  public static final String DIGEST_FREQUENCY_HOURLY = 'Hourly';

  /** Weekly digest runs Monday at 7:00 AM in the org default timezone. */
  public static final Integer DIGEST_WEEKLY_LOCAL_HOUR = 7;
  public static final Integer DIGEST_WEEKLY_LOCAL_MINUTE = 0;
  public static final String DIGEST_WEEKLY_CRON_EXPRESSION = '0 0 7 ? * MON';

  public static final String STATUS_PENDING = 'Pending';
  public static final String STATUS_QUEUED = 'Queued';
  public static final String STATUS_SENT = 'Sent';
  public static final String STATUS_SUPPRESSED = 'Suppressed';
  public static final String STATUS_FAILED = 'Failed';

  public static final String CHANNEL_IN_APP = 'In_App';
  public static final String CHANNEL_EMAIL = 'Email';
  public static final String CHANNEL_ZOOM = 'Zoom';

  /** Verified org-wide email address used as the sender for notification emails. */
  public static final String ORG_WIDE_NOTIFICATION_EMAIL =
    'arc.notifications@diversify.com';

  public static final List<String> CHANNEL_ORDER = new List<String>{
    CHANNEL_IN_APP,
    CHANNEL_EMAIL
  };

  public static final String CUSTOM_NOTIFICATION_PREFERENCE = 'Notification_Preference';

  public static final Integer MAX_DIGEST_DELIVERY_ATTEMPTS = 3;
  public static final Integer MAX_IMMEDIATE_DELIVERY_ATTEMPTS = 3;
  public static final Integer IMMEDIATE_RECOVERY_STALE_MINUTES = 15;
  public static final Integer MAX_DIGEST_JOBS_PER_TRANSACTION = 45;
  /** Minimum free queueable slots required before synchronous prepare/enqueue work. */
  public static final Integer MIN_QUEUEABLE_BUDGET_FOR_SYNC_PREPARE = 3;
  /** Slots reserved for overflow chain queueables when chunking delivery jobs. */
  public static final Integer QUEUEABLE_CHAIN_RESERVE_SLOTS = 1;

  /**
   * Leave this many SOQL queries unused so the transaction never hits
   * System.LimitException: Too many SOQL queries: 101 (uncatchable).
   */
  public static final Integer SOQL_HARD_STOP_BUFFER = 5;
  public static final Integer SOQL_SAFETY_BUFFER = 15;
  /**
   * Sync prepare is skipped unless this many buffered SOQL queries remain.
   * Recipient resolution + change enrich + preferences can exceed 40 queries
   * when the Flow has already used some of the 100-query limit.
   */
  public static final Integer SOQL_PREPARE_DEFER_MIN_BUDGET = 55;
  public static final Integer SOQL_QUERIES_PER_PREPARE_SOURCE = 40;
  public static final Integer SOQL_QUERIES_PER_RECIPIENT_PREPARE_CHUNK = 6;
  public static final Integer SOQL_QUERIES_PER_IMMEDIATE_DELIVERY = 8;
  /**
   * Salesforce allows 10 Messaging.sendEmail invocations per transaction.
   * Each invocation may include up to 10 SingleEmailMessage records.
   * See https://help.salesforce.com/s/articleView?id=000385111&type=1
   */
  public static final Integer MAX_EMAIL_INVOCATIONS_PER_TRANSACTION = 10;
  public static final Integer MAX_EMAILS_PER_SEND_EMAIL_INVOCATION = 10;
  public static final Integer EMAIL_INVOCATION_SAFETY_BUFFER = 1;
  public static final Integer MAX_RECIPIENTS_PER_PREPARE_CHUNK = 50;
  public static final Integer MIN_RECIPIENTS_PER_PREPARE_CHUNK = 1;
  public static final Integer MAX_RECIPIENT_IDS_PER_SOQL_IN = 200;
  public static final Integer MAX_LOGS_PER_DML_CHUNK = 200;
  public static final Integer MAX_RECIPIENT_PREPARE_CHAIN_ATTEMPTS = 3;

  public static final String ERROR_GOVERNOR_LIMIT =
    'Governor limit reached while preparing notification logs';
  public static final String ERROR_SOQL_QUERY_LIMIT =
    'Insufficient SOQL query budget for notification prepare';
  public static final String ERROR_EMAIL_INVOCATION_LIMIT =
    'Insufficient email invocation budget for notification delivery';
  public static final String ERROR_QUEUEABLE_JOB_LIMIT =
    'Insufficient queueable job budget for notification async work';

  public static final String SUPPRESSION_USER_DIGEST_DISABLED =
    'User digest disabled for channel';
  public static final String SUPPRESSION_USER_IMMEDIATE_DISABLED =
    'User immediate delivery disabled for channel';
  public static final String SUPPRESSION_NO_PREFERENCE = 'No matching notification preference';

  /** Resolved scope label when pit stop tasks bypass user notification preferences. */
  public static final String PREFERENCE_SCOPE_PIT_STOP_BYPASS = 'PIT_STOP_BYPASS';

  public static final String LOG_BRANCH_ALL = 'ALL';
  public static final String LOG_BRANCH_DAS = 'DAS';
  public static final String LOG_BRANCH_DWM = 'DWM';
  public static final String LOG_STATUS_ALL = 'ALL';
  public static final String LOG_STATUS_DELIVERED = 'DELIVERED';
  public static final String LOG_STATUS_SUPPRESSED = 'SUPPRESSED';
  public static final String LOG_STATUS_QUEUED = 'QUEUED';
  public static final String LOG_STATUS_PENDING = 'PENDING';
  public static final String LOG_STATUS_FAILED = 'FAILED';

  public static Set<String> allLogViewStatuses() {
    return new Set<String>{
      STATUS_SENT,
      STATUS_SUPPRESSED,
      STATUS_QUEUED,
      STATUS_PENDING,
      STATUS_FAILED
    };
  }

  public static final String LOG_CATEGORY_ALL = 'ALL';
  public static final String LOG_CATEGORY_URGENT = 'URGENT';
  public static final String LOG_CATEGORY_SERVICE = 'SERVICE';
  public static final String LOG_CATEGORY_INFO = 'INFO';

  /** Standard placeholder when a notification display value is unavailable. */
  public static final String DISPLAY_NOT_APPLICABLE = '(n/a)';

  public static final Decimal CATEGORY_URGENT_MIN_PRIORITY = 40;
  public static final Decimal CATEGORY_SERVICE_MIN_PRIORITY = 10;

  public static final String PROFILE_NEXS = 'Nexs';
  public static final String PROFILE_ADVISOR = 'Advisor';
  public static final String PROFILE_HOME_OFFICE = 'Home Office';
  public static final String PROFILE_SYSTEM_ADMINISTRATOR = 'System Administrator';

  public static Boolean isNexSProfile(String profileName) {
    return profileName == PROFILE_NEXS;
  }

  public static Boolean isAdvisorProfile(String profileName) {
    return profileName == PROFILE_ADVISOR;
  }

  public static Boolean isHomeOfficeProfile(String profileName) {
    return profileName == PROFILE_HOME_OFFICE;
  }

  public static Boolean isBranchUserProfile(String profileName) {
    return isNexSProfile(profileName) || isAdvisorProfile(profileName);
  }

  /**
   * Profiles that may receive pit stop notifications for the given task flags.
   */
  public static Set<String> pitStopRecipientProfileNames(Task taskRecord) {
    Set<String> profileNames = new Set<String>();

    if (taskRecord == null) {
      return profileNames;
    }

    if (taskRecord.Branch_Pit_Stop__c == true) {
      profileNames.add(PROFILE_NEXS);
      profileNames.add(PROFILE_ADVISOR);
    }

    if (taskRecord.Home_Office_Pit_Stop__c == true) {
      profileNames.add(PROFILE_HOME_OFFICE);
    }

    return profileNames;
  }

  public static Boolean isPitStopRecipientProfile(
    Task taskRecord,
    String profileName
  ) {
    if (taskRecord == null || String.isBlank(profileName)) {
      return false;
    }

    if (taskRecord.Branch_Pit_Stop__c == true && isBranchUserProfile(profileName)) {
      return true;
    }

    return taskRecord.Home_Office_Pit_Stop__c == true &&
      isHomeOfficeProfile(profileName);
  }

  /**
   * Branch pit stop tasks bypass Notification Center rules for branch assignees only.
   * Normal NC recipient resolution is skipped entirely.
   */
  public static Boolean shouldResolveNormalTaskRecipientsForPitStopTask(
    Task taskRecord
  ) {
    return taskRecord == null || taskRecord.Branch_Pit_Stop__c != true;
  }

  /**
   * Home Office pit stop tasks bypass NC rules for HO assignees only.
   * Branch users are suppressed on the normal path when the task is Case-related.
   */
  public static Boolean shouldIncludeRecipientInNormalTaskNotifications(
    Task taskRecord,
    String profileName
  ) {
    if (taskRecord == null) {
      return true;
    }

    if (taskRecord.Branch_Pit_Stop__c == true) {
      return false;
    }

    if (taskRecord.Home_Office_Pit_Stop__c == true) {
      if (isHomeOfficeProfile(profileName)) {
        return false;
      }

      if (isBranchUserProfile(profileName) && isCaseRelatedTask(taskRecord)) {
        return false;
      }
    }

    return true;
  }

  public static Boolean isCaseRelatedTask(Task taskRecord) {
    return taskRecord != null &&
      taskRecord.WhatId != null &&
      String.valueOf(taskRecord.WhatId).startsWith('500');
  }

  public static Boolean isSystemAdministratorProfile(String profileName) {
    return profileName == PROFILE_SYSTEM_ADMINISTRATOR;
  }

  public static Boolean isRunningUserSystemAdministrator() {
    User runningUser = [
      SELECT Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    return isSystemAdministratorProfile(runningUser.Profile.Name);
  }

  public static Boolean isNotificationEligibleProfile(String profileName) {
    return isNexSProfile(profileName) ||
      isAdvisorProfile(profileName) ||
      isHomeOfficeProfile(profileName) ||
      isSystemAdministratorProfile(profileName);
  }

  public static Boolean isFrequencyEnabledForChannel(
    String channel,
    String frequency
  ) {
    if (String.isBlank(channel) || String.isBlank(frequency)) {
      return false;
    }

    if (channel == CHANNEL_IN_APP) {
      return frequency == FREQUENCY_IMMEDIATE;
    }

    if (channel == CHANNEL_EMAIL) {
      return true;
    }

    return false;
  }

  public static Boolean isImmediateEnabledForChannel(String channel) {
    return isFrequencyEnabledForChannel(channel, FREQUENCY_IMMEDIATE);
  }

  public static Set<String> notificationEligibleProfileNames() {
    return new Set<String>{
      PROFILE_NEXS,
      PROFILE_ADVISOR,
      PROFILE_HOME_OFFICE,
      PROFILE_SYSTEM_ADMINISTRATOR
    };
  }

  /**
   * Pit stop tasks are identified by Branch or Home Office pit stop flags.
   */
  public static Boolean isPitStopTask(Task taskRecord) {
    return taskRecord != null &&
      (taskRecord.Branch_Pit_Stop__c == true ||
      taskRecord.Home_Office_Pit_Stop__c == true);
  }

  private NotificationConstants() {
  }
}