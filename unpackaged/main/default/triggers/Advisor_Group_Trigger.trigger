/**
 * Mirrors synced field changes from a Branch (Advisor Group) to its open
 * Primary Branch Opportunity. See BranchOpportunitySyncService.
 */
trigger Advisor_Group_Trigger on Advisor_Group__c (after update) {
    BranchOpportunitySyncService.syncFromAdvisorGroups(Trigger.new, Trigger.oldMap);
}