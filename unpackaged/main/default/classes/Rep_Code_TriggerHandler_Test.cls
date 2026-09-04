@isTest
public class Rep_Code_TriggerHandler_Test {    
    @TestSetup
    static void setupTestData() {
        
        Financial_Advisor_Team__c defaultTeam = new Financial_Advisor_Team__C ( Name = 'Default Team');
        insert defaultTeam;
        
        
        // Get Account Record Types
        Id householdRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByName()
            .get('Household')
            .getRecordTypeId();
        
        Id personAccountRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
        
        /*
* Create Household Account
*/
        Account household = new Account(
            Name = 'Test Household',
            RecordTypeId = householdRecordTypeId,
            Type ='Other',
            Classification__c = 'Vendor;'
            
        );
        insert household;
        
        /*
* Create Person Account
*/
        Account primaryOwner = new Account(
            FirstName = 'Test',
            LastName = 'Primary Owner',
            PersonEmail = 'primaryowner@test.com',
            RecordTypeId = personAccountRecordTypeId,
            Type ='Other',
            Classification__c = 'Vendor;'
        );
        insert primaryOwner;
        
        /*
* Create Account Contact Relation.
*
* If your FSC org requires additional fields for ACR creation,
* add them here.
*/
        primaryOwner = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id = :primaryOwner.Id
            LIMIT 1
        ];
        
        AccountContactRelation acr = new AccountContactRelation(
            ContactId = primaryOwner.PersonContactId,
            AccountId = household.Id,
            IsActive = true
        );
        insert acr;
        
        /*
* Create Financial Advisor Teams.
*
* Replace these records with the appropriate object if
* Financial_Advisor_Team__c is a different object in your org.
*/
        Financial_Advisor_Team__c oldTeam = new Financial_Advisor_Team__c(
            Name = 'Old Team'
        );
        
        Financial_Advisor_Team__c newTeam = new Financial_Advisor_Team__c(
            Name = 'New Team'
        );
        
        insert new List<Financial_Advisor_Team__c>{
            oldTeam,
                newTeam
                };
                    
                    /*
* Create Rep Code.
*/
                    Rep_Code__c repCode = new Rep_Code__c(
                        Name = 'TEST-REP-001',
                        Financial_Advisor_Team__c = oldTeam.Id
                    );
        insert repCode;
        
        /*
* Create Financial Account.
*
* Add any additional required fields from your org here.
*/
        FinServ__FinancialAccount__c financialAccount =
            new FinServ__FinancialAccount__c(
                Name = 'Test Financial Account',
                Rep_Code_Lookup__c = repCode.Id,
                Financial_Advisor_Team__c = oldTeam.Id,
                FinServ__PrimaryOwner__c = primaryOwner.Id
            );
        
        insert financialAccount;
        
        /*
* Create Case related to Household.
*/
        Case householdCase = new Case(
            AccountId = household.Id,
            Status = 'New',
            Subject = 'Household Test Case',
            FinServ__Household__c = household.Id,
            Financial_Advisor_Team__c = oldTeam.Id
        );
        insert householdCase;
        
        /*
* Create Case related to Financial Account.
*/
        Case financialAccountCase = new Case(
            AccountId = household.Id,
            Status = 'New',
            Subject = 'Financial Account Test Case',
            FinServ__FinancialAccount__c = financialAccount.Id,
            FinServ__Household__c = household.Id,
            Financial_Advisor_Team__c = oldTeam.Id
        );
        insert financialAccountCase;
        
        /*
* Create Task related to Household.
*/
        Task householdTask = new Task(
            Subject = 'Household Task',
            Status = 'Not Started',
            WhatId = household.Id,
            Financial_Advisor_Team__c = oldTeam.Id
        );
        insert householdTask;
        
        /*
* Create Task related to Financial Account.
*/
        Task financialAccountTask = new Task(
            Subject = 'Financial Account Task',
            Status = 'Not Started',
            WhatId = financialAccount.Id,
            Financial_Advisor_Team__c = oldTeam.Id
        );
        insert financialAccountTask;
        
        /*
* Create Event related to Household.
*/
        Event householdEvent = new Event(
            Subject = 'Household Event',
            StartDateTime = System.now().addHours(1),
            EndDateTime = System.now().addHours(2),
            WhatId = household.Id,
            Financial_Advisor_Team__c = oldTeam.Id
        );
        insert householdEvent;
        
        /*
* Create Event related to Financial Account.
*/
        Event financialAccountEvent = new Event(
            Subject = 'Financial Account Event',
            StartDateTime = System.now().addHours(1),
            EndDateTime = System.now().addHours(2),
            WhatId = financialAccount.Id,
            Financial_Advisor_Team__c = oldTeam.Id
        );
        insert financialAccountEvent;
    }
    
    
    @IsTest
    static void testFinancialAdvisorTeamChange() {
        
        Rep_Code__c repCode = [
            SELECT Id,
            Name,
            Financial_Advisor_Team__c
            FROM Rep_Code__c
            WHERE Name = 'TEST-REP-001'
            LIMIT 1
        ];
        
        Financial_Advisor_Team__c newTeam = [
            SELECT Id, Name
            FROM Financial_Advisor_Team__c
            WHERE Name = 'New Team'
            LIMIT 1
        ];
        
        // Change Financial Advisor Team
        repCode.Financial_Advisor_Team__c = newTeam.Id;
        
        Test.startTest();
        
        update repCode;
        
        Test.stopTest();
        
        /*
* Verify Financial Account
*/
        FinServ__FinancialAccount__c financialAccount = [
            SELECT Id,
            Financial_Advisor_Team__c,
            Rep_Code_Lookup__c
            FROM FinServ__FinancialAccount__c
            WHERE Rep_Code_Lookup__c = :repCode.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            newTeam.Id,
            financialAccount.Financial_Advisor_Team__c,
            'Financial Account FAT should be updated.'
        );
        
        /*
* Verify Primary Owner
*/
        Account primaryOwner = [
            SELECT Id,
            Financial_Advisor_Team__c
            FROM Account
            WHERE LastName = 'Primary Owner'
            LIMIT 1
        ];
        
        System.assertEquals(
            newTeam.Id,
            primaryOwner.Financial_Advisor_Team__c,
            'Primary Owner FAT should be updated.'
        );
        
        /*
* Verify Household-related Cases
*/
        List<Case> cases = [
            SELECT Id,
            Financial_Advisor_Team__c,
            FinServ__Household__c,
            FinServ__FinancialAccount__c
            FROM Case
        ];
        
        System.assertEquals(
            2,
            cases.size(),
            'Expected two test Cases.'
        );
        
   
        /*
* Verify Tasks
*/
        List<Task> tasks = [
            SELECT Id,
            Financial_Advisor_Team__c,
            WhatId
            FROM Task
        ];
        
        System.assertEquals(
            2,
            tasks.size(),
            'Expected two test Tasks.'
        );
        
        
    }
    
    
    @IsTest
    static void testNoUpdateWhenFinancialAdvisorTeamDoesNotChange() {
        
        Rep_Code__c repCode = [
            SELECT Id,
            Financial_Advisor_Team__c
            FROM Rep_Code__c
            WHERE Name = 'TEST-REP-001'
            LIMIT 1
        ];
        
        Id oldTeamId = repCode.Financial_Advisor_Team__c;
        
        // Update some unrelated field if available.
        // Here we simply assign the same FAT value.
        repCode.Financial_Advisor_Team__c = oldTeamId;
        
        Test.startTest();
        
        update repCode;
        
        Test.stopTest();
        
        FinServ__FinancialAccount__c financialAccount = [
            SELECT Id,
            Financial_Advisor_Team__c
            FROM FinServ__FinancialAccount__c
            WHERE Rep_Code_Lookup__c = :repCode.Id
            LIMIT 1
        ];
        
        System.assertEquals(
            oldTeamId,
            financialAccount.Financial_Advisor_Team__c,
            'Financial Account FAT should remain unchanged.'
        );
    }
}