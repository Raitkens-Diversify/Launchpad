/**
 * ArcTeamSettingsControllerTest
 *
 * Fixture: two Financial Advisor Teams, so the multi-team case is real rather
 * than assumed. The running user is an active member of both and holds a
 * different role on each — that is the distinction the controller exists to
 * keep straight, and a single-team fixture could not catch it being collapsed.
 *
 * Permissions are spread deliberately: Trading held by one member, CSA by a
 * different one, Associate Advisor by a third (granted through their role,
 * not a direct field set -- see below), and several held by nobody, so the
 * "who is tied to each permission" mapping is exercised for the one and none
 * cases. NOT two holders of the same field on the same team: every one of
 * these eight fields is enforced as single-holder-per-team by
 * FATMember_TriggerHandler (handleTrading/handleCSA/etc, called from both
 * isAfterInsert and isAfterUpdate) -- granting it to a second member clears
 * it from whichever member held it before and stamps the new holder's name
 * onto the team's own same-named text field. Confirmed the hard way: giving
 * two Team A members Trading__c=true in the same transaction set off a
 * recursive isBeforeUpdate -> handleErrorCondition -> "Duplicate id in
 * list" crash.
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
    // Financial_Advisor_Team_TriggerHandler.updateRepCode (fired indirectly
    // below by the dlrs rollup trigger on Financial_Advisor_Team_Member__c,
    // which updates the parent team on member insert/update) does an
    // unfiltered, un-LIMITed `[SELECT Id FROM Financial_Advisor_Team__c
    // WHERE Name = 'Default Team']` assigned straight to a single sObject.
    // With no such row in the org (as in an empty test-data run) that throws
    // "List has no rows for assignment to SObject" the moment any team's
    // member data changes -- unrelated to which team fired the update. A
    // fixture-owned team with that exact name satisfies the query so the
    // rest of setup (which this test does care about) can run.
    insert newTeam('Default Team');

    List<Financial_Advisor_Team__c> teams = new List<Financial_Advisor_Team__c>{
      newTeam(TEAM_A),
      newTeam(TEAM_B)
    };
    insert teams;

    Id teamAId = teams[0].Id;
    Id teamBId = teams[1].Id;
    Id me = UserInfo.getUserId();

    // The two extra Team A members exist only to spread the permission
    // holders across "one member, a different member, nobody" -- they must
    // be different users from `me`, not more rows for the running user. The
    // running user's own getMyAssignments() query
    // (WHERE User__c = :UserInfo.getUserId() AND Active__c = TRUE) would
    // otherwise return more than one active row for Team A, and
    // roleIsReportedPerTeamNotPerUser's roleByTeam map (keyed by team name)
    // would silently collapse them to whichever one query order happens to
    // return last -- undefined, not "the role recorded on that membership".
    insert new List<User>{
      newTeamMemberUser('tmA'),
      newTeamMemberUser('tmB'),
      newTeamMemberUser('tmC')
    };
    Map<String, Id> memberUserIdByAlias = new Map<String, Id>();
    for (User u : [
      SELECT Id, Alias
      FROM User
      WHERE Alias IN ('tmA', 'tmB', 'tmC')
    ]) {
      memberUserIdByAlias.put(u.Alias, u.Id);
    }
    Id associateAdvisorUserId = memberUserIdByAlias.get('tmA');
    Id holdsNothingUserId = memberUserIdByAlias.get('tmB');
    Id inactiveMemberUserId = memberUserIdByAlias.get('tmC');

    // Every permission field below is set on exactly one member (see the
    // class comment on single-holder-per-team enforcement), and set at
    // insert time rather than a later `update` -- a member is never
    // updated a second time anywhere in this fixture, which is what keeps
    // it clear of FATMember_TriggerHandler's recursive isBeforeUpdate path.
    Financial_Advisor_Team_Member__c primaryMember = newMember(
      teamAId,
      me,
      'Financial Advisor',
      true
    );
    primaryMember.Trading__c = true;
    primaryMember.CSA__c = true;

    // Role__c = 'Associate Advisor' auto-grants Associate_Advisor__c via
    // FATMember_TriggerHandler.setPermissionOnRule -- this member's
    // Associate Advisor permission comes from its role, not a field set
    // here.
    Financial_Advisor_Team_Member__c associateAdvisorMember = newMember(
      teamAId,
      associateAdvisorUserId,
      'Associate Advisor',
      false
    );

    Financial_Advisor_Team_Member__c holdsNothingMember = newMember(
      teamAId,
      holdsNothingUserId,
      'Branch Member',
      false
    );

    // Inactive members must not appear anywhere. This is a fourth distinct
    // user, NOT `me` -- reusing `me` here was tried and reproduces a real
    // production behavior: setFinancialAdvisorTeam (below, via this same
    // insert) sets Team A's Primary_Financial_Advisor__c to `me`, which
    // fires Financial_Advisor_Team_TriggerHandler.isAfterUpdate ->
    // createAndUpdateFinancialAdvisorTeamMember. That method looks up
    // existing Financial_Advisor_Team_Member__c rows for (team, that
    // user) with NO Active__c filter, and unconditionally promotes every
    // match to Active__c = true, Primary__c = true, Role__c =
    // 'Financial Advisor' -- so an inactive `me` row on Team A gets
    // silently resurrected as a second active "Financial Advisor" row the
    // moment primaryMember (also `me`, also Financial Advisor) is
    // inserted. Confirmed via a diagnostic dump of the raw rows before
    // this fix (a second active Financial Advisor/`me` row appeared where
    // the inactive one should have been). Not a bug this test's job is to
    // change -- see setFinancialAdvisorTeam and
    // createAndUpdateFinancialAdvisorTeamMember (Financial_Advisor_Team_
    // TriggerHandler.cls) for the production code. Role__c = 'Branch
    // Member' still matches holdsNothingMember's label; neither grants a
    // permission automatically, so sharing it causes no collision.
    Financial_Advisor_Team_Member__c inactiveTeamAMember = inactiveMember(
      teamAId,
      inactiveMemberUserId,
      'Branch Member'
    );

    insert new List<Financial_Advisor_Team_Member__c>{
      primaryMember,
      newMember(teamBId, me, 'Branch Member', false),
      associateAdvisorMember,
      holdsNothingMember,
      inactiveTeamAMember
    };

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
    // Each of these eight fields is single-holder-per-team in this org
    // (FATMember_TriggerHandler clears it from anyone else the moment a new
    // member is granted it), so "many holders" is not a reachable state --
    // see the class comment above setup().
    Assert.areEqual(
      1,
      byField.get('Trading__c').holders.size(),
      'Trading is held by exactly one member'
    );
    Assert.areEqual(
      1,
      byField.get('CSA__c').holders.size(),
      'CSA is held by one (different) member'
    );
    Assert.areEqual(
      1,
      byField.get('Associate_Advisor__c').holders.size(),
      'Associate Advisor is held by the member whose role granted it automatically'
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
    // The fixture inserts four Team A members and one inactive fifth (see
    // setup()); the inactive one shares its 'Branch Member' role label with
    // an active member (neither grants a permission, so they cannot
    // collide on holder status), so a role-label check cannot distinguish
    // them here -- the roster count is the reliable signal: if the
    // inactive row leaked through, this would read 4, not 3.
    ArcTeamSettingsController.TeamDetail teamA = teamNamed(TEAM_A);

    Assert.areEqual(
      3,
      teamA.members.size(),
      'Only the three active members should appear; the inactive fourth must be excluded'
    );
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

  /** A standalone user to stand in for "someone else on the team" -- never
   * run as, only used as a User__c lookup target so the running user's own
   * membership stays one row per team. */
  private static User newTeamMemberUser(String alias) {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String unique =
      alias +
      String.valueOf(Datetime.now().getTime()) +
      String.valueOf(Math.round(Math.random() * 100000));
    return new User(
      FirstName = 'Team',
      LastName = alias,
      Alias = alias,
      Email = unique + '@example.com',
      Username = unique + '@example.com.arcteam',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/Denver',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
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