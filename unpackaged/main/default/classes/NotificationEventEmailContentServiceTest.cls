/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class NotificationEventEmailContentServiceTest {
  @IsTest
  static void buildIncludesLinkedEventContactAndHouseholdColumns() {
    Account household = new Account(Name = 'Event Household');
    NotificationTestDataFactory.insertRecord(household);

    Contact contactRecord = new Contact(
      LastName = 'Simpson',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(contactRecord);

    Event eventRecord = new Event(
      Subject = 'Portfolio Review Meeting',
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      DurationInMinutes = 60,
      WhoId = contactRecord.Id,
      WhatId = household.Id,
      Description = 'Quarterly portfolio review.'
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Contact attendeeContact = new Contact(
      LastName = 'Attendee',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(attendeeContact);

    NotificationTestDataFactory.insertRecord(new EventRelation(
      EventId = eventRecord.Id,
      RelationId = attendeeContact.Id,
      Status = 'Accepted',
      IsInvitee = true
    ));
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventRecord.Id),
      Household__c = household.Id,
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationEventEmailContentService.ContentResult result = NotificationEventEmailContentService.build(
      logRecord
    );

    System.assertEquals('New event', result.title);
    System.assert(result.htmlBody.contains('/lightning/r/Event/'));
    System.assert(result.htmlBody.contains('/lightning/r/Contact/'));
    System.assert(result.htmlBody.contains('/lightning/r/Account/'));
    System.assert(result.htmlBody.contains('Change Made'));
    System.assert(result.htmlBody.contains('Assigned To'));
    System.assert(result.htmlBody.contains('Attendees'));
    System.assert(result.htmlBody.contains('Start Date/Time'));
    System.assert(result.htmlBody.contains('End Date/Time'));
    System.assert(result.htmlBody.contains('Contact'));
    System.assert(result.htmlBody.contains('Household'));
    System.assert(result.htmlBody.contains('Description'));
    System.assert(result.htmlBody.contains('Portfolio Review Meeting'));
    System.assert(result.htmlBody.contains('Quarterly portfolio review.'));
    System.assert(result.htmlBody.contains('Event created'));
    System.assert(result.htmlBody.contains(contactRecord.LastName));
    System.assert(result.htmlBody.contains(attendeeContact.LastName));
    System.assert(result.htmlBody.contains(household.Name));
    System.assert(result.plainBody.contains('Contact: ' + contactRecord.LastName));
    System.assert(result.plainBody.contains('Household: ' + household.Name));
    System.assertEquals(String.valueOf(eventRecord.Id), result.targetRecordId);
  }

  @IsTest
  static void buildIncludesChangeSummaryForOwnerUpdate() {
    Account household = new Account(Name = 'Owner Change Household');
    NotificationTestDataFactory.insertRecord(household);

    User currentUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    User assigneeUser = [
      SELECT Id, Name
      FROM User
      WHERE IsActive = TRUE AND Id != :currentUser.Id
      LIMIT 1
    ];

    Event eventRecord = new Event(
      Subject = 'Advisor Check-in',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      WhatId = household.Id,
      OwnerId = currentUser.Id
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'OwnerId',
        'Assigned to',
        String.valueOf(currentUser.Id),
        String.valueOf(assigneeUser.Id),
        currentUser.Name,
        assigneeUser.Name
      )
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventRecord.Id),
      Household__c = household.Id,
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationEventEmailContentService.ContentResult result = NotificationEventEmailContentService.build(
      logRecord
    );

    System.assertEquals('Event assignment changed', result.title);
    System.assert(
      result.htmlBody.contains(
        '<strong>Assigned to</strong><br/>Old: ' +
          currentUser.Name +
          '<br/>New: ' +
          assigneeUser.Name
      )
    );
  }

  @IsTest
  static void enrichLogUsesHtmlForEmailChannel() {
    Account household = new Account(Name = 'Digest Event Household');
    NotificationTestDataFactory.insertRecord(household);

    Event eventRecord = new Event(
      Subject = 'Digest Event',
      StartDateTime = Datetime.now().addDays(3),
      EndDateTime = Datetime.now().addDays(3).addHours(1),
      DurationInMinutes = 60,
      WhatId = household.Id
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventRecord.Id),
      Household__c = household.Id,
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_EVENT,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationDigestContentService.enrichLog(logRecord);

    System.assertEquals('New event', logRecord.Title__c);
    System.assert(logRecord.Body__c.contains('<table'));
    System.assert(logRecord.Body__c.contains('Digest Event'));
  }

  @IsTest
  static void buildUsesEmailContentCacheForRepeatedSourceRecord() {
    NotificationEmailContentCache.clear();
    Account household = new Account(Name = 'Cached Event Household');
    NotificationTestDataFactory.insertRecord(household);

    Event eventRecord = new Event(
      Subject = 'Cached Event',
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(3),
      EndDateTime = Datetime.now().addDays(3).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_EVENT,
      Source_Record_Id__c = String.valueOf(eventRecord.Id),
      Household__c = household.Id,
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_EVENT,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationEventEmailContentService.ContentResult firstResult = NotificationEventEmailContentService.build(
      logRecord
    );
    NotificationEventEmailContentService.ContentResult secondResult = NotificationEventEmailContentService.build(
      logRecord
    );

    String cacheKey = NotificationEmailContentCache.buildSourceKey(
      NotificationConstants.OBJECT_TYPE_EVENT,
      String.valueOf(eventRecord.Id)
    );

    System.assertNotEquals(null, NotificationEmailContentCache.get(cacheKey));
    System.assertEquals(firstResult.title, secondResult.title);
    NotificationEmailContentCache.clear();
  }
}