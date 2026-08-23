public class RecipientStatus_TriggerHandler {
    public void isBeforeInsert(List<dfsle__RecipientStatus__c> newList){}
    public void isBeforeUpdate(Map<Id, dfsle__RecipientStatus__c> newMap, Map<Id, dfsle__RecipientStatus__c> oldMap){}
    public void isBeforeDelete(Map<Id, dfsle__RecipientStatus__c> oldMap){}
    public void isAfterInsert(Map<Id, dfsle__RecipientStatus__c> newMap){
        updateACROnComplete(newMap);
    }	
    public void isAfterUpdate(Map<Id, dfsle__RecipientStatus__c> newMap, Map<Id, dfsle__RecipientStatus__c> oldMap){
    }
    public void isAfterDelete(Map<Id, dfsle__RecipientStatus__c> oldMap){}
    public void isAfterUndelete(Map<Id, dfsle__RecipientStatus__c> newMap){}
    
    public static void updateACROnComplete(Map<Id, dfsle__RecipientStatus__c> newMap){
        List<AccountContactRelation> acrsToUpdate = new List<AccountContactRelation>();
        //Get Recipient Status Records With Completed Status
        List<dfsle__RecipientStatus__c> completedRecptStatus = [SELECT Id, Name, dfsle__EnvelopeStatus__c, dfsle__EnvelopeStatus__r.dfsle__SourceId__c,
                                                                dfsle__Completed__c, dfsle__SourceId__c, dfsle__Status__c FROM dfsle__RecipientStatus__c
                                                                WHERE ID IN :newMap.keySet() AND dfsle__Status__c = 'Completed' AND DAY_ONLY(dfsle__Completed__c) = :Date.today()];
        
        Map<String, Date> mapAccContFormatToSignedDate = new Map<String, Date>();
        Set<String> accountIds = new Set<String>();
        Set<String> contactIds = new Set<String>();
        //Get Ids of Account and Contact for AccountContactRelation
        for(dfsle__RecipientStatus__c recptStatus : completedRecptStatus){
            if(recptStatus.dfsle__EnvelopeStatus__r.dfsle__SourceId__c.startsWith('001') && recptStatus.dfsle__SourceId__c.startsWith('003')){
                accountIds.add(recptStatus.dfsle__EnvelopeStatus__r.dfsle__SourceId__c);
                contactIds.add(recptStatus.dfsle__SourceId__c);
                String formatString = recptStatus.dfsle__EnvelopeStatus__r.dfsle__SourceId__c + ':' + recptStatus.dfsle__SourceId__c;
                mapAccContFormatToSignedDate.put(formatString, recptStatus.dfsle__Completed__c.date());
            }
        }
        
        //Get all the AccountContactRelation records
        List<AccountContactRelation> acrs = [SELECT Id, ContactId, AccountId, IMA_Signed_Date__c FROM AccountContactRelation
                                             WHERE ContactId IN :contactIds AND AccountId IN :accountIds AND Roles INCLUDES ('Client') AND IMA_Signed_Date__c != :Date.today()];
        
        //Update IMA Signed Date if format matches
        for(AccountContactRelation acr : acrs){
            String formatString = acr.AccountId + ':' + acr.ContactId;
            if(mapAccContFormatToSignedDate.containsKey(formatString)){
                acr.IMA_Signed_Date__c = mapAccContFormatToSignedDate.get(formatString);
                acrsToUpdate.add(acr);
            }
        } 
        
        if(!acrsToUpdate.isEmpty()){
            update acrsToUpdate;
        }
        
    }
}