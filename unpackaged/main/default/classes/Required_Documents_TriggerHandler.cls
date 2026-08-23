public class Required_Documents_TriggerHandler {
    /*public void isBeforeInsert(List<Required_Documents__c> newList){ }
    
    public void isBeforeUpdate(Map<Id, Required_Documents__c> newMap, Map<Id, Required_Documents__c> oldMap){ }
    
    public void isBeforeDelete(Map<Id, Required_Documents__c> oldMap){ }
    
    public void isAfterInsert(Map<Id, Required_Documents__c> newMap){ }*/
    
    public void isAfterUpdate(Map<Id, Required_Documents__c> newMap, Map<Id, Required_Documents__c> oldMap){ 
        updateRelatedCases(newMap, oldMap);
        updateCasesOnStatusCompleted(newMap, oldMap);
    }
    
    /*public void isAfterDelete(Map<Id, Required_Documents__c> oldMap){ }
    
    public void isAfterUndelete(Map<Id, Required_Documents__c> newMap){ }*/
    
    public void updateRelatedCases(Map<Id, Required_Documents__c> newMap, Map<Id, Required_Documents__c> oldMap){
        List<Case> casesToUpdate = new List<Case>();
        Set<Id> householdIds = new Set<Id>();
        Map<Id, Set<String>> householdIdToReqDocsNameMap = new Map<Id, Set<String>>();
        
        for(Required_Documents__c newDoc : newMap.values()) {
            Required_Documents__c oldDoc = oldMap.get(newDoc.Id);            
            if (newDoc.Status__c == 'Signed' && oldDoc.Status__c != 'Signed' && newDoc.Docusign_Envelope__c != null) {
                householdIds.add(newDoc.Household__c);
                if (!householdIdToReqDocsNameMap.containsKey(newDoc.Household__c)) {
                    householdIdToReqDocsNameMap.put(newDoc.Household__c, new Set<String>());
                }
                householdIdToReqDocsNameMap.get(newDoc.Household__c).add(newDoc.Name);
            }
        }
        
        if (!householdIds.isEmpty()) {
            List<Case> caseList = [SELECT Id, Documents_Ready__c, AccountId, Required_Documents__c FROM Case
                                   WHERE AccountId IN :householdIds AND IsClosed = false]; 
            
            for(Case c : caseList) {
                Set<String> requiredDocs = householdIdToReqDocsNameMap.get(c.AccountId);
                if (requiredDocs != null && requiredDocs.contains(c.Required_Documents__c)) {
                    c.Documents_Ready__c = true;
                    casesToUpdate.add(c);
                }
            }
        }
        
        // Update the Case records
        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
    }
    public void updateCasesOnStatusCompleted(Map<Id, Required_Documents__c> newMap, Map<Id, Required_Documents__c> oldMap){
        List<Case> casesToUpdate = new List<Case>();
        Set<Id> caseIds = new Set<Id>();
        
        for(Required_Documents__c newDoc : newMap.values()) {
            if (newDoc.Status__c == 'completed' && oldMap.get(newDoc.Id).Status__c != 'completed' && newDoc.Case__c != null) {
                caseIds.add(newDoc.Case__c);
            }
        }
        
        if (!caseIds.isEmpty()) {
            List<Required_Documents__c> requiredDocuments = [SELECT Id,Case__c,Status__c FROM Required_Documents__c WHERE case__c IN :caseIds ]; 
            
            for(Required_Documents__c rd : requiredDocuments) {
                if(rd.Status__c != 'completed'){
                    caseIds.remove(rd.Case__c);
                }
            }
        }
        for(Id caseId : caseIds){
            case c = new Case(Id = caseId);
            c.Documents_Ready__c = true;
            casesToUpdate.add(c);
        }
        
        // Update the Case records
        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
    }
    
}