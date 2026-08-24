@IsTest
private class NewBranchOppRedirectCtrlTest {
    /** The record type the redirect is expected to preselect. */
    private static Id branchRecordTypeId() {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Branch')
            .getRecordTypeId();
    }

    @IsTest
    static void redirect_withoutBranchId_omitsDefaultFieldValues() {
        Test.setCurrentPage(Page.NewBranchOpportunityRedirect);

        Test.startTest();
        PageReference result = new NewBranchOpportunityRedirectController().redirect();
        Test.stopTest();

        Assert.isNotNull(result, 'Expected a redirect PageReference');
        Assert.isTrue(
            result.getUrl().startsWith('/lightning/o/Opportunity/new'),
            'Expected redirect to the Opportunity create page'
        );

        Map<String, String> params = result.getParameters();
        Assert.areEqual('1', params.get('nooverride'), 'Expected the create override to be bypassed');
        Assert.areEqual(
            String.valueOf(branchRecordTypeId()),
            params.get('recordTypeId'),
            'Expected the Branch record type to be preselected'
        );
        Assert.isNull(
            params.get('defaultFieldValues'),
            'Expected no default field values when branchId is absent'
        );
    }

    @IsTest
    static void redirect_withBranchId_includesAdvisorGroupDefault() {
        Test.setCurrentPage(Page.NewBranchOpportunityRedirect);
        ApexPages.currentPage().getParameters().put('branchId', 'a0X000000000001AAA');

        Test.startTest();
        PageReference result = new NewBranchOpportunityRedirectController().redirect();
        Test.stopTest();

        Map<String, String> params = result.getParameters();
        Assert.areEqual(
            String.valueOf(branchRecordTypeId()),
            params.get('recordTypeId'),
            'Expected the Branch record type to be preselected'
        );
        Assert.areEqual(
            'Advisor_Group__c=a0X000000000001AAA',
            params.get('defaultFieldValues'),
            'Expected the Branch lookup to be defaulted on the new Opportunity'
        );
        Assert.areEqual(
            'RELATED_LIST',
            params.get('navigationLocation'),
            'Expected related list navigation when branchId is provided'
        );
    }
}