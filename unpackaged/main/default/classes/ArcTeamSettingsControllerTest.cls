/**
 * ArcTeamSettingsControllerTest
 *
 * Fixture: two Financial Advisor Teams, so the multi-team case is real rather
 * than assumed. The running user is an active member of both and holds a
 * different role on each — that is the distinction the controller exists to
 * keep straight, and a single-team fixture could not catch it being collapsed.
 *
 * Permissions are spread deliberately: Trading is held by two members, CSA by
 * one, and several by nobody, so the "who is tied to each permission" mapping
 * is exercised for the many, one and none cases in a single pass.
 *
 * Org prerequisites: Financial_Advisor_Team_Member__c is a master-detail child
 * of Financial_Advisor_Team__c, and Rep_Code__c likewise, so the parents are
 * inserted first. No @seeAllData — every record here is built by the setup.
 */
@IsTest
private class ArcTeamSettingsControllerTest {
  private static final String TEAM_A = 'Alpha Advisors';
  private static final String TEAM_B = 'Beta Advisors';

  @TestSetup
  static void setup() {
    List<Financial_Advisor_Team__c> teams = new List<Financial_Advisor_Team__c>{
      newTeam(TEAM_A),
      newTeam(TEAM_B)
    };
    insert teams;

    Id teamAId = teams[0].Id;
    Id teamBId = teams[1].Id;
    Id me = UserInfo.getUserId();

    insert new List<Financial_Advisor_Team_Member__c>{
      // The running user, with a different role on each team.
      newMember(teamAId, me, 'Financial Advisor', true),
      newMember(teamBId, me, 'Branch Member', false),
      // Two more on team A: one shares Trading with the running user,
      // one holds nothing at all.
      newMember(teamAId, me, 'Operations', false),
      // Inactive members must not appear anywhere.
      inactiveMember(teamAId, me, 'Former Advisor')
    };

    // Trading on two of team A's members, CSA on one. Everything else is
    // left false so the empty-holder rows are covered too.
    List<Financial_Advisor_Team_Member__c> teamAMembers = [
      SELECT Id, Role__c
      FROM Financial_Advisor_Team_Member__c
      WHERE Financial_Advisor_Team__c = :teamAId AND Active__c = TRUE
      ORDER BY Role__c
    ];
    for (Financial_Advisor_Team_Member__c m : teamAMembers) {
      if (m.Role__c == 'Financial Advisor') {
        m.Trading__c = true;
        m.CSA__c = true;
      } else if (m.Role__c == 'Operations') {
        m.Trading__c = true;
      }
    }
    update teamAMembers;

    insert new List<Rep_Code__c>{
      new Rep_Code__c(
        Financial_Advisor_Team__c = teamAId,
        Status__c = 'Active'
      ),
      new Rep_Code__c(Financial_Advisor_Team__c = teamAId, Status__c = 'Active')
    };
  }

  @IsTest
  static void getMyTeamsReturnsEveryTeamTheUserIsOn() {
    Test.startTest();
    List<ArcTeamSettingsController.TeamDetail> teams = ArcTeamSettingsController.getMyTeams();
    Test.stopTest();

    Assert.areEqual(
      2,
      teams.size(),
      'Both teams the user is active on should come back'
    );

    Set<String> names = new Set<String>();
    for (ArcTeamSettingsController.TeamDetail t : teams) {
      names.add(t.name);
    }
    Assert.isTrue(names.contains(TEAM_A), 'Team A should be present');
    Assert.isTrue(names.contains(TEAM_B), 'Team B should be present');
  }

  @IsTest
  static void roleIsReportedPerTeamNotPerUser() {
    Test.startTest();
    List<ArcTeamSettingsController.MyAssignment> mine = ArcTeamSettingsController.getMyAssignments();
    Test.stopTest();

    Map<String, String> roleByTeam = new Map<String, String>();
    for (ArcTeamSettingsController.MyAssignment a : mine) {
      roleByTeam.put(a.teamName, a.role);
    }

    // The same user, two teams, two different roles. If the controller ever
    // starts treating a role as a property of the person rather than of the
    // membership, this is the assertion that fails.
    Assert.areEqual(
      'Financial Advisor',
      roleByTeam.get(TEAM_A),
      'Role on team A should be the role recorded on that membership'
    );
    Assert.areEqual(
      'Branch Member',
      roleByTeam.get(TEAM_B),
      'Role on team B should differ from the role on team A'
    );
  }

  @IsTest
  static void permissionRowsNameEveryHolder() {
    ArcTeamSettingsController.TeamDetail teamA = teamNamed(TEAM_A);

    Map<String, ArcTeamSettingsController.PermissionRow> byField = new Map<String, ArcTeamSettingsController.PermissionRow>();
    for (ArcTeamSettingsController.PermissionRow r : teamA.permissions) {
      byField.put(r.field, r);
    }

    Assert.areEqual(
      8,
      teamA.permissions.size(),
      'Every permission should get a row, held or not'
    );
    Assert.areEqual(
      2,
      byField.get('Trading__c').holders.size(),
      'Trading is held by two members'
    );
    Assert.areEqual(
      1,
      byField.get('CSA__c').holders.size(),
      'CSA is held by one member'
    );
    Assert.areEqual(
      0,
      byField.get('Project_Manager__c').holders.size(),
      'Nobody holds Project Manager, and the row should still be returned'
    );
    Assert.areEqual(
      'Trading',
      byField.get('Trading__c').label,
      'Rows carry the display label, not just the field name'
    );
  }

  @IsTest
  static void inactiveMembersAreExcluded() {
    ArcTeamSettingsController.TeamDetail teamA = teamNamed(TEAM_A);

    for (ArcTeamSettingsController.TeamMember m : teamA.members) {
      Assert.areNotEqual(
        'Former Advisor',
        m.role,
        'An inactive membership should not appear on the roster'
      );
    }
    Assert.areEqual(3, teamA.members.size(), 'Only the three active members');
  }

  @IsTest
  static void repCodesBelongToTheTeam() {
    ArcTeamSettingsController.TeamDetail teamA = teamNamed(TEAM_A);
    ArcTeamSettingsController.TeamDetail teamB = teamNamed(TEAM_B);

    Assert.areEqual(2, teamA.repCodes.size(), 'Team A owns both rep codes');
    Assert.areEqual(
      0,
      teamB.repCodes.size(),
      'Rep codes must not leak across teams'
    );
  }

  @IsTest
  static void getTeamHandlesAMissingId() {
    Test.startTest();
    ArcTeamSettingsController.TeamDetail result = ArcTeamSettingsController.getTeam(
      null
    );
    Test.stopTest();

    Assert.isNull(result, 'A null id should return null rather than throwing');
  }

  // ---- Fixture helpers ----------------------------------------------------

  private static ArcTeamSettingsController.TeamDetail teamNamed(String name) {
    for (
      ArcTeamSettingsController.TeamDetail t : ArcTeamSettingsController.getMyTeams()
    ) {
      if (t.name == name) {
        return t;
      }
    }
    Assert.fail('Fixture team ' + name + ' was not returned');
    return null;
  }

  private static Financial_Advisor_Team__c newTeam(String name) {
    return new Financial_Advisor_Team__c(Name = name, Status__c = 'Active');
  }

  private static Financial_Advisor_Team_Member__c newMember(
    Id teamId,
    Id userId,
    String role,
    Boolean isPrimary
  ) {
    return new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = teamId,
      User__c = userId,
      Role__c = role,
      Active__c = true,
      Primary__c = isPrimary
    );
  }

  private static Financial_Advisor_Team_Member__c inactiveMember(
    Id teamId,
    Id userId,
    String role
  ) {
    Financial_Advisor_Team_Member__c m = newMember(teamId, userId, role, false);
    m.Active__c = false;
    return m;
  }
}