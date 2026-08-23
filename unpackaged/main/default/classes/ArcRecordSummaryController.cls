/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Loads the read-only Record summary card for Experience Cloud account pages.
 */
public with sharing class ArcRecordSummaryController {

  @AuraEnabled(cacheable=true)
  public static RecordSummaryContext load(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account Id is required.');
    }

    if (accountId.getSObjectType() != Account.SObjectType) {
      throw new AuraHandledException('Record is not an Account.');
    }

    List<Account> accounts = [
      SELECT
        Id,
        Type,
        CreatedDate,
        Classification__c,
        RecordType.DeveloperName,
        RecordType.Name,
        Household__c,
        Household__r.Name,
        Financial_Advisor_Team__r.Primary_Financial_Advisor__r.FirstName,
        Financial_Advisor_Team__r.Primary_Financial_Advisor__r.LastName,
        Financial_Advisor_Team__r.Primary_Financial_Advisor__r.Name
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];

    if (accounts.isEmpty()) {
      throw new AuraHandledException('Account not found.');
    }

    Account account = accounts[0];
    List<String> roles = loadMemberRoles(accountId);

    RecordSummaryContext context = new RecordSummaryContext();
    context.recordTypeDeveloperName = account.RecordType?.DeveloperName;
    context.recordTypeLabel = account.RecordType?.Name;
    context.accountType = account.Type;
    context.roles = roles;
    context.classification = account.Classification__c;
    context.householdId = account.Household__c;
    context.householdName = account.Household__r?.Name;
    context.primaryAdvisorName = resolvePrimaryAdvisorName(account);
    context.createdDate = account.CreatedDate;
    context.status = account.Type;
    return context;
  }

  private static String resolvePrimaryAdvisorName(Account account) {
    if (account?.Financial_Advisor_Team__r?.Primary_Financial_Advisor__r == null) {
      return null;
    }

    User advisor = account.Financial_Advisor_Team__r.Primary_Financial_Advisor__r;
    List<String> parts = new List<String>();

    if (String.isNotBlank(advisor.FirstName)) {
      parts.add(advisor.FirstName.trim());
    }

    if (String.isNotBlank(advisor.LastName)) {
      parts.add(advisor.LastName.trim());
    }

    if (!parts.isEmpty()) {
      return String.join(parts, ' ');
    }

    return advisor.Name;
  }

  private static List<String> loadMemberRoles(Id accountId) {
    List<String> roles = new List<String>();
    Set<String> seen = new Set<String>();

    for (Account_Account_Relationship__c relation : [
      SELECT Roles__c
      FROM Account_Account_Relationship__c
      WHERE Related_Account__c = :accountId AND Active__c = TRUE
    ]) {
      for (String role : FscRelRoleUtils.parseRoles(relation.Roles__c)) {
        if (String.isBlank(role) || seen.contains(role)) {
          continue;
        }

        seen.add(role);
        roles.add(role);
      }
    }

    return roles;
  }

  public class RecordSummaryContext {
    @AuraEnabled
    public String recordTypeDeveloperName;

    @AuraEnabled
    public String recordTypeLabel;

    @AuraEnabled
    public String accountType;

    @AuraEnabled
    public List<String> roles;

    @AuraEnabled
    public String classification;

    @AuraEnabled
    public Id householdId;

    @AuraEnabled
    public String householdName;

    @AuraEnabled
    public String primaryAdvisorName;

    @AuraEnabled
    public Datetime createdDate;

    @AuraEnabled
    public String status;
  }
}