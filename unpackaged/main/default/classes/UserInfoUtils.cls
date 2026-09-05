/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-02
 *
 * User profile and branch helpers for the running user and arbitrary user context.
 */
public with sharing class UserInfoUtils {
  /** Arc profile name; {@link #isNexSProfile} also covers Arc Login and community users. */
  public static final String PROFILE_NEXS = 'Arc';
  public static final String PROFILE_ADVISOR = 'Advisor';
  public static final String PROFILE_HOME_OFFICE = 'Home Office';
  public static final String PROFILE_SYSTEM_ADMINISTRATOR = 'System Administrator';
  public static final String USER_TYPE_STANDARD = 'Standard';
  public static final String PROFILE_NEXS_LOGIN = 'Arc Login';

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
      SELECT Profile.Name, Branch__c, UserType
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    return currentUserCache;
  }

  public static Set<String> nexsProfileNames() {
    return new Set<String>{ PROFILE_NEXS, PROFILE_NEXS_LOGIN };
  }

  public static Boolean isCommunityUserType(String userType) {
    return String.isNotBlank(userType) && userType != USER_TYPE_STANDARD;
  }

  /**
   * NexS profile-name check (Arc or Arc Login). Use the two-arg overload when UserType is available.
   */
  public static Boolean isNexSProfile(String profileName) {
    return nexsProfileNames().contains(profileName);
  }

  /**
   * NexS user: Arc, Arc Login, or any non-Standard (community) license user.
   */
  public static Boolean isNexSProfile(String profileName, String userType) {
    return isNexSProfile(profileName) || isCommunityUserType(userType);
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
    return isNexSProfile(profileName) || isAdvisorProfile(profileName);
  }

  public static Boolean isBranchUser(String profileName, String userType) {
    return isNexSProfile(profileName, userType) || isAdvisorProfile(profileName);
  }

  public static Boolean isSystemAdministratorProfile(String profileName) {
    return profileName == PROFILE_SYSTEM_ADMINISTRATOR;
  }

  public static Boolean isNotificationEligibleProfile(String profileName) {
    return isNexSProfile(profileName) ||
      isAdvisorProfile(profileName) ||
      isHomeOfficeProfile(profileName) ||
      isSystemAdministratorProfile(profileName);
  }

  public static Boolean isNotificationEligibleUser(
    String profileName,
    String userType
  ) {
    return isNexSProfile(profileName, userType) ||
      isAdvisorProfile(profileName) ||
      isHomeOfficeProfile(profileName) ||
      isSystemAdministratorProfile(profileName);
  }

  public static Set<String> notificationEligibleProfileNames() {
    Set<String> profileNames = nexsProfileNames();
    profileNames.add(PROFILE_ADVISOR);
    profileNames.add(PROFILE_HOME_OFFICE);
    profileNames.add(PROFILE_SYSTEM_ADMINISTRATOR);
    return profileNames;
  }

  public static Boolean isCurrentUserNexS() {
    User currentUser = getCurrentUser();
    return isNexSProfile(currentUser.Profile.Name, currentUser.UserType);
  }

  public static Boolean isCurrentUserAdvisor() {
    return isAdvisorProfile(getCurrentUser().Profile.Name);
  }

  public static Boolean isCurrentUserHomeOffice() {
    User currentUser = getCurrentUser();
    return isHomeOfficeUser(currentUser.Profile.Name, currentUser.Branch__c);
  }

  public static Boolean isCurrentUserBranchUser() {
    User currentUser = getCurrentUser();
    return isBranchUser(currentUser.Profile.Name, currentUser.UserType);
  }

  public static Boolean isCurrentUserSystemAdministrator() {
    return isSystemAdministratorProfile(getCurrentUser().Profile.Name);
  }

  public static Boolean isCurrentUserNotificationEligible() {
    User currentUser = getCurrentUser();
    return isNotificationEligibleUser(
      currentUser.Profile.Name,
      currentUser.UserType
    );
  }

  private UserInfoUtils() {
  }
}