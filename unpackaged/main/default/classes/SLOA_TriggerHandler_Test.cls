@isTest
public class SLOA_TriggerHandler_Test {

    @isTest
    private static void test_setFATonSLOA(){
        Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c();
        fat.Name = 'Test';
        insert fat;
        
        Financial_Advisor_Team__c fat1 = new Financial_Advisor_Team__c();
        fat1.Name = 'Test2';
        insert fat1;
        
        Test.startTest();
        Standing_Letter_of_Authorization__c sloa = new Standing_Letter_of_Authorization__c(Financial_Advisor_Team__c = fat.Id);
        insert sloa;
        Test.stopTest();
        
        Financial_Advisor_Team__c fatGroup = [SELECT Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Id =: fat.Id];
        System.assertEquals(fatGroup.Public_Group_Id__c, [SELECT UserOrGroupId FROM Standing_Letter_of_Authorization__Share WHERE ParentId =:sloa.Id AND UserOrGroupId =:fatGroup.Public_Group_ID__c].UserOrGroupId);
        
        //for coverage
        delete sloa;
        undelete sloa;
    }
    
    @isTest
    private static void test_UPDATEFATonSLOA(){
        Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c();
        fat.Name = 'Test';
        insert fat;
        
        Financial_Advisor_Team__c fat1 = new Financial_Advisor_Team__c();
        fat1.Name = 'Test2';
        insert fat1;
        
        Test.startTest();
        Standing_Letter_of_Authorization__c sloa = new Standing_Letter_of_Authorization__c(Financial_Advisor_Team__c = fat.Id);
        insert sloa;
        sloa.Financial_Advisor_Team__c = fat1.Id;
        update sloa;
        Test.stopTest();
        
        Financial_Advisor_Team__c fatGroup = [SELECT Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Id =: fat1.Id];
        Financial_Advisor_Team__c fatGroup1 = [SELECT Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Id =: fat.Id];
        System.assertEquals(fatGroup.Public_Group_Id__c, [SELECT UserOrGroupId FROM Standing_Letter_of_Authorization__Share WHERE ParentId =:sloa.Id AND UserOrGroupId =:fatGroup.Public_Group_ID__c].UserOrGroupId);
        System.assertEquals(1, [SELECT UserOrGroupId FROM Standing_Letter_of_Authorization__Share WHERE ParentId =:sloa.Id AND UserOrGroupId =:fatGroup1.Public_Group_ID__c].size());

        //for coverage
        delete sloa;
        undelete sloa;
    }
}