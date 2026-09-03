/**
 * Cases tab on the Account/Household/Business/Trust/Retirement Plan detail
 * page (arcHouseholdDetail). Same column set as the standardized "All Cases"
 * list (Case_List content.json): Case Number, Case, Assignee | Current Task
 * Subject, Case Overall Status, Milestone, Case Owner, Date/Time Opened,
 * Financial Advisor Team.
 *
 * A case reaches this account either directly (AccountId) or through its
 * household (Household__c) -- the same two fields ArcCaseDetailController's
 * own household-cases query already trusts (not the deprecated
 * FinServ__Household__c). For a Household record, only the second clause
 * ever matches; for everything else, the first does, and the second still
 * catches a case raised at the household level.
 */
public with sharing class ArcAccountCasesController {
  /** Matches arcRecordListView's own table page size default. */
  private static final Integer DEFAULT_PAGE_SIZE = 25;
  private static final Integer MAX_PAGE_SIZE = 100;

  @AuraEnabled(cacheable=true)
  public static CasesPage getCasesForAccount(
    Id accountId,
    Integer offsetValue,
    Integer pageSize
  ) {
    CasesPage result = new CasesPage();
    result.rows = new List<CaseRow>();
    result.hasMore = false;

    if (accountId == null) {
      return result;
    }

    Integer effectiveOffset = offsetValue == null
      ? 0
      : Math.max(offsetValue, 0);
    Integer effectivePageSize = pageSize == null
      ? DEFAULT_PAGE_SIZE
      : Math.min(Math.max(pageSize, 1), MAX_PAGE_SIZE);
    Integer queryLimit = effectivePageSize + 1;

    List<Case> records = [
      SELECT
        CaseNumber,
        Case_Branch_Name_DisplayName__c,
        Current_Task_Subject_Assignee__c,
        Current_Task_Status__c,
        Milestone__c,
        Owner.Name,
        CreatedDate,
        Financial_Advisor_Team__r.Name
      FROM Case
      WHERE AccountId = :accountId OR Household__c = :accountId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT :queryLimit
      OFFSET :effectiveOffset
    ];

    result.hasMore = records.size() > effectivePageSize;
    if (result.hasMore) {
      records.remove(effectivePageSize);
    }

    for (Case record : records) {
      CaseRow row = new CaseRow();
      row.id = record.Id;
      row.caseNumber = record.CaseNumber;
      row.caseName = record.Case_Branch_Name_DisplayName__c;
      row.currentTaskSubjectAssignee = record.Current_Task_Subject_Assignee__c;
      row.overallStatus = record.Current_Task_Status__c;
      row.milestone = record.Milestone__c;
      row.ownerName = record.Owner?.Name;
      row.createdDate = record.CreatedDate;
      row.financialAdvisorTeamName = record.Financial_Advisor_Team__r?.Name;
      result.rows.add(row);
    }

    return result;
  }

  public class CasesPage {
    @AuraEnabled
    public List<CaseRow> rows;
    @AuraEnabled
    public Boolean hasMore;
  }

  public class CaseRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String caseName;
    @AuraEnabled
    public String currentTaskSubjectAssignee;
    @AuraEnabled
    public String overallStatus;
    @AuraEnabled
    public String milestone;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String financialAdvisorTeamName;
  }
}