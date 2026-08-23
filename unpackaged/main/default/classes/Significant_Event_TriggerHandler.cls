public class Significant_Event_TriggerHandler {
	public void isBeforeInsert(List<Significant_Event__c> newList){

	}

	public void isBeforeUpdate(Map<Id,Significant_Event__c> newMap, Map<Id,Significant_Event__c> oldMap){

	}

	public void isBeforeDelete(Map<Id,Significant_Event__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Significant_Event__c> newMap){
        createShareRecord(newMap, null);
	}

	public void isAfterUpdate(Map<Id,Significant_Event__c> newMap, Map<Id,Significant_Event__c> oldMap){
		createShareRecord(newMap, oldMap);
	}

	public void isAfterDelete(Map<Id,Significant_Event__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Significant_Event__c> newMap){

	}
    
    public void createShareRecord(Map<Id, Significant_Event__c> newMap, Map<Id, Significant_Event__c> oldMap){
        Set<Id> fatIdSet = new Set<Id>();
        
        for(Significant_Event__c se : newMap.values()){
            if(oldMap == null){
                if(se.Financial_Advisor_Team__c != null)
                    fatIdSet.add(se.Financial_Advisor_Team__c);
            } else if(oldMap.get(se.Id).Financial_Advisor_Team__c != se.Financial_Advisor_Team__c || oldMap.get(se.Id).OwnerId != se.OwnerId){
                if(se.Financial_Advisor_Team__c != null)
                    fatIdSet.add(se.Financial_Advisor_Team__c);
                if(oldMap.get(se.Id).Financial_Advisor_Team__c != null){
                    fatIdSet.add(oldMap.get(se.Id).Financial_Advisor_Team__c);
                }
            } 
        }
        
        if(!fatIdSet.isEmpty()){
            Map<Id, Financial_Advisor_Team__c> fATeamMap = new Map<Id, Financial_Advisor_Team__c>([SELECT Id, Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Id IN : fatIdSet]);
            if(!fATeamMap.isEmpty()){
                List<Significant_Event__Share> shareRecordList = new List<Significant_Event__Share>();
                //For revoke Share
                Set<Id> groupIdSet = new Set<Id>();
                Set<Id> parentIdSet = new Set<Id>();
                for(Significant_Event__c se : newMap.values()){
                    Significant_Event__share shareRec = new Significant_Event__share();
                    if(fATeamMap.get(se.Financial_Advisor_Team__c)!=null){
                        shareRec.ParentId = se.Id;
                        if(se.Financial_Advisor_Team__c != null){
                            shareRec.UserOrGroupId = fATeamMap.get(se.Financial_Advisor_Team__c).Public_Group_Id__c;
                        }
                        
                        shareRec.AccessLevel = 'Edit';
                        shareRec.RowCause = Schema.Significant_Event__Share.RowCause.Manual;
                        if(oldMap == null){
                            if(se.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);
                            }
                        } else if(oldMap != null && (oldMap.get(se.Id).Financial_Advisor_Team__c != se.Financial_Advisor_Team__c ||oldMap.get(se.Id).OwnerId != se.OwnerId)){
                            if(oldMap.get(se.Id).Financial_Advisor_Team__c != null && fATeamMap.get(oldMap.get(se.Id).Financial_Advisor_Team__c) != null)
                            {
                                groupIdSet.add(fATeamMap.get(oldMap.get(se.Id).Financial_Advisor_Team__c).Public_Group_Id__c);
                                parentIdSet.add(se.Id);
                            }            
                            if(se.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);                                 
                            }
                        }
                    }
                }
                if(groupIdSet.size() > 0 && parentIdSet.size() > 0){
                    List<Significant_Event__Share> removeShareList = new List<Significant_Event__Share>();
                    for(Significant_Event__Share shareRec: [SELECT Id, ParentId, UserOrGroupId FROM Significant_Event__Share WHERE ParentId IN: parentIdSet and UserOrGroupId IN: groupIdSet]){
                        if(groupIdSet.Contains(shareRec.UserOrGroupId) && parentIdSet.contains(shareRec.ParentId) ){
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