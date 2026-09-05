/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-17
 *
 * Pit stop task notifications: immediate email and in-app for branch or home office
 * task assignees or queue members when the related Case is on a supported client account.
 */
public without sharing class NotificationTaskPitStopService {
  public static Boolean isEligiblePitStopTask(Task taskRecord) {
    if (taskRecord == null || !NotificationConstants.isPitStopTask(taskRecord)) {
      return false;
    }

    if (!isCaseId(taskRecord.WhatId)) {
      return false;
    }

    return isSupportedCase(selectRelatedCase(taskRecord.WhatId));
  }

  public static List<Id> resolveRecipients(Task taskRecord) {
    if (!isEligiblePitStopTask(taskRecord)) {
      return new List<Id>();
    }

    Set<Id> candidateUserIds = new Set<Id>();

    if (isUserId(taskRecord.OwnerId)) {
      candidateUserIds.add(taskRecord.OwnerId);
    } else if (isQueueId(taskRecord.OwnerId)) {
      candidateUserIds.addAll(selectQueueMemberUserIds(taskRecord.OwnerId));
    }

    if (candidateUserIds.isEmpty()) {
      return new List<Id>();
    }

    Map<Id, String> profileNameByUserId = NotificationRecipientUserRepository.selectPitStopRecipientProfileNameByUserId(
      candidateUserIds,
      taskRecord
    );
    List<Id> recipientIds = new List<Id>();

    for (Id userId : candidateUserIds) {
      if (profileNameByUserId.containsKey(userId)) {
        recipientIds.add(userId);
      }
    }

    return recipientIds;
  }

  public static Boolean isSupportedCase(Case caseRecord) {
    if (caseRecord == null || caseRecord.AccountId == null) {
      return false;
    }

    List<Account> accounts = [
      SELECT Id, RecordType.Name, RecordType.DeveloperName
      FROM Account
      WHERE Id = :caseRecord.AccountId
      LIMIT 1
    ];

    if (accounts.isEmpty()) {
      return false;
    }

    return isSupportedAccount(accounts[0]);
  }

  @TestVisible
  private static Boolean isSupportedAccount(Account accountRecord) {
    if (accountRecord == null) {
      return false;
    }

    if (FscRelAccountRepository.isHouseholdRecordType(accountRecord)) {
      return true;
    }

    if (accountRecord.RecordType == null) {
      return false;
    }

    return FscRelClientAccountUtils.isClientRecordType(
      accountRecord.RecordType.Name,
      accountRecord.RecordType.DeveloperName
    );
  }

  private static Case selectRelatedCase(Id caseId) {
    List<Case> cases = [
      SELECT Id, AccountId
      FROM Case
      WHERE Id = :caseId
      LIMIT 1
    ];

    return cases.isEmpty() ? null : cases[0];
  }

  private static Set<Id> selectQueueMemberUserIds(Id queueId) {
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
}