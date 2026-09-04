/**
 * UatTestDataFactory
 *
 * Shared test-data builders for the Helios UAT test-management suite
 * (System__c → Module__c taxonomy, Test_Case__c/Test_Step__c definitions,
 * Test_Book__c, Team__c, Test_Cycle__c, Test_Execution__c).
 *
 * Platform facts baked in here so individual tests don't rediscover them:
 *  - Org automation (Assign_NexS_App_To_New_Users flow, plus tour/tutorial
 *    siblings) assigns permission sets to EVERY new active internal user.
 *    User builders strip those automation-granted assignments so permission
 *    tests start from a known baseline, then add only what was asked for.
 *    Never manually assign NexSHelpCenter to a new user — the flow already
 *    did, and a second insert is a duplicate error.
 *  - Mixed-DML: create users in a separate context from UAT records
 *    (System.runAs(currentUser()) around setup DML, or build users first).
 *  - Sequence__c is set explicitly by makeCase so tests don't depend on the
 *    Test_Case_Before_Save_Set_Sequence flow being deployed/active.
 */
@IsTest
public class UatTestDataFactory {

    @TestVisible
    public static User createUser(String aliasPrefix, List<String> permissionSetNames) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String uniq = aliasPrefix + Math.abs(Crypto.getRandomLong());
        User u = new User(
            Alias = aliasPrefix.left(8),
            Email = uniq + '@uat.test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'UAT ' + aliasPrefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniq + '@uat.test.invalid'
        );
        insert u;
        // Strip automation-assigned sets (Assign_NexS_App_To_New_Users et al.)
        // so this user has exactly the access the test grants below.
        delete [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :u.Id
            AND (PermissionSetGroupId != null OR PermissionSet.IsOwnedByProfile = false)
        ];
        if (permissionSetNames != null && !permissionSetNames.isEmpty()) {
            List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
            for (PermissionSet ps : [
                SELECT Id FROM PermissionSet WHERE Name IN :permissionSetNames
            ]) {
                psas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
            }
            insert psas;
        }
        return u;
    }

    @TestVisible
    public static User createTesterUser(String aliasPrefix) {
        return createUser(aliasPrefix, new List<String>{ 'UAT_Tester' });
    }

    @TestVisible
    public static User createAdminUser(String aliasPrefix) {
        return createUser(aliasPrefix, new List<String>{ 'UAT_Admin' });
    }

    /** The running user — for System.runAs wrappers that avoid mixed DML. */
    @TestVisible
    public static User currentUser() {
        return new User(Id = UserInfo.getUserId());
    }

}