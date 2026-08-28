public class Batch_FindUnAssignedTasks implements Schedulable, Database.Batchable<sObject> {
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query all Not closed Tasks that are owned by the 'UnAssigned' owner
        return Database.getQueryLocator('SELECT Id, WhatId, Full_Template_Order__c FROM Task WHERE IsClosed = False AND createddate=today AND OwnerId IN (SELECT Id FROM Group WHERE Type = \'Queue\' AND Name = \'UnAssigned\')');
    }
    
    // The execute method processes each batch of records. 
    // It receives a list of Task records and processes them.
    public void execute(Database.BatchableContext bc, List<Task> tasks) {
        // Set to hold the Previous_Task__c Ids from related Cases
        Set<Id> previousTaskIds = new Set<Id>();
        
        // Set to hold the Case Ids that are linked to the Tasks via WhatId
        Set<Id> caseIds = new Set<Id>();
        
        // Loop through the list of tasks and collect the WhatId (Case Id) of each Task
        for (Task tsk : tasks) {
            caseIds.add(tsk.WhatId);
        }        
        // Query the Case object for records with matching Case Ids and retrieve Previous_Task__c
        Map<Id, Case> caseMap = new Map<Id, Case>([SELECT Id, Previous_Task__c FROM Case WHERE Id IN :caseIds]);
        
        // Loop through the Case records and add the Previous_Task__c to the previousTaskIds set
        for (Case caseRecord : caseMap.values()) {
            previousTaskIds.add(caseRecord.Previous_Task__c);
        }
        system.debug('previousTaskIds'+previousTaskIds);
        // Query the Task object for Previous Tasks that are closed
        Map<Id, Task> previousTaskMap = new Map<Id, Task>([SELECT Id, Full_Template_Order__c FROM Task WHERE Id IN :previousTaskIds AND IsClosed = TRUE]);
        
        // List to hold tasks that need to be updated
        List<Task> taskToUpdate = new List<Task>();
        
        // Loop through the original list of Tasks
        for (Task tsk : tasks) {
            // Check if the Task's WhatId is present in the Case map
            if (!caseMap.isEmpty() && caseMap.containsKey(tsk.WhatId)) {
                if(!previousTaskMap.isEmpty() && previousTaskMap.containsKey(caseMap.get(tsk.WhatId).Previous_Task__c)){
                    // Check if the Previous_Task__c of the related Case is present in the previousTaskMap
                    Task previousTask = previousTaskMap.get(caseMap.get(tsk.WhatId).Previous_Task__c);                    
                    if(tsk.Full_Template_Order__c == previousTask.Full_Template_Order__c + 1 ) {
                        // Set IsSystemAssigned__c to true if conditions are met
                        tsk.IsSystemAssigned__c = TRUE;
                        // Add Task to the list to be updated
                        taskToUpdate.add(tsk);
                    }
                }
            }
        }        
        // Update tasks if there are any that meet the conditions
        if (!taskToUpdate.isEmpty()) {
            update taskToUpdate;
        }
    }
    
    // The execute method from Schedulable interface. It starts the batch job.
    public void execute(SchedulableContext ctx) {
        // Execute the batch class
        Database.executeBatch(new Batch_FindUnAssignedTasks());
    }
    
    public void finish(Database.BatchableContext bc) {
    }
}