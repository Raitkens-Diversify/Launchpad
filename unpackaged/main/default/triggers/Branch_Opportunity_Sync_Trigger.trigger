/**
 * Mirrors synced field changes from an open Branch Opportunity back to the
 * Branch (Advisor Group) that designates it as primary. Opportunities that are
 * not a Branch's primary never write back. See BranchOpportunitySyncService.
 */
trigger Branch_Opportunity_Sync_Trigger on Opportunity (after update) {
    BranchOpportunitySyncService.syncFromOpportunities(Trigger.new, Trigger.oldMap);
}