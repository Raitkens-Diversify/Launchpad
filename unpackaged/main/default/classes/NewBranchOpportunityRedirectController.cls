public with sharing class NewBranchOpportunityRedirectController {
    public PageReference redirect() {
        Id recordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Branch')
            .getRecordTypeId();

        String branchId = ApexPages.currentPage().getParameters().get('branchId');

        String backgroundContext = String.isNotBlank(branchId)
            ? '%2Flightning%2Fr%2FAdvisor_Group__c%2F' + branchId + '%2Fview'
            : '%2Flightning%2Fo%2FOpportunity%2Flist';

        String url = '/lightning/o/Opportunity/new?nooverride=1&recordTypeId=' + recordTypeId
            + '&backgroundContext=' + backgroundContext;

        if (String.isNotBlank(branchId)) {
            url += '&defaultFieldValues=Advisor_Group__c=' + branchId
                + '&navigationLocation=RELATED_LIST';
        }

        PageReference pageRef = new PageReference(url);
        pageRef.setRedirect(true);
        return pageRef;
    }
}