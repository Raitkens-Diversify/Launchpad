public class Compliance_Exception_TriggerHandler {
	public void isBeforeInsert(List<Compliance_Exception__c> newList){

	}

	public void isBeforeUpdate(Map<Id,Compliance_Exception__c> newMap, Map<Id,Compliance_Exception__c> oldMap){

	}

	public void isBeforeDelete(Map<Id,Compliance_Exception__c> oldMap){

	}

	public void isAfterInsert(Map<Id,Compliance_Exception__c> newMap){
        createCDLforComplianceException(newMap, null);
	}

	public void isAfterUpdate(Map<Id,Compliance_Exception__c> newMap, Map<Id,Compliance_Exception__c> oldMap){

	}

	public void isAfterDelete(Map<Id,Compliance_Exception__c> oldMap){

	}

	public void isAfterUndelete(Map<Id,Compliance_Exception__c> newMap){

	}
    
    /*
	* method to create Content Document Links for Compliance Exception
	* @param newMap: contain new Compliance Exception records   
	* @param oldMap: contain old Compliance Exception records	  
	*/
    private static void createCDLforComplianceException(Map<Id, Compliance_Exception__c> newMap, Map<Id, Compliance_Exception__c> oldMap) {
        List<ContentDocumentLink> cdlsToInsert = new List<ContentDocumentLink>();
        Map<String, Id> flowInterviewIdsToExceptionIds = new Map<String,Id>();
        
        for (Compliance_Exception__c newException : newMap.values()) {
            if (newException.Flow_Interview_Id__c != null) {
                flowInterviewIdsToExceptionIds.put(newException.Flow_Interview_Id__c, newException.Id);
            }
        }
    
        if (!flowInterviewIdsToExceptionIds.isEmpty()) {
            // SOQL to fetch favourable ContentVersions 
            List<ContentVersion> ceCVRecords = [SELECT Id, ContentDocumentId, Flow_Interview_Id__c
                                                FROM ContentVersion
                                                WHERE Flow_Interview_Id__c IN :flowInterviewIdsToExceptionIds.keySet()
            ];
            
            for (ContentVersion c : ceCVRecords) {
                ContentDocumentLink ceCDL = new ContentDocumentLink(
                	LinkedEntityId = flowInterviewIdsToExceptionIds.get(c.Flow_Interview_Id__c),
                    ShareType = 'V',
                    ContentDocumentId = c.ContentDocumentId
                );
                cdlsToInsert.add(ceCDL);
            }
            
            if (!cdlsToInsert.isEmpty()) {
                insert cdlsToInsert;
            }
        }
    }


}