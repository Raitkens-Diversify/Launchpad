public without sharing class Rep_Code_TriggerHandler {
    public Rep_Code_TriggerHandler() {}
    
    public void isBeforeInsert(List<Rep_Code__c> newList){
        //prepopulateRepoCodeRecords(newList);
    }
    public void isBeforeUpdate(Map<Id, Rep_Code__c> newMap, Map<Id, Rep_Code__c> oldMap){
        //updateRepCode(newMap,oldMap);
        //updateFinFinancialAccounts(newMap,oldMap);
        updateFinAcctsWFATChange(newMap,oldMap);
    }
    
    public void isBeforeDelete(List<Rep_Code__c> newList){
        
    }
    
    public void isAfterInsert(Map<Id, Rep_Code__c> newMap){
        
    }
    
    public void isAfterUpdate(Map<Id, Rep_Code__c> newMap, Map<Id, Rep_Code__c> oldMap){
        
    }
    
    public void isAfterDelete(Map<Id, Rep_Code__c> oldMap){
        
    }
    
    public void isAfterUnDelete(Map<Id, Rep_Code__c> newMap){
        
    }
    
    public void updateFinAcctsWFATChange(Map<Id,Rep_Code__c> newMap, Map<Id,Rep_Code__c> oldMap){
        Set<Id> changedRepCodes = new Set<Id>();
        for(Rep_Code__c newRC : newMap.values()){
            Rep_Code__c oldRC = oldMap.get(newRC.Id);
            if(newRC.Financial_Advisor_Team__c != null && newRC.Financial_Advisor_Team__c != oldRC.Financial_Advisor_Team__c){
                changedRepCodes.add(newRC.Id);
                System.debug('changedRepCodes: ' + changedRepCodes);
            }
        }
        if(!changedRepCodes.isEmpty()){
            Map<Id,FinServ__FinancialAccount__c> finAcctsToUpdate = new Map<Id, FinServ__FinancialAccount__c>([SELECT Id, Rep_Code_Lookup__c, Financial_Advisor_Team__c, FinServ__PrimaryOwner__c, FinServ__PrimaryOwner__r.PersonContactId, 
                                                                   FinServ__PrimaryOwner__r.Financial_Advisor_Team__c, FinServ__PrimaryOwner__r.Household__c FROM FinServ__FinancialAccount__c 
                                                                   WHERE Rep_Code_Lookup__c in: changedRepCodes]);
            System.debug('finAcctsToUpdate: ' + finAcctsToUpdate);
            Set<Id> finAcctIds = new Set<Id>();
            Map<Id,Id> primaryToFAT = new Map<Id,Id>();
            Map<Id,Id> hhToFAT = new Map<Id,Id>();
            Set<Id> contactIds = new Set<Id>();
            Set<Id> acctsToUpdateIds = new Set<Id>();
            List<Account> acctsToUpdate = new List<Account>();
            
            for(FinServ__FinancialAccount__c f : finAcctsToUpdate.values()){
                System.debug('f' + f);
                f.Financial_Advisor_Team__c = newMap.get(f.Rep_Code_Lookup__c).Financial_Advisor_Team__c;
                finAcctIds.add(f.Id);
                primaryToFAT.put(f.FinServ__PrimaryOwner__r.PersonContactId, f.Financial_Advisor_Team__c);
                Account a = new Account(Id = f.FinServ__PrimaryOwner__c, Financial_Advisor_Team__c = f.Financial_Advisor_Team__c);
                acctsToUpdateIds.add(f.FinServ__PrimaryOwner__c);
                acctsToUpdate.add(a);
            }
            update finAcctsToUpdate.values();
            
            List<AccountContactRelation> acrs = [SELECT Id, AccountId, ContactId, Contact.AccountId FROM AccountContactRelation WHERE ContactId in: primaryToFAT.keyset()];
            System.debug('acrList: ' + acrs);
            for(AccountContactRelation a : acrs){
                hhToFAT.put(a.AccountId, primaryToFAT.get(a.Contact.AccountId));
                contactIds.add(a.ContactId);
            }
            List<AccountContactRelation> acrsMinusPrimary = [SELECT Id, AccountId, ContactId, Contact.AccountId FROM AccountContactRelation WHERE AccountId in: hhToFAT.keyset() AND ContactId NOT in: primaryToFAT.keyset()];
            for(AccountContactRelation a : acrsMinusPrimary){
                if(!acctsToUpdateIds.contains(a.Contact.AccountId)){
                    Account acc = new Account(Id=a.Contact.AccountId, Financial_Advisor_Team__c = hhToFAT.get(a.AccountId));
                    acctsToUpdateIds.add(a.Contact.AccountId);
                    acctsToUpdate.add(acc); 
                }
            }
            
            Map<Id,Case> casesToUpdate = new Map<Id,Case>([SELECT Id, Financial_Advisor_Team__c, FinServ__FinancialAccount__r.Rep_Code_Lookup__c, FinServ__Household__c  FROM Case WHERE FinServ__Household__c in: hhToFAT.keyset() OR FinServ__FinancialAccount__c in: finAcctIds]);
            for(Case c : casesToUpdate.values()){
                if(hhToFAT.keyset().contains(c.FinServ__Household__c)){
                    c.Financial_Advisor_Team__c = hhToFAT.get(c.FinServ__Household__c);
                } else {
                    c.Financial_Advisor_Team__c = newMap.get(c.FinServ__FinancialAccount__r.Rep_Code_Lookup__c).Financial_Advisor_Team__c;
                }
            }
            
            List<Task> tasksToUpdate = [SELECT Id, Financial_Advisor_Team__c, WhatId, What.Type FROM Task WHERE WhatId in: hhToFAT.keyset() OR WhatId in: finAcctIds OR WhoId in: contactIds];
            for(Task t : tasksToUpdate){
                System.debug('t: ' + t);
                System.debug('t.WhatId.SobjectType: ' + t.what.Type);
                if(hhToFAT.keyset().contains(t.WhatId)){
                    t.Financial_Advisor_Team__c = hhToFAT.get(t.WhatId);
                } else if (t.What.Type == 'Case'){
                    t.Financial_Advisor_Team__c = casesToUpdate.get(t.WhatId).Financial_Advisor_Team__c;
                } else {
                    t.Financial_Advisor_Team__c = newMap.get(finAcctsToUpdate.get(t.WhatId).Rep_Code_Lookup__c).Financial_Advisor_Team__c;
                }
            }
            
            List<Event> eventsToupdate = [SELECT Id, Financial_Advisor_Team__c, WhatId, What.Type FROM Event WHERE WhatId in: hhToFAT.keyset() OR WhatId in: finAcctIds OR WhoId in: contactIds];
            for(Event e : eventsToUpdate){
                if(hhToFAT.keyset().contains(e.WhatId)){
                    e.Financial_Advisor_Team__c = hhToFAT.get(e.WhatId);
                } else if (e.What.Type == 'Case'){
                    e.Financial_Advisor_Team__c = casesToUpdate.get(e.WhatId).Financial_Advisor_Team__c;
                } else {
                    e.Financial_Advisor_Team__c = newMap.get(finAcctsToUpdate.get(e.WhatId).Rep_Code_Lookup__c).Financial_Advisor_Team__c;
                }
            }
            if(!acctsToUpdate.isEmpty()){
                System.debug('accounts To Update: ' + acctsToUpdate);
                update acctsToUpdate;
            }
            if(!casesToUpdate.isEmpty()){
                update casesToUpdate.values();
            }
            if(!tasksToUpdate.isEmpty()){
                update tasksToUpdate;
            }
            if(!eventsToupdate.isEmpty()){
                update eventsToupdate;
            }
        }
    }

    /*public static void updateRepCode(Map<Id, Rep_Code__c> newMap, Map<Id, Rep_Code__c> oldMap){
        Map<Rep_Code__c,String> changedRepCodes = new Map<Rep_Code__c,String>();
        for(Id newId:newMap.keyset())
        {
            if(newMap.get(newId).Related_Advisors__c !=oldMap.get(newId).Related_Advisors__c)
            {
                changedRepCodes.put(newMap.get(newId),newMap.get(newId).Related_Advisors__c);
            }
        }
        if(!changedRepCodes.isEmpty())
        {
            Financial_Advisor_Team__c fAdvisorTeam = [Select id, Name From Financial_Advisor_Team__c Where Name = 'Default Team' Limit 1]; 

            Map<String,Id> teamMembersTeam = new Map<String,Id>();
            List<Financial_Advisor_Team__c> lst = [Select Id,Related_Advisors__c from Financial_Advisor_Team__c where Related_Advisors__c in:changedRepCodes.values()];
            for(Financial_Advisor_Team__c fat:lst)
            {
                teamMembersTeam.put(fat.Related_Advisors__c,fat.Id);
            }
            for(Rep_Code__c repCode:changedRepCodes.keyset())
            {
                repCode.Financial_Advisor_Team__c = fAdvisorTeam.Id;
                if(teamMembersTeam.get(repCode.Related_Advisors__c)!=null)
                {
                    repCode.Financial_Advisor_Team__c = teamMembersTeam.get(repCode.Related_Advisors__c);
                }
            }
        }
    }*/
   /* public static List<Rep_Code__c> prepopulateRepoCodeRecords(List<Rep_Code__c> newList){
        List<Financial_Advisor_Team__c> defaultTeam = [Select Id from Financial_Advisor_Team__c where Name = 'Default Team' limit 1];
        Set<String> advisorTexIdSet = new Set<String>();
        for(Rep_Code__c record : newList){
            if(String.isnotBlank(record.Advisor_Tax_Id__c)){
                advisorTexIdSet.add(record.Advisor_Tax_Id__c);
            }
            if(record.Ext_Id__c == null){
                record.Ext_Id__c = record.Name + record.Advisor_Tax_Id__c;
            }
        }  
        if(advisorTexIdSet.size() > 0){
            List<Financial_Advisor_Team_Member__c> finAccountList = [Select id, Financial_Advisor_Team__c, User__r.Advisor_SSN__c From Financial_Advisor_Team_Member__c 
                                                                     Where User__r.Advisor_SSN__c IN : advisorTexIdSet];
            
            Map<String, List<Id>> codeWithListOfTeamMemberId = new Map<String, List<Id>>();
            for(Financial_Advisor_Team_Member__c fadvisorTMemmebr : finAccountList){
                if(!codeWithListOfTeamMemberId.containsKey(fadvisorTMemmebr.User__r.Advisor_SSN__c)){
                    codeWithListOfTeamMemberId.put(fadvisorTMemmebr.User__r.Advisor_SSN__c,new List<Id>{fadvisorTMemmebr.Financial_Advisor_Team__c});
                    
                } else{
                    List<Id> teamMamebrIdList = codeWithListOfTeamMemberId.get(fadvisorTMemmebr.User__r.Advisor_SSN__c);
                    teamMamebrIdList.add(fadvisorTMemmebr.Financial_Advisor_Team__c);
                    codeWithListOfTeamMemberId.put(fadvisorTMemmebr.User__r.Advisor_SSN__c,teamMamebrIdList);
                }
            }
            for(Rep_Code__c record : newList){
                if(codeWithListOfTeamMemberId.get(record.Advisor_Tax_Id__c) != null){
                    List<Id> teamMemberIdList = codeWithListOfTeamMemberId.get(record.Advisor_Tax_Id__c);
                    if(teamMemberIdList.size() == 1){
                        record.Financial_Advisor_Team__c = codeWithListOfTeamMemberId.get(record.Advisor_Tax_Id__c)[0];
                    }
                }
                if(record.Financial_Advisor_Team__c ==null && !defaultTeam.isEmpty())
                {
                    record.Financial_Advisor_Team__c = defaultTeam[0].Id;
                }
            }
        }
        return newList;
    }*/
    /*private static void updateFinFinancialAccounts(Map<Id, Rep_Code__c> newMap, Map<Id, Rep_Code__c> oldMap){
        Set<Id> repCodeIdsForBatch = new Set<Id>();
        //Map<String, Id> repCodeWithFinAdTeamIdMap = new Map<String, Id>();
        //Set<String> repCodes = new Set<String>();
        //Set<String> intTypes = new Set<String>();
        for(Rep_Code__c record : newMap.values()){
            if(record.Financial_Advisor_Team__c != null && String.isnotBlank(record.Name) &&
               oldMap.get(record.Id).Financial_Advisor_Team__c != record.Financial_Advisor_Team__c){
                //repCodes.add(record.Name);
                //intTypes.add(record.Interface_Type__c);
                //String codeInterfaceId = record.Name + record.Interface_Type__c;
                //repCodeWithFinAdTeamIdMap.put(codeInterfaceId, record.Financial_Advisor_Team__c);
                repCodeIdsForBatch.add(record.Id);
               }
        }  
        if(!repCodeIdsForBatch.isEmpty())
        {
            UpdateFATeamQueueable updateJob = new UpdateFATeamQueueable(repCodeIdsForBatch);
			System.enqueueJob(updateJob);
            //Database.executeBatch(new Batch_UpdateFATeam(repCodeIdsForBatch));
        }
        //if(repCodeWithFinAdTeamIdMap.size() > 0){
           // List<FinServ__FinancialAccount__c> finAccountList = [Select id, Financial_Advisor_Team__c, Rep_Code__c,Code_Interface_Id__c,Interface_Type__c
                                                                 //From FinServ__FinancialAccount__c 
                                                                 //Where Rep_Code__c IN : repCodes and Interface_Type__c in:intTypes];
           // if(finAccountList.size() > 0){
               // for(FinServ__FinancialAccount__c finAcc : finAccountList){
                 //   finAcc.Financial_Advisor_Team__c = repCodeWithFinAdTeamIdMap.get(finAcc.Code_Interface_Id__c);
                //}
            //}
           // update finAccountList;
        //}
    }*/
}