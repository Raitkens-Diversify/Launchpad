public class AccountEntitlementQueueable implements Queueable {
    private Set<Id> accountIds;

    public AccountEntitlementQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds == null ? new Set<Id>() : accountIds;
    }

    public void execute(QueueableContext context) {
        if (accountIds.isEmpty()) {
            return;
        }

        try {
            List<Case_Entitlement_Values__mdt> entitlementValues = [
                SELECT Business_Hours__c, SLA_Policy__c
                FROM Case_Entitlement_Values__mdt
                LIMIT 1
            ];
            if (entitlementValues.isEmpty()
                || String.isBlank(entitlementValues[0].Business_Hours__c)
                || String.isBlank(entitlementValues[0].SLA_Policy__c)) {
                return;
            }

            List<BusinessHours> businessHoursList = [
                SELECT Id
                FROM BusinessHours
                WHERE Name = :entitlementValues[0].Business_Hours__c
                LIMIT 1
            ];
            List<SlaProcess> slaProcessList = [
                SELECT Id
                FROM SlaProcess
                WHERE Name = :entitlementValues[0].SLA_Policy__c
                LIMIT 1
            ];
            if (businessHoursList.isEmpty() || slaProcessList.isEmpty()) {
                return;
            }

            Id businessHoursId = businessHoursList[0].Id;
            Id slaProcessId = slaProcessList[0].Id;

            Set<Id> accountsWithStandardSla = new Set<Id>();
            for (Entitlement existingEntitlement : [
                SELECT AccountId
                FROM Entitlement
                WHERE AccountId IN :accountIds
                    AND Name LIKE '% - Standard SLA'
            ]) {
                accountsWithStandardSla.add(existingEntitlement.AccountId);
            }

            List<Entitlement> entitlementsToInsert = new List<Entitlement>();
            for (Account accountRecord : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :accountIds
            ]) {
                if (accountsWithStandardSla.contains(accountRecord.Id)) {
                    continue;
                }
                entitlementsToInsert.add(new Entitlement(
                    Name = accountRecord.Name + ' - Standard SLA',
                    StartDate = Date.today(),
                    BusinessHoursId = businessHoursId,
                    SlaProcessId = slaProcessId,
                    AccountId = accountRecord.Id
                ));
            }

            if (!entitlementsToInsert.isEmpty()) {
                Database.insert(entitlementsToInsert, false);
            }
        } catch (Exception ex) {
            System.debug(
                'AccountEntitlementQueueable exception at line '
                + ex.getLineNumber() + ': ' + ex.getMessage()
            );
        }
    }
}