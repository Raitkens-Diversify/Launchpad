global class BatchEventEmailNotification implements Database.Batchable<sObject>, Schedulable {
    
    global Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator([SELECT Id, Name, CreatedBy.Email, CreatedBy.FirstName, CreatedById FROM Advertising_Item__c 
                                         WHERE Attendee_List_Required__c = true AND Date_of_Event__c = YESTERDAY]);
    }
    
    global void execute(Database.BatchableContext BC, List<Advertising_Item__c> scope){
        String templateName = 'Event_Attendee_List_Reminder';
        EmailTemplate et = [SELECT Id, Subject, Body, HtmlValue, FolderId FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];           
        List<Messaging.SingleEmailMessage> emails =  new List<Messaging.SingleEmailMessage>();
        List<Task> tasks = new List<Task>();
        for(Advertising_Item__c adItem : scope){
            List<String> toAddress = new List<String>();
            toAddress.add(adItem.CreatedBy.Email);
            Messaging.SingleEmailMessage email = Messaging.renderStoredEmailTemplate(et.Id, null, adItem.Id);
            String emailBody = email.htmlBody;
            if(emailBody != null){
                if(emailBody.contains('&lt;&lt;First Name&gt;&gt')){
                    emailBody = emailBody.replace('&lt;&lt;First Name&gt;&gt;', adItem.CreatedBy.FirstName);
                }
                if(emailBody.contains('&lt;&lt;Event Name&gt;&gt')){
                    emailBody = emailBody.replace('&lt;&lt;Event Name&gt;&gt;', adItem.Name);
                }
                if(emailBody.contains('here')){
                    String recordLink = URL.getSalesforceBaseUrl().toExternalForm()+ '/'+adItem.Id;
                    emailBody = emailBody.replace('here', recordLink);
                }
                email.setHtmlbody(emailBody);
            }
            email.toAddresses = toAddress;
            email.setSaveAsActivity(false); //To avoid creating task records for Email activity.
            emails.add(email);
            Task t = new Task();
            t.ActivityDate = Date.today();
            t.OwnerId = adItem.CreatedById;
            t.Subject = 'Upload Event Attendee List';
            t.WhatId = adItem.Id;
            t.Status = 'Not Started';
            t.Priority = 'Normal';
            t.Description = 'Upload Event Attendee List';
            insert t;
            System.debug(t.Id);
        }
        
        try{
            Messaging.sendEmail(emails);
            
        }
        catch(Exception e){
            System.debug('Error occured while sending email:' + e.getMessage());    
        }
    }
    
    global void finish(Database.BatchableContext BC){
    }
    
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new BatchEventEmailNotification());
    }
}