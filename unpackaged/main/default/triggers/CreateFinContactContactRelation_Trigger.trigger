trigger CreateFinContactContactRelation_Trigger on Create_Fin_Contact_Contact_Relation__e (after insert) {
    Set<Id> ccrIds = new Set<Id>();
    
    for(Create_Fin_Contact_Contact_Relation__e event : Trigger.New) {
        ccrIds.add(event.ContactContactRelationId__c);
    }
    System.debug(ccrIds);
    Map<ID, Contact_Contact_Relationship__c> contactConatctRelMap = new Map<ID, Contact_Contact_Relationship__c>([SELECT Id,Active__c,Contact__c,Related_Contact__c,IMA_Signed_Date__c,Related_Role_ID__c,Percentage_of_Ownership__c
                                                                                                                  FROM Contact_Contact_Relationship__c WHERE Id IN:ccrIds ]);
     
    Map<ID, FinServ__ContactContactRelation__c> finContactConatctRelMap = new Map<ID, FinServ__ContactContactRelation__c>([SELECT Id,FinServ__Active__c,FinServ__Contact__c,FinServ__RelatedContact__c,IMA_Signed_Date__c,FinServ__Role__c,Percentage_of_Ownership__c,
                                                                                                                           Contact_Contact_Relationship__c FROM FinServ__ContactContactRelation__c WHERE Contact_Contact_Relationship__c IN:ccrIds ]);
    Map<ID, List<FinServ__ContactContactRelation__c>> finContactContactIdMap = new Map<ID, List<FinServ__ContactContactRelation__c>>();
    for(FinServ__ContactContactRelation__c fccr : finContactConatctRelMap.values()){
        if(!finContactContactIdMap.containsKey(fccr.Contact_Contact_Relationship__c)){
            finContactContactIdMap.put(fccr.Contact_Contact_Relationship__c,new List<FinServ__ContactContactRelation__c>());
        }
        finContactContactIdMap.get(fccr.Contact_Contact_Relationship__c).add(fccr);        
    }
    
    List<FinServ__ContactContactRelation__c> finServContactsToUpdate = new List<FinServ__ContactContactRelation__c>();
    for(Contact_Contact_Relationship__c ccr : contactConatctRelMap.values()){
        if(finContactContactIdMap.containsKey(ccr.Id)){
            for(FinServ__ContactContactRelation__c fccr : finContactContactIdMap.get(ccr.Id)){
                fccr.FinServ__Active__c = ccr.Active__c ;
                //fccr.FinServ__Contact__c = ccr.Contact__c;
                //fccr.FinServ__RelatedContact__c = ccr.Related_Contact__c;
                fccr.IMA_Signed_Date__c = ccr.IMA_Signed_Date__c;
                //fccr.FinServ__Role__c = ccr.Related_Role_ID__c;
                fccr.Percentage_of_Ownership__c = ccr.Percentage_of_Ownership__c;
                finServContactsToUpdate.add(fccr);
            }
        }else{
            FinServ__ContactContactRelation__c fccr = new FinServ__ContactContactRelation__c();
            fccr.FinServ__Active__c = ccr.Active__c ;
            fccr.FinServ__Contact__c = ccr.Contact__c;
            fccr.FinServ__RelatedContact__c = ccr.Related_Contact__c;
            fccr.IMA_Signed_Date__c = ccr.IMA_Signed_Date__c;
            fccr.FinServ__Role__c = ccr.Related_Role_ID__c;
            fccr.Percentage_of_Ownership__c = ccr.Percentage_of_Ownership__c;
            fccr.Contact_Contact_Relationship__c = ccr.ID;
            finServContactsToUpdate.add(fccr);
        }
    }
    if(!finServContactsToUpdate.isEmpty()){
        upsert finServContactsToUpdate;
    }
}