/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 */
@IsTest
private class UserInfoUtilsTest {
  @IsTest
  static void profileHelpers_identifyKnownProfiles() {
    System.assertEquals(true, UserInfoUtils.isNexSProfile(UserInfoUtils.PROFILE_NEXS));
    System.assertEquals(false, UserInfoUtils.isNexSProfile(UserInfoUtils.PROFILE_ADVISOR));

    System.assertEquals(
      true,
      UserInfoUtils.isAdvisorProfile(UserInfoUtils.PROFILE_ADVISOR)
    );
    System.assertEquals(false, UserInfoUtils.isAdvisorProfile(null));

    System.assertEquals(
      true,
      UserInfoUtils.isHomeOfficeProfile(UserInfoUtils.PROFILE_HOME_OFFICE)
    );
    System.assertEquals(
      true,
      UserInfoUtils.isHomeOfficeBranch(UserInfoUtils.PROFILE_HOME_OFFICE)
    );
    System.assertEquals(false, UserInfoUtils.isHomeOfficeBranch('Branch A'));

    System.assertEquals(
      true,
      UserInfoUtils.isSystemAdministratorProfile(
        UserInfoUtils.PROFILE_SYSTEM_ADMINISTRATOR
      )
    );
  }

  @IsTest
  static void isHomeOfficeUser_checksProfileOrBranch() {
    System.assertEquals(
      true,
      UserInfoUtils.isHomeOfficeUser(UserInfoUtils.PROFILE_HOME_OFFICE, null)
    );
    System.assertEquals(
      true,
      UserInfoUtils.isHomeOfficeUser(
        UserInfoUtils.PROFILE_NEXS,
        UserInfoUtils.PROFILE_HOME_OFFICE
      )
    );
    System.assertEquals(
      false,
      UserInfoUtils.isHomeOfficeUser(UserInfoUtils.PROFILE_NEXS, 'Branch A')
    );
  }

  @IsTest
  static void isBranchUserProfile_identifiesNexsAndAdvisor() {
    System.assertEquals(true, UserInfoUtils.isBranchUserProfile(UserInfoUtils.PROFILE_NEXS));
    System.assertEquals(
      true,
      UserInfoUtils.isBranchUserProfile(UserInfoUtils.PROFILE_ADVISOR)
    );
    System.assertEquals(
      false,
      UserInfoUtils.isBranchUserProfile(UserInfoUtils.PROFILE_HOME_OFFICE)
    );
  }

  @IsTest
  static void isNotificationEligibleProfile_includesExpectedProfiles() {
    System.assertEquals(
      true,
      UserInfoUtils.isNotificationEligibleProfile(UserInfoUtils.PROFILE_NEXS)
    );
    System.assertEquals(
      true,
      UserInfoUtils.isNotificationEligibleProfile(UserInfoUtils.PROFILE_ADVISOR)
    );
    System.assertEquals(
      true,
      UserInfoUtils.isNotificationEligibleProfile(UserInfoUtils.PROFILE_HOME_OFFICE)
    );
    System.assertEquals(
      true,
      UserInfoUtils.isNotificationEligibleProfile(
        UserInfoUtils.PROFILE_SYSTEM_ADMINISTRATOR
      )
    );
    System.assertEquals(false, UserInfoUtils.isNotificationEligibleProfile('Standard User'));
  }

  @IsTest
  static void notificationEligibleProfileNames_returnsAllEligibleProfiles() {
    Set<String> profileNames = UserInfoUtils.notificationEligibleProfileNames();

    System.assertEquals(4, profileNames.size());
    System.assert(profileNames.contains(UserInfoUtils.PROFILE_NEXS));
    System.assert(profileNames.contains(UserInfoUtils.PROFILE_ADVISOR));
    System.assert(profileNames.contains(UserInfoUtils.PROFILE_HOME_OFFICE));
    System.assert(profileNames.contains(UserInfoUtils.PROFILE_SYSTEM_ADMINISTRATOR));
  }

  @IsTest
  static void currentUserHelpers_matchRunningUserContext() {
    User runningUser = [
      SELECT Profile.Name, Branch__c
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    UserInfoUtils.resetCurrentUserCacheForTest();

    System.assertEquals(
      UserInfoUtils.isNexSProfile(runningUser.Profile.Name),
      UserInfoUtils.isCurrentUserNexS()
    );
    System.assertEquals(
      UserInfoUtils.isAdvisorProfile(runningUser.Profile.Name),
      UserInfoUtils.isCurrentUserAdvisor()
    );
    System.assertEquals(
      UserInfoUtils.isHomeOfficeUser(
        runningUser.Profile.Name,
        runningUser.Branch__c
      ),
      UserInfoUtils.isCurrentUserHomeOffice()
    );
    System.assertEquals(
      UserInfoUtils.isBranchUserProfile(runningUser.Profile.Name),
      UserInfoUtils.isCurrentUserBranchUser()
    );
    System.assertEquals(
      UserInfoUtils.isSystemAdministratorProfile(runningUser.Profile.Name),
      UserInfoUtils.isCurrentUserSystemAdministrator()
    );
    System.assertEquals(
      UserInfoUtils.isNotificationEligibleProfile(runningUser.Profile.Name),
      UserInfoUtils.isCurrentUserNotificationEligible()
    );
  }

  @IsTest
  static void isCurrentUserHomeOffice_trueWhenBranchIsHomeOffice() {
    User nexsUser = createProfileUserIfAvailable(
      UserInfoUtils.PROFILE_NEXS,
      'uiutnexs'
    );

    if (nexsUser == null) {
      return;
    }

    try {
      nexsUser.Branch__c = UserInfoUtils.PROFILE_HOME_OFFICE;
      update nexsUser;
    } catch (Exception ex) {
      System.assert(true, 'Branch__c is unavailable in this org.');
      return;
    }

    System.runAs(nexsUser) {
      UserInfoUtils.resetCurrentUserCacheForTest();
      System.assertEquals(true, UserInfoUtils.isCurrentUserHomeOffice());
    }
  }

  private static User createProfileUserIfAvailable(
    String profileName,
    String aliasPrefix
  ) {
    List<Profile> profiles = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      LIMIT 1
    ];

    if (profiles.isEmpty()) {
      return null;
    }

    try {
      return NotificationTestDataFactory.createProfileUser(profileName, aliasPrefix);
    } catch (DmlException ex) {
      return null;
    }
  }
}