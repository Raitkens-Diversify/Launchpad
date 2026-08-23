public class CreateGroupMemberQueue implements Queueable {
    
    private Map<String,Id> groupIdWithUserIdMap;
    private List<Financial_Advisor_Team_Member__c> newList;
    private Map<Id, Financial_Advisor_Team__c> fATeamMap;
    
    public CreateGroupMemberQueue(Map<String,Id> groupIdWithUserIdMap, List<Financial_Advisor_Team_Member__c> newList, Map<Id, Financial_Advisor_Team__c> fATeamMap) {
        this.groupIdWithUserIdMap = groupIdWithUserIdMap;
        this.newList = newList;
        this.fATeamMap = fATeamMap;
        
    }
    public void execute(QueueableContext context) {
        try {
            List<GroupMember> groupMemberToBeInsertList = new List<GroupMember>();
            system.debug('groupIdWithUserIdMap  :'+groupIdWithUserIdMap);
            for(String groupId : groupIdWithUserIdMap.keyset()){
                GroupMember groupMemberRecord = new GroupMember();
                groupMemberRecord.groupId = Id.valueOf(groupId);
                groupMemberRecord.UserOrGroupId = groupIdWithUserIdMap.get(groupId);
                groupMemberToBeInsertList.add(groupMemberRecord);
            }
            system.debug('groupMemberToBeInsertList  :'+groupMemberToBeInsertList);
            insert groupMemberToBeInsertList;
            if(!Test.isRunningTest()){
                System.enqueueJob(new UpdateFATMemberAfterGroupMemberQueue(groupIdWithUserIdMap, newList, fATeamMap));
            }
        } catch(Exception ex){
            System.debug('CreateGroupMemberQueue exception at line No.: '+ex.getLineNumber() + ' '+ex.getMessage());
        }
    }
}