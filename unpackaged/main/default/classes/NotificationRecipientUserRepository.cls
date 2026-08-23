/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Shared user queries for notification recipient eligibility.
 */
public without sharing class NotificationRecipientUserRepository {
  public static Map<Id, String> selectEligibleProfileNameByUserId(Set<Id> userIds) {
    Map<Id, String> userIdToProfileName = new Map<Id, String>();

    if (userIds == null || userIds.isEmpty()) {
      return userIdToProfileName;
    }

    for (User recipientUser : [
      SELECT Id, Profile.Name
      FROM User
      WHERE
        Id IN :userIds
        AND IsActive = TRUE
        AND Profile.Name IN :NotificationConstants.notificationEligibleProfileNames()
    ]) {
      userIdToProfileName.put(recipientUser.Id, recipientUser.Profile.Name);
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

    for (User recipientUser : [
      SELECT Id, Profile.Name
      FROM User
      WHERE
        Id IN :userIds
        AND IsActive = TRUE
        AND Profile.Name IN :profileNames
    ]) {
      userIdToProfileName.put(recipientUser.Id, recipientUser.Profile.Name);
    }

    return userIdToProfileName;
  }

  public static Set<Id> selectEligibleActiveMemberUserIds(Id teamId) {
    Set<Id> activeMemberUserIds = new Set<Id>();

    if (teamId == null) {
      return activeMemberUserIds;
    }

    for (Financial_Advisor_Team_Member__c teamMember : [
      SELECT User__c
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c = :teamId
        AND Active__c = TRUE
        AND User__c != NULL
        AND User__r.Profile.Name IN :NotificationConstants.notificationEligibleProfileNames()
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

    for (Financial_Advisor_Team_Member__c teamMember : [
      SELECT User__c, Financial_Advisor_Team__c
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c IN :teamIds
        AND Active__c = TRUE
        AND User__c != NULL
        AND User__r.Profile.Name IN :NotificationConstants.notificationEligibleProfileNames()
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