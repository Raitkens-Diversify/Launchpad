/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Loads account header context for arcAccountHeader on Experience Cloud record pages.
 */
public with sharing class ArcAccountHeaderController {

  @AuraEnabled(cacheable=true)
  public static AccountHeaderContext load(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account Id is required.');
    }

    if (accountId.getSObjectType() != Account.SObjectType) {
      throw new AuraHandledException('Record is not an Account.');
    }

    List<Account> accounts = [
      SELECT
        Id,
        Name,
        FirstName,
        LastName,
        PhotoUrl,
        IsPersonAccount,
        Type,
        RecordType.DeveloperName,
        RecordType.Name
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

    AccountHeaderContext context = new AccountHeaderContext();
    context.accountId = account.Id;
    context.name = resolveDisplayName(account);
    context.photoUrl = account.PhotoUrl;
    context.isPersonAccount = account.IsPersonAccount == true;
    context.recordTypeDeveloperName = account.RecordType?.DeveloperName;
    context.recordTypeLabel = account.RecordType?.Name;
    context.accountType = account.Type;
    context.roles = roles;
    return context;
  }

  private static String resolveDisplayName(Account account) {
    if (account == null) {
      return '';
    }

    if (account.IsPersonAccount == true) {
      List<String> parts = new List<String>();

      if (String.isNotBlank(account.FirstName)) {
        parts.add(account.FirstName.trim());
      }

      if (String.isNotBlank(account.LastName)) {
        parts.add(account.LastName.trim());
      }

      if (!parts.isEmpty()) {
        return String.join(parts, ' ');
      }
    }

    return account.Name;
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

  public class AccountHeaderContext {
    @AuraEnabled
    public Id accountId;

    @AuraEnabled
    public String name;

    @AuraEnabled
    public String photoUrl;

    @AuraEnabled
    public Boolean isPersonAccount;

    @AuraEnabled
    public String recordTypeDeveloperName;

    @AuraEnabled
    public String recordTypeLabel;

    @AuraEnabled
    public String accountType;

    @AuraEnabled
    public List<String> roles;
  }
}