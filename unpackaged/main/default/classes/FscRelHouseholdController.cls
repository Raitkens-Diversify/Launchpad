/**
 * Author: Hoang Long Vu To
 * Date: 2026-05-20
 *
 * Aura-enabled facade for FSC Relationship Tree writes.
 * Delegates to FscRelHouseholdService.
 */
public with sharing class FscRelHouseholdController {
  private static final FscRelHouseholdService SERVICE = new FscRelHouseholdService();

  /**
   * Returns the Name of the supplied Account so the LWC can render initials.
   */
  @AuraEnabled(cacheable=true)
  public static String getAccountName(Id accountId) {
    return SERVICE.getAccountName(accountId);
  }

  /**
   * Returns the default Account record type id for person or business accounts.
   */
  @AuraEnabled(cacheable=true)
  public static String getAccountRecordTypeId(Boolean personAccountsOnly) {
    return SERVICE.getAccountRecordTypeId(personAccountsOnly);
  }

  /**
   * Default field values for inline Account create from member relationship context.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, String> getAccountCreatePrefillFieldValues(
    Id memberAccountId,
    Id recordTypeId,
    String searchTerm
  ) {
    return SERVICE.getAccountCreatePrefillFieldValues(
      memberAccountId,
      recordTypeId,
      searchTerm
    );
  }

  /**
   * Resolves the most recent Account created by the running user after a native
   * create overlay was opened.
   */
  @AuraEnabled
  public static FscRelHouseholdModels.LookupOption resolveRecentlyCreatedAccount(
    Id recordTypeId,
    Long createdAfterEpochMs
  ) {
    return SERVICE.resolveRecentlyCreatedAccount(
      recordTypeId,
      createdAfterEpochMs
    );
  }

  /**
   * Returns the Name of the supplied Contact.
   */
  @AuraEnabled(cacheable=true)
  public static String getContactName(Id contactId) {
    return SERVICE.getContactName(contactId);
  }

  /**
   * Returns the display label for the supplied Reciprocal Role.
   */
  @AuraEnabled
  public static String getReciprocalRoleName(Id reciprocalRoleId) {
    return SERVICE.getReciprocalRoleName(reciprocalRoleId);
  }

  /**
   * Sharing-enforced contact search for the record lookup combobox.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.LookupOption> searchContacts(
    String searchTerm
  ) {
    return SERVICE.searchContacts(searchTerm);
  }

  /**
   * Sharing-enforced reciprocal role search for the record lookup combobox.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.LookupOption> searchReciprocalRoles(
    String searchTerm,
    String recordTypeDeveloperName
  ) {
    return SERVICE.searchReciprocalRoles(searchTerm, recordTypeDeveloperName);
  }

  /**
   * Returns active AAR record types for member relationship menus.
   */
  @AuraEnabled(cacheable=true)
  public static List<FscRelHouseholdModels.RecordTypeOption> getMemberRelationshipRecordTypes() {
    return SERVICE.getMemberRelationshipRecordTypes();
  }

  /**
   * Returns all member account relationships for tree expansion.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.TreeMemberAccountRelationship> getMemberAccountRelationshipsForAccount(
    Id memberAccountId
  ) {
    return SERVICE.getMemberAccountRelationshipsForAccounts(
      new Set<Id>{ memberAccountId }
    );
  }

  /**
   * Returns member account relationships filtered by record type.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.TreeMemberAccountRelationship> getMemberAccountRelationships(
    Id memberAccountId,
    String recordTypeDeveloperName
  ) {
    return SERVICE.getMemberAccountRelationships(
      memberAccountId,
      recordTypeDeveloperName
    );
  }

  /**
   * Returns active member account relationship counts keyed by account id.
   */
  @AuraEnabled
  public static Map<String, Integer> getMemberAccountRelationshipCounts(
    List<Id> accountIds
  ) {
    return SERVICE.getMemberAccountRelationshipCounts(accountIds);
  }

  /**
   * Returns the consolidated household family card count for the supplied members.
   */
  @AuraEnabled
  public static Integer getHouseholdFamilyCardCount(List<Id> memberAccountIds) {
    return SERVICE.getHouseholdFamilyCardCount(memberAccountIds);
  }

  /**
   * Returns the consolidated household network card count for the supplied members.
   */
  @AuraEnabled
  public static Integer getHouseholdNetworkCardCount(List<Id> memberAccountIds) {
    return SERVICE.getHouseholdNetworkCardCount(memberAccountIds);
  }

  /**
   * Validates and persists multiple member account relationships in one request.
   */
  @AuraEnabled
  public static FscRelHouseholdModels.MemberAccountRelationshipsSaveResult saveMemberAccountRelationships(
    Id memberAccountId,
    String recordTypeDeveloperName,
    String relationshipsJson
  ) {
    return SERVICE.saveMemberAccountRelationships(
      memberAccountId,
      recordTypeDeveloperName,
      parseMemberAccountRelationshipInputs(relationshipsJson)
    );
  }

  /**
   * Deletes member account relationships and their mirror rows.
   */
  @AuraEnabled
  public static FscRelHouseholdModels.DeleteResult deleteMemberAccountRelationships(
    List<String> relationIds
  ) {
    return SERVICE.deleteMemberAccountRelationships(relationIds);
  }

  /**
   * Validates a reciprocal role before create and returns duplicate warnings.
   */
  @AuraEnabled
  public static FscRelHouseholdModels.ReciprocalRoleDuplicateCheckResult validateReciprocalRoleForCreate(
    String role
  ) {
    return SERVICE.validateReciprocalRoleForCreate(role);
  }

  /**
   * Creates a Reciprocal_Role__c record.
   */
  @AuraEnabled
  public static FscRelHouseholdModels.ReciprocalRoleCreateResult createReciprocalRole(
    String role,
    Boolean confirmDuplicate,
    String recordTypeDeveloperName
  ) {
    return SERVICE.createReciprocalRole(
      role,
      confirmDuplicate,
      recordTypeDeveloperName
    );
  }

  /**
   * Returns creatable record types for inline lookup create actions.
   */
  @AuraEnabled(cacheable=true)
  public static List<FscRelHouseholdModels.CreateRecordTypeOption> getCreateableRecordTypes(
    String objectApiName
  ) {
    return SERVICE.getCreateableRecordTypes(objectApiName);
  }

  /**
   * Resolves a record type id (and person-type flag) from object + developer name.
   */
  @AuraEnabled(cacheable=true)
  public static FscRelHouseholdModels.RecordTypeInfo getRecordTypeByDeveloperName(
    String objectApiName,
    String recordTypeDeveloperName
  ) {
    return SERVICE.getRecordTypeByDeveloperName(
      objectApiName,
      recordTypeDeveloperName
    );
  }

  /**
   * Sharing-enforced account search for the record lookup combobox.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.LookupOption> searchAccounts(
    String searchTerm,
    Boolean personAccountsOnly
  ) {
    return SERVICE.searchAccounts(searchTerm, personAccountsOnly);
  }

  /**
   * Sharing-enforced account search limited to a supplied id scope.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.LookupOption> searchAccountsInScope(
    String searchTerm,
    Boolean personAccountsOnly,
    List<String> allowedAccountIds
  ) {
    return SERVICE.searchAccountsInScope(
      searchTerm,
      personAccountsOnly,
      allowedAccountIds
    );
  }

  /**
   * Sharing-enforced account search filtered by Classification__c value.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.LookupOption> searchAccountsByClassification(
    String searchTerm,
    String classificationValue
  ) {
    return SERVICE.searchAccountsByClassification(searchTerm, classificationValue);
  }

  /**
   * Links a classified account to the household through AAR when needed.
   */
  @AuraEnabled
  public static FscRelHouseholdModels.TreeAccountResult linkClassificationAccountToHousehold(
    Id rootAccountId,
    Id accountId,
    String classificationValue
  ) {
    return SERVICE.linkClassificationAccountToHousehold(
      rootAccountId,
      accountId,
      classificationValue
    );
  }

  /**
   * Returns lookup options for the supplied person account ids.
   */
  @AuraEnabled
  public static List<FscRelHouseholdModels.LookupOption> getAccountsByIds(
    List<String> accountIds,
    Boolean personAccountsOnly
  ) {
    return SERVICE.getAccountsByIds(accountIds, personAccountsOnly);
  }

  /**
   * Returns active household member counts keyed by account id.
   */
  @AuraEnabled
  public static Map<String, Integer> getAccountMemberCounts(List<Id> accountIds) {
    return SERVICE.getAccountMemberCounts(accountIds);
  }

  @TestVisible
  private static List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput> parseMemberAccountRelationshipInputs(
    String relationshipsJson
  ) {
    if (String.isBlank(relationshipsJson)) {
      return new List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>();
    }

    return (List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>) JSON.deserialize(
      relationshipsJson,
      List<FscRelHouseholdModels.TreeMemberAccountRelationshipInput>.class
    );
  }
}