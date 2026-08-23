public class AccountContactRelationTriggerHandler {
    public void isBeforeInsert(List<AccountContactRelation> newList){
    }
    
    public void isBeforeUpdate(Map<Id, AccountContactRelation> newMap, Map<Id, AccountContactRelation> oldMap){}
    
    public void isBeforeDelete(Map<Id, AccountContactRelation> oldMap){ }
    
    public void isAfterInsert(Map<Id, AccountContactRelation> newMap){ 
        setfinancialAdvisorTeam(newMap.values());
    }
    
    public void isAfterUpdate(Map<Id, AccountContactRelation> newMap, Map<Id, AccountContactRelation> oldMap){}
    
    public void isAfterDelete(Map<Id, AccountContactRelation> oldMap){ }
    
    public void isAfterUndelete(Map<Id, AccountContactRelation> newMap){ }
    
    private void setfinancialAdvisorTeam(List<AccountContactRelation> newList){
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        List<Account> accountsToUpdate = new List<Account>();
        for(AccountContactRelation acr : newList){
            if(!string.isEmpty(acr.ContactId)){
                contactIds.add(acr.ContactId);
            }
            if(!string.isEmpty(acr.AccountId)){
                accountIds.add(acr.AccountId);
            }
        }
        
        Map<Id,Contact> contactMap =  new Map<Id,Contact>([SELECT Id,account.financial_advisor_team__c,AccountId  FROM Contact WHERE Id =: contactIds]);
        Map<Id,Account> accountMap =  new Map<Id,Account>([SELECT Id,financial_advisor_team__c  FROM Account WHERE Id =: accountIds]);
        system.debug('accountIds'+accountIds);
        system.debug('contactIds'+contactIds);
        system.debug('contactMap'+contactMap);
        system.debug('accountMap'+accountMap);
        
        for(AccountContactRelation acr : newList){
            system.debug('accountMap.get(acr.AccountId).financial_advisor_team__c'+accountMap.get(acr.AccountId).financial_advisor_team__c);
            system.debug('contactMap.get(acr.ContactId).account.financial_advisor_team__c'+contactMap.get(acr.ContactId).account.financial_advisor_team__c);
            
            if(!string.isEmpty(acr.AccountId) && accountMap.containsKey(acr.AccountId) 
               && accountMap.get(acr.AccountId).financial_advisor_team__c != null && contactMap.containsKey(acr.ContactId)
               && contactMap.get(acr.ContactId).account !=null  && contactMap.get(acr.ContactId).account.financial_advisor_team__c == null ){
                   Account acc = new Account(Id = contactMap.get(acr.ContactId).AccountId,financial_advisor_team__c = accountMap.get(acr.AccountId).financial_advisor_team__c);
                   accountsToUpdate.add(acc);
               }
        }
        system.debug('accountsToUpdate'+accountsToUpdate);
        if(!accountsToUpdate.isEmpty()){
            update accountsToUpdate;
        }
    }
}