/**
 * Aura-enabled facade exposing the current user's Financial Advisor Team
 * membership (via FinancialAdvisorTeamAccessService) to LWCs that need to
 * do their own client-side "My Team" filtering — e.g. envelopeTable, which
 * fetches a broader record set up front and filters in the browser rather
 * than re-querying Apex per scope toggle.
 */
public with sharing class FinancialAdvisorTeamAccessController {
  @AuraEnabled(cacheable=true)
  public static List<Id> getMyTeamIds() {
    FinancialAdvisorTeamAccessService.TeamAccessContext teamAccess = new FinancialAdvisorTeamAccessService()
      .getCurrentUserTeamAccess();
    return new List<Id>(teamAccess.teamIds);
  }
}