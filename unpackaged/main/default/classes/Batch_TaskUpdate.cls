global class Batch_TaskUpdate implements Schedulable,Database.Batchable<sObject> {
    public Map<Id,Task> taskMap;
    public Date todaysDate = Date.today();
    public Id accOpenRT = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Opening').getRecordTypeId();
    public Id accServRT = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Servicing').getRecordTypeId();
	Map<Id,List<Task>> caseToTasksMap = new Map<Id,List<Task>>();
    
    global Batch_TaskUpdate(){
        taskMap = new Map<Id,Task>([SELECT Id, WhatId, OwnerId, Owner.Name, Order__c, ActivityDate FROM Task 
                                         WHERE Status != 'Completed' AND Status != 'Approved' AND 
                                         WhatId_Object__c = 'Case' ORDER BY Order__c asc]);
        for(Task t : taskMap.values()){
            if(caseToTasksMap.get(t.WhatId)== null){
        		List<Task> tempList = new List<Task>();
        		tempList.add(t);
        		caseToTasksMap.put(t.WhatId,tempList);
    		} else {
        		List<Task> tempList = caseToTasksMap.get(t.WhatId);
        		tempList.add(t);
        		caseToTasksMap.put(t.WhatId,tempList);
    		}
        }
    }
    
    global Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator([SELECT Id, Current_Task_Id__c, Next_Task__c, Owner_Group__c, Number_of_Open_Tasks__c, 
                                    Date_Task_Script_Last_Ran__c, Due_Date_of_Current_Task__c FROM Case 
                                    WHERE Date_Task_Script_Last_Ran__c !=: todaysDate AND 
                                    (RecordTypeId =: accOpenRT OR RecordTypeId =: accServRT)]);
    }
    
    global void execute(Database.BatchableContext BC, List<Case> scope){
        for(Case c : scope){ 
            List<Task> tempList = new List<Task>();
            if(caseToTasksMap.get(c.Id)!= null){
        		tempList = caseToTasksMap.get(c.Id);
    		}
    		if(!tempList.isEmpty()){
        		if(tempList.size()>1){
            		c.Current_Task_Id__c = caseToTasksMap.get(c.Id)[0].Id;
            		c.Next_Task__c = caseToTasksMap.get(c.Id)[1].Id;
            		c.Owner_Group__c = caseToTasksMap.get(c.Id)[0].Owner.Name;
            		c.Number_of_Open_tasks__c = tempList.size();
            		c.Date_Task_Script_Last_Ran__c = todaysDate;
            		c.Due_Date_of_Current_Task__c = caseToTasksMap.get(c.Id)[0].ActivityDate;
        		} else if(tempList.size()==1){
            		c.Current_Task_Id__c = caseToTasksMap.get(c.Id)[0].Id;
            		c.Owner_Group__c = caseToTasksMap.get(c.Id)[0].Owner.Name;
            		c.Number_of_Open_Tasks__C = tempList.size();
            		c.Date_Task_Script_Last_Ran__c = todaysDate;
            		c.Due_Date_of_Current_Task__c = caseToTasksMap.get(c.Id)[0].ActivityDate;
        		}
    		} else {
        		c.Number_of_Open_Tasks__c = 0;
                c.Date_Task_Script_Last_Ran__c = todaysDate;
                c.Owner_Group__c = '';
                c.Current_Task_Id__c = '';
                c.Due_Date_of_Current_Task__c = null;
                c.Next_Task__c = '';
    		}
    	}
        Database.update(scope,false);
    }
    
    global void finish(Database.BatchableContext BC){
        
    }
    
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new Batch_TaskUpdate());
    }
}