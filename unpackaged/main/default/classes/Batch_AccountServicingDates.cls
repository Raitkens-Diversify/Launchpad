global class Batch_AccountServicingDates implements Schedulable,Database.Batchable<sObject> {
    
    global Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator([SELECT Id,Financial_Advisor_Team__c, Financial_Advisor_Team__r.Associate_Advisor__c, 
                                         Financial_Advisor_Team__r.CSA__c, OwnerId, 
                                         Account_Funding_Next_Service_Date__c,Donation_in_Kind_Next_Service_Date__c,
                                         QCD_Next_Service_Date__c,Roth_Conversion_Next_Service_Date__c,FinServ__NextReview__c FROM Account 
                                         WHERE Account_Funding_Next_Service_Date__c = TODAY
                                         OR Donation_in_Kind_Next_Service_Date__c = TODAY
                                         OR QCD_Next_Service_Date__c = TODAY
                                         OR FinServ__NextReview__c = TODAY
                                         OR Roth_Conversion_Next_Service_Date__c = TODAY]);
    }
    
    global void execute(Database.BatchableContext BC, List<Account> scope){
        List<Task> taskList= New  List<Task>();
        for(Account acc : scope){ 
            System.debug('account: ' + acc);
            if(acc.Account_Funding_Next_Service_Date__c == system.Today()){
                Task t = createTask(acc);
                t.Subject = 'Account Funding Servicing';
                t.Description = 'Please follow up with the client to discuss an annual account funding strategy.';
                taskList.add(t);
            }
            if(acc.Donation_In_Kind_Next_Service_Date__c == system.Today()){
                Task t = createTask(acc);
                t.Subject = 'Donation in Kind Servicing';
                t.Description = 'Please follow up with the client to discuss an annual donation in kind strategy.';
                taskList.add(t);
            }
            if(acc.QCD_Next_Service_Date__c == system.Today()){
                Task t = createTask(acc);
                t.Subject = 'Qualified Charitable Distribution Servicing';
                t.Description = 'Please follow up with the client to discuss an annual qualified charitable distribution strategy.';
                taskList.add(t);
            }
            if(acc.Roth_Conversion_Next_Service_Date__c == system.Today()){
                Task t = createTask(acc);
                t.Subject = 'Roth Conversion Servicing';
                t.Description = 'Please follow up with the client to discuss an annual roth conversion strategy.';
                taskList.add(t);
            }
            if(acc.FinServ__NextReview__c == system.Today()){
                Task t = createTask(acc);
                t.Subject = 'Review Meeting';
                t.Description = 'Please follow up with the client to schedule a Review Meeting.';
                taskList.add(t);
            }
        }
        if(!taskList.isEmpty()){
            insert taskList;
        }
    }
    
    global void finish(Database.BatchableContext BC){
    }
    
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new Batch_AccountServicingDates());
    }
    private Task createTask(Account acc){
        List<User> users = [SELECT Id, Name FROM User];
        Map<String,Id> nameToId = new Map<String,Id>();
        for(User u : users){
            nameToId.put(u.Name, u.Id);
        }
        Task t = new Task();
        t.WhatId = acc.Id;
        t.FinServ__Household__c = acc.Id;
        t.ActivityDate = system.Today(); 
        if(acc.Financial_Advisor_Team__c != null && acc.Financial_Advisor_Team__r.Associate_Advisor__c !=null){
            System.debug('nameToId.get(AssociateAdvisor): ' + nameToId.get(acc.Financial_Advisor_Team__r.Associate_Advisor__c));
            t.OwnerId = nameToId.get(acc.Financial_Advisor_Team__r.Associate_Advisor__c);      
        } else if(acc.Financial_Advisor_Team__c != null && acc.Financial_Advisor_Team__r.CSA__c != null){
            System.debug('nameToId.get(CSA): ' + nameToId.get(acc.Financial_Advisor_Team__r.CSA__c));
            t.OwnerId = nameToId.get(acc.Financial_Advisor_Team__r.CSA__c);
        } else {
            t.OwnerId = acc.OwnerId;
        }
        System.debug('t.Ownerid: ' + t.OwnerId);
        t.Priority = 'Normal';    
        t.Status = 'Not Started';    
        t.TaskSubtype = 'Task';
        return t;
    }
}