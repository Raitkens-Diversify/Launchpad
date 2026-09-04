/**
 * HelpCenterTestDataFactoryTest
 *
 * Proves the two things the Help Center test suite leans on: the running user
 * ends up with the package's own access after grantAdminToRunningUser (object
 * perms, FLS on Metadata API-deployed fields, Modify Metadata), and createUser
 * hands back exactly the access a test asks for.
 */
@IsTest
private class HelpCenterTestDataFactoryTest {

    @TestSetup
    static void setup() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
    }

    @IsTest
    static void runningUserCarriesThePackageAccess() {
        Assert.isTrue(Schema.sObjectType.Resource__c.isCreateable(),
            'Resource__c create comes from the permission set');
        Assert.isTrue(Schema.sObjectType.Help_Guide_Draft__c.isCreateable(),
            'Help_Guide_Draft__c create comes from the permission set');
        Assert.isTrue(Schema.sObjectType.Article_Submission__c.isCreateable(),
            'Article_Submission__c create comes from the permission set');
        Assert.isTrue(Schema.sObjectType.Knowledge__kav.fields.Embed_URL__c.isAccessible(),
            'FLS on a Metadata API-deployed Knowledge field comes from the permission set');
        Assert.isTrue(Schema.sObjectType.Knowledge__kav.fields.Content__c.isUpdateable(),
            'FLS edit on the article body comes from the permission set');
        Assert.isTrue(AdminAccessService.hasModifyMetadata(),
            'Modify Metadata comes from the permission set');
    }

    @IsTest
    static void grantIsIdempotent() {
        HelpCenterTestDataFactory.grantAdminToRunningUser();
        Assert.areEqual(1, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :HelpCenterTestDataFactory.ADMIN_PERMISSION_SET
        ], 'A second grant never duplicates the assignment');
    }

    @IsTest
    static void createUserStripsAutomationAndGrantsWhatWasAsked() {
        User bare;
        User admin;
        System.runAs(HelpCenterTestDataFactory.currentUser()) {
            bare = HelpCenterTestDataFactory.createUser('hcbare', null);
            admin = HelpCenterTestDataFactory.createUser('hcadm',
                new List<String>{ HelpCenterTestDataFactory.ADMIN_PERMISSION_SET });
        }
        Assert.areEqual(0, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :bare.Id AND PermissionSet.IsOwnedByProfile = false
        ], 'A bare user carries no permission set, whatever org automation assigns');
        Assert.areEqual(1, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :admin.Id
            AND PermissionSet.Name = :HelpCenterTestDataFactory.ADMIN_PERMISSION_SET
        ], 'Requested permission sets are granted');
        Assert.areEqual(UserInfo.getUserId(), HelpCenterTestDataFactory.currentUser().Id,
            'currentUser is the running user');
    }
}