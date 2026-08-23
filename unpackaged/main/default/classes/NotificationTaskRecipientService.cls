/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Resolves Task notification recipients by profile-specific eligibility rules.
 *
 * NexS, Advisor, and System Administrator users may qualify when a Task is assigned to them,
 * linked to a Case they own or submitted, linked to a Case on their FA team,
 * or linked to a Household where they are the primary advisor.
 *
 * Home Office users qualify when a Task is assigned to them or linked to a Case
 * they own or that is owned by a queue they belong to.
 *
 * NexS, Advisor, and System Administrator users also qualify when linked to a
 * Case they own, submitted, FA team serves, or a queue they belong to owns.
 *
 * Notification_Rule__c records control delivery settings after eligibility passes.
 */
public without sharing class NotificationTaskRecipientService {
  @TestVisible
  private static Map<Id, List<Id>> testRecipientOverrides;

  private final Map<Id, Id> householdIdToTeamId = new Map<Id, Id>();
  private final Map<Id, Set<Id>> teamIdToPrimaryAdvisorUserIds = new Map<Id, Set<Id>>();
  private final Map<Id, Set<Id>> teamIdToActiveMemberUserIds = new Map<Id, Set<Id>>();
  private final Map<Id, Set<Id>> queueIdToMemberUserIds = new Map<Id, Set<Id>>();

  public List<Id> resolveRecipients(Task taskRecord, Id householdId) {
    if (taskRecord == null || taskRecord.Id == null) {
      return new List<Id>();
    }

    if (Test.isRunningTest() && testRecipientOverrides != null) {
      if (testRecipientOverrides.containsKey(taskRecord.Id)) {
        return new List<Id>(testRecipientOverrides.get(taskRecord.Id));
      }

      if (householdId != null && testRecipientOverrides.containsKey(householdId)) {
        return new List<Id>(testRecipientOverrides.get(householdId));
      }
    }

    TaskRecipientContext context = buildContext(taskRecord, householdId);
    Set<Id> candidateUserIds = collectCandidateUserIds(context);
    if (candidateUserIds.isEmpty()) {
      return new List<Id>();
    }

    Map<Id, String> userIdToProfileName = NotificationRecipientUserRepository.selectEligibleProfileNameByUserId(
      candidateUserIds
    );
    List<Id> eligibleRecipientIds = new List<Id>();

    for (Id userId : candidateUserIds) {
      String profileName = userIdToProfileName.get(userId);
      if (profileName == null) {
        continue;
      }

      if (isEligibleRecipient(userId, profileName, context)) {
        eligibleRecipientIds.add(userId);
      }
    }

    return eligibleRecipientIds;
  }

  private TaskRecipientContext buildContext(Task taskRecord, Id householdId) {
    TaskRecipientContext context = new TaskRecipientContext();
    context.taskRecord = taskRecord;
    context.householdId = householdId;
    context.hasHouseholdAssociation = householdId != null;

    if (isUserId(taskRecord.OwnerId)) {
      context.assigneeUserId = taskRecord.OwnerId;
    }

    if (isCaseId(taskRecord.WhatId)) {
      context.relatedCase = selectRelatedCase(taskRecord.WhatId);
      context.hasCaseAssociation = context.relatedCase != null;

      if (context.relatedCase != null) {
        populateCaseContext(context, context.relatedCase);
      }
    } else if (isAccountId(taskRecord.WhatId)) {
      context.hasHouseholdAssociation = true;
      if (context.householdId == null) {
        context.householdId = taskRecord.WhatId;
      }
    }

    if (context.householdId != null) {
      context.householdFinancialAdvisorTeamId = selectHouseholdFinancialAdvisorTeamId(
        context.householdId
      );

      if (context.householdFinancialAdvisorTeamId != null) {
        context.householdPrimaryAdvisorUserIds = selectPrimaryAdvisorUserIds(
          context.householdFinancialAdvisorTeamId
        );
      }
    }

    return context;
  }

  private void populateCaseContext(TaskRecipientContext context, Case relatedCase) {
    context.caseSubmitterUserId = relatedCase.CreatedById;

    if (isUserId(relatedCase.OwnerId)) {
      context.caseOwnerUserId = relatedCase.OwnerId;
    } else if (isQueueId(relatedCase.OwnerId)) {
      context.caseOwnerIsQueue = true;
      context.caseQueueMemberUserIds = selectQueueMemberUserIds(relatedCase.OwnerId);
    }

    if (relatedCase.Financial_Advisor_Team__c != null) {
      context.caseFinancialAdvisorTeamId = relatedCase.Financial_Advisor_Team__c;
      context.caseFaTeamMemberUserIds = selectActiveMemberUserIds(
        relatedCase.Financial_Advisor_Team__c
      );
    }
  }

  private static Set<Id> collectCandidateUserIds(TaskRecipientContext context) {
    Set<Id> candidateUserIds = new Set<Id>();

    if (context.assigneeUserId != null) {
      candidateUserIds.add(context.assigneeUserId);
    }

    if (context.caseOwnerUserId != null) {
      candidateUserIds.add(context.caseOwnerUserId);
    }

    if (context.caseSubmitterUserId != null) {
      candidateUserIds.add(context.caseSubmitterUserId);
    }

    if (context.caseQueueMemberUserIds != null) {
      candidateUserIds.addAll(context.caseQueueMemberUserIds);
    }

    if (context.caseFaTeamMemberUserIds != null) {
      candidateUserIds.addAll(context.caseFaTeamMemberUserIds);
    }

    if (context.householdPrimaryAdvisorUserIds != null) {
      candidateUserIds.addAll(context.householdPrimaryAdvisorUserIds);
    }

    return candidateUserIds;
  }

  private static Boolean isEligibleRecipient(
    Id userId,
    String profileName,
    TaskRecipientContext context
  ) {
    Boolean isAssignee = context.assigneeUserId == userId;
    Boolean isCaseOwner = context.caseOwnerUserId == userId;
    Boolean isCaseSubmitter = context.caseSubmitterUserId == userId;
    Boolean isCaseQueueMember = context.caseQueueMemberUserIds != null &&
      context.caseQueueMemberUserIds.contains(userId);
    Boolean isCaseFaTeamMember = context.caseFaTeamMemberUserIds != null &&
      context.caseFaTeamMemberUserIds.contains(userId);
    Boolean isPrimaryAdvisorOnHousehold = context.householdPrimaryAdvisorUserIds != null &&
      context.householdPrimaryAdvisorUserIds.contains(userId) &&
      context.hasHouseholdAssociation;

    if (NotificationConstants.isHomeOfficeProfile(profileName)) {
      return isAssignee ||
        (context.hasCaseAssociation && (isCaseOwner || isCaseQueueMember));
    }

    if (NotificationConstants.isNexSProfile(profileName)) {
      return isAssignee ||
        isPrimaryAdvisorOnHousehold ||
        (context.hasCaseAssociation &&
        (isCaseOwner || isCaseSubmitter || isCaseFaTeamMember || isCaseQueueMember));
    }

    if (NotificationConstants.isAdvisorProfile(profileName)) {
      return isAssignee ||
        isPrimaryAdvisorOnHousehold ||
        (context.hasCaseAssociation &&
        (isCaseOwner || isCaseSubmitter || isCaseFaTeamMember || isCaseQueueMember));
    }

    if (NotificationConstants.isSystemAdministratorProfile(profileName)) {
      return isAssignee ||
        isPrimaryAdvisorOnHousehold ||
        (context.hasCaseAssociation &&
        (isCaseOwner || isCaseSubmitter || isCaseFaTeamMember || isCaseQueueMember));
    }

    return false;
  }

  private Case selectRelatedCase(Id caseId) {
    List<Case> cases = [
      SELECT Id, OwnerId, CreatedById, Financial_Advisor_Team__c, AccountId
      FROM Case
      WHERE Id = :caseId
      LIMIT 1
    ];

    return cases.isEmpty() ? null : cases[0];
  }

  private Id selectHouseholdFinancialAdvisorTeamId(Id householdId) {
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

    for (Financial_Advisor_Team_Member__c teamMember : [
      SELECT User__c
      FROM Financial_Advisor_Team_Member__c
      WHERE
        Financial_Advisor_Team__c = :teamId
        AND Primary__c = TRUE
        AND Active__c = TRUE
        AND User__c != NULL
        AND User__r.Profile.Name IN :NotificationConstants.notificationEligibleProfileNames()
    ]) {
      primaryAdvisorUserIds.add(teamMember.User__c);
    }

    teamIdToPrimaryAdvisorUserIds.put(teamId, primaryAdvisorUserIds);
    return primaryAdvisorUserIds;
  }

  private Set<Id> selectActiveMemberUserIds(Id teamId) {
    if (teamIdToActiveMemberUserIds.containsKey(teamId)) {
      return teamIdToActiveMemberUserIds.get(teamId);
    }

    Set<Id> activeMemberUserIds = NotificationRecipientUserRepository.selectEligibleActiveMemberUserIds(
      teamId
    );
    teamIdToActiveMemberUserIds.put(teamId, activeMemberUserIds);
    return activeMemberUserIds;
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

  @TestVisible
  private static Boolean isUserId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('005');
  }

  @TestVisible
  private static Boolean isQueueId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('00G');
  }

  @TestVisible
  private static Boolean isCaseId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('500');
  }

  @TestVisible
  private static Boolean isAccountId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('001');
  }

  private class TaskRecipientContext {
    public Task taskRecord;
    public Id householdId;
    public Boolean hasHouseholdAssociation = false;
    public Boolean hasCaseAssociation = false;
    public Id assigneeUserId;
    public Case relatedCase;
    public Id caseOwnerUserId;
    public Boolean caseOwnerIsQueue = false;
    public Set<Id> caseQueueMemberUserIds = new Set<Id>();
    public Id caseSubmitterUserId;
    public Id caseFinancialAdvisorTeamId;
    public Set<Id> caseFaTeamMemberUserIds = new Set<Id>();
    public Id householdFinancialAdvisorTeamId;
    public Set<Id> householdPrimaryAdvisorUserIds = new Set<Id>();
  }
}