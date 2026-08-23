public without sharing class Financial_Advisor_Team_TriggerHandler { 
    public Financial_Advisor_Team_TriggerHandler() {}
    
    public void isBeforeInsert(List<Financial_Advisor_Team__c> newList){
        createPublicGroup(newList, null);
    }
    public void isBeforeUpdate(Map<Id, Financial_Advisor_Team__c> newMap, Map<Id, Financial_Advisor_Team__c> oldMap){
        createPublicGroup(newMap.values(), oldMap);
        updateRepCode(newMap,oldMap);
    }
    public void isBeforeDelete(Map<Id, Financial_Advisor_Team__c> oldMap){}
    public void isAfterInsert(Map<Id, Financial_Advisor_Team__c> newMap){
        createShareRecord(newMap);
        createFinancialAdvisorTeamMember(newMap);
    }
    public void isAfterUpdate(Map<Id, Financial_Advisor_Team__c> newMap, Map<Id, Financial_Advisor_Team__c> oldMap){
        createAndUpdateFinancialAdvisorTeamMember(newMap,oldMap);
    }
    public void isAfterDelete(Map<Id, Financial_Advisor_Team__c> oldMap){}
    public void isAfterUnDelete(Map<Id, Financial_Advisor_Team__c> newMap){}
    
    // Method to create Financial Advisor Team Members when Primary Financial Advisor is missing
    private void createFinancialAdvisorTeamMember(Map<Id,Financial_Advisor_Team__c> newMap){
        List<Financial_Advisor_Team_Member__c> fastmListToInsert = new List<Financial_Advisor_Team_Member__c>();
        
        // Loop through the Financial Advisor Teams
        for(Financial_Advisor_Team__c fat : newMap.values()){
            // Check if the Primary Financial Advisor is missing
            if(!string.isEmpty(fat.Primary_Financial_Advisor__c))
            {
                // Create a new Financial Advisor Team Member
                Financial_Advisor_Team_Member__c fatm = new Financial_Advisor_Team_Member__c();
                fatm.Financial_Advisor_Team__c = fat.Id;
                fatm.User__c = fat.Primary_Financial_Advisor__c;
                fatm.Active__c = true;
                fatm.Primary__c = true;
                fatm.Role__c = 'Financial Advisor';
                
                // Add to the list to be inserted
                fastmListToInsert.add(fatm);
            }
        }
        
        // Insert the new team members if the list is not empty
        if(!fastmListToInsert.isEmpty()){
            insert fastmListToInsert;
        }
    }
    
    // Method to create and update Financial Advisor Team Members based on changes in the Primary Financial Advisor
    private void createAndUpdateFinancialAdvisorTeamMember(Map<Id,Financial_Advisor_Team__c> newMap,Map<Id,Financial_Advisor_Team__c> oldMap){
        Set<Id> fatIds = new Set<Id>();
        Set<Id> pfaIds = new Set<Id>();
        
        // Loop through the new Financial Advisor Teams
        for(Financial_Advisor_Team__c fat : newMap.values()){
                            system.debug('fat.Primary_Financial_Advisor__c'+ fat.Primary_Financial_Advisor__c);
                            system.debug('fat.Primary_Financial_Advisor__c'+ fat.Primary_Financial_Advisor__c);
                            system.debug('oldMap.get(fat.Id).Primary_Financial_Advisor__c)'+ oldMap.get(fat.Id).Primary_Financial_Advisor__c);

            // Check if the Primary Financial Advisor has changed or is missing
            if(!string.isEmpty(fat.Primary_Financial_Advisor__c) 
               && fat.Primary_Financial_Advisor__c != oldMap.get(fat.Id).Primary_Financial_Advisor__c){
                   // Add to the sets for processing
                   fatIds.add(fat.Id);
                   pfaIds.add(fat.Primary_Financial_Advisor__c);
               }
        }
                system.debug('fatIds'+ fatIds);
        system.debug('pfaIds'+ pfaIds);

        // Query existing Financial Advisor Team Members for the relevant teams and advisors
        List<Financial_Advisor_Team_Member__c> fatmList = [SELECT Id,Financial_Advisor_Team__c,User__c FROM  Financial_Advisor_Team_Member__c 
                                                           WHERE Financial_Advisor_Team__c IN : fatIds AND User__c IN : pfaIds];
        
        // Map to organize Financial Advisor Team Members by team and user
        Map<String,List<Financial_Advisor_Team_Member__c>> keyAndFatmListMap = new Map<String,List<Financial_Advisor_Team_Member__c>>();
        for(Financial_Advisor_Team_Member__c fatm : fatmList){
            string key = fatm.Financial_Advisor_Team__c + '::' + fatm.User__c;
            if(!keyAndFatmListMap.containsKey(key)){
                keyAndFatmListMap.put(key, new List<Financial_Advisor_Team_Member__c>());
            }
            keyAndFatmListMap.get(key).add(fatm);
        }
        system.debug('keyAndFatmListMap'+ keyAndFatmListMap);
        // Lists for inserting new members and updating existing ones
        List<Financial_Advisor_Team_Member__c> fastmListToInsert = new List<Financial_Advisor_Team_Member__c>();
        Map<Id, Financial_Advisor_Team_Member__c> fastmMapToUpdate = new Map<Id, Financial_Advisor_Team_Member__c>();
        
        // Process each Financial Advisor Team for the updates
        for(Id fatId : fatIds){
            Financial_Advisor_Team__c fat = newMap.get(fatId);
            string key = fat.Id + '::' + fat.Primary_Financial_Advisor__c;
                    system.debug('key'+ key);

            // If the team members exist,update them
            if(keyAndFatmListMap.containsKey(key)){
                for(Financial_Advisor_Team_Member__c fatm : keyAndFatmListMap.get(key)){
                    fatm.Active__c = true;
                    fatm.Primary__c = true;
                    fatm.Role__c = 'Financial Advisor';
                    fastmMapToUpdate.put(fatm.Id, fatm);
                }
            }else{
                // If the team member does exist, create a new one for insertion
                Financial_Advisor_Team_Member__c fatm = new Financial_Advisor_Team_Member__c();
                fatm.Financial_Advisor_Team__c = fat.Id;
                fatm.User__c = fat.Primary_Financial_Advisor__c;
                fatm.Active__c = true;
                fatm.Primary__c = true;
                fatm.Role__c = 'Financial Advisor';
                fastmListToInsert.add(fatm);
            }
        }
        
        // Query existing primary Financial Advisor Team Members to deactivate others
        List<Financial_Advisor_Team_Member__c> fatmOtherList = [SELECT Id,Financial_Advisor_Team__c,User__c FROM  Financial_Advisor_Team_Member__c 
                                                                WHERE Financial_Advisor_Team__c IN : fatIds AND Primary__c = true]; 
        
        // Deactivate previous primary advisors if they are not in the current updates
        for(Financial_Advisor_Team_Member__c fatm : fatmOtherList){
            if(!fastmMapToUpdate.containsKey(fatm.Id)){
                fatm.Primary__c = false;
                fastmMapToUpdate.put(fatm.Id, fatm);
            }
        }
                system.debug('fastmListToInsert'+fastmListToInsert);

        // Insert new Financial Advisor Team Members if needed
        if(!fastmListToInsert.isEmpty()){
            insert fastmListToInsert;
        }
        system.debug('fastmMapToUpdate'+fastmMapToUpdate);
        // Update existing team members if needed
        if(!fastmMapToUpdate.isEmpty()){
            update fastmMapToUpdate.values();
        }
    }
    
    
    private void createPublicGroup(List<Financial_Advisor_Team__c> newList, Map<Id, Financial_Advisor_Team__c> oldMap){
        Map<String, Group> fAdvisorTeamNameWithGroupMap = new Map<String, Group>();
        Set<Id> publicGroupIdSet = new Set<Id>();
        for(Financial_Advisor_Team__c fAdvisorTeam : newList) {
            if(oldMap == null){
                Group groupRecord = new Group();
                groupRecord.Name = fAdvisorTeam.Name.left(40);
                fAdvisorTeamNameWithGroupMap.put(fAdvisorTeam.Name, groupRecord);
            } else if (oldMap != null && oldMap.get(fAdvisorTeam.Id).Name.left(40) != fAdvisorTeam.Name){
                publicGroupIdSet.add(fAdvisorTeam.Public_Group_Id__c);
            }
        }
        
        //Insert case
        if(fAdvisorTeamNameWithGroupMap.size() > 0){
            insert fAdvisorTeamNameWithGroupMap.values();
            for(Financial_Advisor_Team__c fAdvisorTeam : newList) {
                fAdvisorTeam.Public_Group_ID__c = fAdvisorTeamNameWithGroupMap.get(fAdvisorTeam.Name).Id;
            }
        }
        
        //Update Case
        if(publicGroupIdSet.size() > 0){
            Map<Id, Group> publicGroupMap = new Map<Id, Group>([Select Id, Name From Group Where Id IN : publicGroupIdSet]);
            for(Financial_Advisor_Team__c fAdvisorTeam : newList) {
                if (oldMap != null && oldMap.get(fAdvisorTeam.Id).Name != fAdvisorTeam.Name){
                    if(publicGroupMap.size() > 0){
                        Group existingGroup = publicGroupMap.get(fAdvisorTeam.Public_Group_ID__c);
                        existingGroup.Name = fAdvisorTeam.Name.left(40);
                    }
                }
            }
            update publicGroupMap.values();
        }
    }
    
    private void createShareRecord(Map<Id, Financial_Advisor_Team__c> newMap) {
        List<Financial_Advisor_Team__Share> fatShareRecordList = new List<Financial_Advisor_Team__Share>();
        for(Financial_Advisor_Team__c fatRecord : newMap.values()) {
            if(fatRecord.Public_Group_ID__c != null){
                Financial_Advisor_Team__Share shareRec = new Financial_Advisor_Team__Share();
                shareRec.ParentId = fatRecord.Id;
                shareRec.UserOrGroupId = fatRecord.Public_Group_ID__c;
                shareRec.AccessLevel = 'Read';
                shareRec.RowCause = Schema.Financial_Advisor_Team__Share.RowCause.Manual;
                fatShareRecordList.add(shareRec);
            }
        }
        if(!fatShareRecordList.isEmpty()){
            insert fatShareRecordList;
        }
    }
    
    private void updateRepCode(Map<Id, Financial_Advisor_Team__c> newMap, Map<Id, Financial_Advisor_Team__c> oldMap){
        Map<String, Financial_Advisor_Team__c> relatedAdvisorsFATs = new Map<String, Financial_Advisor_Team__c>();
        System.debug('Default team is 1 ');
        Financial_Advisor_Team__c defaultTeam = [SELECT Id FROM Financial_Advisor_Team__C WHERE Name = 'Default Team'];
        System.debug('Default team is 2');
        for(Financial_Advisor_Team__c newFAT : newMap.values()){
            Financial_Advisor_Team__c oldFAT = oldMap.get(newFAT.id);
            if(newFAT.Related_Advisors__c != oldFAT.Related_Advisors__c && newFAT.Related_Advisors__c != null){
                relatedAdvisorsFATs.put(newFAT.Related_Advisors__c, newFAT);
            }
        }
        
        Map<Rep_Code__c,String> changedRepCodes = new Map<Rep_Code__c,String>();
        List<Rep_Code__c> repCodes = [SELECT Id, Related_Advisors__c FROM Rep_Code__c WHERE Financial_Advisor_Team__c != null AND Financial_Advisor_Team__c =: defaultTeam.Id AND Related_Advisors__c =: relatedAdvisorsFATs.keyset()];
        if(!repCodes.isEmpty()){
            for(Rep_Code__c r:repCodes){
                changedRepCodes.put(r, r.Related_Advisors__c);
            }
        }
        if(!changedRepCodes.isEmpty())
        {
            for(Rep_Code__c repCode:changedRepCodes.keyset())
            {
                if(relatedAdvisorsFATs.get(repCode.Related_Advisors__c)!=null)
                {
                    repCode.Financial_Advisor_Team__c = relatedAdvisorsFATs.get(repCode.Related_Advisors__c).id;
                }
            }
        }
        update repCodes;
    }
}