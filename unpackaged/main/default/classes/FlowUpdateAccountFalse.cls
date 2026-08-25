global class FlowUpdateAccountFalse {

    @InvocableMethod(label='Updates Accounts to isPortalUserActive__c = false' description='Provide an Account Id') 
    global static void accountUpdate (List<String> accountId){
        //Account acc = [SELECT Id, isPortalUserEnabled__pc FROM Account WHERE Id =: accountId[0]];
        //acc.isPortalUserEnabled__pc = true;
        //update acc;
        updateAccount(accountId[0]);
    }
    
    @future
    static void updateAccount(Id accountId){
        Account acc = [SELECT Id, isPortalUserEnabled__pc, isPortalUserActive__c FROM Account WHERE Id =: accountId];
        acc.isPortalUserActive__c = false;
        try{
            update acc;
        } catch(Exception e){
            System.debug('Error: '+e.getMessage());
        }
    }
}