@isTest
public class UpdateFATMemberAfterGroupQueue_Test {
    @testsetup
    public static void TestData(){
         List<Financial_Advisor_Team_Member__c> fatmList=new List<Financial_Advisor_Team_Member__c>();
        List<Financial_Advisor_Team__c> fatList=new List<Financial_Advisor_Team__c>();
        Financial_Advisor_Team__c fat=new Financial_Advisor_Team__c(Name='Default Team');
        Financial_Advisor_Team__c fat1=new Financial_Advisor_Team__c(Name='Test');
        fatList.add(fat);
        fatList.add(fat1);
        insert fatList;
        Financial_Advisor_Team_Member__c fatm=new Financial_Advisor_Team_Member__c();
        fatm.Active__c=true;
        fatm.Role__c='Financial Advisor';
        fatm.Financial_Advisor_Team__c=fat1.Id;
        fatm.User__c=UserInfo.getUserId();
        fatmList.add(fatm);
         Financial_Advisor_Team_Member__c fatm1=new Financial_Advisor_Team_Member__c();
        fatm1.Active__c=true;
        fatm1.Role__c='Financial Advisor';
        fatm1.Financial_Advisor_Team__c=fat1.Id;
        fatm1.User__c=UserInfo.getUserId();
        fatmList.add(fatm1);
        insert fatmList;
        
    }
    @istest
    private static void testupdateFATMemberAfterGrpQueue(){
        List<Financial_Advisor_Team_Member__c> fatmList=[select Id,Group_Member_Id__c,User__c,Financial_Advisor_Team__c from Financial_Advisor_Team_Member__c];
        Map<Id,Financial_Advisor_Team__c> fatMap=new Map<Id,Financial_Advisor_Team__c>([select Id,Public_Group_Id__c from Financial_Advisor_Team__c]);
       	
        Map<String,Id> groupIdWithUserIdMap=new Map<String,Id>();
        for(Financial_Advisor_Team_Member__c fatm:fatmList){
            groupIdWithUserIdMap.put(fatMap.get(fatm.Financial_Advisor_Team__c).Public_Group_Id__c,fatm.User__c);
        }
       Id groupId=[select Id,Public_Group_Id__c from Financial_Advisor_Team__c where Name='Test'][0].Public_Group_Id__c;
       List<GroupMember> groupMemberList = [Select Id From  GroupMember Where groupId =:groupId];
        test.startTest();
        system.enqueueJob(new UpdateFATMemberAfterGroupMemberQueue(groupIdWithUserIdMap,fatmList,fatMap));
        test.stopTest();
        system.assertEquals(groupMemberList[0].Id,[select Id,Group_Member_Id__c from Financial_Advisor_Team_Member__c where Id=:fatmList[0].Id][0].Group_Member_Id__c);
        
    }
}