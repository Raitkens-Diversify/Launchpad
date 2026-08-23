public with sharing class ProspectOrClientController {
    @TestVisible
    private static final String DRP_RECORD_TYPE_DEV_NAME = 'Diversify_Related_Person';

    @TestVisible
    private static final String DRP_CUSTOM_PERMISSION = 'Create_DRP_Standard';

    /**
     * Determines whether the Account "New" override should bypass the Wizard
     * flow and route the user to the native create screen (assigned flexipage).
     *
     * This is true only when the running user holds the Create_DRP_Standard
     * custom permission AND the selected record type is the Diversify Related
     * Person Account record type. In every other case the override keeps its
     * existing behavior and launches the Wizard flow.
     *
     * @param recordTypeId The record type selected on the standard New chooser.
     * @return true to route to the native create screen, false to use the Wizard.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean shouldRouteToDrpStandard(Id recordTypeId) {
        if (recordTypeId == null) {
            return false;
        }
        if (!FeatureManagement.checkPermission(DRP_CUSTOM_PERMISSION)) {
            return false;
        }
        Schema.RecordTypeInfo drpInfo = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(DRP_RECORD_TYPE_DEV_NAME);
        return drpInfo != null && recordTypeId == drpInfo.getRecordTypeId();
    }
}