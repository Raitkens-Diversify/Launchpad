/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class NotificationChangeDisplayResolverTest {
  @IsTest
  static void resolveDisplayFieldApiNameUsesCaseNumberForCase() {
    System.assertEquals(
      'CaseNumber',
      NotificationChangeDisplayResolver.resolveDisplayFieldApiName('Case')
    );
    System.assertEquals(
      'Name',
      NotificationChangeDisplayResolver.resolveDisplayFieldApiName('Account')
    );
  }

  @IsTest
  static void resolveRecordDisplaysReturnsUserAndAccountNames() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    User otherUser = NotificationTestDataFactory.createStandardUser('displayutil');

    User recipientUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :context.recipientUser.Id
      LIMIT 1
    ];
    User assigneeUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :otherUser.Id
      LIMIT 1
    ];

    Map<Id, String> idToDisplay = NotificationChangeDisplayResolver.resolveRecordDisplays(
      new Set<Id>{ recipientUser.Id, context.household.Id }
    );

    System.assertEquals(recipientUser.Name, idToDisplay.get(recipientUser.Id));
    System.assertEquals(context.household.Name, idToDisplay.get(context.household.Id));
    System.assertEquals(
      assigneeUser.Name,
      NotificationChangeDisplayResolver.resolveRecordDisplays(
          new Set<Id>{ assigneeUser.Id }
        )
        .get(assigneeUser.Id)
    );
  }

  @IsTest
  static void resolveRecordDisplaysUsesCaseNumberForCase() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Case caseRecord = new Case(
      Subject = 'Case display test',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    caseRecord = [
      SELECT Id, CaseNumber
      FROM Case
      WHERE Id = :caseRecord.Id
      LIMIT 1
    ];

    Map<Id, String> idToDisplay = NotificationChangeDisplayResolver.resolveRecordDisplays(
      new Set<Id>{ caseRecord.Id }
    );

    System.assertEquals(caseRecord.CaseNumber, idToDisplay.get(caseRecord.Id));
  }

  @IsTest
  static void enrichChangeContextResolvesUnresolvedReferenceIds() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    User otherUser = NotificationTestDataFactory.createStandardUser('changeutil');

    User recipientUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :context.recipientUser.Id
      LIMIT 1
    ];
    User assigneeUser = [
      SELECT Id, Name
      FROM User
      WHERE Id = :otherUser.Id
      LIMIT 1
    ];

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'OwnerId',
        'Assigned To',
        String.valueOf(recipientUser.Id),
        String.valueOf(assigneeUser.Id),
        String.valueOf(recipientUser.Id),
        String.valueOf(assigneeUser.Id)
      )
    );

    NotificationChangeDisplayResolver.enrichChangeContext(changeContext);

    System.assertEquals(recipientUser.Name, changeContext.changedFields[0].oldDisplay);
    System.assertEquals(assigneeUser.Name, changeContext.changedFields[0].newDisplay);
  }

  @IsTest
  static void enrichChangeContextIgnoresPlainTextValuesThatMatchDisplay() {
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'Subject',
        'Subject',
        'Original subject',
        'Updated subject',
        'Original subject',
        'Updated subject'
      )
    );

    NotificationChangeDisplayResolver.enrichChangeContext(changeContext);

    System.assertEquals('Original subject', changeContext.changedFields[0].oldDisplay);
    System.assertEquals('Updated subject', changeContext.changedFields[0].newDisplay);
  }
}