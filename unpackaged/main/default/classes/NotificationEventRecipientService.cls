/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Resolves Event notification recipients by profile-specific eligibility rules.
 *
 * NexS, Advisor, and System Administrator users may qualify via eligible related records
 * plus primary-advisor FA team membership, event creator, or attendee status.
 * Home Office users qualify only as event creator or attendee.
 *
 * Notification_Rule__c records control delivery settings after eligibility passes.
 */
public without sharing class NotificationEventRecipientService {
  @TestVisible
  private static Map<Id, List<Id>> testRecipientOverrides;

  private final Map<Id, Set<Id>> teamIdToPrimaryAdvisorUserIds = new Map<Id, Set<Id>>();

  public List<Id> resolveRecipients(Event eventRecord, Id householdId) {
    if (eventRecord == null || eventRecord.Id == null) {
      return new List<Id>();
    }

    if (Test.isRunningTest() && testRecipientOverrides != null) {
      if (testRecipientOverrides.containsKey(eventRecord.Id)) {
        return new List<Id>(testRecipientOverrides.get(eventRecord.Id));
      }

      if (householdId != null && testRecipientOverrides.containsKey(householdId)) {
        return new List<Id>(testRecipientOverrides.get(householdId));
      }
    }

    EventRecipientContext context = buildContext(eventRecord, householdId);
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

  private EventRecipientContext buildContext(Event eventRecord, Id householdId) {
    EventRecipientContext context = new EventRecipientContext();
    context.eventRecord = eventRecord;
    context.householdId = householdId;
    context.creatorUserId = eventRecord.CreatedById;
    context.attendeeUserIds = selectAttendeeUserIds(eventRecord.Id);

    if (isContactId(eventRecord.WhoId)) {
      context.contactId = eventRecord.WhoId;
      context.contactFinancialAdvisorTeamId = selectContactFinancialAdvisorTeamId(
        eventRecord.WhoId
      );
      if (context.contactFinancialAdvisorTeamId != null) {
        context.teamIds.add(context.contactFinancialAdvisorTeamId);
      }
    }

    if (isAccountId(eventRecord.WhatId)) {
      context.relatedAccount = selectRelatedAccount(eventRecord.WhatId);
      if (context.relatedAccount != null) {
        context.hasEligibleRelatedAccount = isEligibleRelatedAccount(
          context.relatedAccount
        );

        if (context.relatedAccount.Financial_Advisor_Team__c != null) {
          context.teamIds.add(context.relatedAccount.Financial_Advisor_Team__c);
        }

        if (
          context.householdId == null &&
          FscRelAccountRepository.isHouseholdRecordType(context.relatedAccount)
        ) {
          context.householdId = context.relatedAccount.Id;
        }
      }
    }

    if (context.householdId != null) {
      context.hasHouseholdAssociation = true;
      Id householdTeamId = selectHouseholdFinancialAdvisorTeamId(context.householdId);
      if (householdTeamId != null) {
        context.teamIds.add(householdTeamId);
      }
    }

    context.hasContactAssociation = context.contactId != null;

    for (Id teamId : context.teamIds) {
      context.primaryAdvisorUserIds.addAll(selectPrimaryAdvisorUserIds(teamId));
    }

    return context;
  }

  private static Set<Id> collectCandidateUserIds(EventRecipientContext context) {
    Set<Id> candidateUserIds = new Set<Id>();

    if (context.creatorUserId != null) {
      candidateUserIds.add(context.creatorUserId);
    }

    if (context.attendeeUserIds != null) {
      candidateUserIds.addAll(context.attendeeUserIds);
    }

    if (context.primaryAdvisorUserIds != null) {
      candidateUserIds.addAll(context.primaryAdvisorUserIds);
    }

    return candidateUserIds;
  }

  private static Boolean isEligibleRecipient(
    Id userId,
    String profileName,
    EventRecipientContext context
  ) {
    Boolean isCreator = context.creatorUserId == userId;
    Boolean isAttendee = context.attendeeUserIds != null &&
      context.attendeeUserIds.contains(userId);
    Boolean isPrimaryAdvisor = context.primaryAdvisorUserIds != null &&
      context.primaryAdvisorUserIds.contains(userId);
    Boolean hasNexSAssociation = hasNexSEligibleAssociation(context);
    Boolean hasAdvisorAssociation = hasAdvisorEligibleAssociation(context);

    if (UserInfoUtils.isHomeOfficeProfile(profileName)) {
      return isCreator || isAttendee;
    }

    if (UserInfoUtils.isNexSProfile(profileName)) {
      return isCreator ||
        isAttendee ||
        (isPrimaryAdvisor && hasNexSAssociation);
    }

    if (UserInfoUtils.isAdvisorProfile(profileName)) {
      return isCreator ||
        isAttendee ||
        (isPrimaryAdvisor && hasAdvisorAssociation);
    }

    if (UserInfoUtils.isSystemAdministratorProfile(profileName)) {
      return isCreator ||
        isAttendee ||
        (isPrimaryAdvisor && hasNexSAssociation);
    }

    return false;
  }

  private static Boolean hasNexSEligibleAssociation(EventRecipientContext context) {
    return context.hasEligibleRelatedAccount ||
      context.hasHouseholdAssociation ||
      context.hasContactAssociation;
  }

  private static Boolean hasAdvisorEligibleAssociation(EventRecipientContext context) {
    return context.hasEligibleRelatedAccount ||
      context.hasHouseholdAssociation ||
      context.hasContactAssociation;
  }

  private static Boolean isEligibleRelatedAccount(Account account) {
    if (account == null) {
      return false;
    }

    if (FscRelAccountRepository.isHouseholdRecordType(account)) {
      return true;
    }

    if (FscRelAccountRepository.isPersonAccountRecord(account)) {
      return true;
    }

    if (account.RecordType == null) {
      return false;
    }

    return FscRelClientAccountUtils.isClientRecordType(
      account.RecordType.Name,
      account.RecordType.DeveloperName
    );
  }

  private Set<Id> selectAttendeeUserIds(Id eventId) {
    Set<Id> attendeeUserIds = new Set<Id>();

    for (EventRelation attendeeRelation : [
      SELECT RelationId
      FROM EventRelation
      WHERE EventId = :eventId AND IsInvitee = TRUE AND RelationId != NULL
    ]) {
      if (isUserId(attendeeRelation.RelationId)) {
        attendeeUserIds.add(attendeeRelation.RelationId);
      }
    }

    return attendeeUserIds;
  }

  private static Id selectContactFinancialAdvisorTeamId(Id contactId) {
    List<Contact> contacts = [
      SELECT Account.Financial_Advisor_Team__c
      FROM Contact
      WHERE Id = :contactId
      LIMIT 1
    ];

    return contacts.isEmpty() ? null : contacts[0].Account.Financial_Advisor_Team__c;
  }

  private static Account selectRelatedAccount(Id accountId) {
    List<Account> accounts = [
      SELECT
        Id,
        IsPersonAccount,
        PersonContactId,
        Household__c,
        Financial_Advisor_Team__c,
        RecordType.Name,
        RecordType.DeveloperName
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];

    return accounts.isEmpty() ? null : accounts[0];
  }

  private static Id selectHouseholdFinancialAdvisorTeamId(Id householdId) {
    List<Account> households = [
      SELECT Financial_Advisor_Team__c
      FROM Account
      WHERE Id = :householdId
      LIMIT 1
    ];

    return households.isEmpty() ? null : households[0].Financial_Advisor_Team__c;
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
        AND User__r.Profile.Name IN :UserInfoUtils.notificationEligibleProfileNames()
    ]) {
      primaryAdvisorUserIds.add(teamMember.User__c);
    }

    teamIdToPrimaryAdvisorUserIds.put(teamId, primaryAdvisorUserIds);
    return primaryAdvisorUserIds;
  }

  @TestVisible
  private static Boolean isUserId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('005');
  }

  @TestVisible
  private static Boolean isContactId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('003');
  }

  @TestVisible
  private static Boolean isAccountId(Id recordId) {
    return recordId != null && String.valueOf(recordId).startsWith('001');
  }

  private class EventRecipientContext {
    public Event eventRecord;
    public Id householdId;
    public Id creatorUserId;
    public Id contactId;
    public Id contactFinancialAdvisorTeamId;
    public Account relatedAccount;
    public Set<Id> attendeeUserIds = new Set<Id>();
    public Set<Id> teamIds = new Set<Id>();
    public Set<Id> primaryAdvisorUserIds = new Set<Id>();
    public Boolean hasEligibleRelatedAccount = false;
    public Boolean hasHouseholdAssociation = false;
    public Boolean hasContactAssociation = false;
  }
}