/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Bulk SOQL helpers for notification email content generation.
 */
public without sharing class NotificationEmailBulkQueryService {
  public static Map<Id, String> selectLatestPublishedCommentByCaseId(
    Set<Id> caseIds
  ) {
    Map<Id, String> commentByCaseId = new Map<Id, String>();

    if (caseIds == null || caseIds.isEmpty()) {
      return commentByCaseId;
    }

    for (CaseComment caseComment : [
      SELECT ParentId, CommentBody
      FROM CaseComment
      WHERE ParentId IN :caseIds AND IsPublished = TRUE
      ORDER BY CreatedDate DESC, Id DESC
    ]) {
      if (
        commentByCaseId.containsKey(caseComment.ParentId) ||
        String.isBlank(caseComment.CommentBody)
      ) {
        continue;
      }

      commentByCaseId.put(
        caseComment.ParentId,
        caseComment.CommentBody.trim()
      );
    }

    return commentByCaseId;
  }

  public static Map<Id, String> selectAttendeeSummaryByEventId(
    Set<Id> eventIds
  ) {
    Map<Id, List<String>> attendeeNamesByEventId = new Map<Id, List<String>>();

    if (eventIds == null || eventIds.isEmpty()) {
      return new Map<Id, String>();
    }

    for (EventRelation attendeeRelation : [
      SELECT EventId, Relation.Name
      FROM EventRelation
      WHERE EventId IN :eventIds AND IsInvitee = TRUE
      ORDER BY Relation.Name ASC NULLS LAST
    ]) {
      if (String.isBlank(attendeeRelation.Relation.Name)) {
        continue;
      }

      if (!attendeeNamesByEventId.containsKey(attendeeRelation.EventId)) {
        attendeeNamesByEventId.put(
          attendeeRelation.EventId,
          new List<String>()
        );
      }

      attendeeNamesByEventId.get(attendeeRelation.EventId)
        .add(attendeeRelation.Relation.Name.trim());
    }

    Map<Id, String> summaryByEventId = new Map<Id, String>();

    for (Id eventId : attendeeNamesByEventId.keySet()) {
      List<String> attendeeNames = attendeeNamesByEventId.get(eventId);
      summaryByEventId.put(
        eventId,
        attendeeNames.isEmpty() ? NotificationConstants.DISPLAY_NOT_APPLICABLE : String.join(attendeeNames, ', ')
      );
    }

    return summaryByEventId;
  }

  public static Map<Id, Account> selectAccountsById(Set<Id> accountIds) {
    Map<Id, Account> accountById = new Map<Id, Account>();

    if (accountIds == null || accountIds.isEmpty()) {
      return accountById;
    }

    for (Account accountRecord : [
      SELECT Id, Name, Financial_Advisor_Team__c, Financial_Advisor_Team__r.Name
      FROM Account
      WHERE Id IN :accountIds
    ]) {
      accountById.put(accountRecord.Id, accountRecord);
    }

    return accountById;
  }

  public static Map<Id, Contact> selectContactsById(Set<Id> contactIds) {
    Map<Id, Contact> contactById = new Map<Id, Contact>();

    if (contactIds == null || contactIds.isEmpty()) {
      return contactById;
    }

    for (Contact contactRecord : [
      SELECT Id, Name
      FROM Contact
      WHERE Id IN :contactIds
    ]) {
      contactById.put(contactRecord.Id, contactRecord);
    }

    return contactById;
  }
}