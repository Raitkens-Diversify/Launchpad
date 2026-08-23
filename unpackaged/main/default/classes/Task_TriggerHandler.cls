public class Task_TriggerHandler {
    
    public void isBeforeInsert(List<Task> newList){
        setOriginalOwner(newList);
        updateTask(newList, null);
        setHousehold(newList, null);
        setEmailTemplate(newList);
        setDFPGFinancialAccountOnTask(newList);    
    }
    
    public void isBeforeUpdate(Map<Id, Task> newMap, Map<Id, Task> oldMap){
        updateTask(newMap.values(), oldMap);
        setHousehold(newMap.values(), oldMap);
        setDFPGFinancialAccountOnTask(newMap.values());
        setSSEDate(newMap, oldMap);
    }
    
    public void isBeforeDelete(Map<Id, Task> oldMap){ }
    
    public void isAfterInsert(Map<Id, Task> newMap){
        setIsSystemAssignedField(newMap.values());
        NotificationChangePublisher.publishInserts(
            NotificationConstants.OBJECT_TYPE_TASK,
            newMap.values()
        );
        //CaseTaskAutomationService.processAfterInsert(newMap);
    }
    
    public void isAfterUpdate(Map<Id, Task> newMap, Map<Id, Task> oldMap){
        updateOwnerAndDueDateOnTask(newMap.values(), oldMap);
        setDateOfDeathOnCase(newMap.values(), oldMap);
        recalcOn3WayCall(newMap, oldMap);
        updateCaseStatus(newMap.values(), oldMap);
        setIsSystemAssignedField(newMap.values());
        updateCaseGroupOwnerField(newMap,oldMap);
        NotificationChangePublisher.publishUpdates(
            NotificationConstants.OBJECT_TYPE_TASK,
            newMap,
            oldMap
        );
        //createCaseFeed(newMap.values(), oldMap);
        //CaseTaskAutomationService.processAfterUpdate(newMap, oldMap);
    }
    
    public void isAfterDelete(Map<Id, Task> oldMap){ }
    
    public void isAfterUndelete(Map<Id, Task> newMap){ }
    
    private static void updateCaseStatus(List<Task> newList, Map<Id, Task> oldMap){
        List<Case> casesToUpdate = new List<Case>();
        Set<Id> setOfCaseId = new Set<Id>();
        
        for(Task newTask : newList) {
            setOfCaseId.add(newTask.WhatId);
        }
        Map<Id,Case> caseMap = new Map<Id,Case>([SELECT Id,Current_Task_Id__c FROM Case WHERE Id IN : setOfCaseId]);
        for(Task newTask : newList) {
            if(caseMap.containsKey(newTask.WhatId) && newTask.Status != oldMap.get(newTask.Id).Status && newTask.Status != 'Completed' 
               && newTask.Status != 'Canceled' && caseMap.get(newTask.WhatId).Current_Task_Id__c == newTask.Id) {
                   casesToUpdate.add(new case(Id =newTask.WhatId,Sub_Status__C=newTask.Status));
               }
        }
        if(!casesToUpdate.isEmpty()){
            update casesToUpdate;
        }
        
    }
    
    /*private static void createCaseFeed(List<Task> newList, Map<Id, Task> oldMap) {
        List<FeedItem> feedsToInsert = new List<FeedItem>();
    	System.debug('newList :' + newList);
        for (Task t : newList) {
            Task oldT = oldMap.get(t.Id);
            // Status Change to Completed/Approved 
            if (
                (t.Status == 'Completed' || t.Status == 'Approved') &&
                (oldT.Status != 'Completed' && oldT.Status != 'Approved') &&
                String.valueOf(t.WhatId).startsWith('500')   // ensures it's a Case Cause WhatId is Required
            ) {
                feedsToInsert.add(
                    new FeedItem(
                        ParentId  = t.WhatId,
                        //Type      = 'TextPost',
                        Visibility= 'AllUsers',
                        Status    = 'Published',
                        Body      = 'Task status updated to ' + t.Status
                    )
                );
            }
    
            // Assignment Changed
            if (
                t.OwnerId != oldT.OwnerId &&
                String.valueOf(t.WhatId).startsWith('500')
            ) {
                feedsToInsert.add(
                    new FeedItem(
                        ParentId  = t.WhatId,
                        //Type      = 'TextPost',
                        Visibility= 'AllUsers',
                        Status    = 'Published',
                        Body      = 'Task reassigned from ' + oldT.OwnerId + ' to ' + t.OwnerId
                    )
                );
            }
    
            // ActivityDate Change
            if (
                t.ActivityDate != oldT.ActivityDate &&
                String.valueOf(t.WhatId).startsWith('500')
            ) {
                feedsToInsert.add(
                    new FeedItem(
                        ParentId  = t.WhatId,
                        //Type      = 'TextPost',
                        Visibility= 'AllUsers',
                        Status    = 'Published',
                        Body      = 'Task due date changed from ' + oldT.ActivityDate + ' to ' + t.ActivityDate
                    )
                );
            }
        }
    
        // Insert FeedItem only once
        if (!feedsToInsert.isEmpty()) {
            insert feedsToInsert;
        }
    }*/
    

    private static void updateTask(List<Task> newList, Map<Id, Task> oldMap){
        List<Task> tasksToUpdate = new List<Task>();
        Set<Id> accountIds = new Set<Id>();
        
        //List All the tasks and accounts which are related
        for(Task task : newList) {
            if(task.WhatId != null && task.WhatId.getSObjectType() == Account.sObjectType && (oldMap == null || (oldMap != null && task.WhatId != oldMap.get(task.Id).WhatId))) {
                accountIds.add(task.WhatId);
                tasksToUpdate.add(task);
            }
        }
        
        if(!accountIds.isEmpty()){
            Map<Id, Account> accountMap = new Map<Id, Account>([SELECT Id, Financial_Advisor_Team__c FROM Account
                                                                WHERE Id IN : accountIds]);
            // Update Task where WhatId is of Account Type
            for(Task task : tasksToUpdate){
                task.Financial_Advisor_Team__c = accountMap.get(task.WhatId).Financial_Advisor_Team__c;
            }
        }
    }
    
    private static void setHousehold(List<Task> newList, Map<Id, Task> oldMap){
        List<Task> tasksToUpdate = new List<Task>();
        Set<Id> contactIds = new Set<Id>();
        
        //List All the tasks and accounts which are related
        for(Task task : newList) {
            if(task.WhoId != null && task.WhoId.getSObjectType() == Contact.sObjectType && (oldMap == null || (oldMap != null && task.WhoId != oldMap.get(task.Id).WhoId))) {
                contactIds.add(task.WhoId);
                tasksToUpdate.add(task);
            }
        }
        
        if(!contactIds.isEmpty()){
            Map<Id, Contact> contactMap = new Map<Id, Contact>([SELECT Id, AccountId, Account.Household__c FROM Contact
                                                                WHERE Id IN : contactIds]);
            // Update Task where WhatId is of Account Type
            for(Task task : tasksToUpdate){
                task.FinServ__Household__c = contactMap.get(task.WhoId).Account.Household__c;
            }
        }
    }
    
    private static void updateOwnerAndDueDateOnTask(List<Task> newList, Map<Id, Task> oldMap){
        Set<Id> setOfCaseIds = new Set<Id>();
        Set<Id> setOfTaskTempItemIds = new Set<Id>();
        Set<Id> setOfFATIds = new Set<Id>();
        Set<String> setOfQueueNames = new Set<String>();
        List<Task> lstTask = new List<Task>();
        Map<Id,Task> updateTasksMap =new Map<Id,Task>();
        List<Group> lstGroup = new List<Group>();
        Set<Id> setOfTaskIds = new Set<Id>();
        Map<Id, Case> mapOfCase = new Map<Id, Case>();
        Map<String, Id> mapOfQueueIdByName = new Map<String, Id>();
        Map<Id, List<Task>> mapOfCaseIdToTask = new Map<Id, List<Task>>();
        Map<Id, Task_Template_Item__c> mapOfTaskTempItem = new Map<Id, Task_Template_Item__c>();
        Map<Id, Financial_Advisor_Team__c> mapOfFATeam = new Map<Id, Financial_Advisor_Team__c>();
        Map<Id,Id> mapOfFatTeamAndUserForPrimary = new Map<Id,Id>();
        Map<Id,Id> mapOfFatTeamAndUserForOperations = new Map<Id,Id>();
        Map<Id,Case> updatedCaseMap = new Map<Id,Case>();
        
        for(Task newTask : newList){
            if(!String.isEmpty(newTask.Task_Template_Item__c) && !String.isEmpty(newTask.Task_Template__c) && 
               newTask.isClosed && newTask.isClosed != oldMap.get(newTask.Id).isClosed && newTask.Requires_a_3_Way_Call__c == null){
                   setOfCaseIds.add(newTask.WhatId);
                   setOfTaskIds.add(newTask.Id);  
                   setOfTaskTempItemIds.add(newTask.Task_Template_Item__c);
               }
        }
        
        mapOfTaskTempItem = new Map<Id, Task_Template_Item__c>([SELECT Id, Order__c ,Task_Template__r.Due_Date__c, Task_Template__r.Referenced_Field__c, Task_Template__r.Queue__c,Task_Template__r.FA_Team_Permission__c
                                                                FROM Task_Template_Item__c 
                                                                WHERE Id IN : setOfTaskTempItemIds]);
        
        lstTask = [SELECT Id, WhatId, Task_Template_Item__c, Task_Template__c, Task_Template_Item__r.Task_Template__c, Task_Template_Item__r.Order__c, Task_Template__r.Assigned_To__c,
                   Task_Template__r.FA_Team_Permission__c, Task_Template__r.Due_Date__c, Task_Template__r.Referenced_Field__c, Task_Template__r.Number_of_Days__c, Task_Template__r.Queue__c, 
                   isClosed,Owner.Name, OwnerName__c FROM Task WHERE WhatId IN :setOfCaseIds AND Id NOT IN :setOfTaskIds AND Task_Template_Item__c != null];
        
        mapOfCase = new Map<Id, Case>([SELECT Id, Financial_Advisor_Team__c, Status, Review_Meeting_Scheduled_Date__c, OwnerId FROM Case WHERE Id IN :setOfCaseIds]);
        
        for(Case caseRecord : mapOfCase.values()){
            if(!String.isEmpty(caseRecord.Financial_Advisor_Team__c)){
                setOfFATIds.add(caseRecord.Financial_Advisor_Team__c);
            }
        }
        
        mapOfFATeam = new Map<Id, Financial_Advisor_Team__c>([SELECT Id, (SELECT ID, Associate_Advisor__c, CSA__c, Send_Notifications__c,
                                                                          Review_Paperwork__c, Draft_Paperwork__c, Trading__c, User__c,Operations__c,Primary__c FROM Financial_Advisor_Team_Members__r)
                                                              FROM Financial_Advisor_Team__c WHERE Id IN :setOfFATIds]);
        
        //Get User from FAT Team Member thoese have Primary and Operations permission true
        for(Financial_Advisor_Team__c fat : mapOfFATeam.values()){
            for(Financial_Advisor_Team_Member__c fatm : fat.Financial_Advisor_Team_Members__r){
                if(fatm.Operations__c){
                    mapOfFatTeamAndUserForOperations.put(fat.Id,fatm.User__c);
                }
                if(fatm.Primary__c){
                    mapOfFatTeamAndUserForPrimary.put(fat.Id,fatm.User__c);
                }
            }
        }
        
        for(Task taskRecord : lstTask){
            if(!mapOfCaseIdToTask.containsKey(taskRecord.WhatId)){
                mapOfCaseIdToTask.put(taskRecord.WhatId, new List<Task>());
            }
            if(!String.isEmpty(taskRecord.Task_Template__r.Queue__c)){
                setOfQueueNames.add(taskRecord.Task_Template__r.Queue__c);
            }
            mapOfCaseIdToTask.get(taskRecord.WhatId).add(taskRecord);
        }
        
        setOfQueueNames.add('Operations'); 
        
        lstGroup = [Select Id, Name from Group where type = 'Queue' and Name = :setOfQueueNames];
        
        for(Group groupRecord : lstGroup){
            mapOfQueueIdByName.put(groupRecord.Name, groupRecord.Id);
        }
        
        Id approvalTaskRecordTypeId = Schema.sObjectType.Task.getRecordTypeInfosByName().get('Approval Task').getRecordTypeId();
        
        for(Task newTask : newList){
            if(!String.isEmpty(newTask.Task_Template_Item__c) && !String.isEmpty(newTask.Task_Template__c) && newTask.isClosed &&
               newTask.isClosed != oldMap.get(newTask.Id).isClosed && mapOfCaseIdToTask.containsKey(newTask.WhatId)){
                   Task_Template_Item__c taskTempItemRecord = mapOfTaskTempItem.get(newTask.Task_Template_Item__c);
                   List<Task> lstRelatedTask = mapOfCaseIdToTask.get(newTask.WhatId);
                   Case relatedCase = mapOfCase.get(newTask.WhatId);
                   Boolean isTaskFound = false;
                   //Update fields of related case 
                   relatedCase.Next_Task__c = null;
                   relatedCase.Current_Task_Id__c = null;
                   relatedCase.Previous_Task__c = newTask.Id;
                   relatedCase.Owner_Group__c = null;
                   for(Task relatedTask : lstRelatedTask){
                       if(!String.isEmpty(relatedTask.Task_Template_Item__c) && !String.isEmpty(relatedTask.Task_Template__c) && 
                          taskTempItemRecord.Order__c != null && relatedTask.Task_Template_Item__r.Order__c == taskTempItemRecord.Order__c + 1){
                              Date ActivityDate = System.Today();
                              
                              if(relatedTask.Task_Template__r.Due_Date__c == 'Immediate'){
                                  relatedTask.ActivityDate = System.Today();
                              } else if(relatedTask.Task_Template__r.Due_Date__c == 'Days from Case Creation' ||
                                        relatedTask.Task_Template__r.Due_Date__c == 'Days from Previous Task Completion'){
                                            relatedTask.ActivityDate = System.Today()+(Integer)relatedTask.Task_Template__r.Number_of_Days__c;
                              } else if(relatedTask.Task_Template__r.Due_Date__c == 'After Referenced Field' && relatedTask.Task_Template__r.Referenced_Field__c == 'Review_Meeting_Scheduled_Date__c'){
                                            ActivityDate = relatedCase.Review_Meeting_Scheduled_Date__c + (Integer)relatedTask.Task_Template__r.Number_of_Days__c;
                                            relatedTask.ActivityDate = ActivityDate;
                              } else if(relatedTask.Task_Template__r.Due_Date__c == 'Before Referenced Field' && relatedTask.Task_Template__r.Referenced_Field__c == 'Review_Meeting_Scheduled_Date__c'){
                                            ActivityDate = relatedCase.Review_Meeting_Scheduled_Date__c - (Integer)relatedTask.Task_Template__r.Number_of_Days__c;
                                            relatedTask.ActivityDate = ActivityDate;
                                            //System.debug('relatedTask.ActivityDate: ' + relatedTask.ActivityDate);
                              } 
                              //Update case
                              System.debug('relatedTask.OwnerId: ' + relatedTask.OwnerId);
                              relatedCase.Current_Task_Id__c = relatedTask.Id;
                              relatedCase.Owner_Group__c = relatedTask.Owner.Name;
                              System.debug('relatedTask.OwnerId: ' + relatedTask.OwnerId);
                              System.debug('relatedTask.Owner.Name: ' + relatedTask.OwnerName__c);
                              relatedCase.Sub_Status__c ='New';
                              updateTasksMap.put(relatedTask.Id,relatedTask);          
                              
                              if(relatedTask.Task_Template__r.Assigned_To__c == 'Queue'){
                                  if(!String.isEmpty(relatedTask.Task_Template__r.Queue__c)){
                                      if(relatedTask.Task_Template__r.Queue__c == 'Compliance'||relatedTask.Task_Template__r.Queue__c == 'Principal Review'){
                                          relatedTask.RecordTypeId = approvalTaskRecordTypeId;
                                          relatedTask.OwnerId =  mapOfQueueIdByName.get(relatedTask.Task_Template__r.Queue__c);

                                      } else if(relatedTask.Task_Template__r.Queue__c == 'Back Office Operations'){
                                          relatedTask.OwnerId =  mapOfQueueIdByName.get('Operations');
                                      } else if(relatedTask.Task_Template__r.Queue__c == 'Financial Advisor Team Operations'){
                                          if(mapOfFatTeamAndUserForOperations.containsKey(relatedCase.Financial_Advisor_Team__c)){
                                              relatedTask.OwnerId =  mapOfFatTeamAndUserForOperations.get(relatedCase.Financial_Advisor_Team__c);
                                          } else if(mapOfFatTeamAndUserForPrimary.containsKey(relatedCase.Financial_Advisor_Team__c)){
                                              relatedTask.OwnerId =  mapOfFatTeamAndUserForPrimary.get(relatedCase.Financial_Advisor_Team__c);
                                          }
                                      } else if(!mapOfQueueIdByName.isEmpty() && mapOfQueueIdByName.containsKey(relatedTask.Task_Template__r.Queue__c)){
                                          relatedTask.OwnerId =  mapOfQueueIdByName.get(relatedTask.Task_Template__r.Queue__c);

                                      }                                      
                                  }
                              } else if(relatedTask.Task_Template__r.Assigned_To__c == 'FA Team Permission'){
                                  if(!String.isEmpty(relatedCase.Financial_Advisor_Team__c)){
                                      List<Financial_Advisor_Team_Member__c> lstFATM = mapOfFATeam.get(relatedCase.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
                                      String fieldName = null;
                                      if(relatedTask.Task_Template__r.FA_Team_Permission__c == 'Trading'){
                                          fieldName = 'Trading__c';
                                      } else if(relatedTask.Task_Template__r.FA_Team_Permission__c == 'Draft Paperwork'){
                                          fieldName = 'Draft_Paperwork__c';
                                      } else if(relatedTask.Task_Template__r.FA_Team_Permission__c == 'Review Paperwork'){
                                          fieldName = 'Review_Paperwork__c';
                                      } else if(relatedTask.Task_Template__r.FA_Team_Permission__c == 'Send Notifications'){
                                          fieldName = 'Send_Notifications__c';
                                      } else if(relatedTask.Task_Template__r.FA_Team_Permission__c == 'CSA'){
                                          fieldName = 'CSA__c';
                                      } else if(relatedTask.Task_Template__r.FA_Team_Permission__c == 'Associate Advisor'){
                                          fieldName = 'Associate_Advisor__c';
                                      } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Advisor'){
                                          fieldName = 'Primary__c';
                                      } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Operation'){
                                          fieldName = 'Operations__c';
                                      }
                                      if(fieldName != null){
                                          for(Financial_Advisor_Team_Member__c fatm: lstFATM){
                                              if((Boolean)fatm.get(fieldName)){
                                                  relatedTask.OwnerId = fatm.User__c;
                                                  break;
                                              } else {
                                                relatedTask.OwnerId = relatedCase.OwnerId;
                                              }
                                          }
                                      }
                                  }
                              }

                              updateTasksMap.put(relatedTask.Id,relatedTask);          
                          } else if(!String.isEmpty(relatedTask.Task_Template_Item__c) && !String.isEmpty(relatedTask.Task_Template__c) && 
                                    taskTempItemRecord.Order__c != null && relatedTask.Task_Template_Item__r.Order__c == (taskTempItemRecord.Order__c + 2)){

                                        relatedCase.Next_Task__c = relatedTask.Id;
                                    }
                       if(!relatedTask.isClosed){
                           isTaskFound = true;
                       }
                   }
                   if(!isTaskFound){
                       relatedCase.Status = 'Closed';
                   }
                   updatedCaseMap.put(relatedCase.Id,relatedCase);
               }
        }
        if(!updatedCaseMap.isEmpty()){
            update updatedCaseMap.values();
        } 
        if(!updateTasksMap.isEmpty()){
            update updateTasksMap.values();	           
        }
    }
    
    private static void setDateOfDeathOnCase(List<Task> newList, Map<Id, Task> oldMap){
        List<Case> casesToUpdate = new List<Case>();
        for(Task task : newList){
            if(task.Date_of_Death__c != null && task.Date_of_Death__c != oldMap.get(task.Id).Date_of_Death__c && task.WhatId != null && task.WhatId.getSObjectType() == Case.sObjectType){
                casesToUpdate.add(new Case (Id = task.WhatId, Date_of_Death__c = task.Date_of_Death__c));
            }
        }
        if(!casesToUpdate.isEmpty()){
            update casesToUpdate;
        }
    }
    
    private void setEmailTemplate(List<Task> newList){
        Set<Id> caseIds = new Set<Id>();
        List<Task> tasksToUpdate = new List<Task>();
        for(Task t : newList){
            if(t.Task_Template__c != null && t.WhatId.getSObjectType() == Case.sObjectType){
                caseIds.add(t.WhatId);
                tasksToUpdate.add(t);
            }
        }
        Map<Id,Case> caseMap = new Map<Id,Case>([SELECT Id, Type FROM Case WHERE Id in: caseIds]);
        List<Email_Template_Selector__mdt> emailNames = [SELECT Id, Case_Type__c, Task_Type__c, Template_Name__c, Label FROM Email_Template_Selector__mdt];
        for(Task t : tasksToUpdate){
            for(Email_Template_Selector__mdt e : emailNames){
                if(t.Subject == e.Task_Type__c && caseMap.get(t.WhatId).Type == e.Case_Type__c){
                    t.Email_Template__c = e.Template_Name__c;
                }
            }
        }
    }
    
    private void updateCaseGroupOwnerField(Map<Id,Task> newMap, Map<Id,Task> oldMap){
        //List<Case> caseUpdateList = new List<Case>();
        Map<Id, Case> mapOfCases = new Map<Id, Case>();
        Set<Id> taskIds = new Set<Id>();
        for(Task newTask : newMap.values()){
            if(newTask.ownerId != oldMap.get(newTask.Id).ownerId){
                taskIds.add(newTask.Id);
            }
        }
        for(Task tsk : [SELECT Id,Owner.Name,WhatId FROM Task WHERE Id =: taskIds]){
            if(tsk.WhatId != null && tsk.WhatId.getSObjectType() == Case.sObjectType) {
                Id caseId = tsk.WhatId;
                String ownerName = tsk.Owner.Name;
                mapOfCases.put(caseId, new Case(
                    Id = caseId,
                    Owner_Group__c = ownerName
            	));                
            }
        }
        System.debug('update mapOfCases.values();');
        if(!mapOfCases.values().isEmpty()){
            update mapOfCases.values();
        }
    }
    
    
    private void recalcOn3WayCall(Map<Id,Task> newMap, Map<Id,Task> oldMap){
        Set<Id> caseIds = new Set<Id>();
        List<Task> tasksWithCalls = new List<Task>();
        for(Task newTask : newMap.values()){
            Task oldTask = oldMap.get(newTask.Id);
            if(newTask.Requires_a_3_Way_Call__c != null && newTask.Status == 'Completed' && oldTask.Status != 'Completed'){
                caseIds.add(newTask.WhatId);
                tasksWithCalls.add(newTask);
            }
        }
        if(!caseIds.isEmpty()){
            Map<Id,Case> casesToUpdate = new Map<Id,Case>([SELECT Id, X3_Way_Call__c, Recalculate_Case_Template__c FROM Case WHERE Id in: caseIds]);
            if(!tasksWithCalls.isEmpty()){
                for(Task t : tasksWithCalls){
                    if(casesToUpdate.get(t.WhatId) != null){
                        Case caseToUpdate = casesToUpdate.get(t.WhatId);
                        caseToUpdate.Recalculate_Case_Template__c = true;
                        caseToUpdate.X3_Way_Call_Task_Completed__c = true;
                        if(t.Requires_a_3_Way_Call__c == 'Yes'){
                            caseToUpdate.X3_Way_Call__c = true;
                        } else if(t.Requires_a_3_Way_Call__c == 'No'){
                            caseToUpdate.X3_Way_Call__c = false;
                        }
                    }                
                }
            }
            update casesToUpdate.values();
        }
    }
    public void setDFPGFinancialAccountOnTask(List<Task> newList){
        List<Task> tasksToUpdate = new List<Task>();
        Set<Id> caseIds = new Set<Id>();
        
        //List All the tasks and cases which are related
        for(Task task : newList) {
            if(task.WhatId != null && task.WhatId.getSObjectType() == Case.sObjectType) {
                caseIds.add(task.WhatId);
                tasksToUpdate.add(task);
            }
        }
        
        if(!caseIds.isEmpty()){
            Map<Id, Case> caseMap = new Map<Id, Case>([SELECT Id,Wizard_Financial_Account__c  FROM Case
                                                       WHERE Id IN : caseIds]);
            // Update Task where WhatId is of Case Type
            for(Task task : tasksToUpdate){
                task.DFPG_Financial_Account__c = caseMap.get(task.WhatId).Wizard_Financial_Account__c;
            }
        } 
    }
    
    public static void setOriginalOwner(List<Task> newList){
        for(Task t : newList){
            t.Original_Owner__c = t.OwnerId;
        }
    }
    
    public static void setIsSystemAssignedField(List<Task> tasks){
        Set<Id> taskIds = new Set<Id>();
        User systemUser = [SELECT Id FROM User WHERE Name = 'System'];
        //system.debug('systemUser'+systemUser);
        //system.debug('tasks'+tasks);
        for(Task tsk : tasks){
            if(systemUser.Id == tsk.OwnerId && !tsk.IsSystemAssigned__c){
                taskIds.add(tsk.Id);
            }
        }
        //system.debug('taskIds'+taskIds);
        if(!taskIds.isEmpty()){
            updateTasksForSystemAssignedField(taskIds);
        }
    } 
    
    public static void setSSEDate(Map<Id,Task> newMap, Map<Id,Task> oldMap){
        Set<Id> caseIds = new Set<Id>();
        List<FinServ__FinancialAccount__c> finAcctsToUpdate = new List<FinServ__FinancialAccount__c>();
        for(Task newTask : newMap.values()){
            Task oldTask = oldMap.get(newTask.Id);
            if(newTask.IsClosed && !oldTask.IsClosed && newTask.Needs_2nd_Ops_Review__c && newTask.WhatId_Object__c == 'Case'){
                caseIds.add(newTask.WhatId);
            }
        }
        if(!caseIds.isEmpty()){
            List<Case> cases = [SELECT Id, FinServ__FinancialAccount__c FROM Case WHERE Id in: caseIds];
            for(Case c : cases){
                FinServ__FinancialAccount__c f = new FinServ__FinancialAccount__c(Id = c.FinServ__FinancialAccount__c, Ops_SSE_Review_Completion_Date__c = Date.today());
                finAcctsToUpdate.add(f);
            }
        }
        if(!finAcctsToUpdate.isEmpty()){
            update finAcctsToUpdate;
        }
    }
    
    @future
    public static void updateTasksForSystemAssignedField(Set<Id> ids){
        //system.debug('ids'+ids);
        List<Task> tasksToUpdate = new List<Task>();
        for(Id taskId : ids){
            tasksToUpdate.add(new Task(IsSystemAssigned__c = true,Id = taskId));
        }
        //system.debug('tasksToUpdate'+tasksToUpdate);
        if(!tasksToUpdate.isEmpty()){
            update tasksToUpdate;
        } 
    }
}