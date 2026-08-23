/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-08
 */
@IsTest
private class ActivityTimelineControllerTest {
  @IsTest
  static void getTimelineDataReturnsHouseholdActivities() {
    Account household = new Account(Name = 'Timeline Test Household');
    insert household;

    Contact contactRecord = new Contact(
      LastName = 'Timeline',
      AccountId = household.Id
    );
    insert contactRecord;

    Case caseRecord = new Case(
      Subject = 'Work - Financial plan update',
      AccountId = household.Id,
      Status = 'In Progress',
      Origin = 'Service Request'
    );
    insert caseRecord;

    Task taskRecord = new Task(
      Subject = 'Cadence - Monthly check-in',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert taskRecord;

    Event eventRecord = new Event(
      Subject = 'Quarterly review meeting',
      WhatId = household.Id,
      WhoId = contactRecord.Id,
      Type = 'Meeting',
      StartDateTime = Datetime.now().addDays(-1),
      EndDateTime = Datetime.now().addDays(-1).addHours(1),
      DurationInMinutes = 60
    );
    insert eventRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );
    Test.stopTest();

    System.assertNotEquals(null, data.activities, 'Activities should be returned.');
    System.assert(data.activities.size() >= 3, 'Expected case, task, and event.');
    System.assertEquals(
      2,
      data.categoryCounts.get('Work'),
      'Case and task should be counted under Work.'
    );
    System.assertEquals(
      1,
      data.categoryCounts.get('Interactions'),
      'Meeting event should be counted under Interactions.'
    );

    ActivityTimelineModels.ActivityItem eventItem;
    for (ActivityTimelineModels.ActivityItem item : data.activities) {
      if (item.activityType == 'Meeting') {
        eventItem = item;
        break;
      }
    }

    System.assertNotEquals(null, eventItem, 'Meeting event should be returned.');
    System.assertNotEquals(
      null,
      eventItem.ownerId,
      'Event owner id should be exposed for summary messaging.'
    );
    System.assertEquals(
      1,
      eventItem.relatedParticipants.size(),
      'Event Who contact should be exposed as a related participant.'
    );
    System.assertEquals(
      contactRecord.Id,
      Id.valueOf(eventItem.relatedParticipants[0].id),
      'Related participant should match the event Who contact.'
    );
    System.assertEquals(
      'Meeting',
      eventItem.activityType,
      'Meeting events should normalize to Meeting activity type.'
    );
    System.assertEquals(
      'standard:event',
      eventItem.icon,
      'Meeting events should use the event icon.'
    );
  }

  @IsTest
  static void getTimelineDataMapsCallTaskToPhoneCallActivity() {
    Account household = new Account(Name = 'Call Task Household');
    insert household;

    Task callTask = new Task(
      Subject = 'Call',
      TaskSubtype = 'Call',
      WhatId = household.Id,
      Status = 'Completed',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert callTask;

    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );

    ActivityTimelineModels.ActivityItem callItem;
    for (ActivityTimelineModels.ActivityItem item : data.activities) {
      if (item.title == 'Call') {
        callItem = item;
        break;
      }
    }

    System.assertNotEquals(null, callItem, 'Call task should be returned.');
    System.assertEquals(
      'Phone call',
      callItem.activityType,
      'Call tasks should map to Phone call activity type.'
    );
    System.assertEquals(
      'Interactions',
      callItem.category,
      'Call tasks should appear under Interactions.'
    );
    System.assertEquals(
      'standard:call',
      callItem.icon,
      'Call tasks should use the call icon.'
    );
  }

  @IsTest
  static void getTimelineDataIncludesEmailMessages() {
    Account household = new Account(Name = 'Email Timeline Household');
    insert household;

    User recipient = [
      SELECT Id, Name, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    EmailMessage emailRecord = new EmailMessage(
      RelatedToId = household.Id,
      FromAddress = 'sender@example.com',
      ToAddress = recipient.Email,
      Subject = 'Timeline test email',
      TextBody = 'Email body',
      MessageDate = Datetime.now(),
      Status = '3'
    );
    insert emailRecord;

    insert new EmailMessageRelation(
      EmailMessageId = emailRecord.Id,
      RelationId = recipient.Id,
      RelationType = 'ToAddress',
      RelationAddress = recipient.Email
    );

    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );

    ActivityTimelineModels.ActivityItem emailItem;
    for (ActivityTimelineModels.ActivityItem item : data.activities) {
      if (item.title == 'Timeline test email') {
        emailItem = item;
        break;
      }
    }

    System.assertNotEquals(null, emailItem, 'Email message should be returned.');
    System.assertEquals(
      'Email',
      emailItem.activityType,
      'Email messages should map to Email activity type.'
    );
    System.assertEquals(
      'Interactions',
      emailItem.category,
      'Email messages should appear under Interactions.'
    );
    System.assertEquals(
      'standard:email',
      emailItem.icon,
      'Email messages should use the email icon.'
    );
    System.assertEquals(
      'EmailMessage',
      emailItem.recordObjectApiName,
      'Email messages should link to EmailMessage records.'
    );
    System.assertEquals(
      'sender@example.com',
      emailItem.fromAddress,
      'Email sender address should be exposed.'
    );
    System.assertEquals(
      'Sent',
      emailItem.status,
      'Email status codes should map to readable labels.'
    );
    System.assertEquals(
      1,
      emailItem.relatedParticipants.size(),
      'Email recipient should be exposed as a related participant.'
    );
    System.assertEquals(
      recipient.Id,
      Id.valueOf(emailItem.relatedParticipants[0].id),
      'Email recipient should resolve to the related user.'
    );
  }

  @IsTest
  static void getTimelineDataUsesCorrectIconForNullEventType() {
    Account household = new Account(Name = 'Null Event Type Household');
    insert household;

    Event eventRecord = new Event(
      Subject = 'Untyped household event',
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    insert eventRecord;

    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );

    ActivityTimelineModels.ActivityItem eventItem;
    for (ActivityTimelineModels.ActivityItem item : data.activities) {
      if (item.title == 'Untyped household event') {
        eventItem = item;
        break;
      }
    }

    System.assertNotEquals(null, eventItem, 'Untyped event should be returned.');
    System.assertEquals(
      'Meeting',
      eventItem.activityType,
      'Null event type should default to Meeting.'
    );
    System.assertEquals(
      'standard:event',
      eventItem.icon,
      'Null event type should use the meeting/event icon.'
    );
  }

  @IsTest
  static void getTimelineDataMapsEventTypeToMeeting() {
    Account household = new Account(Name = 'Event Type Household');
    insert household;

    Event eventRecord = new Event(
      Subject = 'Event typed meeting',
      WhatId = household.Id,
      Type = 'Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    insert eventRecord;

    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );

    ActivityTimelineModels.ActivityItem eventItem;
    for (ActivityTimelineModels.ActivityItem item : data.activities) {
      if (item.title == 'Event typed meeting') {
        eventItem = item;
        break;
      }
    }

    System.assertNotEquals(null, eventItem, 'Event record should be returned.');
    System.assertEquals(
      'Meeting',
      eventItem.activityType,
      'Event type picklist value should map to Meeting.'
    );
  }

  @IsTest
  static void getTimelineDataIncludesEventInviteesAsRelatedParticipants() {
    Account household = new Account(Name = 'Event Invite Household');
    insert household;

    Contact firstContact = new Contact(
      LastName = 'Alpha Contact',
      AccountId = household.Id
    );
    Contact secondContact = new Contact(
      LastName = 'Beta Contact',
      AccountId = household.Id
    );
    insert new List<Contact>{ firstContact, secondContact };

    Event eventRecord = new Event(
      Subject = 'Multi-attendee meeting',
      WhatId = household.Id,
      WhoId = firstContact.Id,
      Type = 'Meeting',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    insert eventRecord;

    insert new EventRelation(
      EventId = eventRecord.Id,
      RelationId = secondContact.Id,
      IsInvitee = true
    );

    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );

    ActivityTimelineModels.ActivityItem eventItem;
    for (ActivityTimelineModels.ActivityItem item : data.activities) {
      if (item.title == 'Multi-attendee meeting') {
        eventItem = item;
        break;
      }
    }

    System.assertNotEquals(null, eventItem, 'Multi-attendee event should be returned.');
    System.assertEquals(
      2,
      eventItem.relatedParticipants.size(),
      'Who and invitee contacts should both be related participants.'
    );
    System.assertEquals(
      firstContact.Id,
      Id.valueOf(eventItem.relatedParticipants[0].id),
      'Who contact should appear first.'
    );
  }

  @IsTest
  static void activityTimelineModelsExposeDtoFields() {
    ActivityTimelineModels.Participant participant = new ActivityTimelineModels.Participant(
      UserInfo.getUserId(),
      UserInfo.getName(),
      'User'
    );
    System.assertEquals('User', participant.objectApiName);

    ActivityTimelineModels.ActivityTimelineData timelineData = new ActivityTimelineModels.ActivityTimelineData();
    System.assertNotEquals(null, timelineData.activities);
    System.assertNotEquals(null, timelineData.categoryCounts);

    ActivityTimelineModels.ActivityItem item = new ActivityTimelineModels.ActivityItem();
    item.relatedParticipants.add(participant);
    System.assertEquals(0, item.participants.size());
    System.assertEquals(
      false,
      timelineData.isHouseholdRecordContext,
      'Household context flag should default to false.'
    );
  }

  @IsTest
  static void getTimelineDataFlagsHouseholdRecordContext() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData householdData = ActivityTimelineController.getTimelineData(
      scenario.rootAccount.Id,
      false
    );
    ActivityTimelineModels.ActivityTimelineData personAccountData = ActivityTimelineController.getTimelineData(
      scenario.linkedPersonAccount.Id,
      false
    );
    Test.stopTest();

    System.assertEquals(
      true,
      householdData.isHouseholdRecordContext,
      'Household account context should be flagged as household.'
    );
    System.assertEquals(
      false,
      personAccountData.isHouseholdRecordContext,
      'Person account context should not be flagged as household.'
    );
  }

  @IsTest
  static void getTimelineDataIncludesLinkedClientAccountActivities() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );

    Case linkedAccountCase = new Case(
      Subject = 'Linked person account case',
      AccountId = scenario.linkedPersonAccount.Id,
      Status = 'New',
      Origin = 'Service Request'
    );
    insert linkedAccountCase;

    Task linkedAccountTask = new Task(
      Subject = 'Linked person account task',
      WhatId = scenario.linkedPersonAccount.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert linkedAccountTask;

    Event linkedAccountEvent = new Event(
      Subject = 'Linked person account meeting',
      WhatId = scenario.linkedPersonAccount.Id,
      WhoId = scenario.linkedPersonAccount.PersonContactId,
      Type = 'Call',
      StartDateTime = Datetime.now().addDays(-2),
      EndDateTime = Datetime.now().addDays(-2).addHours(1),
      DurationInMinutes = 60
    );
    insert linkedAccountEvent;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      scenario.rootAccount.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      titles.contains('Linked person account case'),
      'Household timeline should include cases from linked person accounts.'
    );
    System.assert(
      titles.contains('Linked person account task'),
      'Household timeline should include tasks from linked person accounts.'
    );
    System.assert(
      titles.contains('Linked person account meeting'),
      'Household timeline should include events from linked person accounts.'
    );
  }

  @IsTest
  static void getTimelineDataFromLinkedPersonAccountLimitsScopeToOwnAccount() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );

    Case householdCase = new Case(
      Subject = 'Household scoped case',
      AccountId = scenario.rootAccount.Id,
      Status = 'New',
      Origin = 'Service Request'
    );
    insert householdCase;

    Case linkedAccountCase = new Case(
      Subject = 'Linked person account case',
      AccountId = scenario.linkedPersonAccount.Id,
      Status = 'New',
      Origin = 'Service Request'
    );
    insert linkedAccountCase;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      scenario.linkedPersonAccount.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      !titles.contains('Household scoped case'),
      'Non-household account views should not include household member activities.'
    );
    System.assert(
      titles.contains('Linked person account case'),
      'Non-household account views should include their own direct activities.'
    );
  }

  @IsTest
  static void getTimelineDataFromCaseRecordUsesAccountScope() {
    Account household = new Account(Name = 'Timeline Case Scope Household');
    insert household;

    Case caseRecord = new Case(
      Subject = 'Case page timeline case',
      AccountId = household.Id,
      Status = 'New',
      Origin = 'Service Request'
    );
    insert caseRecord;

    Task taskRecord = new Task(
      Subject = 'Case page timeline task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert taskRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      caseRecord.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      titles.contains('Case page timeline case'),
      'Case record context should resolve to the related account timeline.'
    );
    System.assert(
      titles.contains('Case page timeline task'),
      'Case record context should include household account activities.'
    );
  }

  @IsTest
  static void getTimelineDataExposesAssociatedAccountOnCaseActivitiesWhenExternal() {
    Account household = new Account(Name = 'External Case Account Household');
    insert household;

    Case caseRecord = new Case(
      Subject = 'Account Closure',
      AccountId = household.Id,
      Status = 'New',
      Origin = 'Service Request'
    );
    insert caseRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      caseRecord.Id,
      true
    );
    Test.stopTest();

    ActivityTimelineModels.ActivityItem caseItem;
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      if (activity.title == 'Account Closure') {
        caseItem = activity;
        break;
      }
    }

    System.assertNotEquals(null, caseItem, 'Case activity should be returned.');
    System.assertEquals(
      String.valueOf(household.Id),
      caseItem.associatedAccountId,
      'Case activity should expose the related account id.'
    );
    System.assertEquals(
      household.Name,
      caseItem.associatedAccountName,
      'Case activity should expose the related account name.'
    );
  }

  @IsTest
  static void getTimelineDataFromContactRecordUsesAccountScope() {
    Account household = new Account(Name = 'Timeline Contact Scope Household');
    insert household;

    Contact contactRecord = new Contact(
      LastName = 'Timeline Contact',
      AccountId = household.Id
    );
    insert contactRecord;

    Task taskRecord = new Task(
      Subject = 'Contact page timeline task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert taskRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      contactRecord.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      titles.contains('Contact page timeline task'),
      'Contact record context should resolve to the related account timeline.'
    );
  }

  @IsTest
  static void getTimelineDataFromTaskRecordUsesRelatedAccountScope() {
    Account household = new Account(Name = 'Timeline Task Scope Household');
    insert household;

    Task taskRecord = new Task(
      Subject = 'Task page timeline task',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert taskRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      taskRecord.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      titles.contains('Task page timeline task'),
      'Task record context should resolve through WhatId to the account timeline.'
    );
  }

  @IsTest
  static void getTimelineDataExposesLinkedCaseReferenceOnRelatedTask() {
    Account household = new Account(Name = 'Timeline Linked Case Household');
    insert household;

    Case caseRecord = new Case(
      Subject = 'Linked case task subject',
      AccountId = household.Id,
      Status = 'New',
      Origin = 'Service Request'
    );
    insert caseRecord;

    caseRecord = [
      SELECT Id, CaseNumber
      FROM Case
      WHERE Id = :caseRecord.Id
      LIMIT 1
    ];

    Task taskRecord = new Task(
      Subject = 'Upload SIS Document to Household Files',
      WhatId = caseRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert taskRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );
    Test.stopTest();

    ActivityTimelineModels.ActivityItem linkedTask;
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      if (activity.title == 'Upload SIS Document to Household Files') {
        linkedTask = activity;
        break;
      }
    }

    System.assertNotEquals(null, linkedTask, 'Task related to a case should be returned.');
    System.assertEquals(
      caseRecord.CaseNumber,
      linkedTask.linkedRecord,
      'Linked record label should use the case number.'
    );
    System.assertEquals(
      String.valueOf(caseRecord.Id),
      linkedTask.linkedRecordId,
      'Linked record id should point to the related case.'
    );
    System.assertEquals(
      'Case',
      linkedTask.linkedRecordObjectApiName,
      'Linked record object should be Case.'
    );
  }

  @IsTest
  static void getTimelineDataExposesLinkedAccountReferenceOnRelatedTask() {
    Account household = new Account(Name = 'Timeline Linked Account Household');
    insert household;

    Task taskRecord = new Task(
      Subject = 'Task related to household account',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert taskRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );
    Test.stopTest();

    ActivityTimelineModels.ActivityItem linkedTask;
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      if (activity.title == 'Task related to household account') {
        linkedTask = activity;
        break;
      }
    }

    System.assertNotEquals(null, linkedTask, 'Task related to an account should be returned.');
    System.assertEquals(
      household.Name,
      linkedTask.linkedRecord,
      'Linked record label should use the account name.'
    );
    System.assertEquals(
      String.valueOf(household.Id),
      linkedTask.linkedRecordId,
      'Linked record id should point to the related account.'
    );
    System.assertEquals(
      'Account',
      linkedTask.linkedRecordObjectApiName,
      'Linked record object should be Account.'
    );
  }

  @IsTest
  static void getTimelineDataExposesAssociatedAccountOnTaskAndEvent() {
    Account household = new Account(Name = 'Timeline Associated Account Household');
    insert household;

    Contact contactRecord = new Contact(
      LastName = 'Associated Account Contact',
      AccountId = household.Id
    );
    insert contactRecord;

    Task taskRecord = new Task(
      Subject = 'Task with associated account',
      WhoId = contactRecord.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert taskRecord;

    Event eventRecord = new Event(
      Subject = 'Event with associated account',
      WhoId = contactRecord.Id,
      StartDateTime = Datetime.now(),
      DurationInMinutes = 60
    );
    insert eventRecord;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );
    Test.stopTest();

    ActivityTimelineModels.ActivityItem associatedTask;
    ActivityTimelineModels.ActivityItem associatedEvent;
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      if (activity.title == 'Task with associated account') {
        associatedTask = activity;
      } else if (activity.title == 'Event with associated account') {
        associatedEvent = activity;
      }
    }

    System.assertNotEquals(null, associatedTask, 'Task with AccountId should be returned.');
    System.assertEquals(
      String.valueOf(household.Id),
      associatedTask.associatedAccountId,
      'Task associated account id should match AccountId.'
    );
    System.assertEquals(
      household.Name,
      associatedTask.associatedAccountName,
      'Task associated account name should match the account name.'
    );

    System.assertNotEquals(null, associatedEvent, 'Event with AccountId should be returned.');
    System.assertEquals(
      String.valueOf(household.Id),
      associatedEvent.associatedAccountId,
      'Event associated account id should match AccountId.'
    );
    System.assertEquals(
      household.Name,
      associatedEvent.associatedAccountName,
      'Event associated account name should match the account name.'
    );
  }

  @IsTest
  static void getTimelineDataReturnsEmptyTimelineForUnsupportedRecord() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];

    User timelineUser = new User(
      Alias = 'tlusr',
      Email = 'timeline.user@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Timeline',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standardProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = 'timeline.user.' + String.valueOf(Datetime.now().getTime()) + '@example.com'
    );
    insert timelineUser;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      timelineUser.Id,
      false
    );
    Test.stopTest();

    System.assertEquals(0, data.activities.size());
    System.assertEquals(0, data.categoryCounts.get('Work'));
    System.assertEquals(0, data.categoryCounts.get('Interactions'));
  }

  @IsTest
  static void getTimelineDataIncludesWhoIdEventsForRelatedContacts() {
    Account household = new Account(Name = 'WhoId Event Household');
    insert household;

    Contact contactRecord = new Contact(
      LastName = 'Timeline Contact',
      AccountId = household.Id
    );
    insert contactRecord;

    Event whoEvent = new Event(
      Subject = 'WhoId only meeting',
      WhoId = contactRecord.Id,
      Type = 'Meeting',
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      DurationInMinutes = 60
    );
    insert whoEvent;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      titles.contains('WhoId only meeting'),
      'Timeline should include events linked through WhoId.'
    );
  }

  @IsTest
  static void getTimelineDataFromBranchIncludesMemberDrpActivities() {
    List<RecordType> drpRecordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Diversify_Related_Person'
      LIMIT 1
    ];

    if (drpRecordTypes.isEmpty()) {
      return;
    }

    Account drpAccount = new Account(
      LastName = 'Branch Member DRP',
      RecordTypeId = drpRecordTypes[0].Id
    );
    insert drpAccount;

    Advisor_Group__c branch = new Advisor_Group__c(Name = 'Timeline Branch');
    insert branch;

    insert new Advisor_Group_Member__c(
      Advisor_Group__c = branch.Id,
      Diversify_Related_Person__c = drpAccount.Id
    );

    Task branchTask = new Task(
      Subject = 'Branch direct task',
      WhatId = branch.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    Task drpTask = new Task(
      Subject = 'Branch member DRP task',
      WhatId = drpAccount.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert new List<Task>{ branchTask, drpTask };

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      branch.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      titles.contains('Branch direct task'),
      'Branch timeline should include tasks related directly to the branch.'
    );
    System.assert(
      titles.contains('Branch member DRP task'),
      'Branch timeline should include tasks from branch member DRP accounts.'
    );
  }

  @IsTest
  static void getTimelineDataFromDrpAccountIncludesDirectTask() {
    List<RecordType> drpRecordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Diversify_Related_Person'
      LIMIT 1
    ];

    if (drpRecordTypes.isEmpty()) {
      return;
    }

    Account drpAccount = new Account(
      LastName = 'Timeline DRP',
      RecordTypeId = drpRecordTypes[0].Id
    );
    insert drpAccount;

    Task drpTask = new Task(
      Subject = 'DRP direct task',
      WhatId = drpAccount.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert drpTask;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      drpAccount.Id,
      false
    );
    Test.stopTest();

    Set<String> titles = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      titles.add(activity.title);
    }

    System.assert(
      titles.contains('DRP direct task'),
      'DRP account timeline should include tasks related to the DRP record.'
    );
  }

  @IsTest
  static void getTimelineDataUsesCreatedDateForTasksWithoutDueDate() {
    Account household = new Account(Name = 'Undated Task Household');
    insert household;

    Task undatedTask = new Task(
      Subject = 'Undated task created date fallback',
      WhatId = household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    insert undatedTask;

    undatedTask = [
      SELECT CreatedDate
      FROM Task
      WHERE Id = :undatedTask.Id
      LIMIT 1
    ];

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );
    Test.stopTest();

    ActivityTimelineModels.ActivityItem undatedItem;
    for (ActivityTimelineModels.ActivityItem activity : data.activities) {
      if (activity.title == 'Undated task created date fallback') {
        undatedItem = activity;
        break;
      }
    }

    System.assertNotEquals(
      null,
      undatedItem,
      'Undated task should be returned on the timeline.'
    );
    System.assertEquals(
      undatedTask.CreatedDate.getTime(),
      undatedItem.activityDateTime,
      'Tasks without a due date should sort and display using CreatedDate.'
    );
    System.assertEquals(
      false,
      undatedItem.hasDueDate,
      'Tasks without a due date should be flagged for no-due-date display.'
    );
    System.assertNotEquals(
      '',
      undatedItem.dateValue,
      'Tasks without a due date should expose a created-date value for filtering.'
    );
  }

  @IsTest
  static void getTimelineDataFromBranchIncludesExternalHouseholdActivitiesWhenEnabled() {
    List<RecordType> drpRecordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Diversify_Related_Person'
      LIMIT 1
    ];

    if (drpRecordTypes.isEmpty()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );

    Account drpAccount = new Account(
      LastName = 'External Scope DRP',
      RecordTypeId = drpRecordTypes[0].Id,
      Household__c = scenario.rootAccount.Id
    );
    insert drpAccount;

    Event externalEvent = new Event(
      Subject = 'External household meeting',
      WhatId = scenario.linkedPersonAccount.Id,
      WhoId = scenario.linkedPersonAccount.PersonContactId,
      Type = 'Meeting',
      StartDateTime = Datetime.now().addDays(-1),
      EndDateTime = Datetime.now().addDays(-1).addHours(1),
      DurationInMinutes = 60
    );
    insert externalEvent;

    Advisor_Group__c branch = new Advisor_Group__c(Name = 'External Scope Branch');
    insert branch;

    insert new Advisor_Group_Member__c(
      Advisor_Group__c = branch.Id,
      Diversify_Related_Person__c = drpAccount.Id
    );

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData withoutExternal = ActivityTimelineController.getTimelineData(
      branch.Id,
      false
    );
    ActivityTimelineModels.ActivityTimelineData withExternal = ActivityTimelineController.getTimelineData(
      branch.Id,
      true
    );
    Test.stopTest();

    Set<String> titlesWithoutExternal = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : withoutExternal.activities) {
      titlesWithoutExternal.add(activity.title);
    }

    Set<String> titlesWithExternal = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : withExternal.activities) {
      titlesWithExternal.add(activity.title);
    }

    System.assert(
      !titlesWithoutExternal.contains('External household meeting'),
      'Branch timeline without external scope should exclude household client activities.'
    );
    System.assert(
      titlesWithExternal.contains('External household meeting'),
      'Branch timeline with external scope should include household client activities.'
    );
  }

  @IsTest
  static void getTimelineDataFromDrpIncludesBranchExternalActivitiesWhenEnabled() {
    List<RecordType> drpRecordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Diversify_Related_Person'
      LIMIT 1
    ];

    if (drpRecordTypes.isEmpty()) {
      return;
    }

    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );

    Account drpAccount = new Account(
      LastName = 'DRP External Scope',
      RecordTypeId = drpRecordTypes[0].Id,
      Household__c = scenario.rootAccount.Id
    );
    insert drpAccount;

    Event externalEvent = new Event(
      Subject = 'DRP external household meeting',
      WhatId = scenario.linkedPersonAccount.Id,
      WhoId = scenario.linkedPersonAccount.PersonContactId,
      Type = 'Meeting',
      StartDateTime = Datetime.now().addDays(-1),
      EndDateTime = Datetime.now().addDays(-1).addHours(1),
      DurationInMinutes = 60
    );
    insert externalEvent;

    Advisor_Group__c branch = new Advisor_Group__c(Name = 'DRP External Scope Branch');
    insert branch;

    insert new Advisor_Group_Member__c(
      Advisor_Group__c = branch.Id,
      Diversify_Related_Person__c = drpAccount.Id
    );

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData withoutExternal = ActivityTimelineController.getTimelineData(
      drpAccount.Id,
      false
    );
    ActivityTimelineModels.ActivityTimelineData withExternal = ActivityTimelineController.getTimelineData(
      drpAccount.Id,
      true
    );
    Test.stopTest();

    Set<String> titlesWithoutExternal = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : withoutExternal.activities) {
      titlesWithoutExternal.add(activity.title);
    }

    Set<String> titlesWithExternal = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : withExternal.activities) {
      titlesWithExternal.add(activity.title);
    }

    System.assert(
      !titlesWithoutExternal.contains('DRP external household meeting'),
      'DRP timeline without external scope should exclude linked branch household client activities.'
    );
    System.assert(
      titlesWithExternal.contains('DRP external household meeting'),
      'DRP timeline with external scope should include activities from linked branch external scope.'
    );
    System.assertEquals(
      true,
      withExternal.isDrpRecordContext,
      'DRP timeline should be flagged as DRP record context.'
    );
    System.assertEquals(
      String.valueOf(branch.Id),
      withExternal.contextBranchId,
      'DRP external timeline should expose the linked branch id.'
    );
    System.assertEquals(
      branch.Name,
      withExternal.contextBranchName,
      'DRP external timeline should expose the linked branch name.'
    );
  }

  @IsTest
  static void getTimelineDataFromBranchIncludesFinancialAdvisorTeamClientActivitiesWhenEnabled() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.createTreeScenario(
      new FscDataTestDataFactory.TreeScenarioOptions().withUniqueNames()
    );

    Advisor_Group__c branch = new Advisor_Group__c(
      Name = 'Financial Advisor Team Scope Branch'
    );
    insert branch;

    Financial_Advisor_Team__c advisorTeam = new Financial_Advisor_Team__c(
      Name = 'Branch Advisor Team',
      Advisor_Group__c = branch.Id
    );
    insert advisorTeam;

    scenario.linkedPersonAccount.Financial_Advisor_Team__c = advisorTeam.Id;
    update scenario.linkedPersonAccount;

    Task teamClientTask = new Task(
      Subject = 'Financial advisor team client task',
      WhatId = scenario.linkedPersonAccount.Id,
      Status = 'Not Started',
      Priority = 'Normal',
      ActivityDate = Date.today()
    );
    insert teamClientTask;

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData withoutExternal = ActivityTimelineController.getTimelineData(
      branch.Id,
      false
    );
    ActivityTimelineModels.ActivityTimelineData withExternal = ActivityTimelineController.getTimelineData(
      branch.Id,
      true
    );
    Test.stopTest();

    Set<String> titlesWithoutExternal = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : withoutExternal.activities) {
      titlesWithoutExternal.add(activity.title);
    }

    Set<String> titlesWithExternal = new Set<String>();
    for (ActivityTimelineModels.ActivityItem activity : withExternal.activities) {
      titlesWithExternal.add(activity.title);
    }

    System.assert(
      !titlesWithoutExternal.contains('Financial advisor team client task'),
      'Branch timeline without external scope should exclude financial advisor team client activities.'
    );
    System.assert(
      titlesWithExternal.contains('Financial advisor team client task'),
      'Branch timeline with external scope should include activities from accounts assigned to branch financial advisor teams.'
    );
  }

  @IsTest
  static void getTimelineData_householdAccount_includesMemberSignificantEvents() {
    Account household = SignificantEventTestDataFactory.createHouseholdAccount(
      'Timeline Significant Event Household'
    );

    Significant_Event__c eventRecord = new Significant_Event__c(
      Name = 'Household Timeline Event',
      Event_Type__c = 'Birthday',
      Start_Date__c = Date.today(),
      Description__c = 'Graduation celebration details',
      Household__c = household.Id
    );
    insert eventRecord;

    insert new Significant_Event_Contact__c(
      Significant_Event__c = eventRecord.Id,
      Account__c = household.Id
    );

    Test.startTest();
    ActivityTimelineModels.ActivityTimelineData data = ActivityTimelineController.getTimelineData(
      household.Id,
      false
    );
    Test.stopTest();

    ActivityTimelineModels.ActivityItem significantEventItem;
    for (ActivityTimelineModels.ActivityItem item : data.activities) {
      if (item.activityType == 'Significant Event') {
        significantEventItem = item;
        break;
      }
    }

    System.assertNotEquals(
      null,
      significantEventItem,
      'Household timeline should include member significant events.'
    );
    System.assertEquals(
      String.valueOf(eventRecord.Id),
      significantEventItem.id,
      'Timeline item should reference the significant event record.'
    );
    System.assertEquals(
      'Household Timeline Event',
      significantEventItem.title,
      'Timeline item title should match the significant event name.'
    );
    System.assertEquals(
      'Graduation celebration details',
      significantEventItem.description,
      'Timeline item should include the significant event description.'
    );
    System.assertEquals(
      String.valueOf(household.Id),
      significantEventItem.associatedAccountId,
      'Household timeline should expose the linked participant account.'
    );
    System.assertEquals(true, data.isHouseholdRecordContext);
  }
}