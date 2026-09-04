@isTest
public class FlowSelectableCard_Controller_Test{
	@testSetup
	public static void makeData(){
	Account accs1 = new Account(FirstName='Account',LastName='Test1',Classification__c='Unclassified');
    Account accs2 = new Account(FirstName='Account',LastName='Test2',Classification__c='Unclassified');
	insert accs1;
    insert accs2;																																												
	}
	
	@isTest
	private static void getRecordsInfoTest(){
	String sObjectName = 'Account';
	String fields = 'FirstName';
    List<Id> accountIds = new List<Id>();
	List<Account> accounts = [Select Id from Account];
	for(Account acc: accounts){
	accountIds.add(acc.Id);
    }
	Test.startTest();
	List<SObject> recordsIdList = FlowSelectableCard_Controller.getRecordsInfo(sObjectName,accountIds,fields,'');
	Test.stopTest();
    System.assertEquals(2,recordsIdList.size());
        system.assertEquals('Account',[select Id,FirstName from Account][0].FirstName);
	}
    
    @isTest
    private static void getRecordInfoTest(){
     String sObjectName = 'Account';
	String fields = 'FirstName';
    List<Account> accounts = [Select Id from Account LIMIT 1];
    ID accountIds = accounts[0].Id;
    Test.startTest();
    List<SObject> recordIdList = FlowSelectableCard_Controller.getRecordInfo(sObjectName,accountIds,fields,'');
    Test.stopTest();
    System.assertEquals(1,recordIdList.size());
    }
    @isTest
    private static void getRecordsInfoWithFilterTest(){
        String sObjectName = 'Account';
        String fields = 'FirstName';
        String recordFilter = 'LastName = \'Test1\'';
        
        List<Id> accountIds = new List<Id>();
        List<Account> accounts = [Select Id from Account];
        for(Account acc: accounts){
            accountIds.add(acc.Id);
        }
        Test.startTest();
        List<SObject> recordsIdList = FlowSelectableCard_Controller.getRecordsInfo(sObjectName,accountIds,fields,recordFilter);
        Test.stopTest();
        System.assertEquals(1,recordsIdList.size());
        system.assertEquals('Account',[select Id,FirstName from Account][0].FirstName);
    }
    
    @isTest
    private static void getRecordInfoWithFilterTest(){
        String sObjectName = 'Account';
        String fields = 'FirstName';
        String recordFilter = 'LastName = \'Test1\'';
        List<Account> accounts = [Select Id from Account LIMIT 1];
        ID accountIds = accounts[0].Id;
        Test.startTest();
        List<SObject> recordIdList = FlowSelectableCard_Controller.getRecordInfo(sObjectName,accountIds,fields,recordFilter);
        Test.stopTest();
        System.assertEquals(1,recordIdList.size());
    }
}