@isTest
public class Batch_AccountServicingDatesTest {
    
    @isTest
    private static void batchTest(){
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(name = 'Test Account',Account_Funding_Next_Service_Date__c = System.Today(),
                                  Donation_in_Kind_Next_Service_Date__c = System.Today(),
                                  QCD_Next_Service_Date__c = System.Today(),
                                  Roth_Conversion_Next_Service_Date__c = System.Today(),
								  FinServ__NextReview__c = System.Today(),Type ='Other' ));
         accounts.add(new Account(name = 'Test Account 1',Account_Funding_Next_Service_Date__c = System.Today(), Type ='Other'));
        insert accounts;
        Test.startTest();
        Database.executebatch(New Batch_AccountServicingDates());
        Test.stopTest();
        Assert.areEqual([SELECT Id FROM Task].size(),6);  
    }
}