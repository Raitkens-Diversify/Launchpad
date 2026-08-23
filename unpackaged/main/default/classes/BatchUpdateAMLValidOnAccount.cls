global class BatchUpdateAMLValidOnAccount implements Database.Batchable<sObject>, Schedulable{
    
    global Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator([SELECT Id, AML_Valid__c FROM Account 
                                         WHERE AML_Expiration_Date__c < TODAY AND AML_Valid__c = true]);
    }
    
    global void execute(Database.BatchableContext BC, List<Account> scope){
        for(Account acc : scope){
            acc.AML_Valid__c = false;
        }
        update scope;
    }
    
    global void finish(Database.BatchableContext BC){
    }
    
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new BatchUpdateAMLValidOnAccount());
    }
}