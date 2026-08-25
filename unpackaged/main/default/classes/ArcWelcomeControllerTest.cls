/**
 * Tests for ArcWelcomeController. Uses System.runAs against a freshly
 * inserted user so the flag starts false and we exercise the real update path
 * on the running user's own record.
 */
@IsTest
private class ArcWelcomeControllerTest {

    static User makeUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = 'arc' + String.valueOf(System.currentTimeMillis());
        return new User(
            FirstName = 'Arc',
            LastName = 'Tester',
            Alias = 'nxstst',
            Email = unique + '@example.com',
            Username = unique + '@example.com.arc',
            CommunityNickname = unique,
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Denver',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    @IsTest
    static void welcomeStateFlipsAfterMarkSeen() {
        User u = makeUser();
        insert u;

        // Grant FLS on Has_Seen_Welcome__c via the shipped permission set, the
        // same way a real Arc user is provisioned.
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'ArcHelpCenter' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);

        Test.startTest();
        System.runAs(u) {
            Assert.isFalse(ArcWelcomeController.getWelcomeState(),
                'A new user has not seen the welcome video.');

            ArcWelcomeController.markWelcomeSeen();

            Assert.isTrue(ArcWelcomeController.getWelcomeState(),
                'After marking seen the flag should be true.');
        }
        Test.stopTest();

        User refreshed = [SELECT Has_Seen_Welcome__c FROM User WHERE Id = :u.Id];
        Assert.isTrue(refreshed.Has_Seen_Welcome__c, 'Flag persisted on the user record.');
    }

    @IsTest
    static void noFieldAccessThrows() {
        // A user WITHOUT the Arc permission set has no FLS on the flag, so both
        // methods should surface a friendly AuraHandledException rather than data.
        User u = makeUser();
        insert u;

        Test.startTest();
        System.runAs(u) {
            try {
                ArcWelcomeController.getWelcomeState();
                Assert.fail('Expected an exception without field access.');
            } catch (AuraHandledException e) {
                // expected
            }
            try {
                ArcWelcomeController.markWelcomeSeen();
                Assert.fail('Expected an exception without field access.');
            } catch (AuraHandledException e) {
                // expected
            }
        }
        Test.stopTest();
    }
}