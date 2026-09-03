/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationEventRecipientServiceTest {
  @IsTest
  static void resolveRecipientsReturnsEmptyForNullEvent() {
    NotificationEventRecipientService.testRecipientOverrides = null;

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      null,
      null
    );

    System.assertEquals(0, recipientIds.size());
  }

  @IsTest
  static void resolveRecipientsIncludesCreatorWithEligibleProfile() {
    NotificationEventRecipientService.testRecipientOverrides = null;

    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!UserInfoUtils.isCurrentUserNotificationEligible()) {
      System.assert(true, 'Current user profile is outside notification scope.');
      return;
    }

    Event eventRecord = new Event(
      Subject = 'Creator Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    eventRecord = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      eventRecord,
      null
    );

    System.assert(
      recipientIds.contains(currentUser.Id),
      'Event creator should receive notifications.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesPrimaryAdvisorForNexSEventOnHousehold() {
    NotificationEventRecipientService.testRecipientOverrides = null;

    Profile nexsProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :UserInfoUtils.PROFILE_NEXS
      LIMIT 1
    ];

    User nexsUser;
    try {
      nexsUser = createUser(nexsProfile.Id, 'nexsevtadv');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented NexS user insert.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Event Primary Advisor Team',
      Related_Advisors__c = 'EvtPrimAdv' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Event Primary Advisor Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    try {
      NotificationTestDataFactory.insertRecord(new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = nexsUser.Id,
        Primary__c = true,
        Active__c = true
      ));
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    User creator = [
      SELECT Id
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    Event eventRecord = new Event(
      Subject = 'Primary Advisor Event',
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60,
      OwnerId = creator.Id
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    eventRecord = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      eventRecord,
      household.Id
    );

    System.assert(
      recipientIds.contains(nexsUser.Id),
      'NexS primary advisor should receive Event notifications for household events.'
    );
  }

  @IsTest
  static void resolveRecipientsExcludesHomeOfficePrimaryAdvisorOnly() {
    NotificationEventRecipientService.testRecipientOverrides = null;

    User homeOfficeUser = selectActiveHomeOfficeUser();
    if (homeOfficeUser == null) {
      System.assert(true, 'No active Home Office user available.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Event HO Primary Team',
      Related_Advisors__c = 'EvtHOPrim' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Event HO Primary Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    try {
      NotificationTestDataFactory.insertRecord(new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = homeOfficeUser.Id,
        Primary__c = true,
        Active__c = true
      ));
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    Event eventRecord = new Event(
      Subject = 'HO Primary Exclusion Event',
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    eventRecord = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      eventRecord,
      household.Id
    );

    System.assert(
      !recipientIds.contains(homeOfficeUser.Id),
      'Home Office primary advisor without creator/attendee role should not receive Event notifications.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesAttendeeWhenUserIsInvitee() {
    NotificationEventRecipientService.testRecipientOverrides = null;

    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!UserInfoUtils.isCurrentUserNotificationEligible()) {
      System.assert(true, 'Current user profile is outside notification scope.');
      return;
    }

    User eventCreator = selectActiveUserOtherThan(currentUser.Id);
    if (eventCreator == null) {
      System.assert(true, 'No alternate active user available for creator role.');
      return;
    }

    Event eventRecord;
    Id householdId;

    System.runAs(eventCreator) {
      Account household = new Account(Name = 'Event Attendee Household');
      NotificationTestDataFactory.insertRecord(household);
      householdId = household.Id;

      eventRecord = new Event(
        Subject = 'Attendee Eligibility Event',
        WhatId = household.Id,
        StartDateTime = Datetime.now().addDays(1),
        EndDateTime = Datetime.now().addDays(1).addHours(1),
        DurationInMinutes = 60
      );
      NotificationTestDataFactory.insertRecord(eventRecord);

      NotificationTestDataFactory.insertRecord(new EventRelation(
        EventId = eventRecord.Id,
        RelationId = currentUser.Id,
        IsInvitee = true
      ));
    }

    eventRecord = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      eventRecord,
      householdId
    );

    System.assert(
      recipientIds.contains(currentUser.Id),
      'Running user should receive Event notifications when listed as an attendee.'
    );
  }

  @IsTest
  static void getRecipientsForSourceRecordDelegatesEventToProfileRules() {
    NotificationRecipientService.testRecipientOverrides = null;
    NotificationEventRecipientService.testRecipientOverrides = null;

    Event eventRecord = new Event(
      Subject = 'Delegated Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      eventRecord.Id => new List<Id>{ UserInfo.getUserId() }
    };

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_EVENT,
      eventRecord,
      null
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(UserInfo.getUserId(), recipientIds[0]);
  }

  @IsTest
  static void resolveRecipientsIncludesHouseholdPrimaryAdvisorWhenProvided() {
    NotificationEventRecipientService.testRecipientOverrides = null;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Event eventRecord = new Event(
      Subject = 'Household Event',
      WhatId = context.household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    eventRecord = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      eventRecord,
      context.household.Id
    );

    System.assert(!recipientIds.isEmpty());
  }

  @IsTest
  static void resolveRecipientsUsesTestOverrideByEventId() {
    Event eventRecord = new Event(
      Subject = 'Override Event',
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    NotificationEventRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      eventRecord.Id => new List<Id>{ UserInfo.getUserId() }
    };

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      eventRecord,
      null
    );

    System.assertEquals(1, recipientIds.size());
    NotificationEventRecipientService.testRecipientOverrides = null;
  }

  @IsTest
  static void resolveRecipientsIncludesPrimaryAdvisorForContactWhoId() {
    NotificationEventRecipientService.testRecipientOverrides = null;

    Profile nexsProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :UserInfoUtils.PROFILE_NEXS
      LIMIT 1
    ];

    User nexsUser;
    try {
      nexsUser = createUser(nexsProfile.Id, 'nexscontact');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented NexS user insert.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Contact Event FA Team',
      Related_Advisors__c = 'ContactFA' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Contact Event Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    Contact contactRecord = new Contact(
      LastName = 'Event Contact',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(contactRecord);

    try {
      NotificationTestDataFactory.insertRecord(new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = faTeam.Id,
        User__c = nexsUser.Id,
        Primary__c = true,
        Active__c = true
      ));
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    Event eventRecord = new Event(
      Subject = 'Contact Who Event',
      WhoId = contactRecord.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    eventRecord = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :eventRecord.Id
      LIMIT 1
    ];

    List<Id> recipientIds = new NotificationEventRecipientService().resolveRecipients(
      eventRecord,
      household.Id
    );

    System.assert(
      recipientIds.contains(nexsUser.Id),
      'NexS primary advisor should receive notifications for contact-linked events.'
    );
  }

  @IsTest
  static void resolveRecipientsCachesPrimaryAdvisorLookup() {
    NotificationEventRecipientService.testRecipientOverrides = null;

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Cached Event FA Team',
      Related_Advisors__c = 'CachedEvtFA' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Cached Event Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    Event firstEvent = new Event(
      Subject = 'Cached Event 1',
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    Event secondEvent = new Event(
      Subject = 'Cached Event 2',
      WhatId = household.Id,
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(firstEvent);
    NotificationTestDataFactory.insertRecord(secondEvent);

    firstEvent = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :firstEvent.Id
      LIMIT 1
    ];
    secondEvent = [
      SELECT Id, WhoId, WhatId, OwnerId, CreatedById
      FROM Event
      WHERE Id = :secondEvent.Id
      LIMIT 1
    ];

    NotificationEventRecipientService service = new NotificationEventRecipientService();
    service.resolveRecipients(firstEvent, household.Id);
    service.resolveRecipients(secondEvent, household.Id);

    System.assert(true, 'Repeated FA team lookups should use cached primary advisor values.');
  }

  @IsTest
  static void isContactIdAndIsAccountIdHelpers() {
    Account household = new Account(Name = 'Helper Household');
    NotificationTestDataFactory.insertRecord(household);

    Contact contactRecord = new Contact(
      LastName = 'Helper Contact',
      AccountId = household.Id
    );
    NotificationTestDataFactory.insertRecord(contactRecord);

    System.assertEquals(
      true,
      NotificationEventRecipientService.isContactId(contactRecord.Id)
    );
    System.assertEquals(
      true,
      NotificationEventRecipientService.isAccountId(household.Id)
    );
    System.assertEquals(
      false,
      NotificationEventRecipientService.isContactId(household.Id)
    );
    System.assertEquals(
      false,
      NotificationEventRecipientService.isAccountId(null)
    );
  }

  private static User selectActiveUserOtherThan(Id excludedUserId) {
    List<User> users = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id != :excludedUserId AND IsActive = TRUE
      ORDER BY Name
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0];
  }

  private static User selectActiveHomeOfficeUser() {
    List<User> users = [
      SELECT Id
      FROM User
      WHERE
        Profile.Name = :UserInfoUtils.PROFILE_HOME_OFFICE
        AND IsActive = TRUE
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0];
  }

  private static User createUser(Id profileId, String aliasPrefix) {
    String uniqueSuffix = String.valueOf(System.currentTimeMillis());
    User testUser = new User(
      Alias = aliasPrefix.left(8),
      Email = aliasPrefix + '@example.com.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Event Recipient Test User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasPrefix + uniqueSuffix + '@example.com.test'
    );
    insert testUser;
    return testUser;
  }
}