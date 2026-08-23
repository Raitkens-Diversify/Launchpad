@isTest
public class CustomObjListLookupController_Test {
	@testSetup
    public static void setup()
    {
        Account testAccount = new Account();
        testAccount.Name = 'Test Account';
		insert testAccount;
    }
    
    @isTest
    public static void test_getResults()
    {
        Test.startTest();
        List<CustomObjListLookupController.SObJectResult> testresult = CustomObjListLookupController.getResults('Account', 'Name', 'Test', null, null, null);
        Test.stopTest();
        Assert.areEqual(1, testresult.size());
        Assert.areEqual(CustomObjListLookupController.getParentObjectName('Contact','AccountId'),'Account');
    }
    
    @isTest
    public static void test_getSelectedRecordDetails(){
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Test.startTest();
        SObject objData = CustomObjListLookupController.getSelectedRecordDetails(testAccount.Id);
        Test.stopTest();
        Assert.areEqual('Test Account', objData.get('Name'));
    }
    
    @isTest
    public static void test_getIconName(){
        Test.startTest();
        String iconName = CustomObjListLookupController.getIconName('Account');
        Test.stopTest();
        //Assert.isNotNull(iconName);
    }
}