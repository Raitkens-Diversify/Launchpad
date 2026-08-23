public class SelectPrimaryAndJointController {
    
    @AuraEnabled
    public static List<AccountContactRelation> getHouseholdMembers(String recordId){
        System.debug('recordId: ' + recordId);
        List<AccountContactRelation> acrs = [SELECT Id, AccountId, ContactId, Contact.AccountId, Contact.Name FROM AccountContactRelation
                                            WHERE AccountId =: recordId];
        Map<Id,String> householdMembers = new Map<Id,String>();
        for(AccountContactRelation a : acrs){
            householdMembers.put(a.Contact.AccountId, a.Contact.Name);
        }
        System.debug('acrs: ' + acrs);
        return acrs;
    }
    
    @AuraEnabled
    public static List<AccountContactRelation> getHouseholdMembersMinusPrimary(String recordId, String primaryOwnerId){
        System.debug('recordId: ' + recordId);
        System.debug('primaryOwnerId: ' + primaryOwnerId);
        List<AccountContactRelation> acrs = [SELECT Id, AccountId, ContactId, Contact.AccountId, Contact.Name FROM AccountContactRelation
                                            WHERE AccountId =: recordId AND Contact.AccountId !=: primaryOwnerId];
        Map<Id,String> householdMembers = new Map<Id,String>();
        for(AccountContactRelation a : acrs){
            householdMembers.put(a.Contact.AccountId, a.Contact.Name);
        }
        System.debug('acrs: ' + acrs);
        return acrs;
    }

}