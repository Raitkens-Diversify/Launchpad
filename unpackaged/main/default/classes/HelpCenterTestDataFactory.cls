/**
 * HelpCenterTestDataFactory
 *
 * Test users for the Help Center / Resource Center Apex tests. Split from the
 * UAT test factory on 2026-09-04 so the production package carries no UAT
 * test dependency; the semantics are unchanged.
 *
 * Why a factory at all: an org flow auto-assigns permission sets to every new
 * internal user (NexSHelpCenter et al.), so a freshly inserted user is never
 * "bare". createUser strips those assignments after insert and grants only
 * what the test asks for, so "no access" really means no access.
 *
 * Callers wrap user/PSA DML in System.runAs(currentUser()) to avoid MIXED_DML
 * with the data setup in the same test.
 *
 * Why grantAdminToRunningUser exists: most Help Center tests run as the
 * deploying user. In a sandbox that user carries the Help Center permission
 * sets; in production the deployer holds none of them, and fields deployed
 * through the Metadata API get no field-level security on the admin profile.
 * Every gate in the admin controllers (object describes, FLS checks,
 * SECURITY_ENFORCED queries, Modify Metadata) then answers false and the test
 * classes report 0% coverage. Tests therefore assign the package's own
 * permission set to whoever is running them, from @TestSetup, so the access
 * they exercise is the access the package ships.
 */
@IsTest
public class HelpCenterTestDataFactory {

    /**
     * Internal user on the Standard User profile with automation-assigned
     * permission sets stripped. Pass the permission set name(s) the test
     * needs, or null/empty for a bare user.
     */
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
            Email = uniq + '@hc.test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'HC ' + aliasPrefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniq + '@hc.test.invalid'
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

    /** The running user — for System.runAs wrappers that avoid mixed DML. */
    public static User currentUser() {
        return new User(Id = UserInfo.getUserId());
    }

    /** The permission set the production package ships for console admins. */
    public static final String ADMIN_PERMISSION_SET = 'Resource_Center_Admin';

    /**
     * Assigns Resource_Center_Admin to the running user when it isn't already
     * assigned. Call it first thing in @TestSetup: each test method then starts
     * in a fresh context with the assignment in place, so the running user has
     * the package's object permissions, field-level security and Modify
     * Metadata regardless of what the deploying user holds in the target org.
     * The setup-object DML runs inside runAs(currentUser()) so it never mixes
     * with the records the same @TestSetup inserts afterwards.
     */
    public static void grantAdminToRunningUser() {
        System.runAs(currentUser()) {
            Id me = UserInfo.getUserId();
            PermissionSet ps = [
                SELECT Id FROM PermissionSet WHERE Name = :ADMIN_PERMISSION_SET LIMIT 1
            ];
            Integer assigned = [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :me AND PermissionSetId = :ps.Id
            ];
            if (assigned == 0) {
                insert new PermissionSetAssignment(AssigneeId = me, PermissionSetId = ps.Id);
            }
        }
    }
}