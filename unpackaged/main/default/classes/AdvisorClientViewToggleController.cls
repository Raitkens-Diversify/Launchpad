public class AdvisorClientViewToggleController {

    @AuraEnabled
    public static void toggleView(String recordId, String viewState){
        System.debug('recordId: ' + recordId);
        Account a = [SELECT Id, View_State__c FROM Account WHERE Id =: recordId];
        a.View_State__c = viewState;
        update a;
    }
    
    @AuraEnabled
    public static String getViewState(String recordId){
        Account a = [SELECT View_State__c FROM Account WHERE Id =: recordId];
        return a.View_State__c;
    }
}