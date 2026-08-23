public class Advertising_Item_TriggerHandler {
    
    public void isBeforeInsert(List<Advertising_Item__c> newList){
        updateSocialMediaProfile(newList);
        
    }
    
    public void isBeforeUpdate(Map<Id, Advertising_Item__c> newMap, Map<Id, Advertising_Item__c> oldMap){
        setRecordLock(newMap, oldMap);
    }
    
    public void isBeforeDelete(Map<Id, Advertising_Item__c> oldMap){
        
    }
    
    public void isAfterInsert(Map<Id, Advertising_Item__c> newMap){
        createCaseForNullEvent(newMap); 
        reparentContentDocuments(newMap);
        findEventCostLineItems(newMap);
        findSponsorshipCostLineItems(newMap);
        findRadioCostLineItems(newMap);
        findRelatedEvent(newMap.values());
    }
    
    public void isAfterUpdate(Map<Id, Advertising_Item__c> newMap, Map<Id, Advertising_Item__c> oldMap){
        
    }
    
    public void isAfterDelete(Map<Id, Advertising_Item__c> oldMap){
        
    }
    
    public void isAfterUndelete(Map<Id, Advertising_Item__c> newMap){
        
    }
    
    private void updateSocialMediaProfile(List<Advertising_Item__c> newList){
        List<Advertising_Item__c> adItemsList=[select Id,Flow_Interview_ID__c,Social_Media_Profile__c  from Advertising_Item__c where Advertising_Type__c ='Social Media Profile' AND Social_Media_Profile__c !=null];
        
        Map<String,String> SMProfileMap=new Map<String,String>();
        for(Advertising_Item__c adI:adItemsList){
            if(!SMProfileMap.containsKey(adI.Flow_Interview_ID__c)){
                SMProfileMap.put(adI.Flow_Interview_ID__c,adI.Social_Media_Profile__c);
            }
        }
        
        for(Advertising_Item__c adI:newList){
            if(adI.Advertising_Type__c=='Social Media Content' && adI.Social_Media_Profile__c==null){
                adI.Social_Media_Profile__c=SMProfileMap.get(adI.Flow_Interview_ID__c);
            }
            if(adI.Advertising_Type__c == 'Video/Audio' && adI.Social_Media_Profile__c == null && adI.Posting_on_Social_Media__c == true){
                adI.Social_Media_Profile__c = SMProfileMap.get(adI.Flow_Interview_ID__c);
            }
        }
    }
    
    private void createCaseForNullEvent(Map<Id,Advertising_Item__c> newMap){
        Group complianceQId=[select Id from Group where Type='Queue' AND Name='Compliance'];
        set<Id> caseIds=new set<Id>();
        List<Case> casesToBeInsert=new List<Case>();
        set<Id> adItemsId=new set<Id>();
        for(Advertising_Item__c adI:newMap.values()){
            if(adI.Event__c==null){
                Case c=new Case();
                c.Advertising_Type__c=adI.Advertising_Type__c;
                c.Status='New';
                c.OwnerId=complianceQId.Id;
                c.Advertising_Item__c=adI.Id;
                c.Subject = adI.Name;
                c.Financial_Advisor_Team__c = adI.Financial_Advisor_Team__c;
                c.Origin = 'Advisor Request';
                casesToBeInsert.add(c);
            } else{
                adItemsId.add(adI.Id);
            }
        }
        if(casesToBeInsert.size()>0){
            insert casesToBeInsert;
            for(Case c:casesToBeInsert){
                caseIds.add(c.Id);
            }
            updateCaseIdonAdItem(caseIds); 
        }
        if(adItemsId.size()>0){
            setCaseOnAdItem(adItemsId);
        }
    }
    
    @future
    public static void updateCaseIdonAdItem(set<Id> caseIds){
        List<Case> caseList=[select Id,Advertising_Item__c from Case where Id IN:caseIds];
        List<Advertising_Item__c> adItemsToUpdate=new List<Advertising_Item__c>();
        Map<Id,Id> caseMapAdItem=new Map<Id,Id>();
        for(Case c:caseList){
            caseMapAdItem.put(c.Advertising_Item__c,c.Id);
        }
        for(Advertising_Item__c adI:[select Id,	Review_Case__c from Advertising_Item__c where Id IN:caseMapAdItem.keySet()]){
            adI.Review_Case__c=caseMapAdItem.get(adI.Id);
            adItemsToUpdate.add(adI);
        }
        if(adItemsToUpdate.size()>0){
            update adItemsToUpdate;
        }
    }
    
    @future
    private static void setCaseOnAdItem(set<Id> adItemIds){
        
        List<Advertising_Item__c> adItemsToBeUpdate=new List<Advertising_Item__c>();
        Map<Id,Advertising_Item__c> adItemsMap=new Map<Id,Advertising_Item__c>([select Id,Review_Case__c,Event__c from Advertising_Item__c where Id IN:adItemIds]);
        Map<Id,Advertising_Item__c> adItemEventMap=new Map<Id,Advertising_Item__c>();
        set<Id> eventIds=new set<Id>();
        for(Advertising_Item__c adI:adItemsMap.values()){
            eventIds.add(adI.Event__c);
        }
        for(Advertising_Item__c adItem:[select Id,Review_Case__c from Advertising_Item__c where Id IN:eventIds]){
            adItemEventMap.put(adItem.Id,adItem);
        }
        for(Advertising_Item__c adI:adItemsMap.values()){
            adI.Review_Case__c=adItemEventMap.get(adI.Event__c).Review_Case__c;
        }
        update adItemsMap.values();
    }
    
    /* Method to create new ContentDocumentLinks linked to Advertising Items */
    public void reparentContentDocuments(Map<Id, Advertising_Item__c> newMap){
        List<ContentDocumentLink> cdlsToInsert = new List<ContentDocumentLink>();
        Set<Id> aiIds = new Set<Id>();
        Set<String> flowInterviewIds = new Set<String>();
        Set<String> adTypes = new Set<String>();
        Map<String, Id> mapFlowAdTypeStringToAdItem = new Map<String, Id>();
        
        //Getting the list of Flow Interview Ids, Advertising Types and Advertising Items which match the criteria 
        for(Advertising_Item__c newAdItem : newMap.values())
        {
            if(newAdItem.Flow_Interview_ID__c != null && newAdItem.Advertising_Type__c != null)
            {
                aiIds.add(newAdItem.Id);
                flowInterviewIds.add(newAdItem.Flow_Interview_ID__c);
                adTypes.add(newAdItem.Advertising_Type__c);
            }
        }
        
        //Getting List of Content Versions
        List<ContentVersion> cvList = [SELECT Id, ContentDocumentId, Advertising_Type__c, Flow_Interview_ID__c FROM ContentVersion
                                       WHERE Advertising_Type__c IN :adTypes AND Flow_Interview_ID__c IN :flowInterviewIds];
        
        //Creating Map for unique Flow and Advertising Type format to Advertising Item Id
        for(ID aiId : aiIds){
            String flowAndAdTypeString = newMap.get(aiId).Flow_Interview_ID__c + ' : ' + newMap.get(aiId).Advertising_Type__c;
            mapFlowAdTypeStringToAdItem.put(flowAndAdTypeString, aiId);
        }
        
        //Creating ContentDocumentLink records for Content Versions which match the criteria
        for(ContentVersion cv : cvList){
            String flowAndAdTypeString = cv.Flow_Interview_ID__c + ' : ' + cv.Advertising_Type__c;
            if(!mapFlowAdTypeStringToAdItem.isEmpty() && mapFlowAdTypeStringToAdItem.containsKey(flowAndAdTypeString)){
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = cv.ContentDocumentId;
                cdl.LinkedEntityId = mapFlowAdTypeStringToAdItem.get(flowAndAdTypeString);
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';
                cdlsToInsert.add(cdl);
            }
        }
        
        if(!cdlsToInsert.isEmpty()){
            insert cdlsToInsert;
        }
    }
    
    public void findEventCostLineItems(Map<Id,Advertising_Item__c> newMap){
        Map<String,Id> flowIdToEvents = new Map<String,Id>();
        for(Advertising_Item__c a : newMap.values()){
            if(a.Advertising_Type__c  == 'Event' && a.Flow_Interview_Id__c != null){
                flowIdToEvents.put(a.Flow_Interview_Id__c, a.Id);
            }
        }
        List<Event_Cost_Line_Item__c> ecli = [SELECT Id, Event__c, Flow_Interview_Id__c FROM Event_Cost_Line_Item__c WHERE Event__c = null AND Flow_Interview_Id__c != null];
        for(Event_Cost_Line_Item__c e : ecli){
            if(flowIdToEvents.get(e.Flow_Interview_Id__c) != null){
                e.Event__c = flowIdToEvents.get(e.Flow_Interview_Id__c);
            }
        }
        if(!ecli.isEmpty()){
            update ecli;
        }
    }
    
    public void findSponsorshipCostLineItems(Map<Id,Advertising_Item__c> newMap){
        Map<String,Id> flowIdToSponsorships = new Map<String,Id>();
        for(Advertising_Item__c a : newMap.values()){
            if(a.Advertising_Type__c  == 'Sponsorship' && a.Flow_Interview_Id__c != null){
                flowIdToSponsorships.put(a.Flow_Interview_Id__c, a.Id);
            }
        }
        List<Sponsorship_Cost_Line_Item__c> scli = [SELECT Id, Sponsorship__c, Flow_Interview_Id__c FROM Sponsorship_Cost_Line_Item__c WHERE Sponsorship__c = null AND Flow_Interview_Id__c != null];
        for(Sponsorship_Cost_Line_Item__c s : scli){
            if(flowIdToSponsorships.get(s.Flow_Interview_Id__c) != null){
                s.Sponsorship__c = flowIdToSponsorships.get(s.Flow_Interview_Id__c);
            }
        }
        if(!scli.isEmpty()){
            update scli;
        }
    }

	public void findRadioCostLineItems(Map<Id,Advertising_Item__c> newMap){
        Map<String,Id> flowIdToRadio = new Map<String,Id>();
        for(Advertising_Item__c a : newMap.values()){
            if(a.Advertising_Type__c  == 'Radio/TV Ad' && a.Flow_Interview_Id__c != null){
                flowIdToRadio.put(a.Flow_Interview_Id__c, a.Id);
            }
        }
        List<Radio_TV_Ad_Cost_Line_Item__c> rcli = [SELECT Id, Radio_TV_Ad__c, Flow_Interview_Id__c FROM Radio_TV_Ad_Cost_Line_Item__c WHERE Radio_TV_Ad__c = null AND Flow_Interview_Id__c != null];
        for(Radio_TV_Ad_Cost_Line_Item__c r : rcli){
            if(flowIdToRadio.get(r.Flow_Interview_Id__c) != null){
                r.Radio_TV_Ad__c = flowIdToRadio.get(r.Flow_Interview_Id__c);
            }
        }
        if(!rcli.isEmpty()){
            update rcli;
        }
    }
    
    public void findRelatedEvent(List<Advertising_Item__c> newList){
        Map<String,Id> flowIdToEventId = new Map<String,Id>();
        List<Advertising_Item__c> lstToUpdate = new List<Advertising_Item__c>();
        for(Advertising_Item__c a : newList){
            if(a.Advertising_Type__c == 'Event'){
                flowIdToEventId.put(a.Flow_Interview_ID__c, a.Id);
            }
        }
        if(!flowIdToEventId.isEmpty()){
            List<Advertising_Item__c> otherThings = [SELECT Id, Flow_Interview_Id__c FROM Advertising_Item__c WHERE isRelatedToEvent__c = true AND Flow_Interview_Id__c in: flowIdToEventId.keyset()];
            for(Advertising_Item__c o : otherThings){
                o.Event__c = flowIdToEventId.get(o.Flow_Interview_Id__c);
                lstToUpdate.add(o);
            }
        }
        if(!lstToUpdate.isEmpty()){
            update lstToUpdate;
        }
    }
    
    public void setRecordLock(Map<Id, Advertising_Item__c> newMap, Map<Id, Advertising_Item__c> oldMap){
        for(Advertising_Item__c newAdItem : newMap.values()){
            if(newAdItem.Status__c == 'Approved' && oldMap.get(newAdItem.Id).Status__c != 'Approved'){
                newAdItem.Record_Locked__c = true;
            }
        }
    }
}