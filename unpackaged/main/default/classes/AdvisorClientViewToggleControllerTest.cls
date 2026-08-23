@isTest
private class AdvisorClientViewToggleControllerTest {

    @testSetup
    static void setup() {
        // Create a test Account
        Account testAcc = new Account(
            Name = 'Test Advisor Client',
            View_State__c = 'Diversify'
        );
        insert testAcc;
    }

    @isTest
    static void testToggleView() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        String newState = 'Client';

        Test.startTest();
        AdvisorClientViewToggleController.toggleView(acc.Id, newState);
        Test.stopTest();

        Account updatedAcc = [SELECT View_State__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(newState, updatedAcc.View_State__c);
    }

    @isTest
    static void testGetViewState() {
        Account acc = [SELECT Id, View_State__c FROM Account LIMIT 1];

        Test.startTest();
        String result = AdvisorClientViewToggleController.getViewState(acc.Id);
        Test.stopTest();

        System.assertEquals(acc.View_State__c, result);
    }
    
    @isTest
    static void testToggleViewNegative() {
        // Test with invalid ID to ensure it handles Query Exception
        try {
            Test.startTest();
            AdvisorClientViewToggleController.toggleView(null, 'Client');
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown for null ID');
        } catch (Exception e) {
            System.assert(e != null, 'An exception was expected.');
        }
    }
}