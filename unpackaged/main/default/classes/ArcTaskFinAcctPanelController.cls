/**
 * Financial Account Details panel embedded on ARC's Task detail page -- the
 * ARC equivalent of the Lightning Task page's console:relatedRecord
 * "Financial Account Details" component (Task_Record_Page, visible when the
 * task's WhatId is a Case and its Subject calls for an account number),
 * which follows Task.DFPG_Financial_Account__c and edits Financial_Account__c
 * through the Update Account Number quick action. That quick action only
 * ever exposes Name and Account_Number__c, so this does the same, nothing
 * more. Not to be confused with arcFinancialAccountDetail, the unrelated
 * full Financial_Account__c record page.
 */
public with sharing class ArcTaskFinAcctPanelController {
  @AuraEnabled(cacheable=true)
  public static FinancialAccountDetail getFinancialAccountDetail(Id taskId) {
    FinancialAccountDetail result = new FinancialAccountDetail();
    if (taskId == null) {
      return result;
    }

    List<Task> tasks = [
      SELECT DFPG_Financial_Account__c
      FROM Task
      WHERE Id = :taskId
      WITH USER_MODE
      LIMIT 1
    ];
    if (tasks.isEmpty() || tasks[0].DFPG_Financial_Account__c == null) {
      return result;
    }

    List<Financial_Account__c> accounts = [
      SELECT Id, Name, Account_Number__c
      FROM Financial_Account__c
      WHERE Id = :tasks[0].DFPG_Financial_Account__c
      WITH USER_MODE
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      return result;
    }

    result.financialAccountId = accounts[0].Id;
    result.name = accounts[0].Name;
    result.accountNumber = accounts[0].Account_Number__c;
    return result;
  }

  @AuraEnabled
  public static FinancialAccountDetail saveFinancialAccountDetail(
    Id financialAccountId,
    String name,
    String accountNumber
  ) {
    if (financialAccountId == null) {
      throw newAuraError('Financial account is required.');
    }
    if (String.isBlank(name)) {
      throw newAuraError('Financial Account Name is required.');
    }

    SObjectAccessDecision decision = Security.stripInaccessible(
      AccessType.UPDATABLE,
      new List<Financial_Account__c>{
        new Financial_Account__c(
          Id = financialAccountId,
          Name = name,
          Account_Number__c = accountNumber
        )
      }
    );

    try {
      update decision.getRecords();
    } catch (DmlException e) {
      throw newAuraError(formatDmlMessage(e));
    }

    FinancialAccountDetail result = new FinancialAccountDetail();
    result.financialAccountId = financialAccountId;
    result.name = name;
    result.accountNumber = accountNumber;
    return result;
  }

  private static String formatDmlMessage(DmlException error) {
    if (error == null) {
      return 'Something went wrong while saving the financial account. Please try again.';
    }
    if (error.getNumDml() > 0) {
      return error.getDmlMessage(0);
    }
    return error.getMessage();
  }

  /**
   * AuraHandledException's constructor message is only for the platform's
   * own logging -- getMessage() (what a client-side .body.message reads,
   * and what a test's catch block sees) returns the generic "Script-thrown
   * exception" unless setMessage() is also called explicitly.
   */
  private static AuraHandledException newAuraError(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }

  public class FinancialAccountDetail {
    @AuraEnabled
    public Id financialAccountId;

    @AuraEnabled
    public String name;

    @AuraEnabled
    public String accountNumber;
  }
}