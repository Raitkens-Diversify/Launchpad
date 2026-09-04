/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 *
 * User profile and branch helpers for the running user and arbitrary user context.
 */
public with sharing class UserInfoUtils {
  public static final String PROFILE_NEXS = 'Arc';
  public static final String PROFILE_ARC_LOGIN = 'Arc Login';
  public static final String PROFILE_BRANCH_CRM = 'Branch CRM';
  public static final String PROFILE_ADVISOR = 'Advisor';
  public static final String PROFILE_HOME_OFFICE = 'Home Office';
  public static final String PROFILE_SYSTEM_ADMINISTRATOR = 'System Administrator';

  private static User currentUserCache;

  @TestVisible
  static void resetCurrentUserCacheForTest() {
    currentUserCache = null;
  }

  private static User getCurrentUser() {
    if (currentUserCache != null) {
      return currentUserCache;
    }

    currentUserCache = [
      SELECT Profile.Name, Branch__c
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    return currentUserCache;
  }

  public static Boolean isNexSProfile(String profileName) {
    return profileName == PROFILE_NEXS;
  }

  public static Boolean isArcLoginProfile(String profileName) {
    return profileName == PROFILE_ARC_LOGIN;
  }

  public static Boolean isBranchCrmProfile(String profileName) {
    return profileName == PROFILE_BRANCH_CRM;
  }

  public static Boolean isAdvisorProfile(String profileName) {
    return profileName == PROFILE_ADVISOR;
  }

  public static Boolean isHomeOfficeProfile(String profileName) {
    return profileName == PROFILE_HOME_OFFICE;
  }

  public static Boolean isHomeOfficeBranch(String branchName) {
    return branchName == PROFILE_HOME_OFFICE;
  }

  public static Boolean isHomeOfficeUser(String profileName, String branchName) {
    return isHomeOfficeProfile(profileName) || isHomeOfficeBranch(branchName);
  }

  public static Boolean isBranchUserProfile(String profileName) {
    return isBranchNotificationProfile(profileName);
  }

  public static Boolean isBranchNotificationProfile(String profileName) {
    return isNexSProfile(profileName) ||
      isArcLoginProfile(profileName) ||
      isBranchCrmProfile(profileName) ||
      isAdvisorProfile(profileName);
  }

  public static Boolean isSystemAdministratorProfile(String profileName) {
    return profileName == PROFILE_SYSTEM_ADMINISTRATOR;
  }

  public static Boolean isNotificationEligibleProfile(String profileName) {
    return isBranchNotificationProfile(profileName) ||
      isHomeOfficeProfile(profileName) ||
      isSystemAdministratorProfile(profileName);
  }

  public static Set<String> notificationEligibleProfileNames() {
    return new Set<String>{
      PROFILE_NEXS,
      PROFILE_ARC_LOGIN,
      PROFILE_BRANCH_CRM,
      PROFILE_ADVISOR,
      PROFILE_HOME_OFFICE,
      PROFILE_SYSTEM_ADMINISTRATOR
    };
  }

  public static Boolean isCurrentUserNexS() {
    return isNexSProfile(getCurrentUser().Profile.Name);
  }

  public static Boolean isCurrentUserAdvisor() {
    return isAdvisorProfile(getCurrentUser().Profile.Name);
  }

  public static Boolean isCurrentUserHomeOffice() {
    User currentUser = getCurrentUser();
    return isHomeOfficeUser(currentUser.Profile.Name, currentUser.Branch__c);
  }

  public static Boolean isCurrentUserBranchUser() {
    return isBranchUserProfile(getCurrentUser().Profile.Name);
  }

  public static Boolean isCurrentUserSystemAdministrator() {
    return isSystemAdministratorProfile(getCurrentUser().Profile.Name);
  }

  public static Boolean isCurrentUserNotificationEligible() {
    return isNotificationEligibleProfile(getCurrentUser().Profile.Name);
  }

  private UserInfoUtils() {
  }
}