/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class NotificationCaseEmailContentServiceTest {
  @IsTest
  static void buildIncludesLinkedCaseContactHouseholdAndLatestComment() {
    Account household = new Account(Name = 'Case Email Household');
    NotificationTestDataFactory.insertRecord(household);

    Contact contactRecord = new Contact(
      LastName = 'CaseContact',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(contactRecord);

    Case caseRecord = new Case(
      Subject = 'Portfolio Service Request',
      AccountId = household.Id,
      ContactId = contactRecord.Id,
      Status = 'New',
      Origin = 'Phone',
      Due_Date_of_Current_Task__c = Date.today().addDays(7)
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    caseRecord = [
      SELECT Id, Subject, Case_Branch_Name_DisplayName__c
      FROM Case
      WHERE Id = :caseRecord.Id
      LIMIT 1
    ];

    contactRecord = [
      SELECT Id, Name, LastName
      FROM Contact
      WHERE Id = :contactRecord.Id
      LIMIT 1
    ];

    NotificationTestDataFactory.insertRecord(new CaseComment(
      ParentId = caseRecord.Id,
      CommentBody = 'Latest case comment for email body.',
      IsPublished = true
    ));
    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.CHANGE_TYPE_INSERT
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Household__c = household.Id,
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationCaseEmailContentService.ContentResult result = NotificationCaseEmailContentService.build(
      logRecord
    );

    System.assertEquals('New case', result.title);
    System.assert(result.htmlBody.contains('/lightning/r/Case/'));
    System.assert(result.htmlBody.contains('/lightning/r/Contact/'));
    System.assert(result.htmlBody.contains('/lightning/r/Account/'));
    System.assert(result.htmlBody.contains('Case Summary Name'));
    System.assert(result.htmlBody.contains('Change Made'));
    System.assert(result.htmlBody.contains('Assigned To'));
    System.assert(result.htmlBody.contains('Financial Advisor Team'));
    System.assert(result.htmlBody.contains('Due Date'));
    System.assert(result.htmlBody.contains('Case Comments'));
    System.assert(
      result.htmlBody.contains(
        String.isBlank(caseRecord.Case_Branch_Name_DisplayName__c)
          ? caseRecord.Subject
          : caseRecord.Case_Branch_Name_DisplayName__c
      )
    );
    System.assert(result.htmlBody.contains('Portfolio Service Request'));
    System.assert(result.htmlBody.contains('Latest case comment for email body.'));
    System.assert(result.htmlBody.contains(contactRecord.Name), 'Expected linked contact name');
    System.assert(result.htmlBody.contains(household.Name));
    System.assert(result.htmlBody.contains('Case created'));
    System.assertEquals(String.valueOf(caseRecord.Id), result.targetRecordId);
  }

  @IsTest
  static void buildIncludesChangeSummaryForOwnerUpdate() {
    Account household = new Account(Name = 'Case Owner Household');
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

    Case caseRecord = new Case(
      Subject = 'Owner change case',
      AccountId = household.Id,
      Status = 'New',
      OwnerId = currentUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationChangeModels.ChangeContext changeContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    changeContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'OwnerId',
        'Owner',
        String.valueOf(currentUser.Id),
        String.valueOf(assigneeUser.Id),
        currentUser.Name,
        assigneeUser.Name
      )
    );

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Household__c = household.Id,
      Change_Context__c = changeContext.toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationCaseEmailContentService.ContentResult result = NotificationCaseEmailContentService.build(
      logRecord
    );

    System.assertEquals('Case assignment changed', result.title);
    System.assert(
      result.htmlBody.contains(
        '<strong>Owner</strong><br/>Old: ' +
          currentUser.Name +
          '<br/>New: ' +
          assigneeUser.Name
      )
    );
  }

  @IsTest
  static void enrichLogUsesHtmlForEmailChannel() {
    Account household = new Account(Name = 'Digest Case Household');
    NotificationTestDataFactory.insertRecord(household);

    Case caseRecord = new Case(
      Subject = 'Digest Case',
      AccountId = household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    caseRecord = [
      SELECT Id, Subject, Case_Branch_Name_DisplayName__c
      FROM Case
      WHERE Id = :caseRecord.Id
      LIMIT 1
    ];

    Notification_Log__c logRecord = new Notification_Log__c(
      Source_Type__c = NotificationConstants.OBJECT_TYPE_CASE,
      Source_Record_Id__c = String.valueOf(caseRecord.Id),
      Household__c = household.Id,
      Change_Context__c = new NotificationChangeModels.ChangeContext(
          NotificationConstants.OBJECT_TYPE_CASE,
          NotificationConstants.CHANGE_TYPE_INSERT
        )
        .toJson(),
      Channel__c = NotificationConstants.CHANNEL_EMAIL
    );

    NotificationDigestContentService.enrichLog(logRecord);

    System.assertEquals('New case', logRecord.Title__c);
    System.assert(logRecord.Body__c.contains('<table'));
    System.assert(
      logRecord.Body__c.contains(
        String.isBlank(caseRecord.Case_Branch_Name_DisplayName__c)
          ? caseRecord.Subject
          : caseRecord.Case_Branch_Name_DisplayName__c
      )
    );
  }
}