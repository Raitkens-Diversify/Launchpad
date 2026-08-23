global class CreateCasesAndTasksBatch 
implements Database.Batchable<SObject>, Database.Stateful {

    // Query Locator
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Custodian__c, Financial_Advisor_Team__c, ' +
            'FinServ__Household__c, FinServ__PrimaryOwner__r.PersonContactId, ' +
            'Wizard_Financial_Account__c, Rep_Code__c, Rep_Code_Lookup__r.Name ' +
            'FROM FinServ__FinancialAccount__c ' +
            'WHERE Maestro_Load__c = TRUE ' +
            'AND CreatedBy.Name = \'Jonathan Yu\''
        );
    }

    // Execute logic per batch
    global void execute(Database.BatchableContext bc, 
                        List<FinServ__FinancialAccount__c> finAccts) {

        List<Case> casesToInsert = new List<Case>();
        Map<Id, FinServ__FinancialAccount__c> faMap = new Map<Id, FinServ__FinancialAccount__c>();

        // Create Cases & prepare FA updates
        for (FinServ__FinancialAccount__c f : finAccts) {

            Case c = new Case();
            c.Origin = 'Transition';
            c.AccountId = f.FinServ__Household__c;
            c.FinServ__Household__c = f.FinServ__Household__c;
            c.ContactId = f.FinServ__PrimaryOwner__r.PersonContactId;
            c.Subject = 'Transition - Maestro Loader';
            c.Financial_Advisor_Team__c = f.Financial_Advisor_Team__c;
            c.Custodian__c = f.Custodian__c;
            c.Status = 'Closed';
            c.FinServ__FinancialAccount__c = f.Id;
            c.Wizard_Financial_Account__c = f.Wizard_Financial_Account__c;

            casesToInsert.add(c);

            // Update Rep Code
            if (f.Rep_Code_Lookup__r != null) {
                f.Rep_Code__c = f.Rep_Code_Lookup__r.Name;
            }
            faMap.put(f.Id, f);
        }

        if (!casesToInsert.isEmpty()) {
            insert casesToInsert;
        }

        if (!faMap.isEmpty()) {
            update faMap.values();
        }

        // Create Tasks for each Case
        List<Task> tasksToInsert = new List<Task>();
        for (Case c : casesToInsert) {
            Task t = new Task();
            t.WhatId = c.Id;
            t.Subject = 'Ops Final Review - Transitions';
            t.Description =
                'This task is to review the Salesforce data and records ' +
                'to make sure the records are serviceable going forward';
            //t.OwnerId = '03g8X0000037Sp8QAE';
            t.OwnerId = [SELECT Id, Queue.Name, Queue.DeveloperName, SobjectType
						FROM QueueSobject 
						WHERE Queue.Name = 'Operations'and SobjectType = 'Task' LIMIT 1].QueueId; // Operations Queue
            t.ActivityDate = Date.today();
            tasksToInsert.add(t);
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Batch completed successfully.');
    }
}