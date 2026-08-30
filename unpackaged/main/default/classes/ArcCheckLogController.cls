/**
 * Header context and related-list data for ARC's Check Log detail page,
 * mirroring the Lightning Check_Log_Record_Page: the highlights identity
 * (client, financial account, amount, case), the Check Deposits related list
 * with the same columns Lightning shows (Name, Financial Account, Account
 * Number, Amount), the attached files, and a full read-only view of one
 * check deposit for the quick-view popup.
 *
 * Field-level rendering of the check log itself stays with the generic
 * Envelope_Field__mdt pipeline (ArcRecordDetailController); this controller
 * only supplies what that pipeline cannot: FinServ__FinancialAccount__c
 * identity (invisible to portal users — see ArcFinServAccountLabels) and
 * the stitched deposit/file rows.
 *
 * Everything the user reaches here is read under USER_MODE first; only the
 * FinServ account labels for ids found on those rows come from the
 * system-mode resolver.
 */
public with sharing class ArcCheckLogController {
  @AuraEnabled(cacheable=true)
  public static CheckLogContext getCheckLogContext(Id checkLogId) {
    CheckLogContext context = new CheckLogContext();
    if (checkLogId == null) {
      return context;
    }

    // toLabel so a renamed picklist entry shows what Lightning shows
    // (e.g. API value "Remote Deposit" is labeled "Mobile Deposit").
    List<Check_Log__c> matches = [
      SELECT
        Name,
        TOLABEL(Status__c),
        TOLABEL(Review_Status__c),
        Amount__c,
        TOLABEL(Method_of_Forwarding__c),
        Received_Date__c,
        Client__c,
        Client__r.Name,
        Case__c,
        Case__r.CaseNumber,
        Financial_Account__c,
        Wizard_Financial_Account__c,
        Wizard_Financial_Account__r.Name
      FROM Check_Log__c
      WHERE Id = :checkLogId
      WITH USER_MODE
      LIMIT 1
    ];
    if (matches.isEmpty()) {
      return context;
    }

    Check_Log__c record = matches[0];
    context.name = record.Name;
    context.status = record.Status__c;
    context.reviewStatus = record.Review_Status__c;
    context.amount = record.Amount__c;
    context.methodOfForwarding = record.Method_of_Forwarding__c;
    context.receivedDate = record.Received_Date__c;
    context.clientId = record.Client__c;
    context.clientName = record.Client__r != null ? record.Client__r.Name : null;
    context.caseId = record.Case__c;
    context.caseNumber = record.Case__r != null ? record.Case__r.CaseNumber : null;
    context.wizardFinancialAccountId = record.Wizard_Financial_Account__c;
    context.wizardFinancialAccountName = record.Wizard_Financial_Account__r != null
      ? record.Wizard_Financial_Account__r.Name
      : null;

    if (record.Financial_Account__c != null) {
      ArcFinServAccountLabels.Entry label = ArcFinServAccountLabels.resolve(
          new Set<Id>{ record.Financial_Account__c }
        )
        .get(record.Financial_Account__c);
      if (label != null) {
        context.financialAccountName = label.name;
        context.financialAccountNumber = label.accountNumber;
      }
    }

    return context;
  }

  /**
   * The check log's deposits with the Lightning related list's columns.
   * Financial account name/number are stitched in from the system-mode
   * resolver because the lookup targets the FinServ account.
   */
  @AuraEnabled(cacheable=true)
  public static List<CheckDepositInfo> getCheckDeposits(Id checkLogId) {
    List<CheckDepositInfo> results = new List<CheckDepositInfo>();
    if (checkLogId == null) {
      return results;
    }

    List<Check_Deposit__c> deposits = [
      SELECT Id, Name, Amount__c, Financial_Account__c
      FROM Check_Deposit__c
      WHERE Check__c = :checkLogId
      WITH USER_MODE
      ORDER BY Name ASC
      LIMIT 200
    ];

    Set<Id> accountIds = new Set<Id>();
    for (Check_Deposit__c deposit : deposits) {
      if (deposit.Financial_Account__c != null) {
        accountIds.add(deposit.Financial_Account__c);
      }
    }
    Map<Id, ArcFinServAccountLabels.Entry> labels = ArcFinServAccountLabels.resolve(
      accountIds
    );

    for (Check_Deposit__c deposit : deposits) {
      CheckDepositInfo info = new CheckDepositInfo();
      info.id = deposit.Id;
      info.name = deposit.Name;
      info.amount = deposit.Amount__c;
      ArcFinServAccountLabels.Entry label = labels.get(deposit.Financial_Account__c);
      if (label != null) {
        info.financialAccountName = label.name;
        info.financialAccountNumber = label.accountNumber;
      }
      results.add(info);
    }
    return results;
  }

  /** Every field on one deposit, for the read-only quick-view popup. */
  @AuraEnabled(cacheable=true)
  public static CheckDepositDetail getCheckDeposit(Id checkDepositId) {
    if (checkDepositId == null) {
      return null;
    }

    List<Check_Deposit__c> matches = [
      SELECT
        Id,
        Name,
        Amount__c,
        Employee_Deferral_Amount__c,
        Employer_Contribution_Amount__c,
        Financial_Account__c,
        Check__c,
        Check__r.Name,
        CreatedDate,
        CreatedBy.Name,
        LastModifiedDate,
        LastModifiedBy.Name
      FROM Check_Deposit__c
      WHERE Id = :checkDepositId
      WITH USER_MODE
      LIMIT 1
    ];
    if (matches.isEmpty()) {
      return null;
    }

    Check_Deposit__c deposit = matches[0];
    CheckDepositDetail detail = new CheckDepositDetail();
    detail.id = deposit.Id;
    detail.name = deposit.Name;
    detail.amount = deposit.Amount__c;
    detail.employeeDeferralAmount = deposit.Employee_Deferral_Amount__c;
    detail.employerContributionAmount = deposit.Employer_Contribution_Amount__c;
    detail.checkLogId = deposit.Check__c;
    detail.checkLogName = deposit.Check__r != null ? deposit.Check__r.Name : null;
    detail.createdDate = deposit.CreatedDate;
    detail.createdByName = deposit.CreatedBy != null ? deposit.CreatedBy.Name : null;
    detail.lastModifiedDate = deposit.LastModifiedDate;
    detail.lastModifiedByName = deposit.LastModifiedBy != null
      ? deposit.LastModifiedBy.Name
      : null;

    if (deposit.Financial_Account__c != null) {
      ArcFinServAccountLabels.Entry label = ArcFinServAccountLabels.resolve(
          new Set<Id>{ deposit.Financial_Account__c }
        )
        .get(deposit.Financial_Account__c);
      if (label != null) {
        detail.financialAccountName = label.name;
        detail.financialAccountNumber = label.accountNumber;
      }
    }

    return detail;
  }

  /** The files attached to the check log, for the Files card. Opening a
   *  file's bytes lives in ArcFileViewerController (its own class for an
   *  invoker-registry reason documented there). */
  @AuraEnabled(cacheable=true)
  public static List<FileInfo> getCheckLogFiles(Id checkLogId) {
    List<FileInfo> results = new List<FileInfo>();
    if (checkLogId == null) {
      return results;
    }

    for (ContentDocumentLink link : [
      SELECT
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.FileExtension,
        ContentDocument.ContentSize,
        ContentDocument.ContentModifiedDate
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :checkLogId
      WITH USER_MODE
      ORDER BY ContentDocument.ContentModifiedDate DESC
      LIMIT 100
    ]) {
      FileInfo info = new FileInfo();
      info.contentDocumentId = link.ContentDocumentId;
      info.title = link.ContentDocument.Title;
      info.fileExtension = link.ContentDocument.FileExtension;
      info.contentSize = link.ContentDocument.ContentSize;
      info.contentModifiedDate = link.ContentDocument.ContentModifiedDate;
      results.add(info);
    }
    return results;
  }

  public class CheckLogContext {
    @AuraEnabled
    public String name;

    @AuraEnabled
    public String status;

    @AuraEnabled
    public String reviewStatus;

    @AuraEnabled
    public Decimal amount;

    @AuraEnabled
    public String methodOfForwarding;

    @AuraEnabled
    public Date receivedDate;

    @AuraEnabled
    public Id clientId;

    @AuraEnabled
    public String clientName;

    @AuraEnabled
    public Id caseId;

    @AuraEnabled
    public String caseNumber;

    /** FinServ account identity — no id is exposed because the site has no
     *  page for it; the wizard account below is the routable one. */
    @AuraEnabled
    public String financialAccountName;

    @AuraEnabled
    public String financialAccountNumber;

    @AuraEnabled
    public Id wizardFinancialAccountId;

    @AuraEnabled
    public String wizardFinancialAccountName;
  }

  public class CheckDepositInfo {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public String name;

    @AuraEnabled
    public String financialAccountName;

    @AuraEnabled
    public String financialAccountNumber;

    @AuraEnabled
    public Decimal amount;
  }

  public class CheckDepositDetail {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public String name;

    @AuraEnabled
    public String financialAccountName;

    @AuraEnabled
    public String financialAccountNumber;

    @AuraEnabled
    public Decimal amount;

    @AuraEnabled
    public Decimal employeeDeferralAmount;

    @AuraEnabled
    public Decimal employerContributionAmount;

    @AuraEnabled
    public Id checkLogId;

    @AuraEnabled
    public String checkLogName;

    @AuraEnabled
    public Datetime createdDate;

    @AuraEnabled
    public String createdByName;

    @AuraEnabled
    public Datetime lastModifiedDate;

    @AuraEnabled
    public String lastModifiedByName;
  }

  public class FileInfo {
    @AuraEnabled
    public Id contentDocumentId;

    @AuraEnabled
    public String title;

    @AuraEnabled
    public String fileExtension;

    @AuraEnabled
    public Integer contentSize;

    @AuraEnabled
    public Datetime contentModifiedDate;
  }
}