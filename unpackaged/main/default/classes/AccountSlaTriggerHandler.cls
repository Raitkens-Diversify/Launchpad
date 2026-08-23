/**
 * Account trigger entry for Standard SLA automation.
 * After insert/update: enqueue Standard SLA Entitlement creation when Submitted__c becomes true.
 */
public with sharing class AccountSlaTriggerHandler {
    public void isAfterInsert(Map<Id, Account> newMap) {
        enqueueStandardEntitlement(newMap, null);
    }

    public void isAfterUpdate(Map<Id, Account> newMap, Map<Id, Account> oldMap) {
        enqueueStandardEntitlement(newMap, oldMap);
    }

    private void enqueueStandardEntitlement(Map<Id, Account> newMap, Map<Id, Account> oldMap) {
        if (newMap == null || newMap.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Account newAccount : newMap.values()) {
            if (newAccount.Submitted__c != true) {
                continue;
            }
            if (oldMap == null) {
                accountIds.add(newAccount.Id);
                continue;
            }
            Account oldAccount = oldMap.get(newAccount.Id);
            if (oldAccount == null || oldAccount.Submitted__c != true) {
                accountIds.add(newAccount.Id);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new AccountEntitlementQueueable(accountIds));
    }
}