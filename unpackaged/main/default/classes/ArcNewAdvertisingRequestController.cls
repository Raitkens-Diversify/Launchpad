/**
 * Backs the Home dashboard's "New Advertising Request" modal (c:arcNewAdvertisingRequestModal),
 * which replicates Case_Screen_Flow_New_Ad_Hoc_Case as an in-page dialog instead of a full-screen
 * flow: an Account (household) search, the same handful of Case fields, and on save the same
 * field assignments the flow's Set_Case/Create_Case elements perform.
 */
public with sharing class ArcNewAdvertisingRequestController {
  public class AccountOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
  }

  /** Name-contains search for the Account Name lookup, capped to a short typeahead list. */
  @AuraEnabled(cacheable=true)
  public static List<AccountOption> searchAccounts(String term) {
    String cleanTerm = (term == null) ? '' : term.trim();
    if (cleanTerm.length() < 2) {
      return new List<AccountOption>();
    }

    String likeTerm = '%' + String.escapeSingleQuotes(cleanTerm) + '%';
    List<AccountOption> results = new List<AccountOption>();
    for (Account record : [
      SELECT Id, Name
      FROM Account
      WHERE Name LIKE :likeTerm
      WITH USER_MODE
      ORDER BY Name
      LIMIT 10
    ]) {
      AccountOption option = new AccountOption();
      option.id = record.Id;
      option.name = record.Name;
      results.add(option);
    }
    return results;
  }

  /**
   * Creates the Ad Hoc Case. Mirrors the flow's Get_Household -> Set_Case -> Create_Case path:
   * RecordTypeId comes from the same Wizard_Flow_Values__mdt record the flow reads (rather than a
   * hardcoded Id, which would be sandbox-specific), Origin is hardcoded to "Ad Hoc", and both
   * AccountId and FinServ__Household__c point at the selected Account — the flow assigns the same
   * Account Id to both.
   */
  @AuraEnabled
  public static Id createAdvertisingRequest(
    Id accountId,
    String subject,
    String description,
    String priority,
    String status
  ) {
    if (accountId == null) {
      throw new AuraHandledException('Account is required.');
    }
    if (String.isBlank(subject)) {
      throw new AuraHandledException('Subject is required.');
    }
    if (String.isBlank(priority)) {
      throw new AuraHandledException('Priority is required.');
    }
    if (String.isBlank(status)) {
      throw new AuraHandledException('Status is required.');
    }

    List<Wizard_Flow_Values__mdt> metadataRows = [
      SELECT Case_Ad_Hoc_Record_Type_Id__c
      FROM Wizard_Flow_Values__mdt
      LIMIT 1
    ];
    if (
      metadataRows.isEmpty() ||
      metadataRows[0].Case_Ad_Hoc_Record_Type_Id__c == null
    ) {
      throw new AuraHandledException(
        'Ad Hoc Case record type is not configured (Wizard_Flow_Values__mdt).'
      );
    }

    List<Account> households = [
      SELECT Id, Financial_Advisor_Team__c
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (households.isEmpty()) {
      throw new AuraHandledException('Account not found.');
    }
    Account household = households[0];

    Case newCase = new Case(
      RecordTypeId = metadataRows[0].Case_Ad_Hoc_Record_Type_Id__c,
      Subject = subject,
      Description = description,
      Priority = priority,
      Status = status,
      Origin = 'Ad Hoc',
      OwnerId = UserInfo.getUserId(),
      AccountId = household.Id,
      FinServ__Household__c = household.Id,
      Financial_Advisor_Team__c = household.Financial_Advisor_Team__c
    );

    insert newCase;
    return newCase.Id;
  }
}