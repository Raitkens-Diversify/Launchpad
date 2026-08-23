@IsTest
private class OnbaseFinancialAccountConsolidationTest {

    /*@IsTest
    static void testConsolidationSimple() {

        Product__c placeholder = new Product__c(Name = 'Onbase Placeholder');
        insert placeholder;

        Id recTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Individual').getRecordTypeId();

        List<Account> accList = new List<Account>{
            new Account(Name = 'Primary Owner', RecordTypeId = recTypeId),
            new Account(Name = 'Joint Owner', RecordTypeId = recTypeId),
            new Account(Name = 'Joint Owner', RecordTypeId = recTypeId)
        };
        insert accList;

        Wizard_Financial_Account__c wfa1 = new Wizard_Financial_Account__c(Name = 'Test Financial Account 1', Household__c = accList[0].Id, Joint_Owner__c = accList[2].Id , 
                                                                              Primary_Owner__c = accList[0].Id, Do_Not_Create_FinAcct__c  = true,
                                                                              Custodian__c = 'Schwab', Registration_Type__c = 'Individual', isDAOEligible__c = True);
        Wizard_Financial_Account__c wfa2 = new Wizard_Financial_Account__c(Name = 'Test Financial Account 2', Household__c = accList[0].Id, Joint_Owner__c = accList[2].Id , 
                                                                              Primary_Owner__c = accList[0].Id, Do_Not_Create_FinAcct__c  = true,
                                                                              Custodian__c = 'Schwab', Registration_Type__c = 'Individual', isDAOEligible__c = True);
        Wizard_Financial_Account__c wfa3 = new Wizard_Financial_Account__c(Name = 'Test Financial Account 3', Household__c = accList[0].Id, Joint_Owner__c = accList[2].Id , 
                                                                              Primary_Owner__c = accList[0].Id, Do_Not_Create_FinAcct__c  = true,
                                                                              Custodian__c = 'Schwab', Registration_Type__c = 'Individual', isDAOEligible__c = True);
        insert new List<Wizard_Financial_Account__c>{ wfa1, wfa2, wfa3 };

        FinServ__FinancialAccount__c keeper = new FinServ__FinancialAccount__c(
            FinServ__FinancialAccountNumber__c = 'ACCT-001',
            FinServ__Balance__c = 100,
            Onbase_Migration_Id__c = 'MIG-KEEPER',
            Wizard_Financial_Account__c = wfa3.Id,
            FinServ__PrimaryOwner__c = accList[0].Id
        );

        FinServ__FinancialAccount__c matched1 = new FinServ__FinancialAccount__c(
            FinServ__FinancialAccountNumber__c = 'ACCT-001',
            FinServ__Balance__c = 250,
            Onbase_Migration_Id__c = 'MIG-OTHER-1',
            Wizard_Financial_Account__c = wfa2.Id,
            FinServ__PrimaryOwner__c = accList[1].Id
        );

        FinServ__FinancialAccount__c unrelated = new FinServ__FinancialAccount__c(
            FinServ__FinancialAccountNumber__c = 'ACCT-002',
            FinServ__Balance__c = 50,
            Wizard_Financial_Account__c = wfa1.Id,
            FinServ__PrimaryOwner__c = accList[2].Id
        );

        insert new List<FinServ__FinancialAccount__c>{ keeper, matched1, unrelated };

        Test.startTest();
            Database.executeBatch(new OnbaseFinancialAccountConsolidation(), 2);
        Test.stopTest();

        FinServ__FinancialAccount__c keeperAfter =
            [SELECT Onbase_Consolidation__c FROM FinServ__FinancialAccount__c WHERE Id = :keeper.Id];
        System.assertEquals(true, keeperAfter.Onbase_Consolidation__c);
		// Deletion functionality
        //System.assertEquals(0,[SELECT COUNT() FROM FinServ__FinancialAccount__c WHERE Id = :matched1.Id]);

        List<Financial_Account_Related_Product__c> rps =
            [SELECT Id FROM Financial_Account_Related_Product__c WHERE Financial_Account__c = :keeper.Id];
        System.assertEquals(2, rps.size());
    }

    @IsTest
    static void testIdempotency() {

        Product__c placeholder = new Product__c(Name='Onbase Placeholder');
        insert placeholder;

        Id recTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Individual').getRecordTypeId();

        List<Account> accList = new List<Account>{
            new Account(Name = 'Primary Owner', RecordTypeId = recTypeId),
            new Account(Name = 'Joint Owner', RecordTypeId = recTypeId),
            new Account(Name = 'Joint Owner', RecordTypeId = recTypeId)
        };
        insert accList;


        Wizard_Financial_Account__c wfa = new Wizard_Financial_Account__c(Name = 'Test Financial Account', Household__c = accList[0].Id, Joint_Owner__c = accList[2].Id , 
                                                                              Primary_Owner__c = accList[0].Id, Do_Not_Create_FinAcct__c = true,
                                                                              Custodian__c = 'Schwab', Registration_Type__c = 'Individual', isDAOEligible__c = True);


        FinServ__FinancialAccount__c keeper = new FinServ__FinancialAccount__c(
            FinServ__FinancialAccountNumber__c = 'ACCT-777',
            FinServ__Balance__c = 500,
            Onbase_Migration_Id__c = 'MIG-777',
            Wizard_Financial_Account__c = wfa.Id,
            FinServ__PrimaryOwner__c = accList[0].Id
        );
        insert keeper;

        Test.startTest();
            Database.executeBatch(new OnbaseFinancialAccountConsolidation(), 1);
            Database.executeBatch(new OnbaseFinancialAccountConsolidation(), 1);
        Test.stopTest();

        Integer countRps =
            [SELECT COUNT() FROM Financial_Account_Related_Product__c WHERE Financial_Account__c = :keeper.Id];

        System.assertEquals(1, countRps);
    }*/
}