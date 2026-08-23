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

    /** Wrapper for the taxonomy triple makeTaxonomy builds in one call. */
    public class Taxonomy {
        public System__c sys;
        public Module_Group__c grp;
        public Module__c mod;
    }

    // ---- Users ------------------------------------------------------------------

    /**
     * Internal user on the Standard User profile with automation-assigned
     * permission sets stripped. Pass the UAT permission set name(s) the test
     * actually needs ('UAT_Tester', 'UAT_Admin'), or none for a bare user.
     */
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

    // ---- Taxonomy ---------------------------------------------------------------

    /** One System → Module Group → Module chain. Prefix keeps names unique. */
    @TestVisible
    public static Taxonomy makeTaxonomy(String prefix) {
        Taxonomy t = new Taxonomy();
        t.sys = new System__c(
            Name = prefix + ' System',
            System_Code__c = prefix.toLowerCase().replaceAll('[^a-z0-9]', '')
        );
        insert t.sys;
        t.grp = new Module_Group__c(Name = prefix + ' Group', System__c = t.sys.Id);
        insert t.grp;
        t.mod = new Module__c(Name = prefix + ' Module', Module_Group__c = t.grp.Id);
        insert t.mod;
        return t;
    }

    // ---- Definitions ------------------------------------------------------------

    /**
     * A Complete-status case with the given number of scripted steps under one
     * condition group. Sequence set explicitly (see class header).
     */
    @TestVisible
    public static Test_Case__c makeCase(Id moduleId, Integer stepCount) {
        return makeCase(moduleId, stepCount, 1001);
    }

    @TestVisible
    public static Test_Case__c makeCase(Id moduleId, Integer stepCount, Integer sequence) {
        Test_Case__c tc = new Test_Case__c(
            Module__c = moduleId,
            Version__c = 'v1.0',
            Sequence__c = sequence,
            Creation_Status__c = 'Complete',
            Testing_Surface__c = 'Lightning App (Internal)'
        );
        insert tc;
        List<Test_Step__c> steps = new List<Test_Step__c>();
        for (Integer i = 1; i <= stepCount; i++) {
            steps.add(new Test_Step__c(
                Test_Case__c = tc.Id,
                Step_Number__c = i,
                Test_Condition__c = 'Default Condition',
                Step_Description__c = 'Do thing ' + i,
                Expected_Result__c = 'Thing ' + i + ' happens'
            ));
        }
        insert steps;
        return tc;
    }

    /** Adds a free-form exploratory step at the end of a case. */
    @TestVisible
    public static Test_Step__c makeExploreStep(Id caseId, Integer stepNumber) {
        Test_Step__c s = new Test_Step__c(
            Test_Case__c = caseId,
            Step_Number__c = stepNumber,
            Test_Condition__c = 'Exploratory',
            Is_Explore__c = true,
            Explore_Prompt__c = 'Try to break it'
        );
        insert s;
        return s;
    }

    /** A book containing the given cases, in list order. */
    @TestVisible
    public static Test_Book__c makeBook(String name, List<Id> caseIds) {
        Test_Book__c book = new Test_Book__c(Name = name);
        insert book;
        List<Test_Book_Item__c> items = new List<Test_Book_Item__c>();
        for (Integer i = 0; i < caseIds.size(); i++) {
            items.add(new Test_Book_Item__c(
                Test_Book__c = book.Id,
                Test_Case__c = caseIds[i],
                Sort_Order__c = i + 1
            ));
        }
        insert items;
        return book;
    }

    // ---- Teams ------------------------------------------------------------------

    @TestVisible
    public static Team__c makeTeam(String name, List<Id> userIds) {
        Team__c team = new Team__c(Name = name);
        insert team;
        List<Team_Member__c> members = new List<Team_Member__c>();
        for (Id uid : userIds) {
            members.add(new Team_Member__c(Team__c = team.Id, User__c = uid));
        }
        insert members;
        return team;
    }

    // ---- Cycles -----------------------------------------------------------------

    /**
     * A cycle with books attached and/or cases added directly. The junction
     * inserts fire the eager-slot triggers, so unclaimed Test_Execution__c
     * records exist for the full effective scope when this returns.
     */
    @TestVisible
    public static Test_Cycle__c makeCycle(String name, Id teamId, List<Id> bookIds, List<Id> directCaseIds) {
        return makeCycle(name, teamId, bookIds, directCaseIds, null);
    }

    /** Variant with seats per case — Max_Testers__c defaults to 1 otherwise,
     *  which hides every multi-seat behavior (claimSeat re-materialization,
     *  pool claimed-by-me filtering) from tests. */
    @TestVisible
    public static Test_Cycle__c makeCycle(String name, Id teamId, List<Id> bookIds,
            List<Id> directCaseIds, Integer maxTesters) {
        Test_Cycle__c cycle = new Test_Cycle__c(
            Name = name,
            Assigned_Team__c = teamId,
            Target_Date__c = Date.today().addDays(14),
            Max_Testers__c = maxTesters
        );
        insert cycle;
        List<SObject> junctions = new List<SObject>();
        if (bookIds != null) {
            for (Id bookId : bookIds) {
                junctions.add(new Test_Cycle_Book__c(Test_Cycle__c = cycle.Id, Test_Book__c = bookId));
            }
        }
        if (directCaseIds != null) {
            for (Id caseId : directCaseIds) {
                junctions.add(new Test_Cycle_Case__c(Test_Cycle__c = cycle.Id, Test_Case__c = caseId));
            }
        }
        if (!junctions.isEmpty()) {
            insert junctions;
        }
        return cycle;
    }

    // ---- Files ------------------------------------------------------------------

    /** Attaches a small file to any record; returns the ContentDocumentId. */
    @TestVisible
    public static Id attachFile(Id recordId, String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.png',
            VersionData = Blob.valueOf('uat-test-file-bytes')
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = recordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return cv.ContentDocumentId;
    }
}