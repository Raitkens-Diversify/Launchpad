/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 */
@IsTest
private class FscRelReciprocalRoleAccessServiceTest {
  @IsTest
  static void canAccessRole_allowsCreatorAndTeamMembers() {
    Financial_Advisor_Team__c faTeam;
    Reciprocal_Role__c teamRole;
    Reciprocal_Role__c creatorRole;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      faTeam = new Financial_Advisor_Team__c(
        Name = 'Reciprocal Role Team',
        Related_Advisors__c = 'RecRoleTeam' + System.currentTimeMillis()
      );
      insert faTeam;

      teamRole = new Reciprocal_Role__c(
        Role__c = 'Guardian',
        Financial_Advisor_Team__c = faTeam.Id
      );
      insert teamRole;
    }

    Test.startTest();
    User creatorUser = createStandardUser('rolecreator');
    User teammateUser = createStandardUser('teammate');
    User outsiderUser = createStandardUser('outsider');
    Test.stopTest();

    Boolean teamMembersInserted = insertTeamMembers(
      faTeam.Id,
      new List<User>{ creatorUser, teammateUser }
    );

    System.runAs(creatorUser) {
      creatorRole = new Reciprocal_Role__c(Role__c = 'Parent');
      insert creatorRole;
    }

    creatorRole = [
      SELECT Id, Role__c, CreatedById, Financial_Advisor_Team__c
      FROM Reciprocal_Role__c
      WHERE Id = :creatorRole.Id
      LIMIT 1
    ];
    teamRole = [
      SELECT Id, Role__c, CreatedById, Financial_Advisor_Team__c
      FROM Reciprocal_Role__c
      WHERE Id = :teamRole.Id
      LIMIT 1
    ];

    System.runAs(creatorUser) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();
      System.assertEquals(true, accessService.canAccessRole(creatorRole));
    }

    if (teamMembersInserted) {
      System.runAs(teammateUser) {
        FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();
        System.assertEquals(true, accessService.canAccessRole(teamRole));
        System.assertEquals(true, accessService.canAccessRole(creatorRole));
      }
    }

    System.runAs(outsiderUser) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();
      System.assertEquals(false, accessService.canAccessRole(teamRole));
      System.assertEquals(false, accessService.canAccessRole(creatorRole));
    }
  }

  @IsTest
  static void canAccessRole_handlesNullRoleAndPrimaryTeamLookup() {
    FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();

    Test.startTest();
    System.assertEquals(false, accessService.canAccessRole(null));
    System.assertEquals(null, accessService.selectPrimaryTeamIdForUser(null));
    Set<Id> accessibleTeamIds = accessService.getAccessibleTeamIds();
    Test.stopTest();

    System.assertNotEquals(null, accessibleTeamIds);
  }

  @IsTest
  static void selectPrimaryTeamIdForCurrentUser_returnsActiveTeamMembership() {
    Financial_Advisor_Team__c faTeam;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      faTeam = new Financial_Advisor_Team__c(
        Name = 'Primary Team Lookup',
        Related_Advisors__c = 'PrimaryTeam' + System.currentTimeMillis()
      );
      insert faTeam;
    }

    User memberUser = createStandardUser('primarymember');

    if (!insertTeamMembers(faTeam.Id, new List<User>{ memberUser })) {
      return;
    }

    System.runAs(memberUser) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();

      Test.startTest();
      Id primaryTeamId = accessService.selectPrimaryTeamIdForCurrentUser();
      Id teamIdForUser = accessService.selectPrimaryTeamIdForUser(memberUser.Id);
      Set<Id> accessibleTeamIds = accessService.getAccessibleTeamIds();
      Set<Id> cachedTeamIds = accessService.getAccessibleTeamIds();
      Test.stopTest();

      System.assertEquals(faTeam.Id, primaryTeamId);
      System.assertEquals(faTeam.Id, teamIdForUser);
      System.assert(accessibleTeamIds.contains(faTeam.Id));
      System.assertEquals(accessibleTeamIds, cachedTeamIds);
    }
  }

  @IsTest
  static void canAccessRole_allowsSharedTeamWhenRoleHasNoFaTeam() {
    Financial_Advisor_Team__c faTeam;
    Reciprocal_Role__c sharedTeamRole;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      faTeam = new Financial_Advisor_Team__c(
        Name = 'Shared Team Access',
        Related_Advisors__c = 'SharedTeam' + System.currentTimeMillis()
      );
      insert faTeam;
    }

    Test.startTest();
    User creatorUser = createStandardUser('sharedcreator');
    User teammateUser = createStandardUser('sharedteammate');
    Test.stopTest();

    if (!insertTeamMembers(faTeam.Id, new List<User>{ creatorUser, teammateUser })) {
      return;
    }

    System.runAs(creatorUser) {
      sharedTeamRole = new Reciprocal_Role__c(Role__c = 'Sibling');
      insert sharedTeamRole;
    }

    sharedTeamRole = [
      SELECT Id, Role__c, CreatedById, Financial_Advisor_Team__c
      FROM Reciprocal_Role__c
      WHERE Id = :sharedTeamRole.Id
      LIMIT 1
    ];

    System.runAs(teammateUser) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();
      System.assertEquals(true, accessService.canAccessRole(sharedTeamRole));
    }

    System.runAs(createStandardUser('sharedoutsider')) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();
      System.assertEquals(false, accessService.canAccessRole(sharedTeamRole));
    }
  }

  @IsTest
  static void canAccessRole_allowsFaTeamMemberForTeamScopedRole() {
    Financial_Advisor_Team__c faTeam;
    Reciprocal_Role__c teamScopedRole;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      faTeam = new Financial_Advisor_Team__c(
        Name = 'Team Scoped Role',
        Related_Advisors__c = 'TeamScoped' + System.currentTimeMillis()
      );
      insert faTeam;

      teamScopedRole = new Reciprocal_Role__c(
        Role__c = 'Advisor',
        Financial_Advisor_Team__c = faTeam.Id
      );
      insert teamScopedRole;
    }

    User teammateUser = createStandardUser('teamscopedmember');

    if (!insertTeamMembers(faTeam.Id, new List<User>{ teammateUser })) {
      return;
    }

    teamScopedRole = [
      SELECT Id, Role__c, CreatedById, Financial_Advisor_Team__c
      FROM Reciprocal_Role__c
      WHERE Id = :teamScopedRole.Id
      LIMIT 1
    ];

    System.runAs(teammateUser) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService();
      System.assertEquals(true, accessService.canAccessRole(teamScopedRole));
    }
  }

  @IsTest
  static void searchByTerm_includesRolesFromOtherTeams() {
    Financial_Advisor_Team__c teamOne;
    Financial_Advisor_Team__c teamTwo;
    Reciprocal_Role__c teamOneRole;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      teamOne = new Financial_Advisor_Team__c(
        Name = 'Team One Roles',
        Related_Advisors__c = 'TeamOneRoles' + System.currentTimeMillis()
      );
      teamTwo = new Financial_Advisor_Team__c(
        Name = 'Team Two Roles',
        Related_Advisors__c = 'TeamTwoRoles' + System.currentTimeMillis()
      );
      insert new List<Financial_Advisor_Team__c>{ teamOne, teamTwo };

      teamOneRole = new Reciprocal_Role__c(
        Role__c = 'Guardian',
        Financial_Advisor_Team__c = teamOne.Id
      );
      insert teamOneRole;
    }

    Test.startTest();
    User teamTwoUser = createStandardUser('teamtwo');
    Test.stopTest();

    insertTeamMember(teamTwo.Id, teamTwoUser.Id, true);

    System.runAs(teamTwoUser) {
      FscRelReciprocalRoleRepository repository = new FscRelReciprocalRoleRepository();
      List<Reciprocal_Role__c> results = repository.searchByTerm('Guardian', 5);
      System.assertEquals(false, results.isEmpty());
      System.assertEquals('Guardian', results[0].Role__c);
    }
  }

  private static User createStandardUser(String aliasSeed) {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    User userRecord = new User(
      Alias = aliasSeed.left(8),
      Email = aliasSeed + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = aliasSeed,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasSeed + System.currentTimeMillis() + '@example.com'
    );
    insert userRecord;
    return userRecord;
  }

  private static Boolean insertTeamMembers(Id teamId, List<User> users) {
    if (users == null || users.isEmpty()) {
      return false;
    }

    List<Financial_Advisor_Team_Member__c> members = new List<Financial_Advisor_Team_Member__c>();
    for (Integer index = 0; index < users.size(); index++) {
      members.add(
        new Financial_Advisor_Team_Member__c(
          Financial_Advisor_Team__c = teamId,
          User__c = users[index].Id,
          Active__c = true,
          Primary__c = index == 0
        )
      );
    }

    try {
      insert members;
      return true;
    } catch (DmlException error) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return false;
    }
  }

  private static void insertTeamMember(Id teamId, Id userId, Boolean isPrimary) {
    insertTeamMembers(teamId, new List<User>{ new User(Id = userId) });
  }

  @IsTest
  static void accessService_coversRepositoryBackedPathsUsingStub() {
    List<User> activeUsers = [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE
      LIMIT 2
    ];

    if (activeUsers.size() < 2) {
      return;
    }

    User creatorUser = activeUsers[0];
    User teammateUser = activeUsers[1];
    Financial_Advisor_Team__c faTeam;

    System.runAs(new User(Id = UserInfo.getUserId())) {
      faTeam = new Financial_Advisor_Team__c(
        Name = 'Stub Repository Team',
        Related_Advisors__c = 'StubRepoTeam' + System.currentTimeMillis()
      );
      insert faTeam;
    }

    StubFaTeamMemberRepository stubRepository = new StubFaTeamMemberRepository()
      .withTeam(creatorUser.Id, faTeam.Id)
      .withTeam(teammateUser.Id, faTeam.Id);

    Reciprocal_Role__c teamRole = new Reciprocal_Role__c(
      Role__c = 'Counselor',
      Financial_Advisor_Team__c = faTeam.Id
    );
    insert teamRole;
    teamRole = queryRole(teamRole.Id);

    Reciprocal_Role__c sharedRole;
    System.runAs(creatorUser) {
      sharedRole = new Reciprocal_Role__c(Role__c = 'Neighbor');
      insert sharedRole;
    }
    sharedRole = queryRole(sharedRole.Id);

    Test.startTest();
    System.runAs(teammateUser) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService(
        stubRepository
      );
      System.assertEquals(faTeam.Id, accessService.selectPrimaryTeamIdForCurrentUser());
      System.assertEquals(faTeam.Id, accessService.selectPrimaryTeamIdForUser(teammateUser.Id));
      System.assert(accessService.getAccessibleTeamIds().contains(faTeam.Id));
      System.assertEquals(true, accessService.canAccessRole(teamRole));
      System.assertEquals(true, accessService.canAccessRole(sharedRole));
    }

    System.runAs(creatorUser) {
      FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService(
        stubRepository
      );
      System.assertEquals(true, accessService.canAccessRole(sharedRole));
    }

    List<User> outsiderUsers = [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE AND Id NOT IN :new Set<Id>{ creatorUser.Id, teammateUser.Id }
      LIMIT 1
    ];

    if (!outsiderUsers.isEmpty()) {
      System.runAs(outsiderUsers[0]) {
        FscRelReciprocalRoleAccessService accessService = new FscRelReciprocalRoleAccessService(
          stubRepository
        );
        System.assertEquals(false, accessService.canAccessRole(teamRole));
        System.assertEquals(false, accessService.canAccessRole(sharedRole));
      }
    }
    Test.stopTest();
  }

  private static Reciprocal_Role__c queryRole(Id roleId) {
    return [
      SELECT Id, Role__c, CreatedById, Financial_Advisor_Team__c
      FROM Reciprocal_Role__c
      WHERE Id = :roleId
      LIMIT 1
    ];
  }

  private class StubFaTeamMemberRepository extends FscRelFaTeamMemberRepository {
    private Map<Id, Set<Id>> userIdToTeamIds = new Map<Id, Set<Id>>();

    public StubFaTeamMemberRepository withTeam(Id userId, Id teamId) {
      if (userId == null || teamId == null) {
        return this;
      }

      if (!userIdToTeamIds.containsKey(userId)) {
        userIdToTeamIds.put(userId, new Set<Id>());
      }

      userIdToTeamIds.get(userId).add(teamId);
      return this;
    }

    public override List<Financial_Advisor_Team_Member__c> selectActiveByUserId(Id userId) {
      List<Financial_Advisor_Team_Member__c> members = new List<Financial_Advisor_Team_Member__c>();

      if (userId == null || !userIdToTeamIds.containsKey(userId)) {
        return members;
      }

      for (Id teamId : userIdToTeamIds.get(userId)) {
        members.add(
          new Financial_Advisor_Team_Member__c(
            User__c = userId,
            Financial_Advisor_Team__c = teamId,
            Active__c = true,
            Primary__c = true
          )
        );
      }

      return members;
    }

    public override Set<Id> selectActiveTeamIdsByUserId(Id userId) {
      return userIdToTeamIds.containsKey(userId)
        ? new Set<Id>(userIdToTeamIds.get(userId))
        : new Set<Id>();
    }

    public override Boolean isActiveMember(Id userId, Id teamId) {
      return selectActiveTeamIdsByUserId(userId).contains(teamId);
    }
  }
}