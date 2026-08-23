/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationEmailBulkQueryServiceTest {
  @IsTest
  static void selectLatestPublishedCommentByCaseIdReturnsNewestCommentPerCase() {
    Account household = new Account(Name = 'Bulk Comment Household');
    insert household;

    Case firstCase = new Case(Subject = 'Case A', AccountId = household.Id);
    Case secondCase = new Case(Subject = 'Case B', AccountId = household.Id);
    insert new List<Case>{ firstCase, secondCase };

    insert new CaseComment(
      ParentId = firstCase.Id,
      CommentBody = 'Older A',
      IsPublished = true
    );
    CaseComment latestOnFirstCase = new CaseComment(
      ParentId = firstCase.Id,
      CommentBody = 'Latest A',
      IsPublished = true
    );
    insert latestOnFirstCase;

    insert new CaseComment(
      ParentId = secondCase.Id,
      CommentBody = 'Only B',
      IsPublished = true
    );

    Map<Id, String> commentByCaseId = NotificationEmailBulkQueryService.selectLatestPublishedCommentByCaseId(
      new Set<Id>{ firstCase.Id, secondCase.Id }
    );

    System.assertEquals('Latest A', commentByCaseId.get(firstCase.Id));
    System.assertEquals('Only B', commentByCaseId.get(secondCase.Id));
  }

  @IsTest
  static void selectAttendeeSummaryByEventIdJoinsInviteeNames() {
    Account household = new Account(Name = 'Bulk Event Household');
    insert household;

    Contact attendeeOne = new Contact(LastName = 'Alpha', AccountId = household.Id);
    Contact attendeeTwo = new Contact(LastName = 'Beta', AccountId = household.Id);
    insert new List<Contact>{ attendeeOne, attendeeTwo };

    Event eventRecord = new Event(
      Subject = 'Bulk attendee event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    insert eventRecord;

    insert new List<EventRelation>{
      new EventRelation(
        EventId = eventRecord.Id,
        RelationId = attendeeOne.Id,
        Status = 'Accepted',
        IsInvitee = true
      ),
      new EventRelation(
        EventId = eventRecord.Id,
        RelationId = attendeeTwo.Id,
        Status = 'Accepted',
        IsInvitee = true
      )
    };

    Map<Id, String> summaryByEventId = NotificationEmailBulkQueryService.selectAttendeeSummaryByEventId(
      new Set<Id>{ eventRecord.Id }
    );

    System.assert(summaryByEventId.get(eventRecord.Id).contains('Alpha'));
    System.assert(summaryByEventId.get(eventRecord.Id).contains('Beta'));
  }

  @IsTest
  static void selectAccountsAndContactsByIdReturnsRequestedRecords() {
    Account household = new Account(Name = 'Bulk Account');
    insert household;

    Contact contactRecord = new Contact(LastName = 'BulkContact', AccountId = household.Id);
    insert contactRecord;

    Map<Id, Account> accountById = NotificationEmailBulkQueryService.selectAccountsById(
      new Set<Id>{ household.Id }
    );
    Map<Id, Contact> contactById = NotificationEmailBulkQueryService.selectContactsById(
      new Set<Id>{ contactRecord.Id }
    );

    System.assertEquals('Bulk Account', accountById.get(household.Id).Name);
    System.assertEquals('BulkContact', contactById.get(contactRecord.Id).Name);
    System.assertEquals(
      0,
      NotificationEmailBulkQueryService.selectAccountsById(null).size()
    );
  }
}