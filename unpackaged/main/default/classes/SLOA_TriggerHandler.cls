public class SLOA_TriggerHandler {
	public void isBeforeInsert(List<Standing_Letter_of_Authorization__c> newList){
    	setOwnerOnSLOA(newList, null);
	}

	public void isBeforeUpdate(Map<Id,Standing_Letter_of_Authorization__c> newMap, Map<Id,Standing_Letter_of_Authorization__c> oldMap){
		setOwnerOnSLOA(newMap.values(), oldMap);
	}

	public void isBeforeDelete(Map<Id,Standing_Letter_of_Authorization__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Standing_Letter_of_Authorization__c> newMap){
		createShareRecord(newMap, null);
	}

	public void isAfterUpdate(Map<Id,Standing_Letter_of_Authorization__c> newMap, Map<Id,Standing_Letter_of_Authorization__c> oldMap){
		createShareRecord(newMap, oldMap);
	}

	public void isAfterDelete(Map<Id,Standing_Letter_of_Authorization__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Standing_Letter_of_Authorization__c> newMap){

	}
    
    private static void setOwnerOnSLOA(List<Standing_Letter_of_Authorization__c> newList,  Map<Id, Standing_Letter_of_Authorization__c> oldMap){
        Set<Id> finAdvisorTeamIdSet = new Set<Id>();
        for(Standing_Letter_of_Authorization__c record : newList) {
            if(record.Financial_Advisor_Team__c != null && (oldMap == null || (oldMap != null && record.Financial_Advisor_Team__c != oldMap.get(record.Id).Financial_Advisor_Team__c))) {
                finAdvisorTeamIdSet.add(record.Financial_Advisor_Team__c);
            }
        }
        
        if(!finAdvisorTeamIdSet.isEmpty()){
            List<Financial_Advisor_Team__c> finAdTeamList = [SELECT Id, (SELECT ID, User__c FROM Financial_Advisor_Team_Members__r WHERE Active__c = true AND Role__c =: 'Financial Advisor') FROM Financial_Advisor_Team__c WHERE Id IN : finAdvisorTeamIdSet];
            if(!finAdTeamList.isEmpty()){
                Map<Id, Id> finAdTeamIdWithUserIdMap = new Map<Id, Id>();
                for(Financial_Advisor_Team__c finAdTeamRecord : finAdTeamList) {
                    List<Financial_Advisor_Team_Member__c> finAdTeamMemberList = finAdTeamRecord.Financial_Advisor_Team_Members__r;
                    if(!finAdTeamMemberList.isEmpty()) {
                        if(finAdTeamMemberList[0].User__c != null) {
                            finAdTeamIdWithUserIdMap.put(finAdTeamRecord.Id, finAdTeamMemberList[0].User__c);
                        }
                    }
                }
                for(Standing_Letter_of_Authorization__c record : newList) {
                    if(oldMap == null || (oldMap != null && record.Financial_Advisor_Team__c != oldMap.get(record.Id).Financial_Advisor_Team__c)) {
                        if(finAdTeamIdWithUserIdMap.get(record.Financial_Advisor_Team__c) != null) {
                            record.OwnerId = finAdTeamIdWithUserIdMap.get(record.Financial_Advisor_Team__c);
                        }
                    } 
                }
            }
        }
    }
    
    public static void createShareRecord(Map<Id, Standing_Letter_of_Authorization__c> newMap, Map<Id, Standing_Letter_of_Authorization__c> oldMap){
        Set<Id> fAccTeamIdSet = new Set<Id>();
        for(Standing_Letter_of_Authorization__c record : newMap.values()){
            if(oldMap==null){
                if(record.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(record.Financial_Advisor_Team__c);
            } else if(oldMap.get(record.Id).Financial_Advisor_Team__c!=record.Financial_Advisor_Team__c || oldMap.get(record.Id).OwnerId != record.OwnerId){
                if(record.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(record.Financial_Advisor_Team__c);
                if(oldMap.get(record.Id).Financial_Advisor_Team__c != null){
                    fAccTeamIdSet.add(oldMap.get(record.Id).Financial_Advisor_Team__c);
                }
            } 
        }
        if(!fAccTeamIdSet.isEmpty()){
            Map<Id, Financial_Advisor_Team__c> fATeamMap = new Map<Id, Financial_Advisor_Team__c>([Select Id, Public_Group_Id__c From Financial_Advisor_Team__c Where Id IN : fAccTeamIdSet]);
            if(fATeamMap.size() > 0){
                List<Standing_Letter_of_Authorization__Share> shareRecordList = new List<Standing_Letter_of_Authorization__Share>();
                //For revoke Share
                Set<Id> groupIdSet = new Set<Id>();
                Set<Id> parentIdSet = new Set<Id>();
                for(Standing_Letter_of_Authorization__c record : newMap.values()){
                    Standing_Letter_of_Authorization__Share shareRec = new Standing_Letter_of_Authorization__Share();
                    if(fATeamMap.get(record.Financial_Advisor_Team__c)!=null){
                        shareRec.ParentId = record.Id;
                        if(record.Financial_Advisor_Team__c != null){
                            shareRec.UserOrGroupId = fATeamMap.get(record.Financial_Advisor_Team__c).Public_Group_Id__c;
                        }
                        
                        shareRec.AccessLevel = 'Edit';
                        shareRec.RowCause = Schema.Standing_Letter_of_Authorization__Share.RowCause.Manual;
                        if(oldMap == null){
                            if(record.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);
                            }
                        } else if(oldMap != null && (oldMap.get(record.Id).Financial_Advisor_Team__c != record.Financial_Advisor_Team__c ||
                                        oldMap.get(record.Id).OwnerId != record.OwnerId)){
                            if(oldMap.get(record.Id).Financial_Advisor_Team__c != null 
                                && fATeamMap.get(oldMap.get(record.Id).Financial_Advisor_Team__c) != null){
                                    groupIdSet.add(fATeamMap.get(oldMap.get(record.Id).Financial_Advisor_Team__c).Public_Group_Id__c);
                                    parentIdSet.add(record.Id);
                                }            
                            if(record.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);                                 
                            }
                        }
                    }
                }
                if(groupIdSet.size() > 0 && parentIdSet.size() > 0){
                    List<AccountShare> removeShareList = new List<AccountShare>();
                    for(AccountShare shareRec: [SELECT id, AccountId, UserOrGroupId FROM AccountShare WHERE AccountId IN: parentIdSet and UserOrGroupId IN: groupIdSet]){
                        if(groupIdSet.Contains(shareRec.UserOrGroupId) && parentIdSet.contains(shareRec.AccountId) ){
                            removeShareList.add(shareRec);
                        }
                    }
                    if(removeShareList.size() > 0){
                        Database.delete(removeShareList,false);
                    } 
                }
                if(shareRecordList.size() > 0){
                    Database.insert(shareRecordList,false);
                }
            }
        }
    }
}