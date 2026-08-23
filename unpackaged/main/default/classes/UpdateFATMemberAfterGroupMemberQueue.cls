public class UpdateFATMemberAfterGroupMemberQueue implements Queueable {
    
    private Map<String,Id> groupIdWithUserIdMap;
    private List<Financial_Advisor_Team_Member__c> newList;
    private Map<Id, Financial_Advisor_Team__c> fATeamMap;
    
    public UpdateFATMemberAfterGroupMemberQueue(Map<String,Id> groupIdWithUserIdMap, List<Financial_Advisor_Team_Member__c> newList, Map<Id, Financial_Advisor_Team__c> fATeamMap) {
        this.groupIdWithUserIdMap = groupIdWithUserIdMap;
        this.newList = newList;
        this.fATeamMap = fATeamMap;
    }
    public void execute(QueueableContext context) {
        try {
            List<GroupMember> groupMemberList = [Select id, groupId, UserOrGroupId From  GroupMember Where 
                                                 groupId IN: groupIdWithUserIdMap.keySet() 
                                                 AND UserOrGroupId IN :groupIdWithUserIdMap.values()];
            List<Financial_Advisor_Team_Member__c> fATMemberToUpdateList = new List<Financial_Advisor_Team_Member__c>();
            for(Financial_Advisor_Team_Member__c fAdvisorTeamMember : newList) {
                for(GroupMember  gMember : groupMemberList){
                    if(fATeamMap.get(fAdvisorTeamMember.Financial_Advisor_Team__c).Public_Group_Id__c == gMember.groupId
                       && fAdvisorTeamMember.User__c ==  gMember.UserOrGroupId){
                           Financial_Advisor_Team_Member__c fatM = new Financial_Advisor_Team_Member__c(Id = fAdvisorTeamMember.Id);
                           fatM.Group_Member_Id__c = gMember.Id;
                           fATMemberToUpdateList.add(fatM);
                       }
                }
            }
            update fATMemberToUpdateList;
        } catch(Exception ex){
            System.debug('UpdateFATMemberAfterGroupMemberQueue exception at line No.: '+ex.getLineNumber() + ' '+ex.getMessage());
        }
    }
}