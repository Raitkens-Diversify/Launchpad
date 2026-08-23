public with sharing class OnbaseFinancialAccountConsolidation implements Database.Batchable<sObject>, Database.Stateful {

    private Id placeholderProductId;
    private Map<String, Id> acctNumToMasterId = new Map<String, Id>();
    private Set<String> existingRPKeys = new Set<String>();
    private Set<String> createdRPKeys = new Set<String>();

    public static final String PLACEHOLDER_PRODUCT_NAME = 'Onbase Placeholder';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, FinServ__FinancialAccountNumber__c, FinServ__Balance__c,
                   Wizard_Financial_Account__c, Onbase_Migration_Id__c, CreatedDate
            FROM FinServ__FinancialAccount__c
            WHERE Onbase_Migration_Id__c != null
              AND Onbase_Consolidation__c = false
            ORDER BY FinServ__FinancialAccountNumber__c, CreatedDate ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<FinServ__FinancialAccount__c> scope) {

        if (scope.isEmpty()) return;

        if (placeholderProductId == null) {
            try {
                placeholderProductId = [
                    SELECT Id FROM Product__c 
                    WHERE Name = :PLACEHOLDER_PRODUCT_NAME 
                    LIMIT 1
                ].Id;
            } catch (Exception e) {}
        }

        Set<String> acctNumsThisScope = new Set<String>();
        for (FinServ__FinancialAccount__c fa : scope)
            if (fa.FinServ__FinancialAccountNumber__c != null)
                acctNumsThisScope.add(fa.FinServ__FinancialAccountNumber__c);

        if (acctNumsThisScope.isEmpty()) return;

        List<FinServ__FinancialAccount__c> relatedAccounts = [
            SELECT Id, FinServ__FinancialAccountNumber__c, FinServ__Balance__c,
                   Wizard_Financial_Account__c, Onbase_Migration_Id__c, CreatedDate
            FROM FinServ__FinancialAccount__c
            WHERE FinServ__FinancialAccountNumber__c IN :acctNumsThisScope
              AND Onbase_Migration_Id__c != null
            ORDER BY CreatedDate ASC
        ];

        Map<String, List<FinServ__FinancialAccount__c>> acctToList = new Map<String, List<FinServ__FinancialAccount__c>>();

        for (FinServ__FinancialAccount__c r : relatedAccounts) {
            String acct = r.FinServ__FinancialAccountNumber__c;

            if (!acctToList.containsKey(acct)) {
                acctToList.put(acct, new List<FinServ__FinancialAccount__c>());
            }
            acctToList.get(acct).add(r);
        }

        Set<Id> mastersToQueryRP = new Set<Id>();

        for (String acct : acctToList.keySet()) {
            if (!acctNumToMasterId.containsKey(acct)) {
                acctNumToMasterId.put(acct, acctToList.get(acct)[0].Id);
            }
            mastersToQueryRP.add(acctNumToMasterId.get(acct));
        }

        if (!mastersToQueryRP.isEmpty()) {
            for (Financial_Account_Related_Product__c er : [
                SELECT Financial_Account__c, Onbase_Migration_Id__c
                FROM Financial_Account_Related_Product__c
                WHERE Financial_Account__c IN :mastersToQueryRP
            ]) {
                existingRPKeys.add(
                    er.Financial_Account__c + '|' + 
                    (er.Onbase_Migration_Id__c == null ? '' : er.Onbase_Migration_Id__c)
                );
            }
        }

        Map<Id, FinServ__FinancialAccount__c> deleteMap = new Map<Id, FinServ__FinancialAccount__c>();
        Map<Id, FinServ__FinancialAccount__c> updateMap = new Map<Id, FinServ__FinancialAccount__c>();
        List<Financial_Account_Related_Product__c> rpList = new List<Financial_Account_Related_Product__c>();

        for (String acct : acctToList.keySet()) {

            Id masterId = acctNumToMasterId.get(acct);
            FinServ__FinancialAccount__c masterObj;

            for (FinServ__FinancialAccount__c f : acctToList.get(acct))
                if (f.Id == masterId)
                    masterObj = f;

            String masterWizard = masterObj != null ? masterObj.Wizard_Financial_Account__c : null;

            for (FinServ__FinancialAccount__c fa : acctToList.get(acct)) {

                String mig = fa.Onbase_Migration_Id__c == null ? '' : fa.Onbase_Migration_Id__c;
                String key = masterId + '|' + mig;

                if (placeholderProductId != null &&
                    !existingRPKeys.contains(key) &&
                    !createdRPKeys.contains(key)) {

                    rpList.add(new Financial_Account_Related_Product__c(
                        Financial_Account__c = masterId,
                        Product__c = placeholderProductId,
                        Amount__c = fa.FinServ__Balance__c,
                        Onbase_Migration_Id__c = fa.Onbase_Migration_Id__c,
                        Wizard_Financial_Account__c = masterWizard
                    ));

                    createdRPKeys.add(key);
                }

                if (fa.Id != masterId) {
                    deleteMap.put(fa.Id, new FinServ__FinancialAccount__c(Id = fa.Id));
                }
            }

            updateMap.put(masterId,
                new FinServ__FinancialAccount__c(
                    Id = masterId,
                    Onbase_Consolidation__c = true
                )
            );
        }

        if (!rpList.isEmpty()) insert rpList;
        if (!deleteMap.isEmpty()) delete deleteMap.values();
        if (!updateMap.isEmpty()) update updateMap.values();
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Consolidation Completed');
    }
}