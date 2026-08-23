@IsTest
private class CreateCasesAndTasksBatchTest {

    /*@testSetup
    static void setupUser() {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User u = new User(
            FirstName = 'Jonathan',
            LastName = 'Yu',
            Alias = 'jyu',
            Email = 'jonathan.yu@testorg.com',
            Username = 'jonathan.yu@testorg.com.' + DateTime.now().getTime(),
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        PermissionSet ps = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'FinancialServicesCloudStandard'
            LIMIT 1
        ];

        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
        );
    }

    @IsTest
    static void testBatchExecution() {

        User u = [SELECT Id FROM User WHERE Alias = 'jyu' LIMIT 1];

        System.runAs(u) {

            // Person Account
            Account pa = new Account(
                RecordTypeId = Schema.SObjectType.Account
                    .getRecordTypeInfosByName()
                    .get('Person Account')
                    .getRecordTypeId(),
                FirstName = 'Test',
                LastName  = 'Owner'
            );
            insert pa;

            // Household
            Account household = new Account(Name = 'Test Household');
            insert household;

            // Advisor Team
            Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(
                Name = 'Default Team',
                Orion_ID__c = 2
            );
            insert fat;

            // Rep Code
            Rep_Code__c repCode = new Rep_Code__c(
                Name = 'REP-123',
                Financial_Advisor_Team__c = fat.Id
            );
            insert repCode;

            // Wizard FA
            Wizard_Financial_Account__c wfa =
                new Wizard_Financial_Account__c(Name = 'Test Wizard Financial Account');
            insert wfa;

            // Financial Accounts
            List<FinServ__FinancialAccount__c> finAccounts =
                new List<FinServ__FinancialAccount__c>();

            for (Integer i = 0; i < 5; i++) {
                finAccounts.add(new FinServ__FinancialAccount__c(
                    Name = 'FA ' + i,
                    Maestro_Load__c = true,
                    FinServ__Household__c = household.Id,
                    FinServ__PrimaryOwner__c = pa.Id,
                    Wizard_Financial_Account__c = wfa.Id,
                    Rep_Code_Lookup__c = repCode.Id
                ));
            }
            insert finAccounts;

            // Execute Batch
            Test.startTest();
            Database.executeBatch(new CreateCasesAndTasksBatch(), 200);
            Test.stopTest();

            // Assertions
            System.assertEquals(
                5,
                [SELECT Count() FROM Case WHERE Subject = 'Transition - Maestro Loader'],
                'Cases should be created'
            );

            System.assertEquals(
                5,
                [SELECT Count() FROM Task WHERE Subject = 'Ops Final Review - Transitions'],
                'Tasks should be created'
            );

            for (FinServ__FinancialAccount__c fa : [
                SELECT Rep_Code__c
                FROM FinServ__FinancialAccount__c
                WHERE Maestro_Load__c = true
            ]) {
                System.assertEquals('REP-123', fa.Rep_Code__c);
            }
        }
    }*/
}