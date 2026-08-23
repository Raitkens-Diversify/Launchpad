public class ContactContactRelation_TriggerHandler {
    public void isBeforeInsert(List<Contact_Contact_Relationship__c> newList){ }
    
    public void isBeforeUpdate(Map<Id, Contact_Contact_Relationship__c> newMap, Map<Id, Contact_Contact_Relationship__c> oldMap){ }
    
    public void isBeforeDelete(Map<Id, Contact_Contact_Relationship__c> oldMap) { }
    
    public void isAfterInsert(Map<Id, Contact_Contact_Relationship__c> newMap) { 
        createAndUpdateFinContactRel(newMap);
    }
    
    public void isAfterUpdate(Map<Id, Contact_Contact_Relationship__c> newMap, Map<Id, Contact_Contact_Relationship__c> oldMap) { 
        createAndUpdateFinContactRel(newMap);
    }
    
    public void isAfterDelete(Map<Id, Contact_Contact_Relationship__c> oldMap) { }
    
    public void isAfterUnDelete(Map<Id, Contact_Contact_Relationship__c> newMap) { }
    
    private void createAndUpdateFinContactRel(Map<Id, Contact_Contact_Relationship__c> newMap){
        List<Create_Fin_Contact_Contact_Relation__e> finEvents = new List<Create_Fin_Contact_Contact_Relation__e>();
        for(Id ccrId: newMap.keyset()){
            finEvents.add(new Create_Fin_Contact_Contact_Relation__e(ContactContactRelationId__c = ccrId));
        }
        // Call method to publish events
        List<Database.SaveResult> results = EventBus.publish(finEvents);
        
        // Inspect publishing result for each event
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                System.debug('Successfully published event.');
            } else {
                for(Database.Error err : sr.getErrors()) {
                    System.debug('Error returned: ' + err.getStatusCode()+' - '+err.getMessage());
                }
            }       
        }   
    }
}