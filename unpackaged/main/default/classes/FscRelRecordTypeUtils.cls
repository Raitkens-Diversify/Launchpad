/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-21
 *
 * Maps Account_Account_Relationship__c record types to Reciprocal_Role__c record types
 * using FSC_Relationship_Record_Type_Mapping__mdt.
 */
public class FscRelRecordTypeUtils {
  public static final String PERSONAL_AND_FAMILY_RECORD_TYPE = 'Personal_and_Family';
  public static final String COI_REFERRAL_RECORD_TYPE = 'COI_Referral';
  public static final String BUSINESS_RECORD_TYPE = 'Business';
  public static final String SERVICE_PROVIDER_RECORD_TYPE = 'Service_Provider';
  public static final String FIDUCIARY_LEGAL_RECORD_TYPE = 'Fiduciary_Legal';
  public static final String OTHER_RECORD_TYPE = 'Other';

  private static Map<String, FSC_Relationship_Record_Type_Mapping__mdt> aarDeveloperNameToMapping;

  public static String normalizeAccountRelationRecordTypeDeveloperName(
    String developerName
  ) {
    return String.isBlank(developerName) ? developerName : developerName.trim();
  }

  public static RecordType selectRecordTypeByDeveloperName(
    String objectApiName,
    String developerName
  ) {
    if (String.isBlank(objectApiName) || String.isBlank(developerName)) {
      return null;
    }

    List<RecordType> recordTypes = [
      SELECT Id, DeveloperName, IsPersonType
      FROM RecordType
      WHERE
        SObjectType = :objectApiName
        AND DeveloperName = :developerName
        AND IsActive = TRUE
      LIMIT 1
    ];

    return recordTypes.isEmpty() ? null : recordTypes[0];
  }

  public static Id selectDefaultAccountRecordTypeId(Boolean personAccountsOnly) {
    List<RecordType> recordTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND IsPersonType = :personAccountsOnly
      LIMIT 1
    ];

    return recordTypes.isEmpty() ? null : recordTypes[0].Id;
  }

  public static Id selectAccountRelationRecordTypeId(String developerName) {
    if (String.isBlank(developerName)) {
      return null;
    }

    developerName = normalizeAccountRelationRecordTypeDeveloperName(developerName);

    List<RecordType> recordTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account_Account_Relationship__c'
        AND DeveloperName = :developerName
        AND IsActive = TRUE
      LIMIT 1
    ];

    return recordTypes.isEmpty() ? null : recordTypes[0].Id;
  }

  public static Id selectReciprocalRoleRecordTypeId(String aarRecordTypeDeveloperName) {
    if (String.isBlank(aarRecordTypeDeveloperName)) {
      return null;
    }

    String normalizedName = normalizeAccountRelationRecordTypeDeveloperName(
      aarRecordTypeDeveloperName.trim()
    );
    Set<String> developerNames = resolveReciprocalRoleDeveloperNames(normalizedName);
    Map<String, Id> developerNameToId = new Map<String, Id>();

    for (RecordType recordType : [
      SELECT Id, DeveloperName
      FROM RecordType
      WHERE
        SObjectType = 'Reciprocal_Role__c'
        AND DeveloperName IN :developerNames
        AND IsActive = TRUE
      ORDER BY DeveloperName
    ]) {
      developerNameToId.put(recordType.DeveloperName, recordType.Id);
    }

    if (developerNameToId.isEmpty()) {
      return null;
    }

    if (developerNameToId.containsKey(normalizedName)) {
      return developerNameToId.get(normalizedName);
    }

    for (String developerName : developerNames) {
      if (developerNameToId.containsKey(developerName)) {
        return developerNameToId.get(developerName);
      }
    }

    return null;
  }

  public static String resolveReciprocalRoleDeveloperName(
    String aarRecordTypeDeveloperName
  ) {
    if (String.isBlank(aarRecordTypeDeveloperName)) {
      return null;
    }

    String normalizedName = normalizeAccountRelationRecordTypeDeveloperName(
      aarRecordTypeDeveloperName.trim()
    );
    FSC_Relationship_Record_Type_Mapping__mdt mapping = selectAarDeveloperNameToMapping()
      .get(normalizedName);

    if (
      mapping != null &&
      String.isNotBlank(mapping.Reciprocal_Role_RT_Dev_Name__c)
    ) {
      return mapping.Reciprocal_Role_RT_Dev_Name__c.trim();
    }

    return normalizedName;
  }

  public static Set<String> resolveReciprocalRoleDeveloperNames(
    String aarRecordTypeDeveloperName
  ) {
    Set<String> developerNames = new Set<String>();
    if (String.isBlank(aarRecordTypeDeveloperName)) {
      return developerNames;
    }

    String normalizedName = normalizeAccountRelationRecordTypeDeveloperName(
      aarRecordTypeDeveloperName.trim()
    );
    developerNames.add(normalizedName);

    FSC_Relationship_Record_Type_Mapping__mdt mapping = selectAarDeveloperNameToMapping()
      .get(normalizedName);

    if (mapping == null) {
      return developerNames;
    }

    if (
      String.isNotBlank(mapping.Reciprocal_Role_RT_Dev_Name__c)
    ) {
      developerNames.add(
        mapping.Reciprocal_Role_RT_Dev_Name__c.trim()
      );
    }

    appendFallbackDeveloperNames(
      developerNames,
      mapping.Reciprocal_Role_RT_Fallbacks__c
    );

    return developerNames;
  }

  public static List<FscRelHouseholdModels.RecordTypeOption> selectActiveAccountRelationRecordTypes() {
    List<FscRelHouseholdModels.RecordTypeOption> options = new List<FscRelHouseholdModels.RecordTypeOption>();

    for (RecordType recordType : [
      SELECT DeveloperName, Name
      FROM RecordType
      WHERE SObjectType = 'Account_Account_Relationship__c' AND IsActive = TRUE
      ORDER BY Name
    ]) {
      options.add(
        new FscRelHouseholdModels.RecordTypeOption(
          recordType.DeveloperName,
          recordType.Name,
          resolveReciprocalRoleDeveloperName(recordType.DeveloperName)
        )
      );
    }

    return options;
  }

  private static Map<String, FSC_Relationship_Record_Type_Mapping__mdt> selectAarDeveloperNameToMapping() {
    if (aarDeveloperNameToMapping != null) {
      return aarDeveloperNameToMapping;
    }

    aarDeveloperNameToMapping = new Map<String, FSC_Relationship_Record_Type_Mapping__mdt>();

    for (FSC_Relationship_Record_Type_Mapping__mdt mapping : [
      SELECT
        AAR_Record_Type_Developer_Name__c,
        Reciprocal_Role_RT_Dev_Name__c,
        Reciprocal_Role_RT_Fallbacks__c,
        Is_Active__c,
        Sort_Order__c
      FROM FSC_Relationship_Record_Type_Mapping__mdt
      WHERE Is_Active__c = TRUE
      ORDER BY Sort_Order__c NULLS LAST, DeveloperName
    ]) {
      if (String.isBlank(mapping.AAR_Record_Type_Developer_Name__c)) {
        continue;
      }

      aarDeveloperNameToMapping.put(
        normalizeAccountRelationRecordTypeDeveloperName(
          mapping.AAR_Record_Type_Developer_Name__c
        ),
        mapping
      );
    }

    return aarDeveloperNameToMapping;
  }

  private static void appendFallbackDeveloperNames(
    Set<String> developerNames,
    String fallbackDeveloperNames
  ) {
    if (String.isBlank(fallbackDeveloperNames)) {
      return;
    }

    for (String fallbackDeveloperName : fallbackDeveloperNames.split(';')) {
      if (String.isNotBlank(fallbackDeveloperName)) {
        developerNames.add(fallbackDeveloperName.trim());
      }
    }
  }

  @TestVisible
  private static void resetMappingCacheForTest() {
    aarDeveloperNameToMapping = null;
  }
}