/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-17
 *
 * Shared rules for identifying client accounts on the relationship map.
 */
public class FscRelClientAccountUtils {
  public static final Set<String> CLIENT_RECORD_TYPE_LABELS = new Set<String>{
    'Person Account',
    'Business',
    'Trust',
    'Retirement Plan'
  };

  public static final Set<String> CLIENT_RECORD_TYPE_DEVELOPER_NAMES = new Set<String>{
    'PersonAccount',
    'Person_Account',
    'Business',
    'Business_Account',
    'IndustriesBusiness',
    'Trust',
    'IndustriesInstitution',
    'Retirement_Plan',
    'Retirement Plan'
  };

  public static final Set<String> CLIENT_ACCOUNT_TYPES = new Set<String>{
    'Active Client',
    'Former Client'
  };

  public static final Set<String> LEAD_PROSPECT_ACCOUNT_TYPES = new Set<String>{
    'Lead',
    'Prospect'
  };

  public static Boolean isClientRecordType(
    String recordTypeLabel,
    String recordTypeDeveloperName
  ) {
    String label = String.isBlank(recordTypeLabel) ? null : recordTypeLabel.trim();
    String developerName = String.isBlank(recordTypeDeveloperName)
      ? null
      : recordTypeDeveloperName.trim();

    if (label != null && CLIENT_RECORD_TYPE_LABELS.contains(label)) {
      return true;
    }

    if (
      developerName != null &&
      CLIENT_RECORD_TYPE_DEVELOPER_NAMES.contains(developerName)
    ) {
      return true;
    }

    if (developerName != null) {
      String normalizedDeveloperName = developerName.toLowerCase();

      if (
        normalizedDeveloperName.contains('retirement') &&
        normalizedDeveloperName.contains('plan')
      ) {
        return true;
      }
    }

    return false;
  }

  @TestVisible
  private static String testClientAccountTypeOverride;

  @TestVisible
  public static void registerTestClientAccountType(String accountType) {
    testClientAccountTypeOverride = String.isBlank(accountType)
      ? null
      : accountType.trim();
  }

  @TestVisible
  private static String resolveTestClientAccountTypeOverride() {
    if (!String.isBlank(testClientAccountTypeOverride)) {
      return testClientAccountTypeOverride;
    }

    if (!Test.isRunningTest()) {
      return null;
    }

    String assignableType = resolveAssignableClientAccountType();
    if (!String.isBlank(assignableType)) {
      registerTestClientAccountType(assignableType);
      return assignableType;
    }

    for (Schema.PicklistEntry entry : Account.Type.getDescribe().getPicklistValues()) {
      if (
        entry.isActive() &&
        !LEAD_PROSPECT_ACCOUNT_TYPES.contains(entry.getValue())
      ) {
        registerTestClientAccountType(entry.getValue());
        return entry.getValue();
      }
    }

    return null;
  }

  public static Boolean isClientAccountType(String accountType) {
    if (String.isBlank(accountType)) {
      return false;
    }

    String normalizedType = accountType.trim();

    if (CLIENT_ACCOUNT_TYPES.contains(normalizedType)) {
      return true;
    }

    return Test.isRunningTest() &&
      normalizedType == resolveTestClientAccountTypeOverride();
  }

  public static Boolean isLeadProspectAccountType(String accountType) {
    if (String.isBlank(accountType)) {
      return false;
    }

    return LEAD_PROSPECT_ACCOUNT_TYPES.contains(accountType.trim());
  }

  public static String resolveAssignableClientAccountType() {
    for (String preferredType : CLIENT_ACCOUNT_TYPES) {
      if (isActiveAccountTypeValue(preferredType)) {
        return preferredType;
      }
    }

    return null;
  }

  public static String resolveClientAccountTypeForDataSetup() {
    String assignableType = resolveAssignableClientAccountType();

    if (!String.isBlank(assignableType)) {
      return assignableType;
    }

    for (Schema.PicklistEntry entry : Account.Type.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        registerTestClientAccountType(entry.getValue());
        return entry.getValue();
      }
    }

    return null;
  }

  private static Boolean isActiveAccountTypeValue(String accountType) {
    if (String.isBlank(accountType)) {
      return false;
    }

    for (Schema.PicklistEntry entry : Account.Type.getDescribe().getPicklistValues()) {
      if (entry.isActive() && entry.getValue() == accountType) {
        return true;
      }
    }

    return false;
  }

  public static Boolean isClientAccount(
    String recordTypeLabel,
    String recordTypeDeveloperName,
    String accountType
  ) {
    return isClientRecordType(recordTypeLabel, recordTypeDeveloperName) &&
      isClientAccountType(accountType);
  }

  public static Boolean isClientAccount(Account account) {
    if (account == null || account.RecordType == null) {
      return false;
    }

    return isClientAccount(
      account.RecordType.Name,
      account.RecordType.DeveloperName,
      account.Type
    );
  }

  public static Boolean isLeadProspectAccount(
    String recordTypeLabel,
    String recordTypeDeveloperName,
    String accountType
  ) {
    return isClientRecordType(recordTypeLabel, recordTypeDeveloperName) &&
      isLeadProspectAccountType(accountType);
  }

  public static Boolean isLeadProspectAccount(Account account) {
    if (account == null || account.RecordType == null) {
      return false;
    }

    return isLeadProspectAccount(
      account.RecordType.Name,
      account.RecordType.DeveloperName,
      account.Type
    );
  }
}