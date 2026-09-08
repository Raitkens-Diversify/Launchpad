/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-07
 *
 * Resolves Task notification recipients by Assigned To.
 *
 * Insert and Assigned To updates notify the Assigned To user when they have an
 * eligible profile.
 *
 * No Task notification is sent when Assigned To is a queue, Assigned To is
 * Unassigned, the Case modifier is the Assigned To user, or the Task creator
 * is the Assigned To user.
 *
 * Notification_Rule__c records control delivery settings after eligibility passes.
 */
public without sharing class NotificationTaskRecipientService {
  @TestVisible
  private static Map<Id, List<Id>> testRecipientOverrides;

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

    return resolveAssigneeOnlyRecipients(taskRecord, null);
  }

  public List<Id> resolveAssigneeOnlyRecipients(
    Task taskRecord,
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (taskRecord == null) {
      return new List<Id>();
    }

    List<Id> testOverrideRecipientIds = resolveTestRecipientOverride(taskRecord);
    if (testOverrideRecipientIds != null) {
      return testOverrideRecipientIds;
    }

    if (shouldSuppressAssignedToNotification(taskRecord, changeContext)) {
      return new List<Id>();
    }

    if (!isUserId(taskRecord.OwnerId)) {
      return new List<Id>();
    }

    return selectEligibleRecipientIds(new Set<Id>{ taskRecord.OwnerId });
  }

  public List<Id> applyActorSuppression(
    Task taskRecord,
    List<Id> recipientIds,
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (recipientIds == null || recipientIds.isEmpty() || taskRecord == null) {
      return new List<Id>();
    }

    if (shouldSuppressAssignedToNotification(taskRecord, changeContext)) {
      return new List<Id>();
    }

    return excludeCreatorRecipients(
      taskRecord,
      excludeSuppressedUsers(taskRecord, changeContext, recipientIds)
    );
  }

  public static List<Id> excludeCreatorRecipients(
    Task taskRecord,
    List<Id> recipientIds
  ) {
    return excludeCreator(taskRecord, recipientIds);
  }

  private static Id resolveActorUserId(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    if (changeContext != null && !String.isBlank(changeContext.changedByUserId)) {
      return (Id) changeContext.changedByUserId;
    }

    return UserInfo.getUserId();
  }

  private List<Id> resolveTestRecipientOverride(Task taskRecord) {
    if (!Test.isRunningTest() || testRecipientOverrides == null || taskRecord == null) {
      return null;
    }

    if (taskRecord.Id != null && testRecipientOverrides.containsKey(taskRecord.Id)) {
      return new List<Id>(testRecipientOverrides.get(taskRecord.Id));
    }

    if (taskRecord.WhatId != null && testRecipientOverrides.containsKey(taskRecord.WhatId)) {
      return new List<Id>(testRecipientOverrides.get(taskRecord.WhatId));
    }

    return null;
  }

  private Boolean shouldSuppressAssignedToNotification(
    Task taskRecord,
    NotificationChangeModels.ChangeContext changeContext
  ) {
    Id actorUserId = resolveActorUserId(changeContext);
    Id creatorUserId = resolveCreatorUserId(taskRecord);

    if (isAssignedToQueue(taskRecord)) {
      return true;
    }

    if (isUserId(taskRecord.OwnerId)) {
      if (actorUserId != null && actorUserId == taskRecord.OwnerId) {
        return true;
      }

      return isInsert(changeContext) &&
        creatorUserId != null &&
        creatorUserId == taskRecord.OwnerId;
    }

    return true;
  }

  public static Boolean isAssignedToQueue(Task taskRecord) {
    return taskRecord != null && isQueueId(taskRecord.OwnerId);
  }

  private List<Id> excludeSuppressedUsers(
    Task taskRecord,
    NotificationChangeModels.ChangeContext changeContext,
    List<Id> recipientIds
  ) {
    Set<Id> suppressedUserIds = new Set<Id>();
    Id actorUserId = resolveActorUserId(changeContext);
    Id creatorUserId = resolveCreatorUserId(taskRecord);

    if (actorUserId != null) {
      suppressedUserIds.add(actorUserId);
    }
    if (creatorUserId != null) {
      suppressedUserIds.add(creatorUserId);
    }

    List<Id> filteredRecipientIds = new List<Id>();
    for (Id recipientId : recipientIds) {
      if (!suppressedUserIds.contains(recipientId)) {
        filteredRecipientIds.add(recipientId);
      }
    }

    return filteredRecipientIds;
  }

  private static List<Id> excludeCreator(Task taskRecord, List<Id> recipientIds) {
    Id creatorUserId = resolveCreatorUserId(taskRecord);
    if (creatorUserId == null || recipientIds == null || recipientIds.isEmpty()) {
      return recipientIds == null ? new List<Id>() : recipientIds;
    }

    List<Id> recipientIdsExcludingCreator = new List<Id>();
    for (Id recipientId : recipientIds) {
      if (recipientId != creatorUserId) {
        recipientIdsExcludingCreator.add(recipientId);
      }
    }

    return recipientIdsExcludingCreator;
  }

  private static Id resolveCreatorUserId(Task taskRecord) {
    if (taskRecord == null) {
      return null;
    }

    if (isUserId(taskRecord.CreatedById)) {
      return taskRecord.CreatedById;
    }

    if (taskRecord.Id == null) {
      return UserInfo.getUserId();
    }

    List<Task> createdByTasks = [
      SELECT CreatedById
      FROM Task
      WHERE Id = :taskRecord.Id
      LIMIT 1
    ];
    if (createdByTasks.isEmpty() || !isUserId(createdByTasks[0].CreatedById)) {
      return UserInfo.getUserId();
    }

    return createdByTasks[0].CreatedById;
  }

  private static Boolean isInsert(
    NotificationChangeModels.ChangeContext changeContext
  ) {
    return changeContext == null ||
      String.isBlank(changeContext.triggerType) ||
      NotificationConstants.CHANGE_TYPE_INSERT.equalsIgnoreCase(
        changeContext.triggerType
      );
  }

  private static List<Id> selectEligibleRecipientIds(Set<Id> userIds) {
    if (userIds == null || userIds.isEmpty()) {
      return new List<Id>();
    }

    Map<Id, User> eligibleUsersById = NotificationRecipientUserRepository.selectEligibleUsersById(
      userIds
    );
    List<Id> eligibleRecipientIds = new List<Id>();
    for (Id userId : userIds) {
      if (eligibleUsersById.containsKey(userId)) {
        eligibleRecipientIds.add(userId);
      }
    }

    return eligibleRecipientIds;
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
}