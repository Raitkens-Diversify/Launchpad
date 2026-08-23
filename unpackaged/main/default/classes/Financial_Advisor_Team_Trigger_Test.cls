@istest
public class Financial_Advisor_Team_Trigger_Test {
    @istest
    private static void testInsert(){
        system.debug([select count() from Financial_Advisor_Team__Share]);
        Financial_Advisor_Team__c fat=new Financial_Advisor_Team__c(Name='Test');
        test.startTest();
        insert fat;
        test.stopTest();
        Id grpId=[select Id,Public_Group_Id__c from Financial_Advisor_Team__c][0].Public_Group_Id__c;
        system.assertEquals(1,[select count() from Group where Id=:grpId]);
        system.assertEquals('Test', [select Id,Name from Group where Id=:grpId][0].Name);
        delete fat;
        
    }
    @istest
    private static void testIsBeforeUpdate(){
        Financial_Advisor_Team__c fateam=new Financial_Advisor_Team__c(Name='Default Team');
        insert fateam;
        Financial_Advisor_Team__c fat=new Financial_Advisor_Team__c(Name='Test');
        insert fat;
        Id grpId=[select Id,Public_Group_Id__c from Financial_Advisor_Team__c where Id=:fat.Id][0].Public_Group_Id__c;
        test.startTest();
        fat.Name='Test Name Changed';
        update fat;
        test.stopTest();
        system.assertEquals('Test Name Changed', [select Id,Name from Group where Id=:grpId][0].Name);
    }
    @istest
    private static void testAfterInsert(){
        Financial_Advisor_Team__c faTeam=new Financial_Advisor_Team__c(Name='Test');
        test.startTest();
        insert faTeam;
        test.stopTest();
        system.assertEquals(faTeam.Id,[select Id,ParentId from Financial_Advisor_Team__Share][0].ParentId);
    }
    @istest
    private static void testupdateRepCode(){
        List<Financial_Advisor_Team__c> fatList=new List<Financial_Advisor_Team__c>();
        Financial_Advisor_Team__c fat=new Financial_Advisor_Team__c(Name='Default Team');
        Financial_Advisor_Team__c fat1=new Financial_Advisor_Team__c(Name='Test',Related_Advisors__c='Test');
        fatList.add(fat);
        fatList.add(fat1);
        insert fatList;
        Rep_Code__c repCode=new Rep_Code__c(Name='test',Financial_Advisor_Team__c=fat.Id,Related_Advisors__c='UpdateTest');
        insert repCode;
        test.startTest();
        fat1.Related_Advisors__c='UpdateTest';
        update fat1;
        test.stopTest();
        Rep_Code__c repCodeTest=[select Id,Financial_Advisor_Team__c from Rep_Code__c][0];
        system.assertEquals(fat1.Id,repCodeTest.Financial_Advisor_Team__c);
        
    }
    @isTest
    static void testCreateFinancialAdvisorTeamMember() {
        User user = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'TestU',
            Email = 'Test.user@gmail.com',
            Username = 'Test.user.1234@gmail.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert user;
        // Create test data
        Financial_Advisor_Team__c teamWithoutAdvisor = new Financial_Advisor_Team__c(
            Name = 'Default Team',
            Primary_Financial_Advisor__c = user.Id
        );
        
        Test.startTest();
        insert teamWithoutAdvisor;
        Test.stopTest();
        
        // Verify results
        List<Financial_Advisor_Team_Member__c> teamMembers = [
            SELECT Financial_Advisor_Team__c, User__c, Active__c, Primary__c, Role__c 
            FROM Financial_Advisor_Team_Member__c
        ];
        System.assertEquals(1, teamMembers.size(), 'One Financial Advisor Team Member should be created.');
        System.assertEquals(teamWithoutAdvisor.Id, teamMembers[0].Financial_Advisor_Team__c, 'The team member should belong to the correct team.');
        System.assertEquals(true, teamMembers[0].Active__c, 'The team member should be active.');
        System.assertEquals(true, teamMembers[0].Primary__c, 'The team member should be marked as primary.');
        System.assertEquals('Financial Advisor', teamMembers[0].Role__c, 'The team member should have the role of Financial Advisor.');
    }
    @isTest
    static void testCreateAndUpdateFinancialAdvisorTeamMember() {
        // Create test data
        User advisor1 = new User(
            FirstName = 'advisor1',
            LastName = 'example',
            Alias = 'ade1',
            Email = 'advisor1@example.com',
            Username = 'advisor132@example.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert advisor1;
        User advisor2 = new User(
            FirstName = 'advisor2',
            LastName = 'example',
            Alias = 'ade2',
            Email = 'advisor2@example.com',
            Username = 'advisor2434@example.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert advisor2;
        
    
        Financial_Advisor_Team__c team = new Financial_Advisor_Team__c(
            Name = 'Default Team',
            Primary_Financial_Advisor__c = advisor1.Id
        );
        insert team;
        
        // Create an initial team member for advisor1
        Financial_Advisor_Team_Member__c teamMember = new Financial_Advisor_Team_Member__c(
            Financial_Advisor_Team__c = team.Id,
            User__c = advisor1.Id,
            Active__c = true,
            Primary__c = true,
            Role__c = 'Financial Advisor'
        );
        insert teamMember;
        
        // Simulate an update: change the primary advisor to advisor2
        Financial_Advisor_Team__c updatedTeam = new Financial_Advisor_Team__c(
            Id = team.Id,
            Primary_Financial_Advisor__c = advisor2.Id
        );        
        Test.startTest();
        update updatedTeam;
        Test.stopTest();
        
        // Verify results
        Map<Id,Financial_Advisor_Team_Member__c> teamMembers = new Map<Id,Financial_Advisor_Team_Member__c>( [
            SELECT Financial_Advisor_Team__c, User__c, Active__c, Primary__c, Role__c 
            FROM Financial_Advisor_Team_Member__c
        ]);
        System.assertEquals(3, teamMembers.size(), 'There should be two team members.');
                System.assertEquals(False, teamMembers.get(teamMember.Id).Primary__c, 'There should be Primary__c set false.');

    }
}