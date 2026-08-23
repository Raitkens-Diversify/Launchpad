public class FinServ_ContactContact_TriggerHandler {
	public void isBeforeInsert(List<FinServ__ContactContactRelation__c> newList){

	}

	public void isBeforeUpdate(Map<Id,FinServ__ContactContactRelation__c> newMap, Map<Id,FinServ__ContactContactRelation__c> oldMap){

	}

	public void isBeforeDelete(Map<Id,FinServ__ContactContactRelation__c> oldMap){

	}

	public void isAfterInsert(Map<Id,FinServ__ContactContactRelation__c> newMap){
        shareRecordWithGroup(newMap);
	}

	public void isAfterUpdate(Map<Id,FinServ__ContactContactRelation__c> newMap, Map<Id,FinServ__ContactContactRelation__c> oldMap){

	}

	public void isAfterDelete(Map<Id,FinServ__ContactContactRelation__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,FinServ__ContactContactRelation__c> newMap){

	}
    
    private void shareRecordWithGroup(Map<Id, FinServ__ContactContactRelation__c> newMap){
        Set<Id> contactIds = new Set<Id>();
        for(FinServ__ContactContactRelation__c ccr : newMap.values()){
            if(!string.isEmpty(ccr.FinServ__RelatedContact__c)){
                contactIds.add(ccr.FinServ__RelatedContact__c);
            }
        }
        system.debug('contactIds'+contactIds);
        Map<Id, String> contactIdToPublicGroupId = new Map<Id, String>();
        for (Contact cont : [SELECT Id, Account.Financial_Advisor_Team__r.Public_Group_ID__c FROM Contact WHERE Id IN :contactIds]) {
            if (cont.Account != null && cont.Account.Financial_Advisor_Team__r != null && 
                cont.Account.Financial_Advisor_Team__r.Public_Group_ID__c != null) {
                    contactIdToPublicGroupId.put(cont.Id, cont.Account.Financial_Advisor_Team__r.Public_Group_ID__c);
                }
        }
                system.debug('contactIdToPublicGroupId'+contactIdToPublicGroupId);

        // Share the Contact_Contact_Relationship__c records with the public group
        List<FinServ__ContactContactRelation__Share> sharesToInsert = new List<FinServ__ContactContactRelation__Share>();
        for(FinServ__ContactContactRelation__c ccr : newMap.values()){
            if(!string.isEmpty(ccr.FinServ__RelatedContact__c) && contactIdToPublicGroupId.containsKey(ccr.FinServ__RelatedContact__c)){
               String publicGroupId = contactIdToPublicGroupId.get(ccr.FinServ__RelatedContact__c);
            
            // Create a new ObjectShare record to share the record
            sharesToInsert.add(new FinServ__ContactContactRelation__Share(
                ParentId = ccr.Id,
                UserOrGroupId = publicGroupId,  // Public Group ID
                AccessLevel = 'Edit',  
                RowCause = Schema.FinServ__ContactContactRelation__Share.RowCause.Manual
            )); 
            }
            
        }
                        system.debug('sharesToInsert'+sharesToInsert);

        // Insert the share records
        if (!sharesToInsert.isEmpty()) {
            insert sharesToInsert;
        }
    }
}