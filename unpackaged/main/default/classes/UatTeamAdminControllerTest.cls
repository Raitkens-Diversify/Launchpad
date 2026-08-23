/**
 * Tests for UatTeamAdminController — the Admin Console UAT Teams section.
 * PermissionSetAssignment is a setup object visible across test isolation, so
 * pool assertions use contains/not-contains rather than exact counts.
 */
@IsTest
private class UatTeamAdminControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uatadm');
        UatTestDataFactory.createTesterUser('uattst1');
        UatTestDataFactory.createTesterUser('uattst2');
        UatTestDataFactory.createUser('uatbare', null);
    }

    private static User byLastName(String lastName) {
        return [SELECT Id, Name FROM User WHERE LastName = :lastName LIMIT 1];
    }

    private static String teamInput(Id id, String name, List<Id> memberUserIds) {
        UatTeamAdminController.TeamInput input = new UatTeamAdminController.TeamInput();
        input.id = id;
        input.name = name;
        input.memberUserIds = memberUserIds;
        return JSON.serialize(input);
    }

    @IsTest
    static void adminCreatesAndEditsTeam() {
        User tester1 = byLastName('UAT uattst1');
        User tester2 = byLastName('UAT uattst2');
        System.runAs(byLastName('UAT uatadm')) {
            Test.startTest();
            Id teamId = UatTeamAdminController.saveTeam(
                teamInput(null, '  Alpha Team ', new List<Id>{ tester1.Id, tester2.Id }));
            Test.stopTest();

            List<UatTeamAdminController.TeamDTO> teams = UatTeamAdminController.getTeams();
            Assert.areEqual(1, teams.size(), 'One team.');
            Assert.areEqual('Alpha Team', teams[0].name, 'Name trimmed.');
            Assert.areEqual(2, teams[0].members.size(), 'Both members present.');

            // Edit: rename and drop tester2 — reconcile must delete, not duplicate.
            UatTeamAdminController.saveTeam(
                teamInput(teamId, 'Alpha Squad', new List<Id>{ tester1.Id }));
            teams = UatTeamAdminController.getTeams();
            Assert.areEqual('Alpha Squad', teams[0].name);
            Assert.areEqual(1, teams[0].members.size(), 'Removed member deleted.');
            Assert.areEqual(tester1.Id, teams[0].members[0].userId);
            Assert.areEqual(1, [SELECT COUNT() FROM Team_Member__c], 'No junction leftovers.');
        }
    }

    @IsTest
    static void testerPoolListsPermsetHolders() {
        User tester1 = byLastName('UAT uattst1');
        User bare = byLastName('UAT uatbare');
        System.runAs(byLastName('UAT uatadm')) {
            Set<Id> pool = new Set<Id>();
            for (UatTeamAdminController.OptionDTO o : UatTeamAdminController.getTesterPool()) {
                pool.add(o.value);
            }
            Assert.isTrue(pool.contains(tester1.Id), 'UAT_Tester holder is in the pool.');
            Assert.isFalse(pool.contains(bare.Id), 'User without the permset is not.');
        }
    }

    @IsTest
    static void searchFindsNonPoolUsersOnly() {
        User tester1 = byLastName('UAT uattst1');
        User bare = byLastName('UAT uatbare');
        System.runAs(byLastName('UAT uatadm')) {
            Set<Id> found = new Set<Id>();
            for (UatTeamAdminController.OptionDTO o : UatTeamAdminController.searchUsers('UAT uat')) {
                found.add(o.value);
            }
            Assert.isTrue(found.contains(bare.Id), 'Non-pool user shows in search.');
            Assert.isFalse(found.contains(tester1.Id), 'Existing testers are excluded.');

            Assert.areEqual(0, UatTeamAdminController.searchUsers('x').size(),
                'Sub-2-character terms return nothing.');
        }
    }

    @IsTest
    static void addUserToPoolAssignsPermsetIdempotently() {
        User bare = byLastName('UAT uatbare');
        System.runAs(byLastName('UAT uatadm')) {
            Test.startTest();
            UatTeamAdminController.addUserToPool(bare.Id);
            UatTeamAdminController.addUserToPool(bare.Id); // second call = no-op
            Test.stopTest();
        }
        Assert.areEqual(1, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :bare.Id AND PermissionSet.Name = 'UAT_Tester'
        ], 'Exactly one assignment.');
    }

    @IsTest
    static void testerCannotSaveTeam() {
        System.runAs(byLastName('UAT uattst1')) {
            try {
                UatTeamAdminController.saveTeam(teamInput(null, 'Rogue Team', new List<Id>()));
                Assert.fail('Tester write should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), 'Access message: ' + e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Team__c], 'Nothing written.');
    }

    @IsTest
    static void blankNameRejected() {
        System.runAs(byLastName('UAT uatadm')) {
            try {
                UatTeamAdminController.saveTeam(teamInput(null, '  ', new List<Id>()));
                Assert.fail('Blank name should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('name'), 'Blank-name message: ' + e.getMessage());
            }
        }
    }

    // ---- Delete team (2026-08-05: guarded — null team widens visibility) ---------

    @IsTest
    static void deleteTeamBlockedByOpenCycle() {
        Team__c team = UatTestDataFactory.makeTeam('Guarded Team', new List<Id>{
            byLastName('UAT uattst1').Id
        });
        // Null status = legacy Active — it must count as OPEN for the guard.
        Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Open Sprint', team.Id, null, null);

        System.runAs(byLastName('UAT uatadm')) {
            UatTeamAdminController.TeamDeleteImpactDTO impact =
                UatTeamAdminController.getTeamDeleteImpact(team.Id);
            Assert.areEqual(new List<String>{ 'Open Sprint' }, impact.openCycleNames);

            try {
                UatTeamAdminController.deleteTeam(team.Id);
                Assert.fail('A team with open cycles must not delete — their work would open to everyone.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('every tester'), e.getMessage());
                Assert.isTrue(e.getMessage().contains('Open Sprint'), e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Team__c WHERE Id = :team.Id]);
        Assert.areEqual(team.Id, [
            SELECT Assigned_Team__c FROM Test_Cycle__c WHERE Id = :cycle.Id
        ].Assigned_Team__c, 'The cycle keeps its team.');
    }

    @IsTest
    static void deleteTeamClearsClosedCycleRefsAndCascadesMembers() {
        Team__c team = UatTestDataFactory.makeTeam('Retiring Team', new List<Id>{
            byLastName('UAT uattst1').Id, byLastName('UAT uattst2').Id
        });
        Test_Cycle__c closed = UatTestDataFactory.makeCycle('Done Sprint', team.Id, null, null);
        closed.Status__c = 'Closed';
        update closed;

        System.runAs(byLastName('UAT uatadm')) {
            UatTeamAdminController.TeamDeleteImpactDTO impact =
                UatTeamAdminController.getTeamDeleteImpact(team.Id);
            Assert.areEqual(0, impact.openCycleNames.size());
            Assert.areEqual(1, impact.closedCycleCount);
            Assert.areEqual(2, impact.memberCount);

            Test.startTest();
            UatTeamAdminController.deleteTeam(team.Id);
            Test.stopTest();
        }

        Assert.areEqual(0, [SELECT COUNT() FROM Team__c WHERE Id = :team.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM Team_Member__c WHERE Team__c = :team.Id],
            'Member links cascade.');
        Assert.isNull([
            SELECT Assigned_Team__c FROM Test_Cycle__c WHERE Id = :closed.Id
        ].Assigned_Team__c, 'Closed cycle keeps its history with the team reference cleared.');
    }

    @IsTest
    static void deleteTeamGateNegative() {
        Team__c team = UatTestDataFactory.makeTeam('Locked Team', new List<Id>());
        System.runAs(byLastName('UAT uattst1')) {
            try {
                UatTeamAdminController.deleteTeam(team.Id);
                Assert.fail('Testers must not delete teams.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Team__c WHERE Id = :team.Id]);
    }
}