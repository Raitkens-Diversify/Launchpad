/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-08
 *
 * Resolves Case notification recipients by profile-specific ownership eligibility.
 *
 * Branch and System Administrator users receive Case notifications when they own
 * the Case, are members of the owning queue, or are active FA team members on
 * the household team. Home Office users receive only as owner or queue member.
 * The Case creator never receives a Case notification.
 *
 * This service does not read Notification_Rule__c records. After eligibility,
 * NotificationPreferenceService resolves the active Case rule before
 * NotificationRuleLogService creates logs.
 */
public without sharing class NotificationCaseRecipientService {
  @TestVisible
  private static Map<Id, List<Id>> testRecipientOverrides;

  private final Map<Id, Id> householdIdToTeamId = new Map<Id, Id>();
  private final Map<Id, Set<Id>> teamIdToMemberUserIds = new Map<Id, Set<Id>>();
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

    return excludeCreator(caseRecord, eligibleRecipientIds);
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
      context.faTeamMemberUserIds = selectFaTeamMemberUserIds(
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

  private Set<Id> selectFaTeamMemberUserIds(Id teamId) {
    if (teamIdToMemberUserIds.containsKey(teamId)) {
      return teamIdToMemberUserIds.get(teamId);
    }

    Set<Id> memberUserIds = NotificationRecipientUserRepository.selectEligibleActiveMemberUserIds(
      teamId
    );
    teamIdToMemberUserIds.put(teamId, memberUserIds);
    return memberUserIds;
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

    if (context.faTeamMemberUserIds != null) {
      candidateUserIds.addAll(context.faTeamMemberUserIds);
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
    Boolean isFaTeamMember = context.faTeamMemberUserIds != null &&
      context.faTeamMemberUserIds.contains(userId);

    if (UserInfoUtils.isHomeOfficeProfile(profileName)) {
      return isOwner || isQueueMember;
    }

    if (
      UserInfoUtils.isBranchUser(profileName, userType) ||
      UserInfoUtils.isSystemAdministratorProfile(profileName)
    ) {
      return isOwner || isQueueMember || isFaTeamMember;
    }

    return false;
  }

  @TestVisible
  private static List<Id> excludeCreator(Case caseRecord, List<Id> recipientIds) {
    if (recipientIds == null || recipientIds.isEmpty()) {
      return new List<Id>();
    }

    Id creatorUserId = resolveCreatorUserId(caseRecord);
    if (creatorUserId == null) {
      return recipientIds;
    }

    List<Id> recipientIdsExcludingCreator = new List<Id>();
    for (Id recipientId : recipientIds) {
      if (recipientId != creatorUserId) {
        recipientIdsExcludingCreator.add(recipientId);
      }
    }

    return recipientIdsExcludingCreator;
  }

  private static Id resolveCreatorUserId(Case caseRecord) {
    if (caseRecord == null) {
      return null;
    }

    if (isUserId(caseRecord.CreatedById)) {
      return caseRecord.CreatedById;
    }

    if (caseRecord.Id == null) {
      return UserInfo.getUserId();
    }

    List<Case> createdByCases = [
      SELECT CreatedById
      FROM Case
      WHERE Id = :caseRecord.Id
      LIMIT 1
    ];
    if (createdByCases.isEmpty() || !isUserId(createdByCases[0].CreatedById)) {
      return UserInfo.getUserId();
    }

    return createdByCases[0].CreatedById;
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
    public Set<Id> faTeamMemberUserIds;
  }
}