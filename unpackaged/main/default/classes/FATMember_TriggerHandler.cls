public without sharing class FATMember_TriggerHandler {
    private Map<Id, Financial_Advisor_Team_Member__c> fatmForUpdate;
    private Map<Id, Financial_Advisor_Team__c> fatForUpdate;
    public FATMember_TriggerHandler() {}
    
    public void isBeforeInsert(List<Financial_Advisor_Team_Member__c> newList){
        setPermissionOnRule(newList, null);
    }
    
    public void isBeforeUpdate(Map<Id, Financial_Advisor_Team_Member__c> newMap, Map<Id, Financial_Advisor_Team_Member__c> oldMap){
        setPermissionOnRule(newMap.values(), oldMap);
        handleErrorCondition(newMap, oldMap);
    }
    
    public void isBeforeDelete(Map<Id, Financial_Advisor_Team_Member__c> oldMap){}
    
    public void isAfterInsert(Map<Id, Financial_Advisor_Team_Member__c> newMap){
        manageGroupMember(newMap.values(), null);
        managePrimaryFATMember(newMap);
        handlePermissions(newMap, null);
        setFinancialAdvisorTeam(newMap);
        //createAGM(newMap, null);
    }
    
    public void isAfterUpdate(Map<Id, Financial_Advisor_Team_Member__c> newMap, Map<Id, Financial_Advisor_Team_Member__c> oldMap){
        manageGroupMember(newMap.values(), oldMap);
        managePrimaryFATMember(newMap);
        handlePermissions(newMap, oldMap);
        //createAGM(newMap, oldMap);
    }
    
    public void isAfterDelete(Map<Id, Financial_Advisor_Team_Member__c> oldMap){
        deleteGroupMember(oldMap);
    }
    
    public void isAfterUnDelete(Map<Id, Financial_Advisor_Team_Member__c> newMap){}
    
    private void setFinancialAdvisorTeam(Map<Id,Financial_Advisor_Team_Member__c> newMap){
        List<Financial_Advisor_Team__c> fatListToUpdate = new List<Financial_Advisor_Team__c>();
        for(Financial_Advisor_Team_Member__c fatm : newMap.values()){
            if(!string.isEmpty(fatm.Financial_Advisor_Team__c) && !string.isEmpty(fatm.User__c) && fatm.Active__c == true 
               && fatm.Primary__c == true && fatm.Role__c == 'Financial Advisor'){
                fatListToUpdate.add(new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c,Primary_Financial_Advisor__c = fatm.User__c));
            }
        }
        if(!fatListToUpdate.isEmpty()){
            update fatListToUpdate;
        }
    }

    
    
    private void setPermissionOnRule(List<Financial_Advisor_Team_Member__c> newList, Map<Id, Financial_Advisor_Team_Member__c> oldMap){
        for( Financial_Advisor_Team_Member__c fatm : newList){
            if(fatm.Role__c == 'CSA' && (oldMap == null || fatm.Role__c != oldMap.get(fatm.Id).Role__c)) {
                fatm.CSA__c = true;
            }
            else if(fatm.Role__c == 'Associate Advisor' && (oldMap == null || fatm.Role__c != oldMap.get(fatm.Id).Role__c)) {
                fatm.Associate_Advisor__c = true;
            }
        }
    }
    
    private void manageGroupMember(List<Financial_Advisor_Team_Member__c> newList, Map<Id, Financial_Advisor_Team_Member__c> oldMap){
        Set<Id> financialAdTeamIDSet = new Set<Id>();
        for(Financial_Advisor_Team_Member__c fAdvisorTeamMember : newList) {
            if(fAdvisorTeamMember.Financial_Advisor_Team__c != null){
                financialAdTeamIDSet.add(fAdvisorTeamMember.Financial_Advisor_Team__c);
            }
        }
        Map<String, Id> groupIdWithUserIdMap = new Map<String, Id>();
        Set<Id> groupMemberIdSet = new Set<Id>();
        Map<Id, Financial_Advisor_Team__c> fATeamMap = new Map<Id, Financial_Advisor_Team__c>([Select Id, Public_Group_Id__c From Financial_Advisor_Team__c Where Id IN : financialAdTeamIDSet]);
        for(Financial_Advisor_Team_Member__c fAdvisorTeamMember : newList) {
            if((oldMap == null && fAdvisorTeamMember.Active__c) || 
               (oldMap != null && !oldMap.get(fAdvisorTeamMember.Id).Active__c && fAdvisorTeamMember.Active__c)){
                   groupIdWithUserIdMap.put(fATeamMap.get(fAdvisorTeamMember.Financial_Advisor_Team__c).Public_Group_Id__c, fAdvisorTeamMember.User__c);
               } else if(oldMap != null && oldMap.get(fAdvisorTeamMember.Id).Active__c && !fAdvisorTeamMember.Active__c){
                   groupMemberIdSet.add(fAdvisorTeamMember.Group_Member_Id__c);
               }
        }
        if(groupIdWithUserIdMap.size() > 0){
            System.enqueueJob(new CreateGroupMemberQueue(groupIdWithUserIdMap, newList, fATeamMap));
        }
        
        //Update case when Active set from true to false
        if(groupMemberIdSet.size() > 0){
            deleteGroupMember(groupMemberIdSet);
            List<Financial_Advisor_Team_Member__c> fATMemberToUpdateList = new List<Financial_Advisor_Team_Member__c>();
            for(Financial_Advisor_Team_Member__c fAdvisorTeamMember : newList) {
                if(groupMemberIdSet.contains(fAdvisorTeamMember.Group_Member_Id__c)){
                    Financial_Advisor_Team_Member__c fatM = new Financial_Advisor_Team_Member__c(Id = fAdvisorTeamMember.Id);
                    fatM.Group_Member_Id__c = '';
                    fATMemberToUpdateList.add(fatM);
                }
            }
            update fATMemberToUpdateList;
        }
    }
    
    private void deleteGroupMember(Map<Id, Financial_Advisor_Team_Member__c> oldMap){
        Set<Id> groupMemberIdSet = new Set<Id>();
        for(Financial_Advisor_Team_Member__c fATMember : oldMap.values()){
            groupMemberIdSet.add(fATMember.Group_Member_Id__c);
        }
        if(groupMemberIdSet.size() > 0){
            deleteGroupMember(groupMemberIdSet);
        }
    }
    
    @future
    private static void deleteGroupMember(Set<Id> groupMemberIdSet){
        delete [Select Id From GroupMember Where ID IN : groupMemberIdSet];
    }
    
    public void managePrimaryFATMember(Map<Id,Financial_Advisor_Team_Member__c> newMap){
        set<Id> fatIds=new set<Id>();
        List<Financial_Advisor_Team_Member__c> fatmToBeUpdated=new List<Financial_Advisor_Team_Member__c>();
        for(Financial_Advisor_Team_Member__c fatm:newMap.values()){
            fatIds.add(fatm.Financial_Advisor_Team__c);
        }
        Map<Id,Financial_Advisor_Team__c> fatmMap = new Map<Id,Financial_Advisor_Team__c>([select Id,(select Id,Financial_Advisor_Team__c,Primary__c from Financial_Advisor_Team_Members__r where Primary__c=true) from Financial_Advisor_Team__c where Id IN:fatIds]);
        
        
        for(Financial_Advisor_Team_Member__c fatm : newMap.values()){
            if(fatm.Primary__c){
                for(Financial_Advisor_Team_Member__c fatmold : fatmMap.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r){
                    if(fatmold.Id !=fatm.Id){
                        fatmold.Primary__c = false;
                        fatmToBeUpdated.add(fatmold);
                    }
                }
            }
        }
        update fatmToBeUpdated;
    }
    
    private void handlePermissions(Map<Id, Financial_Advisor_Team_Member__c> newMap, Map<Id, Financial_Advisor_Team_Member__c > oldMap){
        Map<Id, Financial_Advisor_Team_Member__c> draftPaperworkMembers = new Map<Id, Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> reviewPaperworkMembers = new Map<Id, Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> sendNotificationsMembers = new Map<Id, Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> tradingMembers = new Map<Id, Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> csaMembers = new Map<Id, Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> aaMembers = new Map<Id, Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> pmMembers = new Map<Id, Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> operations = new Map<Id, Financial_Advisor_Team_Member__c>();
        
        Set<Id> fatIds = new Set<Id>();
        Map<Id, Financial_Advisor_Team__c> mapFat;
        
        fatmForUpdate = new Map<Id, Financial_Advisor_Team_Member__c>();
        fatForUpdate = new Map<Id, Financial_Advisor_Team__c>();
        
        for(Financial_Advisor_Team_Member__c fatm : newMap.values()){
            if(fatm.Draft_Paperwork__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).Draft_Paperwork__c)){
                draftPaperworkMembers.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
            if(fatm.Review_Paperwork__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).Review_Paperwork__c)) {
                reviewPaperworkMembers.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
            if(fatm.Send_Notifications__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).Send_Notifications__c)) {
                sendNotificationsMembers.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
            if(fatm.Trading__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).Trading__c)) {
                tradingMembers.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
            if(fatm.CSA__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).CSA__c)) {
                csaMembers.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
            if(fatm.Associate_Advisor__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).Associate_Advisor__c)) {
                aaMembers.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
            if(fatm.Project_Manager__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).Project_Manager__c)){
                pmMembers.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
            if(fatm.Operations__c && (oldMap == null || oldMap != null && !oldMap.get(fatm.Id).Operations__c)){
                operations.put(fatm.Id, fatm);
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
        }
        
        if(!fatIds.isEmpty()){
            mapFat = new Map<Id, Financial_Advisor_Team__c>([Select Id, (SELECT Id, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c, Trading__c, CSA__c, Associate_Advisor__c, Project_Manager__c,Operations__c FROM Financial_Advisor_Team_Members__r) FROM Financial_Advisor_Team__c WHERE Id IN :fatIds]);
        }
        
        if(!draftPaperworkMembers.isEmpty()){
            handleDraftPaperwork(draftPaperworkMembers, mapFat);
        }
        if(!reviewPaperworkMembers.isEmpty()){
            handleReviewPaperwork(reviewPaperworkMembers, mapFat);
        }
        if(!sendNotificationsMembers.isEmpty()){
            handleSendNotifications(sendNotificationsMembers, mapFat);
        }
        if(!tradingMembers.isEmpty()){
            handleTrading(tradingMembers, mapFat);
        }
        if(!csaMembers.isEmpty()){
            handleCSA(csaMembers, mapFat);
        }
        if(!aaMembers.isEmpty()){
            handleAA(aaMembers, mapFat);
        }
        if(!pmMembers.isEmpty()){
            handlePM(pmMembers, mapFat);
        }
        if(!operations.isEmpty()){
            handleOperations(operations, mapFat);
        }
        if(!fatForUpdate.isEmpty()){
            update fatForUpdate.values();
        }
        if(!fatmForUpdate.isEmpty()){
            update fatmForUpdate.values();
        }
    }
    
    private void handleDraftPaperwork(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).Draft_Paperwork__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.Draft_Paperwork__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).Draft_Paperwork__c = false;
                }
            }
        } 
    }
    
    private void handleReviewPaperwork(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).Review_Paperwork__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.Review_Paperwork__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).Review_Paperwork__c = false;
                }
            }
        } 
    }
    
    private void handleSendNotifications(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).Send_Notifications__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.Send_Notifications__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).Send_Notifications__c = false;
                }
            }
        } 
    }
    
    private void handleTrading(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).Trading__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.Trading__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).Trading__c = false;
                }
            }
        } 
    }
    
    private void handleCSA(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).CSA__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.CSA__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).CSA__c = false;
                }
            }
        } 
    }
    
    private void handleAA(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).Associate_Advisor__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.Associate_Advisor__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).Associate_Advisor__c = false;
                }
            }
        } 
    }
    
    private void handlePM(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).Project_Manager__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.Project_Manager__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).Project_Manager__c = false;
                }
            }
        } 
    }
    private void handleOperations(Map<Id, Financial_Advisor_Team_Member__c> fatmMap, Map<Id, Financial_Advisor_Team__c> mapFat){
        for(Financial_Advisor_Team_Member__c fatm : fatmMap.values()){
            
            List<Financial_Advisor_Team_Member__c> relatedMembers = mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
            if(!fatForUpdate.containsKey(fatm.Financial_Advisor_Team__c)){
                fatForUpdate.put(fatm.Financial_Advisor_Team__c,new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c));
            }
            fatForUpdate.get(fatm.Financial_Advisor_Team__c).Operations__c = fatm.User_Name__c;
            
            for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                if(fatmRelated.Id != fatm.Id && fatmRelated.Operations__c){
                    if(!fatmForUpdate.containsKey(fatmRelated.Id)){
                        fatmForUpdate.put(fatmRelated.Id,new Financial_Advisor_Team_Member__c(Id = fatmRelated.Id));
                    }
                    fatmForUpdate.get(fatmRelated.Id).Operations__c = false;
                }
            }
        } 
    }
    private void handleErrorCondition( Map<Id, Financial_Advisor_Team_Member__c> newMap, Map<Id, Financial_Advisor_Team_Member__c> oldMap) {
        Set<Id> fatIds = new Set<Id>();
        Map<Id, Financial_Advisor_Team__c> mapFat = new Map<Id, Financial_Advisor_Team__c>();
    
        for(Financial_Advisor_Team_Member__c fatm : newMap.values()){
            if(oldMap != null && (
                (!fatm.Draft_Paperwork__c && oldMap.get(fatm.Id).Draft_Paperwork__c) ||
                (!fatm.Review_Paperwork__c && oldMap.get(fatm.Id).Review_Paperwork__c) ||
                (!fatm.Send_Notifications__c && oldMap.get(fatm.Id).Send_Notifications__c) ||
                (!fatm.Trading__c && oldMap.get(fatm.Id).Trading__c) ||
                (!fatm.Associate_Advisor__c && oldMap.get(fatm.Id).Associate_Advisor__c) ||
                (!fatm.Operations__c && oldMap.get(fatm.Id).Operations__c) ||
                (!fatm.CSA__c && oldMap.get(fatm.Id).CSA__c) ||
                (!fatm.Project_Manager__c && oldMap.get(fatm.Id).Project_Manager__c)
            )){
                fatIds.add(fatm.Financial_Advisor_Team__c);
            }
        }
    
        // Query parent FATs and related members
        if(!fatIds.isEmpty()){
            mapFat = new Map<Id, Financial_Advisor_Team__c>(
                [SELECT Id,
                    (SELECT Id, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c,
                            Trading__c, CSA__c, Associate_Advisor__c, Project_Manager__c, Operations__c
                     FROM Financial_Advisor_Team_Members__r)
                 FROM Financial_Advisor_Team__c
                 WHERE Id IN :fatIds]
            );
        }
    
        List<Financial_Advisor_Team__c> teamsToUpdate = new List<Financial_Advisor_Team__c>();
    
        // Check each changed member and decide whether to null out parent fields
        for(Financial_Advisor_Team_Member__c fatm : newMap.values()){
            if(mapFat.containsKey(fatm.Financial_Advisor_Team__c)){
                Integer draftPaperWorkCount = 0;
                Integer reviewPaperWorkCount = 0;
                Integer sendNotificationCount = 0;
                Integer tradingCount = 0;
                Integer csaCount = 0;
                Integer associateAdvisorCount = 0;
                Integer pmCount = 0;
                Integer operationsCount = 0;
    
                List<Financial_Advisor_Team_Member__c> relatedMembers =
                    mapFat.get(fatm.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
    
                for(Financial_Advisor_Team_Member__c fatmRelated : relatedMembers){
                    if(fatmRelated.Draft_Paperwork__c) draftPaperWorkCount++;
                    if(fatmRelated.Review_Paperwork__c) reviewPaperWorkCount++;
                    if(fatmRelated.Send_Notifications__c) sendNotificationCount++;
                    if(fatmRelated.Trading__c) tradingCount++;
                    if(fatmRelated.CSA__c) csaCount++;
                    if(fatmRelated.Associate_Advisor__c) associateAdvisorCount++;
                    if(fatmRelated.Project_Manager__c) pmCount++;
                    if(fatmRelated.Operations__c) operationsCount++;
                }
    
                Financial_Advisor_Team__c parentTeam = new Financial_Advisor_Team__c(Id = fatm.Financial_Advisor_Team__c);
    
                if(oldMap != null && !fatm.Draft_Paperwork__c && oldMap.get(fatm.Id).Draft_Paperwork__c && draftPaperWorkCount <= 1){
                    parentTeam.Draft_Paperwork__c = null;
                }
                if(oldMap != null && !fatm.Review_Paperwork__c && oldMap.get(fatm.Id).Review_Paperwork__c && reviewPaperWorkCount <= 1){
                    parentTeam.Review_Paperwork__c = null;
                }
                if(oldMap != null && !fatm.Send_Notifications__c && oldMap.get(fatm.Id).Send_Notifications__c && sendNotificationCount <= 1){
                    parentTeam.Send_Notifications__c = null;
                }
                if(oldMap != null && !fatm.Trading__c && oldMap.get(fatm.Id).Trading__c && tradingCount <= 1){
                    parentTeam.Trading__c = null;
                }
                if(oldMap != null && !fatm.Associate_Advisor__c && oldMap.get(fatm.Id).Associate_Advisor__c && associateAdvisorCount <= 1){
                    parentTeam.Associate_Advisor__c = null;
                }
                if(oldMap != null && !fatm.CSA__c && oldMap.get(fatm.Id).CSA__c && csaCount <= 1){
                    parentTeam.CSA__c = null;
                }
                if(oldMap != null && !fatm.Project_Manager__c && oldMap.get(fatm.Id).Project_Manager__c && pmCount <= 1){
                    parentTeam.Project_Manager__c = null;
                }
                if(oldMap != null && !fatm.Operations__c && oldMap.get(fatm.Id).Operations__c && operationsCount <= 1){
                    parentTeam.Operations__c = null;
                }
    
                teamsToUpdate.add(parentTeam);
            }
        }
    
        if(!teamsToUpdate.isEmpty()) {
            update teamsToUpdate;
        }
    }
    /*public void createAGM(Map<Id,Financial_Advisor_Team_Member__c> newMap, Map<Id,Financial_Advisor_Team_Member__c> oldMap){
        List<Advisor_Group_Member__c> agmList = [SELECT Id, User__c, Advisor_Group__c FROM Advisor_Group_Member__c];
        Map<String,Advisor_Group_Member__c> agmMap = new Map<String,Advisor_Group_Member__c>();
        Set<String> agmIds = new Set<String>();
        List<Advisor_Group_Member__c> agmsToInsert = new List<Advisor_Group_Member__c>();
        List<Advisor_Group_Member__c> agmsToDelete = new List<Advisor_Group_Member__c>();
        Map<Id,Id> userToDRP = new Map<Id,Id>();
        Set<Id> userIds = new Set<Id>();
        for(Advisor_Group_Member__c a : agmList){
            String agmId = a.Advisor_Group__c + '' + a.User__c;
            agmIds.add(agmId);
            agmMap.put(agmId, a);
        }
        for(Financial_Advisor_Team_Member__c fatm : newMap.values()){
            userIds.add(fatm.User__c);
        }
        List<Account> drpList = [SELECT Id, User__c FROM Account WHERE User__c in: userIds];
        for(Account drp : drpList){
            userToDRP.put(drp.User__c, drp.Id);
        }
        if(oldMap == null){
            for(Financial_Advisor_Team_Member__c fatm : newMap.values()){
                String agmId = fatm.Advisor_Group__c + '' + fatm.User__c;
                if(!agmIds.contains(agmId)){
                    Advisor_Group_Member__c agm = new Advisor_Group_Member__c();
                    agm.User__c = fatm.User__c;
                    if(userToDRP.get(fatm.User__c)!= null){
                        agm.Diversify_Related_Person__c = userToDRP.get(fatm.User__c);
                    }
                    agm.Advisor_Group__c = fatm.Advisor_Group__c;
                    agmsToInsert.add(agm);
                }
            }
        } else {
            for(Financial_Advisor_Team_Member__c newFATM : newMap.values()){
                Financial_Advisor_Team_Member__c oldFATM = oldMap.get(newFATM.Id);
                if(newFATM.Advisor_Group__c != oldFATM.Advisor_Group__c){
                    String agmOldId = oldFATM.Advisor_Group__c + '' + oldFATM.User__c;
                    String agmNewId = newFATM.Advisor_Group__c + '' + newFATM.User__c;
                    if(!agmIds.contains(agmNewId)){
                        Advisor_Group_Member__c agm = new Advisor_Group_Member__c();
                        agm.User__c = newFATM.User__c;
                        if(userToDRP.get(newFATM.User__c)!= null){
                        	agm.Diversify_Related_Person__c = userToDRP.get(newFATM.User__c);
                    	}
                        agm.Advisor_Group__c = newFATM.Advisor_Group__c;
                        agmsToInsert.add(agm);
                    }
                    if(agmIds.contains(agmOldId)){
                        Advisor_Group_Member__c agmToDelete = agmMap.get(agmOldId);
                        agmsToDelete.add(agmToDelete);
                    }
                }            
            }
        }
        if(!agmsToInsert.isEmpty()){
            insert agmsToInsert;
        }
        if(!agmsToDelete.isEmpty()){
            delete agmsToDelete;
        }
    }*/
}