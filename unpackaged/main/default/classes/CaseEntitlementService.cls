/**
 * Assigns Case.EntitlementId from the Account's Active Entitlement.
 * Invoked when the Home Office Submission milestone Task completes (not on Case insert).
 * Clears EntitlementId before Case delete so entitlement-linked Cases can be deleted.
 */
public with sharing class CaseEntitlementService {
    private static Boolean clearingEntitlementOnDelete = false;

    /**
     * Sets EntitlementId on Cases that have AccountId and a blank EntitlementId.
     * When multiple Active Entitlements exist for an Account, takes the most recently created.
     */
    public static void assignEntitlementIds(List<Case> cases) {
        if (cases == null || cases.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Case caseRecord : cases) {
            if (caseRecord.AccountId != null && caseRecord.EntitlementId == null) {
                accountIds.add(caseRecord.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Id> accountIdToEntitlementId = queryActiveEntitlementsByAccount(accountIds);
        for (Case caseRecord : cases) {
            if (caseRecord.AccountId == null || caseRecord.EntitlementId != null) {
                continue;
            }
            Id entitlementId = accountIdToEntitlementId.get(caseRecord.AccountId);
            if (entitlementId != null) {
                caseRecord.EntitlementId = entitlementId;
            }
        }
    }

    /**
     * Before Case delete: clear EntitlementId via update so delete can proceed.
     * Field edits on Trigger.old are not persisted; a separate update is required.
     */
    public static void clearEntitlementIdsBeforeDelete(List<Case> cases) {
        if (clearingEntitlementOnDelete || cases == null || cases.isEmpty()) {
            return;
        }

        List<Case> casesToClear = new List<Case>();
        for (Case caseRecord : cases) {
            if (caseRecord.EntitlementId != null) {
                casesToClear.add(new Case(Id = caseRecord.Id, EntitlementId = null));
            }
        }
        if (casesToClear.isEmpty()) {
            return;
        }

        clearingEntitlementOnDelete = true;
        try {
            update casesToClear;
        } finally {
            clearingEntitlementOnDelete = false;
        }
    }

    private static Map<Id, Id> queryActiveEntitlementsByAccount(Set<Id> accountIds) {
        Map<Id, Id> accountIdToEntitlementId = new Map<Id, Id>();
        for (Entitlement entitlementRecord : [
            SELECT Id, AccountId
            FROM Entitlement
            WHERE AccountId IN :accountIds
                AND Status = 'Active'
            ORDER BY CreatedDate DESC
        ]) {
            if (!accountIdToEntitlementId.containsKey(entitlementRecord.AccountId)) {
                accountIdToEntitlementId.put(entitlementRecord.AccountId, entitlementRecord.Id);
            }
        }
        return accountIdToEntitlementId;
    }
}