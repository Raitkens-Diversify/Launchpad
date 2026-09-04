/**
 * AdminAccessServiceTest
 *
 * The Knowledge User license flag can't be reliably assigned to test users
 * (feature-license dependent), so the license branch is exercised through the
 * @TestVisible knowledgeUserOverride seam; the perm-driven sections are
 * exercised with real users (minimal profile vs. Resource_Center_Admin).
 */
@IsTest
private class AdminAccessServiceTest {

    private static User makeUser(String profileName, String aliasSuffix) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        return new User(
            Alias = 'aas' + aliasSuffix,
            Email = 'admin.access.' + aliasSuffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AccessTest' + aliasSuffix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Denver',
            UserName = 'admin.access.' + aliasSuffix + '.'
                + System.currentTimeMillis() + '@example.com.cosmosdev'
        );
    }

    /**
     * Org flows auto-assign permission sets to every new internal user; strip
     * them so a "minimal" user really is minimal.
     */
    private static void stripAutoAssignedPermSets(Id userId) {
        delete [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND (PermissionSetGroupId != null OR PermissionSet.IsOwnedByProfile = false)
        ];
    }

    @IsTest
    static void minimalUserSeesNoSections() {
        User u = makeUser('Minimum Access - Salesforce', 'min');
        insert u;
        stripAutoAssignedPermSets(u.Id);

        System.runAs(u) {
            AdminAccessService.knowledgeUserOverride = false;
            Test.startTest();
            AdminAccessService.AccessDTO dto = AdminAccessService.getAccess();
            Test.stopTest();

            System.assertEquals(false, dto.articles, 'No article authoring without perms');
            System.assertEquals(false, dto.articlePerms, 'No Knowledge__kav create/edit');
            System.assertEquals(false, dto.resources, 'No Resource__c create/edit');
            System.assertEquals(false, dto.categories, 'No Resource_Category__c create/edit');
            System.assertEquals(false, dto.guides, 'No Help_Guide_Draft__c create');
            System.assertEquals(false, dto.submissions, 'No Article_Submission__c create/edit');
            System.assertEquals(false, dto.synonyms, 'No ModifyMetadata');
            // analytics is read-only describe truth: some orgs grant engagement-object
            // read broadly on the minimal profile (cosmosdev does), so no assertion —
            // the write-capable sections above are what this design controls.
        }
    }

    @IsTest
    static void resourceCenterAdminSeesAdminSections() {
        User u = makeUser('Minimum Access - Salesforce', 'rca');
        insert u;
        stripAutoAssignedPermSets(u.Id);
        PermissionSet ps = [
            SELECT Id FROM PermissionSet WHERE Name = 'Resource_Center_Admin' LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        System.runAs(u) {
            AdminAccessService.knowledgeUserOverride = false;
            Test.startTest();
            AdminAccessService.AccessDTO dto = AdminAccessService.getAccess();
            Test.stopTest();

            System.assertEquals(true, dto.resources, 'Perm set grants Resource__c CRUD');
            System.assertEquals(true, dto.categories, 'Perm set grants Resource_Category__c CRUD');
            System.assertEquals(true, dto.guides, 'Perm set grants Help_Guide_Draft__c create');
            System.assertEquals(true, dto.submissions, 'Perm set grants Article_Submission__c CRUD');
            System.assertEquals(true, dto.synonyms, 'Perm set grants ModifyMetadata');
            System.assertEquals(false, dto.knowledgeUser, 'No Knowledge User license flag');
            System.assertEquals(false, dto.articles,
                'Article authoring stays off without the Knowledge User license');
            System.assertEquals(true, dto.anySection, 'At least one section visible');
        }
    }

    @IsTest
    static void articlesGateCombinesPermsAndLicense() {
        // License present: articles mirrors the object perms.
        AdminAccessService.knowledgeUserOverride = true;
        AdminAccessService.AccessDTO withLicense = AdminAccessService.getAccess();
        System.assertEquals(true, withLicense.knowledgeUser, 'Override should apply');
        System.assertEquals(withLicense.articlePerms, withLicense.articles,
            'With the license, articles == object perms');

        // License absent: articles is off regardless of object perms.
        AdminAccessService.knowledgeUserOverride = false;
        AdminAccessService.AccessDTO withoutLicense = AdminAccessService.getAccess();
        System.assertEquals(false, withoutLicense.articles,
            'Without the license, articles must be false');
    }

    @IsTest
    static void knowledgeUserFlagReadFromUserRecord() {
        // No override: the real User query path runs (value depends on the
        // running user; the assertion is that it matches the record).
        User me = [
            SELECT UserPermissionsKnowledgeUser FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        AdminAccessService.AccessDTO dto = AdminAccessService.getAccess();
        System.assertEquals(me.UserPermissionsKnowledgeUser, dto.knowledgeUser,
            'knowledgeUser should reflect User.UserPermissionsKnowledgeUser');
    }

    @IsTest
    static void canAuthorArticlesFollowsTheLicenseSeam() {
        AdminAccessService.knowledgeUserOverride = false;
        System.assertEquals(false, AdminAccessService.canAuthorArticles(),
            'No license flag means no authoring, whatever the object perms');
    }
}