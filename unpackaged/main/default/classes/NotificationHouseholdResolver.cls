/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Resolves household Account Ids from Case, Task, and Event source records.
 */
public with sharing class NotificationHouseholdResolver {
  private final FscRelHouseholdService householdService;

  public NotificationHouseholdResolver() {
    this(new FscRelHouseholdService());
  }

  @TestVisible
  private NotificationHouseholdResolver(FscRelHouseholdService householdService) {
    this.householdService = householdService;
  }

  public Map<Id, Id> resolveHouseholds(List<SObject> records, String sourceType) {
    Map<Id, Id> recordIdToHouseholdId = new Map<Id, Id>();
    if (records == null || records.isEmpty()) {
      return recordIdToHouseholdId;
    }

    if (sourceType == NotificationConstants.OBJECT_TYPE_CASE) {
      return resolveFromCases(records);
    }

    return resolveFromWhatIdRecords(records);
  }

  private Map<Id, Id> resolveFromCases(List<SObject> records) {
    Map<Id, Id> recordIdToHouseholdId = new Map<Id, Id>();
    Set<Id> financialAccountIds = new Set<Id>();

    for (SObject record : records) {
      Case caseRecord = (Case) record;
      if (caseRecord.AccountId != null) {
        recordIdToHouseholdId.put(caseRecord.Id, caseRecord.AccountId);
        continue;
      }

      Id financialAccountId = (Id) caseRecord.get('FinServ__FinancialAccount__c');
      if (financialAccountId != null) {
        financialAccountIds.add(financialAccountId);
      }
    }

    if (financialAccountIds.isEmpty()) {
      return recordIdToHouseholdId;
    }

    Map<Id, Id> financialAccountIdToHouseholdId = queryFinancialAccountHouseholds(
      financialAccountIds
    );

    for (SObject record : records) {
      Case caseRecord = (Case) record;
      if (recordIdToHouseholdId.containsKey(caseRecord.Id)) {
        continue;
      }

      Id financialAccountId = (Id) caseRecord.get('FinServ__FinancialAccount__c');
      Id householdId = financialAccountIdToHouseholdId.get(financialAccountId);
      if (householdId != null) {
        recordIdToHouseholdId.put(caseRecord.Id, householdId);
      }
    }

    return recordIdToHouseholdId;
  }

  private Map<Id, Id> resolveFromWhatIdRecords(List<SObject> records) {
    Map<Id, Id> recordIdToHouseholdId = new Map<Id, Id>();
    Set<Id> accountWhatIds = new Set<Id>();
    Set<Id> caseWhatIds = new Set<Id>();
    Set<Id> opportunityWhatIds = new Set<Id>();

    for (SObject record : records) {
      Id whatId = (Id) record.get('WhatId');
      if (whatId == null) {
        continue;
      }

      String prefix = String.valueOf(whatId).substring(0, 3);
      if (prefix == '001') {
        accountWhatIds.add(whatId);
      } else if (prefix == '500') {
        caseWhatIds.add(whatId);
      } else if (prefix == '006') {
        opportunityWhatIds.add(whatId);
      }
    }

    Map<Id, Id> accountIdToHouseholdId = resolveAccountIdsToHouseholds(accountWhatIds);
    Map<Id, Id> caseIdToHouseholdId = resolveCaseIdsToHouseholds(caseWhatIds);
    Map<Id, Id> opportunityIdToAccountId = queryOpportunityAccounts(opportunityWhatIds);

    Set<Id> opportunityAccountIds = new Set<Id>(opportunityIdToAccountId.values());
    Map<Id, Id> opportunityAccountToHouseholdId = resolveAccountIdsToHouseholds(
      opportunityAccountIds
    );

    for (SObject record : records) {
      Id whatId = (Id) record.get('WhatId');
      if (whatId == null) {
        continue;
      }

      String prefix = String.valueOf(whatId).substring(0, 3);
      Id householdId;

      if (prefix == '001') {
        householdId = accountIdToHouseholdId.get(whatId);
      } else if (prefix == '500') {
        householdId = caseIdToHouseholdId.get(whatId);
      } else if (prefix == '006') {
        Id accountId = opportunityIdToAccountId.get(whatId);
        householdId = opportunityAccountToHouseholdId.get(accountId);
      }

      if (householdId != null) {
        recordIdToHouseholdId.put(record.Id, householdId);
      }
    }

    return recordIdToHouseholdId;
  }

  private Map<Id, Id> resolveAccountIdsToHouseholds(Set<Id> accountIds) {
    Map<Id, Id> accountIdToHouseholdId = new Map<Id, Id>();
    if (accountIds == null || accountIds.isEmpty()) {
      return accountIdToHouseholdId;
    }

    for (Id accountId : accountIds) {
      FscRelHouseholdModels.RootAccountResolveResult resolveResult = householdService.resolveRootAccount(
        accountId
      );
      if (resolveResult.rootAccountId != null) {
        accountIdToHouseholdId.put(accountId, resolveResult.rootAccountId);
      }
    }

    return accountIdToHouseholdId;
  }

  private Map<Id, Id> resolveCaseIdsToHouseholds(Set<Id> caseIds) {
    Map<Id, Id> caseIdToHouseholdId = new Map<Id, Id>();
    if (caseIds == null || caseIds.isEmpty()) {
      return caseIdToHouseholdId;
    }

    for (Case caseRecord : [
      SELECT Id, AccountId, FinServ__FinancialAccount__c
      FROM Case
      WHERE Id IN :caseIds
    ]) {
      if (caseRecord.AccountId != null) {
        Id householdId = resolveAccountIdsToHouseholds(
            new Set<Id>{ caseRecord.AccountId }
          )
          .get(caseRecord.AccountId);
        if (householdId != null) {
          caseIdToHouseholdId.put(caseRecord.Id, householdId);
        }
      }
    }

    Set<Id> unresolvedCaseIds = new Set<Id>();
    Set<Id> financialAccountIds = new Set<Id>();

    for (Id caseId : caseIds) {
      if (caseIdToHouseholdId.containsKey(caseId)) {
        continue;
      }
      unresolvedCaseIds.add(caseId);
    }

    if (unresolvedCaseIds.isEmpty()) {
      return caseIdToHouseholdId;
    }

    for (Case caseRecord : [
      SELECT Id, FinServ__FinancialAccount__c
      FROM Case
      WHERE Id IN :unresolvedCaseIds
    ]) {
      Id financialAccountId = (Id) caseRecord.get('FinServ__FinancialAccount__c');
      if (financialAccountId != null) {
        financialAccountIds.add(financialAccountId);
      }
    }

    Map<Id, Id> financialAccountIdToHouseholdId = queryFinancialAccountHouseholds(
      financialAccountIds
    );

    for (Case caseRecord : [
      SELECT Id, FinServ__FinancialAccount__c
      FROM Case
      WHERE Id IN :unresolvedCaseIds
    ]) {
      Id financialAccountId = (Id) caseRecord.get('FinServ__FinancialAccount__c');
      Id householdId = financialAccountIdToHouseholdId.get(financialAccountId);
      if (householdId != null) {
        caseIdToHouseholdId.put(caseRecord.Id, householdId);
      }
    }

    return caseIdToHouseholdId;
  }

  private Map<Id, Id> queryFinancialAccountHouseholds(Set<Id> financialAccountIds) {
    Map<Id, Id> financialAccountIdToHouseholdId = new Map<Id, Id>();
    if (financialAccountIds == null || financialAccountIds.isEmpty()) {
      return financialAccountIdToHouseholdId;
    }

    for (SObject financialAccount : Database.query(
      'SELECT Id, FinServ__Household__c FROM FinServ__FinancialAccount__c WHERE Id IN :financialAccountIds'
    )) {
      Id householdId = (Id) financialAccount.get('FinServ__Household__c');
      if (householdId != null) {
        financialAccountIdToHouseholdId.put(financialAccount.Id, householdId);
      }
    }

    return financialAccountIdToHouseholdId;
  }

  private Map<Id, Id> queryOpportunityAccounts(Set<Id> opportunityIds) {
    Map<Id, Id> opportunityIdToAccountId = new Map<Id, Id>();
    if (opportunityIds == null || opportunityIds.isEmpty()) {
      return opportunityIdToAccountId;
    }

    for (Opportunity opportunity : [
      SELECT Id, AccountId
      FROM Opportunity
      WHERE Id IN :opportunityIds
    ]) {
      if (opportunity.AccountId != null) {
        opportunityIdToAccountId.put(opportunity.Id, opportunity.AccountId);
      }
    }

    return opportunityIdToAccountId;
  }
}