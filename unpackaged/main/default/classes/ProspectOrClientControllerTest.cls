@IsTest
private class ProspectOrClientControllerTest {
    private static final String DRP_PERMISSION_SET =
        'Account_Diversify_Related_Person_Record_Create';

    private static Id getDrpRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(ProspectOrClientController.DRP_RECORD_TYPE_DEV_NAME);
        return info == null ? null : info.getRecordTypeId();
    }

    private static User buildTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            FirstName = 'DRP',
            LastName = 'Tester',
            Email = 'drp.tester@example.com.invalid',
            Username = 'drp.tester.' + DateTime.now().getTime() + '@example.com.invalid',
            Alias = 'drptst',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Chicago',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    @IsTest
    static void returnsFalseForNullRecordType() {
        Test.startTest();
        Boolean result = ProspectOrClientController.shouldRouteToDrpStandard(null);
        Test.stopTest();
        System.assertEquals(false, result, 'Null record type should not route to native create.');
    }

    @IsTest
    static void returnsFalseWithoutPermission() {
        User u = buildTestUser();
        insert u;

        Boolean result;
        System.runAs(u) {
            Test.startTest();
            // No DRP permission set assigned, so even the DRP record type routes to the Wizard.
            result = ProspectOrClientController.shouldRouteToDrpStandard(getDrpRecordTypeId());
            Test.stopTest();
        }
        System.assertEquals(false, result, 'Without the custom permission the Wizard should be used.');
    }

    @IsTest
    static void returnsTrueForDrpWithPermission() {
        Id drpRecordTypeId = getDrpRecordTypeId();
        // Guard against orgs/test contexts where the record type is unavailable.
        if (drpRecordTypeId == null) {
            return;
        }

        User u = buildTestUser();
        insert u;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :DRP_PERMISSION_SET LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        Boolean result;
        System.runAs(u) {
            Test.startTest();
            result = ProspectOrClientController.shouldRouteToDrpStandard(drpRecordTypeId);
            Test.stopTest();
        }
        System.assertEquals(true, result, 'DRP record type with permission should route to native create.');
    }

    @IsTest
    static void returnsFalseForOtherRecordTypeWithPermission() {
        // Find an Account record type that is NOT the DRP one.
        Id drpRecordTypeId = getDrpRecordTypeId();
        Id otherRecordTypeId = null;
        for (Schema.RecordTypeInfo info :
                Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isAvailable() && !info.isMaster()
                    && info.getRecordTypeId() != drpRecordTypeId) {
                otherRecordTypeId = info.getRecordTypeId();
                break;
            }
        }
        if (otherRecordTypeId == null) {
            return;
        }

        User u = buildTestUser();
        insert u;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :DRP_PERMISSION_SET LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        Boolean result;
        System.runAs(u) {
            Test.startTest();
            result = ProspectOrClientController.shouldRouteToDrpStandard(otherRecordTypeId);
            Test.stopTest();
        }
        System.assertEquals(false, result, 'A non-DRP record type should always use the Wizard.');
    }
}