@isTest
public class FATMember_TriggerHandler_Test {    
    @testSetup
    private static void setup() {
        User usr = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name='System Administrator'].Id,
            FirstName = 'fName',
            LastName = 'lName',
            Username = 'user@test.com' + System.currentTimeMillis(),
            Email = 'test@none.com',
            CompanyName = 'test',
            Title = 'title',
            Alias = 'alias',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            IsActive = true);
        insert usr;
        /*Advisor_Group__c aGrp = new Advisor_Group__c(
Name = 'Test Advisor Group'
);
insert aGrp;*/
        System.runAs(usr){
            
            List<Financial_Advisor_Team_Member__c> fatmList = new List<Financial_Advisor_Team_Member__c>();
            Financial_Advisor_Team__c defaultTeam = new Financial_Advisor_Team__c(Name = 'Default Team'/*,
Advisor_Group__c = aGrp.Id*/);
            insert defaultTeam;
            
            Group grp = new Group(Name='Test Group');
            insert grp;
            
            Id recTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('IndustriesIndividual').getRecordTypeId();
            List<Account> accList = new List<Account>();
            Account acc = new Account(Name = 'Primary Owner', recordTypeId = recTypeId, Type ='Other');
            Account acc1 = new Account(Name = 'Joint Owner', recordTypeId = recTypeId, Type ='Other');
            accList.add(acc);
            accList.add(acc1);
            insert accList;
            Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c();
            faTeam.Name = 'Test Fin Advisor Team';
            //faTeam.Advisor_Group__c = aGrp.Id;
            insert faTeam;
            FinServ__FinancialAccount__c finAccount = new FinServ__FinancialAccount__c();
            finAccount.Name = 'Test Fin Account';
            finAccount.FinServ__PrimaryOwner__c = accList[0].Id;
            finAccount.FinServ__JointOwner__c = accList[1].Id;
            finAccount.Financial_Advisor_Team__c = faTeam.Id;
            insert finAccount;
            
            accList[0].Financial_Advisor_Team__c = faTeam.Id;
            update accList[0];
            accList[1].Financial_Advisor_Team__c = faTeam.Id;
            update accList[1];
            
            
            Id fatId = [SELECT Id FROM Financial_Advisor_Team__c WHERE Name='Test Fin Advisor Team'][0].Id;
            
            Financial_Advisor_Team_Member__c fatmember = new Financial_Advisor_Team_Member__c();
            fatmember.Active__c = true;
            fatmember.Financial_Advisor_Team__c = fatId;
            fatmember.Role__c = 'Financial Advisor';
            fatmember.User__c = usr.Id;
            fatmList.add(fatmember);
            Financial_Advisor_Team_Member__c fatmember1 = new Financial_Advisor_Team_Member__c();
            fatmember1.Active__c = true;
            fatmember1.Financial_Advisor_Team__c = fatId;
            fatmember1.Role__c = 'Financial Advisor';
            fatmember1.User__c = UserInfo.getUserId();
            fatmList.add(fatmember1);
            insert fatmList;
        }
    }
    
    @isTest
    private static void testOnInsert_manageGroupMember(){ 
        Id faTeamId = [SELECT Id, Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Name='Test Fin Advisor Team'][0].Id;
        Id grpId = [SELECT Id, Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Name='Test Fin Advisor Team'][0].Public_Group_Id__c;
        Financial_Advisor_Team_Member__c fatmember = new Financial_Advisor_Team_Member__c();
        fatmember.Active__c = true;
        fatmember.Financial_Advisor_Team__c = faTeamId;
        fatmember.Role__c = 'Financial Advisor';
        fatmember.User__c = UserInfo.getUserId();
        Test.startTest();
        insert fatmember;
        Test.stopTest();	
        System.assertEquals(2, [SELECT count() FROM GroupMember WHERE groupId =: grpId]);
    }
    
    @isTest
    private static void test_managePrimaryFATMember(){
        List<Financial_Advisor_Team__c> fat=[SELECT Id FROM Financial_Advisor_Team__c];
        Financial_Advisor_Team_Member__c fatmember = [SELECT Id, Active__c,Primary__c,Financial_Advisor_Team__c FROM Financial_Advisor_Team_Member__c][0];
        fatmember.Primary__c=true;
        update fatmember;
        Financial_Advisor_Team_Member__c fatmember1 = new Financial_Advisor_Team_Member__c();
        fatmember1.Active__c = true;
        fatmember1.Primary__c=true;
        fatmember1.Financial_Advisor_Team__c = fatmember.Financial_Advisor_Team__c;
        fatmember1.Role__c = 'Financial Advisor';
        fatmember1.User__c = UserInfo.getUserId();
        Test.startTest();
        insert fatmember1;
        test.stopTest();
        system.assertEquals(false,[SELECT Id, Active__c,Primary__c,Financial_Advisor_Team__c FROM Financial_Advisor_Team_Member__c where Id=:fatmember.Id][0].Primary__c);
    }
    
    @isTest
    private static void test_deleteGroupMember(){
        GroupMember grp = [SELECT Id FROM GroupMember][0];
        List<Financial_Advisor_Team_Member__c> fatTMemberList = [SELECT Id, Group_Member_Id__c FROM
                                                                 Financial_Advisor_Team_Member__c];
        for(Financial_Advisor_Team_Member__c fatm : fatTMemberList){
            fatm.Group_Member_Id__c = grp.Id;
        }
        update fatTMemberList;
        Test.startTest();
        delete [SELECT Id, Group_Member_Id__c FROM Financial_Advisor_Team_Member__c];
        Test.stopTest();       
        Assert.isTrue([SELECT Id FROM GroupMember WHERE Id = :grp.Id].size() == 0);
    }
    
    
    
    @isTest
    private static void test_handlePermissions(){
        List<Financial_Advisor_Team_Member__c> fatMemberList = [SELECT Id, Group_Member_Id__c, Draft_Paperwork__c, 
                                                                Review_Paperwork__c, Send_Notifications__c, Trading__c FROM
                                                                Financial_Advisor_Team_Member__c limit 2];
        fatMemberList[0].Draft_Paperwork__c = true;
        fatMemberList[0].Review_Paperwork__c = true;
        fatMemberList[1].Send_Notifications__c = true;
        fatMemberList[1].Trading__c = true;
        fatMemberList[1].Operations__c = true;
        
        Test.startTest();
        update fatMemberList;
        Test.stopTest();       
        Financial_Advisor_Team__c faTeam = [SELECT Id, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c, Trading__c 
                                            FROM Financial_Advisor_Team__c WHERE Name = 'Test Fin Advisor Team' limit 1];
        Financial_Advisor_Team_Member__c fatMember1 = [SELECT Id, Name, User_Name__c, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c, 
                                                       Trading__c FROM Financial_Advisor_Team_Member__c WHERE Id = 
                                                       :fatMemberList[0].Id limit 1];
        Financial_Advisor_Team_Member__c fatMember2 = [SELECT Id, Name, User_Name__c, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c, 
                                                       Trading__c FROM Financial_Advisor_Team_Member__c WHERE Id = 
                                                       :fatMemberList[1].Id limit 1];
        Assert.isTrue(fatMember1.Draft_Paperwork__c);
        Assert.isTrue(fatMember1.Review_Paperwork__c);
        Assert.isTrue(fatMember2.Send_Notifications__c);
        Assert.isTrue(fatMember2.Trading__c);
        Assert.isFalse(fatMember2.Draft_Paperwork__c);
        Assert.isFalse(fatMember2.Review_Paperwork__c);
        Assert.isFalse(fatMember1.Send_Notifications__c);
        Assert.isFalse(fatMember1.Trading__c);
    }
    
    @isTest
    private static void test_setPermissionOnRule(){
        List<Financial_Advisor_Team_Member__c> fatMemberList = [SELECT Id, Role__c FROM Financial_Advisor_Team_Member__c limit 2];
        fatMemberList[0].Role__c = 'Associate Advisor';
        fatMemberList[1].Role__c = 'CSA';
        update fatMemberList;
        Financial_Advisor_Team__c faTeam = [SELECT Id, Associate_Advisor__c, CSA__c
                                            FROM Financial_Advisor_Team__c WHERE Name = 'Test Fin Advisor Team' limit 1];
        Financial_Advisor_Team_Member__c fatMember1 = [SELECT Id, Name, Role__c, User_Name__c, CSA__c, Associate_Advisor__c FROM Financial_Advisor_Team_Member__c WHERE Id = 
                                                       :fatMemberList[0].Id limit 1];
        Financial_Advisor_Team_Member__c fatMember2 = [SELECT Id, Name, Role__c, User_Name__c, CSA__c, Associate_Advisor__c FROM Financial_Advisor_Team_Member__c WHERE Id = 
                                                       :fatMemberList[1].Id limit 1];
        System.AssertEquals(fatMember1.Role__c, 'Associate Advisor');
        System.AssertEquals(fatMember2.Role__c, 'CSA');
    }
    
    
    @isTest
    private static void test_handlePermissionsBulky(){
        List<Financial_Advisor_Team_Member__c> fatMemberList = [SELECT Id, Group_Member_Id__c, Draft_Paperwork__c, 
                                                                Review_Paperwork__c, Send_Notifications__c, Trading__c FROM
                                                                Financial_Advisor_Team_Member__c limit 2];
        fatMemberList[0].Draft_Paperwork__c = true;
        fatMemberList[0].Review_Paperwork__c = true;
        fatMemberList[0].Send_Notifications__c = true;
        fatMemberList[0].Trading__c = true;
        fatMemberList[0].Operations__c = true;
        
        update fatMemberList[0];
        fatMemberList[1].Send_Notifications__c = true;
        fatMemberList[1].Trading__c = true;
        fatMemberList[1].Operations__c = true;
        
        Test.startTest();
        update fatMemberList[1];
        Test.stopTest();       
        Financial_Advisor_Team__c faTeam = [SELECT Id, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c, Trading__c 
                                            FROM Financial_Advisor_Team__c WHERE Name = 'Test Fin Advisor Team' limit 1];
        Financial_Advisor_Team_Member__c fatMember1 = [SELECT Id, Name, User_Name__c, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c, 
                                                       Trading__c FROM Financial_Advisor_Team_Member__c WHERE Id = 
                                                       :fatMemberList[0].Id limit 1];
        Financial_Advisor_Team_Member__c fatMember2 = [SELECT Id, Name, User_Name__c, Draft_Paperwork__c, Review_Paperwork__c, Send_Notifications__c, 
                                                       Trading__c FROM Financial_Advisor_Team_Member__c WHERE Id = 
                                                       :fatMemberList[1].Id limit 1];
        Assert.areEqual(fatMember1.User_Name__c, faTeam.Draft_Paperwork__c);
        Assert.areEqual(fatMember1.User_Name__c, faTeam.Review_Paperwork__c);
        Assert.areEqual(fatMember2.User_Name__c, faTeam.Send_Notifications__c);
        Assert.areEqual(fatMember2.User_Name__c, faTeam.Trading__c);
        Assert.isTrue(fatMember1.Draft_Paperwork__c);
        Assert.isTrue(fatMember1.Review_Paperwork__c);
        Assert.isTrue(fatMember2.Send_Notifications__c);
        Assert.isTrue(fatMember2.Trading__c);
        Assert.isFalse(fatMember2.Draft_Paperwork__c);
        Assert.isFalse(fatMember2.Review_Paperwork__c);
        Assert.isFalse(fatMember1.Send_Notifications__c);
        Assert.isFalse(fatMember1.Trading__c);
    }
    
    /*@isTest
private static void test_handleError(){
Financial_Advisor_Team_Member__c fatMember = [SELECT Id, Group_Member_Id__c, Draft_Paperwork__c, 
Review_Paperwork__c, Send_Notifications__c, Trading__c FROM
Financial_Advisor_Team_Member__c LIMIT 1];
fatMember.Draft_Paperwork__c = true;
fatMember.Review_Paperwork__c = true;
fatMember.Send_Notifications__c = true;
fatMember.Trading__c = true;
fatMember.Operations__c = true;

update fatMember;
String message = '';
Test.startTest();
try{
fatMember.Draft_Paperwork__c = false;
fatMember.Operations__c = false;
update fatMember;
}
catch(Exception e)
{
message = e.getMessage();
}
Test.stopTest();    

}
*/
    @isTest
    static void test_handleError() {
        Financial_Advisor_Team_Member__c fatMember = [SELECT Id, Group_Member_Id__c, Draft_Paperwork__c, Financial_Advisor_Team__c,
                                                      Review_Paperwork__c, Send_Notifications__c, Trading__c FROM
                                                      Financial_Advisor_Team_Member__c limit 1];        
        Test.startTest();
        // Update member → uncheck Draft_Paperwork__c (last one) and Review_Paperwork__c (last one)
        fatMember.Draft_Paperwork__c = false;
        fatMember.Review_Paperwork__c = false;
        update fatMember;
        Test.stopTest();
        
        System.assertEquals(null, [SELECT Id, Draft_Paperwork__c, Review_Paperwork__c
                                   FROM Financial_Advisor_Team__c
                                   WHERE Id = :fatMember.Financial_Advisor_Team__c LIMIT 1].Draft_Paperwork__c);
        System.assertEquals(null, [SELECT Id, Draft_Paperwork__c, Review_Paperwork__c
                                   FROM Financial_Advisor_Team__c
                                   WHERE Id = :fatMember.Financial_Advisor_Team__c LIMIT 1].Review_Paperwork__c);
    }
    
    @isTest
    static void test_handlePermissionOnFatParent() {
        Financial_Advisor_Team_Member__c fatMember = [SELECT Id, Group_Member_Id__c, Draft_Paperwork__c, Financial_Advisor_Team__c,
                                                      Review_Paperwork__c, Send_Notifications__c, Trading__c FROM
                                                      Financial_Advisor_Team_Member__c limit 1];        
        
        
        Test.startTest();
        // Update member: turn on permissions (false -> true)
        fatMember.Draft_Paperwork__c = true;
        fatMember.Review_Paperwork__c = true;
        fatMember.Send_Notifications__c = true;
        fatMember.Trading__c = true;
        fatMember.CSA__c = true;
        fatMember.Associate_Advisor__c = true;
        fatMember.Project_Manager__c = true;
        fatMember.Operations__c = true;
        update fatMember;
        Test.stopTest();
        
        // Reload parent team
        Financial_Advisor_Team__c team = [
            SELECT Id, Draft_Paperwork__c, Review_Paperwork__c,
            Send_Notifications__c, Trading__c,
            CSA__c, Associate_Advisor__c,
            Project_Manager__c, Operations__c
            FROM Financial_Advisor_Team__c
            WHERE Id = :fatMember.Financial_Advisor_Team__c
        ];
        
        System.assertNotEquals(null, team.Draft_Paperwork__c, 'Parent Draft_Paperwork__c not updated');
        System.assertNotEquals(null, team.Review_Paperwork__c, 'Parent Review_Paperwork__c not updated');
        System.assertNotEquals(null, team.Send_Notifications__c, 'Parent Send_Notifications__c not updated');
        System.assertNotEquals(null, team.Trading__c, 'Parent Trading__c not updated');
        System.assertNotEquals(null, team.CSA__c, 'Parent CSA__c not updated');
        System.assertNotEquals(null, team.Associate_Advisor__c, 'Parent Associate_Advisor__c not updated');
        System.assertNotEquals(null, team.Project_Manager__c, 'Parent Project_Manager__c not updated');
        System.assertNotEquals(null, team.Operations__c, 'Parent Operations__c not updated');
    }
    
    @isTest
    private static void test_undeleteFATmember(){
        Financial_Advisor_Team_Member__c fatMember = [SELECT Id, Role__c, Associate_Advisor__c FROM Financial_Advisor_Team_Member__c limit 1];
        Id fatMemberId = fatMember.Id;
        delete fatMember;
        Test.startTest();
        undelete fatMember;
        Test.stopTest();
        System.AssertNotEquals(null, [SELECT Id, Role__c, Associate_Advisor__c FROM Financial_Advisor_Team_Member__c WHERE Id = :fatMemberId]);
    }
}