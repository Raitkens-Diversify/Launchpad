@isTest
private class TypeHeadLookupControllerTest {
    @isTest
    public static void typeheadLookupTest(){ 
        Test.startTest();        
        Notes__c note = new Notes__c(Type__c = 'Call', Name = 'test');
        insert note;
        Test.stopTest();
        
        String fieldName = 'Type__c';       
        TypeHeadLookupController.getselectOptions(note, fieldName);
    }
}