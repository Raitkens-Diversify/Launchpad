/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Shared user queries for notification recipient eligibility.
 */
public without sharing class NotificationRecipientUserRepository {
  public static Map<Id, User> selectEligibleUsersById(Set<Id> userIds) {
    Map<Id, User> usersById = new Map<Id, User>();

    if (userIds == null || userIds.isEmpty()) {
      return usersById;
    }

    Set<String> eligibleProfileNames = UserInfoUtils.notificationEligibleProfileNames();
    String standardUserType = UserInfoUtils.USER_TYPE_STANDARD;

    for (User recipientUser : [
      SELECT Id, Profile.Name, UserType
      FROM User
      WHERE
        Id IN :userIds
        AND IsActive = TRUE
        AND (
          Profile.Name IN :eligibleProfileNames
          OR UserType != :standardUserType
        )
    ]) {
      usersById.put(recipientUser.Id, recipientUser);
    }

    return usersById;
  }

  public static Map<Id, String> selectEligibleProfileNameByUserId(Set<Id> userIds) {
    Map<Id, String> userIdToProfileName = new Map<Id, String>();

    for (User eligibleUser : selectEligibleUsersById(userIds).values()) {
      userIdToProfileName.put(eligibleUser.Id, eligibleUser.Profile.Name);
    }

    return userIdToProfileName;
  }

  public static Map<Id, String> selectPitStopRecipientProfileNameByUserId(
    Set<Id> userIds,
    Task taskRecord
  ) {
    Map<Id, String> userIdToProfileName = new Map<Id, String>();
    Set<String> profileNames = NotificationConstants.pitStopRecipientProfileNames(
      taskRecord
    );

    if (
      userIds == null ||
      userIds.isEmpty() ||
      profileNames == null ||
      profileNames.isEmpty()
    ) {
      return userIdToProfileName;
    }

    String standardUserType = UserInfoUtils.USER_TYPE_STANDARD;
    Boolean includeCommunityUsers = taskRecord != null &&
      taskRecord.Branch_Pit_Stop__c == true;

    List<User> recipientUsers;
    if (includeCommunityUsers) {
      recipientUsers = [
        SELECT Id, Profile.Name, UserType
        FROM User
        WHERE
          Id IN :userIds
          AND IsActive = TRUE
          AND (
            Profile.Name IN :profileNames
            OR UserType != :standardUserType
          )
      ];
    } else {
      recipientUsers = [
        SELECT Id, Profile.Name, UserType
        FROM User
        WHERE
          Id IN :userIds
          AND IsActive = TRUE
          AND Profile.Name IN :profileNames
      ];
    }

    for (User recipientUser : recipientUsers) {
      userIdToProfileName.put(recipientUser.Id, recipientUser.Profile.Name);
    }

    return userIdToProfileName;
  }

  public static Set<Id> selectEligibleActiveMemberUserIds(Id teamId) {
    Set<Id> activeMemberUserIds = new Set<Id>();

    if (teamId == null) {
      return activeMemberUserIds;
    }

    Set<String> eligibleProfileNames = UserInfoUtils.notificationEligibleProfileNames();
    String standardUserType = UserInfoUtils.USER_TYPE_STANDARD;

    for (Financial_Advisor_Team_Member__c teamMember : [
      SELECT User__c
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c = :teamId
        AND Active__c = TRUE
        AND User__c != NULL
        AND (
          User__r.Profile.Name IN :eligibleProfileNames
          OR User__r.UserType != :standardUserType
        )
    ]) {
      activeMemberUserIds.add(teamMember.User__c);
    }

    return activeMemberUserIds;
  }

  public static Map<Id, Set<Id>> selectEligibleActiveMemberUserIdsByTeamId(
    Set<Id> teamIds
  ) {
    Map<Id, Set<Id>> teamIdToUserIds = new Map<Id, Set<Id>>();

    if (teamIds == null || teamIds.isEmpty()) {
      return teamIdToUserIds;
    }

    Set<String> eligibleProfileNames = UserInfoUtils.notificationEligibleProfileNames();
    String standardUserType = UserInfoUtils.USER_TYPE_STANDARD;

    for (Financial_Advisor_Team_Member__c teamMember : [
      SELECT User__c, Financial_Advisor_Team__c
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c IN :teamIds
        AND Active__c = TRUE
        AND User__c != NULL
        AND (
          User__r.Profile.Name IN :eligibleProfileNames
          OR User__r.UserType != :standardUserType
        )
    ]) {
      addUserIdToTeamMap(
        teamIdToUserIds,
        teamMember.Financial_Advisor_Team__c,
        teamMember.User__c
      );
    }

    return teamIdToUserIds;
  }

  private static void addUserIdToTeamMap(
    Map<Id, Set<Id>> teamIdToUserIds,
    Id teamId,
    Id userId
  ) {
    if (!teamIdToUserIds.containsKey(teamId)) {
      teamIdToUserIds.put(teamId, new Set<Id>());
    }

    teamIdToUserIds.get(teamId).add(userId);
  }
}