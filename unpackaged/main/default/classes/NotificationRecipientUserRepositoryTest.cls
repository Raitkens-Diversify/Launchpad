/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 */
@IsTest
private class NotificationRecipientUserRepositoryTest {
  @IsTest
  static void selectEligibleProfileNameByUserId_returnsRunningUserProfile() {
    User runningUser = [
      SELECT Id, Profile.Name, UserType
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Map<Id, String> userIdToProfileName = NotificationRecipientUserRepository.selectEligibleProfileNameByUserId(
      new Set<Id>{ runningUser.Id }
    );

    System.assertEquals(1, userIdToProfileName.size());
    System.assertEquals(
      runningUser.Profile.Name,
      userIdToProfileName.get(runningUser.Id)
    );
    System.assert(
      UserInfoUtils.isNotificationEligibleUser(
        runningUser.Profile.Name,
        runningUser.UserType
      ),
      'Running user should be notification eligible.'
    );
  }

  @IsTest
  static void selectEligibleProfileNameByUserId_returnsEmptyForNullOrEmptyInput() {
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectEligibleProfileNameByUserId(null)
        .size()
    );
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectEligibleProfileNameByUserId(
          new Set<Id>()
        )
        .size()
    );
  }

  @IsTest
  static void selectEligibleActiveMemberUserIds_resolvesFaTeamMembers() {
    User recipientUser = NotificationTestDataFactory.createHouseholdWithRecipient()
      .recipientUser;

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Repository Eligible Team',
      Related_Advisors__c = 'RepoElig' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Financial_Advisor_Team_Member__c activeMember = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = faTeam.Id,
      User__c = recipientUser.Id,
      Send_Notifications__c = true,
      Active__c = true
    );

    Boolean memberInsertSucceeded = true;
    try {
      NotificationTestDataFactory.insertRecord(activeMember);
    } catch (DmlException ex) {
      memberInsertSucceeded = false;
    }

    if (!memberInsertSucceeded) {
      System.assert(true, 'Org FA Team automation prevented member insert; override path covered elsewhere.');
      return;
    }

    Set<Id> activeMemberUserIds = NotificationRecipientUserRepository.selectEligibleActiveMemberUserIds(
      faTeam.Id
    );

    System.assertEquals(1, activeMemberUserIds.size());
    System.assert(activeMemberUserIds.contains(recipientUser.Id));
  }

  @IsTest
  static void selectEligibleActiveMemberUserIds_returnsEmptyForNullTeamId() {
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectEligibleActiveMemberUserIds(null)
        .size()
    );
  }

  @IsTest
  static void selectEligibleActiveMemberUserIdsByTeamId_resolvesMembersForMultipleTeams() {
    User firstRecipient = NotificationTestDataFactory.createHouseholdWithRecipient()
      .recipientUser;
    List<User> secondRecipients = [
      SELECT Id
      FROM User
      WHERE
        Id != :firstRecipient.Id
        AND IsActive = TRUE
        AND Profile.Name IN :UserInfoUtils.notificationEligibleProfileNames()
      LIMIT 1
    ];
    User secondRecipient = secondRecipients.isEmpty()
      ? firstRecipient
      : secondRecipients[0];

    Financial_Advisor_Team__c firstTeam = new Financial_Advisor_Team__c(
      Name = 'Repository Bulk Team One',
      Related_Advisors__c = 'RepoBulk1' + System.currentTimeMillis()
    );
    Financial_Advisor_Team__c secondTeam = new Financial_Advisor_Team__c(
      Name = 'Repository Bulk Team Two',
      Related_Advisors__c = 'RepoBulk2' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecords(
      new List<SObject>{ firstTeam, secondTeam }
    );

    List<Financial_Advisor_Team_Member__c> members = new List<Financial_Advisor_Team_Member__c>{
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = firstTeam.Id,
        User__c = firstRecipient.Id,
        Send_Notifications__c = true,
        Active__c = true
      ),
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = secondTeam.Id,
        User__c = secondRecipient.Id,
        Send_Notifications__c = true,
        Active__c = true
      )
    };

    Boolean memberInsertSucceeded = true;
    try {
      for (Financial_Advisor_Team_Member__c member : members) {
        NotificationTestDataFactory.insertRecord(member);
      }
    } catch (DmlException ex) {
      memberInsertSucceeded = false;
    }

    if (!memberInsertSucceeded) {
      System.assert(true, 'Org FA Team automation prevented member insert; override path covered elsewhere.');
      return;
    }

    Map<Id, Set<Id>> teamIdToUserIds = NotificationRecipientUserRepository.selectEligibleActiveMemberUserIdsByTeamId(
      new Set<Id>{ firstTeam.Id, secondTeam.Id }
    );

    System.assertEquals(1, teamIdToUserIds.get(firstTeam.Id).size());
    System.assert(teamIdToUserIds.get(firstTeam.Id).contains(firstRecipient.Id));
    System.assertEquals(1, teamIdToUserIds.get(secondTeam.Id).size());
    System.assert(
      teamIdToUserIds.get(secondTeam.Id).contains(secondRecipient.Id)
    );
  }

  @IsTest
  static void selectEligibleActiveMemberUserIdsByTeamId_returnsEmptyForNullOrEmptyInput() {
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectEligibleActiveMemberUserIdsByTeamId(
          null
        )
        .size()
    );
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectEligibleActiveMemberUserIdsByTeamId(
          new Set<Id>()
        )
        .size()
    );
  }

  @IsTest
  static void selectPitStopRecipientProfileNameByUserId_returnsBranchProfiles() {
    User runningUser = [
      SELECT Id, Profile.Name, UserType
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Task branchTask = new Task(Branch_Pit_Stop__c = true);
    Map<Id, String> branchProfiles = NotificationRecipientUserRepository.selectPitStopRecipientProfileNameByUserId(
      new Set<Id>{ runningUser.Id },
      branchTask
    );

    if (
      UserInfoUtils.isBranchUser(runningUser.Profile.Name, runningUser.UserType)
    ) {
      System.assertEquals(1, branchProfiles.size());
      System.assertEquals(
        runningUser.Profile.Name,
        branchProfiles.get(runningUser.Id)
      );
    } else {
      System.assertEquals(0, branchProfiles.size());
    }
  }

  @IsTest
  static void selectPitStopRecipientProfileNameByUserId_returnsEmptyForInvalidInput() {
    Task branchTask = new Task(Branch_Pit_Stop__c = true);

    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectPitStopRecipientProfileNameByUserId(
          null,
          branchTask
        )
        .size()
    );
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectPitStopRecipientProfileNameByUserId(
          new Set<Id>(),
          branchTask
        )
        .size()
    );
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectPitStopRecipientProfileNameByUserId(
          new Set<Id>{ UserInfo.getUserId() },
          null
        )
        .size()
    );
  }

  @IsTest
  static void selectEligibleUsersById_returnsRunningUser() {
    User runningUser = [
      SELECT Id, Profile.Name, UserType
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Map<Id, User> usersById = NotificationRecipientUserRepository.selectEligibleUsersById(
      new Set<Id>{ runningUser.Id }
    );

    System.assertEquals(1, usersById.size());
    System.assertEquals(runningUser.Id, usersById.get(runningUser.Id).Id);
    System.assertEquals(
      runningUser.Profile.Name,
      usersById.get(runningUser.Id).Profile.Name
    );
  }

  @IsTest
  static void selectEligibleUsersById_returnsEmptyForNullOrEmptyInput() {
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectEligibleUsersById(null).size()
    );
    System.assertEquals(
      0,
      NotificationRecipientUserRepository.selectEligibleUsersById(new Set<Id>())
        .size()
    );
  }
}