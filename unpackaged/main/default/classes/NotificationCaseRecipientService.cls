/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Resolves Case notification recipients by profile-specific ownership eligibility.
 *
 * This service answers who may receive a Case notification (NexS, Advisor, Home Office,
 * and System Administrator ownership, queue membership, and primary-advisor paths).
 * It does not read or
 * evaluate Notification_Rule__c records. After a user passes eligibility here,
 * NotificationPreferenceService resolves their active Case rule for channel,
 * frequency, and digest cadence before NotificationRuleLogService creates logs.
 */
public without sharing class NotificationCaseRecipientService {
  @TestVisible
  private static Map<Id, List<Id>> testRecipientOverrides;

  private final Map<Id, Id> householdIdToTeamId = new Map<Id, Id>();
  private final Map<Id, Set<Id>> teamIdToPrimaryAdvisorUserIds = new Map<Id, Set<Id>>();
  private final Map<Id, Set<Id>> queueIdToMemberUserIds = new Map<Id, Set<Id>>();

  public List<Id> resolveRecipients(Case caseRecord, Id householdId) {
    if (caseRecord == null || caseRecord.Id == null) {
      return new List<Id>();
    }

    if (Test.isRunningTest() && testRecipientOverrides != null) {
      if (testRecipientOverrides.containsKey(caseRecord.Id)) {
        return new List<Id>(testRecipientOverrides.get(caseRecord.Id));
      }

      if (householdId != null && testRecipientOverrides.containsKey(householdId)) {
        return new List<Id>(testRecipientOverrides.get(householdId));
      }
    }

    CaseRecipientContext context = buildContext(caseRecord, householdId);
    Set<Id> candidateUserIds = collectCandidateUserIds(context);
    if (candidateUserIds.isEmpty()) {
      return new List<Id>();
    }

    Map<Id, User> eligibleUsersById = NotificationRecipientUserRepository.selectEligibleUsersById(
      candidateUserIds
    );
    List<Id> eligibleRecipientIds = new List<Id>();

    for (Id userId : candidateUserIds) {
      User eligibleUser = eligibleUsersById.get(userId);
      if (eligibleUser == null) {
        continue;
      }

      if (
        isEligibleRecipient(
          userId,
          eligibleUser.Profile.Name,
          eligibleUser.UserType,
          context
        )
      ) {
        eligibleRecipientIds.add(userId);
      }
    }

    return eligibleRecipientIds;
  }

  private CaseRecipientContext buildContext(Case caseRecord, Id householdId) {
    CaseRecipientContext context = new CaseRecipientContext();
    context.caseRecord = caseRecord;
    context.householdId = householdId;
    context.financialAdvisorTeamId = resolveFinancialAdvisorTeamId(
      caseRecord,
      householdId
    );
    context.ownerIsUser = isUserId(caseRecord.OwnerId);
    context.ownerIsQueue = isQueueId(caseRecord.OwnerId);

    if (context.ownerIsUser) {
      context.ownerUserId = caseRecord.OwnerId;
    }

    if (context.ownerIsQueue) {
      context.queueMemberUserIds = selectQueueMemberUserIds(caseRecord.OwnerId);
    }

    if (context.financialAdvisorTeamId != null) {
      context.primaryAdvisorUserIds = selectPrimaryAdvisorUserIds(
        context.financialAdvisorTeamId
      );
    }

    return context;
  }

  private Id resolveFinancialAdvisorTeamId(Case caseRecord, Id householdId) {
    if (caseRecord.Financial_Advisor_Team__c != null) {
      return caseRecord.Financial_Advisor_Team__c;
    }

    if (householdId == null) {
      return null;
    }

    if (householdIdToTeamId.containsKey(householdId)) {
      return householdIdToTeamId.get(householdId);
    }

    List<Account> households = [
      SELECT Financial_Advisor_Team__c
      FROM Account
      WHERE Id = :householdId
      LIMIT 1
    ];

    Id teamId = households.isEmpty() ? null : households[0].Financial_Advisor_Team__c;
    householdIdToTeamId.put(householdId, teamId);
    return teamId;
  }

  private Set<Id> selectPrimaryAdvisorUserIds(Id teamId) {
    if (teamIdToPrimaryAdvisorUserIds.containsKey(teamId)) {
      return teamIdToPrimaryAdvisorUserIds.get(teamId);
    }

    Set<Id> primaryAdvisorUserIds = new Set<Id>();

    Set<String> eligibleProfileNames = UserInfoUtils.notificationEligibleProfileNames();
    String standardUserType = UserInfoUtils.USER_TYPE_STANDARD;

    for (Financial_Advisor_Team_Member__c teamMember : [
      SELECT User__c
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c = :teamId
        AND Primary__c = TRUE
        AND Active__c = TRUE
        AND User__c != NULL
        AND (
          User__r.Profile.Name IN :eligibleProfileNames
          OR User__r.UserType != :standardUserType
        )
    ]) {
      primaryAdvisorUserIds.add(teamMember.User__c);
    }

    teamIdToPrimaryAdvisorUserIds.put(teamId, primaryAdvisorUserIds);
    return primaryAdvisorUserIds;
  }

  private Set<Id> selectQueueMemberUserIds(Id queueId) {
    if (queueIdToMemberUserIds.containsKey(queueId)) {
      return queueIdToMemberUserIds.get(queueId);
    }

    Set<Id> memberUserIds = new Set<Id>();

    for (GroupMember queueMember : [
      SELECT UserOrGroupId
      FROM GroupMember
      WHERE GroupId = :queueId
    ]) {
      if (isUserId(queueMember.UserOrGroupId)) {
        memberUserIds.add(queueMember.UserOrGroupId);
      }
    }

    queueIdToMemberUserIds.put(queueId, memberUserIds);
    return memberUserIds;
  }

  private static Set<Id> collectCandidateUserIds(CaseRecipientContext context) {
    Set<Id> candidateUserIds = new Set<Id>();

    if (context.ownerUserId != null) {
      candidateUserIds.add(context.ownerUserId);
    }

    if (context.queueMemberUserIds != null) {
      candidateUserIds.addAll(context.queueMemberUserIds);
    }

    if (context.primaryAdvisorUserIds != null) {
      candidateUserIds.addAll(context.primaryAdvisorUserIds);
    }

    return candidateUserIds;
  }

  private static Boolean isEligibleRecipient(
    Id userId,
    String profileName,
    String userType,
    CaseRecipientContext context
  ) {
    Boolean isOwner = context.ownerUserId == userId;
    Boolean isQueueMember = context.queueMemberUserIds != null &&
      context.queueMemberUserIds.contains(userId);
    Boolean isPrimaryAdvisor = context.primaryAdvisorUserIds != null &&
      context.primaryAdvisorUserIds.contains(userId) &&
      context.householdId != null;

    if (UserInfoUtils.isHomeOfficeProfile(profileName)) {
      return isOwner || isQueueMember;
    }

    if (
      UserInfoUtils.isBranchUser(profileName, userType) ||
      UserInfoUtils.isSystemAdministratorProfile(profileName)
    ) {
      return isOwner || isQueueMember || isPrimaryAdvisor;
    }

    return false;
  }

  @TestVisible
  private static Boolean isUserId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('005');
  }

  @TestVisible
  private static Boolean isQueueId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('00G');
  }

  private class CaseRecipientContext {
    public Case caseRecord;
    public Id householdId;
    public Id financialAdvisorTeamId;
    public Boolean ownerIsUser;
    public Boolean ownerIsQueue;
    public Id ownerUserId;
    public Set<Id> queueMemberUserIds;
    public Set<Id> primaryAdvisorUserIds;
  }
}