@isTest
public class Account_TriggerHandlerTest {
    
    @isTest
	private static void test_CreateShareRecord() {
        //Advisor_Group__c testgroup = new Advisor_Group__c( Name = 'Test Advisor Group' );
		//Insert testgroup;

    
        Financial_Advisor_Team__c team1 = new Financial_Advisor_Team__c(Name = 'Team 1'/*, Advisor_Group__c  = testGroup.Id*/);
        Financial_Advisor_Team__c team2 = new Financial_Advisor_Team__c(Name = 'Team 2'/*, Advisor_Group__c  = testGroup.Id*/);
        insert new List<Financial_Advisor_Team__c>{team1, team2};
    
        Account acc = new Account(Name = 'Test Account', Financial_Advisor_Team__c = team1.Id);
        Test.startTest();
        insert acc;    
        Test.stopTest();
    
    }
    
    @isTest
	private static void test_UpdateCreateShareRecord() {
        //Advisor_Group__c testgroup = new Advisor_Group__c( Name = 'Test Advisor Group' );
		//Insert testgroup;

    
        Financial_Advisor_Team__c team1 = new Financial_Advisor_Team__c(Name = 'Team 1'/*, Advisor_Group__c  = testGroup.Id*/);
        Financial_Advisor_Team__c team2 = new Financial_Advisor_Team__c(Name = 'Team 2'/*, Advisor_Group__c  = testGroup.Id*/);
        insert new List<Financial_Advisor_Team__c>{team1, team2};
    
        Account acc = new Account(Name = 'Test Account', Financial_Advisor_Team__c = team1.Id);
        insert acc;
    
        Map<Id, Account> newMapInsert = new Map<Id, Account>{ acc.Id => acc };
        List<AccountShare> shareList = [SELECT Id, AccountId, UserOrGroupId, AccountAccessLevel 
                                        FROM AccountShare WHERE AccountId = :acc.Id];
        System.assert(!shareList.isEmpty(), 'AccountShare should be created on insert');
        System.assertEquals('All', shareList[0].AccountAccessLevel, 'Access level should be All');
    
        Account accOld = acc.clone(false, true, false, false);
        acc.Financial_Advisor_Team__c = team2.Id; // changing team to trigger update logic
        Test.startTest();
        update acc;
    
        Test.stopTest();
    
        List<AccountShare> updatedShares = [SELECT Id, AccountId, UserOrGroupId FROM AccountShare WHERE AccountId = :acc.Id];
        System.assert(!updatedShares.isEmpty(), 'AccountShare should exist after update');
    }
    @isTest
    private static void test_updateInvestmentObjectives(){

        Account acct = new Account(Name='update Test', Investment_Objectives__c = 'Growth;Speculation;Balanced');
        insert acct;
        Test.startTest();
        Account acc = new Account(Name='Test', Investment_Objectives__c = 'Growth;Speculation;Income',
                                 Flow_Update__c = false);
        insert acc;
        
        acct.Investment_Objectives__c = 'Growth;Speculation;Income';
        acct.Flow_Update__c = true;
        update acct;
        Test.stopTest();
        
        Map<Id,Account> acctMap = new Map<Id,Account>([SELECT Id, DocuSignIOGrowth__c, DocuSignIOIncome__c, DocuSignIOBalanced__c, 
                                   DocuSignIOSpeculation__c FROM Account]);
        
        // Multipicklist values are stored in picklist definition order, not selection order.
        System.assertEquals(1, acctMap.get(acct.Id).DocuSignIOGrowth__c);
        System.assertEquals(2, acctMap.get(acct.Id).DocuSignIOIncome__c);
        System.assertEquals(null, acctMap.get(acct.Id).DocuSignIOBalanced__c);
        System.assertEquals(3, acctMap.get(acct.Id).DocuSignIOSpeculation__c);
        System.assertEquals(1, acctMap.get(acc.Id).DocuSignIOGrowth__c);
        System.assertEquals(2, acctMap.get(acc.Id).DocuSignIOIncome__c);
        System.assertEquals(null, acctMap.get(acc.Id).DocuSignIOBalanced__c);
        System.assertEquals(3, acctMap.get(acc.Id).DocuSignIOSpeculation__c);
        
        // Coverage for delete/undelete trigger paths. Clear any Standard SLA
        // entitlements so Account delete is allowed.
        delete [SELECT Id FROM Entitlement WHERE AccountId = :acc.Id];
        delete acc;
        undelete acc;
    }

    @isTest
    private static void test_setAccreditationStatus() {
        Account acc = new Account(
            Name = 'Accreditation Test Account',
            Net_Worth_Excluding_Primary_Residence__c = 100000,
            Approximate_Annual_Income_All_Sources__c = 50000
        );
        insert acc;

        Test.startTest();
        acc.Net_Worth_Excluding_Primary_Residence__c = 1500000;
        update acc;
        Test.stopTest();

        Account updated = [
            SELECT Accreditation__c
            FROM Account
            WHERE Id = :acc.Id
        ];
        System.assertEquals('Accredited', updated.Accreditation__c);
    }
}