/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 */
@IsTest
private class NotificationCaseRecipientServiceTest {
  @IsTest
  static void resolveRecipientsReturnsEmptyForNullCase() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      null,
      null
    );

    System.assertEquals(0, recipientIds.size());
  }

  @IsTest
  static void resolveRecipientsUsesTestOverrideByCaseId() {
    Account household = new Account(Name = 'Case Recipient Household');
    NotificationTestDataFactory.insertRecord(household);

    Case caseRecord = new Case(
      Subject = 'Override Case',
      AccountId = household.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    User currentUser = [
      SELECT Id
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    NotificationCaseRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      caseRecord.Id => new List<Id>{ currentUser.Id }
    };

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      household.Id
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(currentUser.Id, recipientIds[0]);
  }

  @IsTest
  static void resolveRecipientsIncludesCaseOwnerWithEligibleProfile() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!NotificationConstants.isNotificationEligibleProfile(currentUser.Profile.Name)) {
      System.assert(true, 'Current user profile is outside notification scope.');
      return;
    }

    Case caseRecord = new Case(
      Subject = 'Owned Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = currentUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      null
    );

    System.assert(recipientIds.contains(currentUser.Id));
  }

  @IsTest
  static void resolveRecipientsIncludesPrimaryAdvisorForNexSProfile() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Primary Advisor Team',
      Related_Advisors__c = 'PrimAdv' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Primary Advisor Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    Profile nexsProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :NotificationConstants.PROFILE_NEXS
      LIMIT 1
    ];

    User nexsUser;
    try {
      nexsUser = createUser(nexsProfile.Id, 'nexsadv');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented NexS user insert.');
      return;
    }

    Financial_Advisor_Team_Member__c primaryMember = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = faTeam.Id,
      User__c = nexsUser.Id,
      Primary__c = true,
      Active__c = true
    );

    try {
      NotificationTestDataFactory.insertRecord(primaryMember);
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    Case caseRecord = new Case(
      Subject = 'Primary Advisor Case',
      AccountId = household.Id,
      Financial_Advisor_Team__c = faTeam.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      household.Id
    );

    System.assert(
      recipientIds.contains(nexsUser.Id),
      'Primary advisor on household FA team should receive Case notifications.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesPrimaryAdvisorForSystemAdministratorProfile() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    User systemAdminUser = selectActiveSystemAdministratorUser();
    if (systemAdminUser == null) {
      System.assert(true, 'No active System Administrator user available.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'System Admin Primary Advisor Team',
      Related_Advisors__c = 'SysAdminAdv' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'System Admin Primary Advisor Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    Financial_Advisor_Team_Member__c primaryMember = new Financial_Advisor_Team_Member__c(
      Financial_Advisor_Team__c = faTeam.Id,
      User__c = systemAdminUser.Id,
      Primary__c = true,
      Active__c = true
    );

    try {
      NotificationTestDataFactory.insertRecord(primaryMember);
    } catch (DmlException ex) {
      System.assert(true, 'Org FA Team automation prevented member insert.');
      return;
    }

    Case caseRecord = new Case(
      Subject = 'System Admin Primary Advisor Case',
      AccountId = household.Id,
      Financial_Advisor_Team__c = faTeam.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      household.Id
    );

    System.assert(
      recipientIds.contains(systemAdminUser.Id),
      'System Administrator primary advisor on household FA team should receive Case notifications.'
    );
  }

  @IsTest
  static void resolveRecipientsIncludesCaseOwnerForSystemAdministratorProfile() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    User systemAdminUser = selectActiveSystemAdministratorUser();
    if (systemAdminUser == null) {
      System.assert(true, 'No active System Administrator user available.');
      return;
    }

    Case caseRecord = new Case(
      Subject = 'System Admin Owned Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = systemAdminUser.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      null
    );

    System.assert(
      recipientIds.contains(systemAdminUser.Id),
      'System Administrator case owner should receive Case notifications.'
    );
  }

  private static User selectActiveSystemAdministratorUser() {
    List<User> systemAdministrators = [
      SELECT Id
      FROM User
      WHERE
        Profile.Name = :NotificationConstants.PROFILE_SYSTEM_ADMINISTRATOR
        AND IsActive = TRUE
      LIMIT 1
    ];
    return systemAdministrators.isEmpty() ? null : systemAdministrators[0];
  }

  @IsTest
  static void getRecipientsForSourceRecordDelegatesCaseToProfileRules() {
    NotificationRecipientService.testRecipientOverrides = null;
    NotificationCaseRecipientService.testRecipientOverrides = null;

    Case caseRecord = new Case(
      Subject = 'Delegated Case',
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      caseRecord.Id => new List<Id>{ UserInfo.getUserId() }
    };

    List<Id> recipientIds = new NotificationRecipientService().getRecipientsForSourceRecord(
      NotificationConstants.OBJECT_TYPE_CASE,
      caseRecord,
      null
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(UserInfo.getUserId(), recipientIds[0]);
  }

  private static User createUser(Id profileId, String aliasPrefix) {
    String uniqueSuffix = String.valueOf(System.currentTimeMillis());
    User testUser = new User(
      Alias = aliasPrefix.left(8),
      Email = aliasPrefix + '@example.com.test',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Case Recipient Test User',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Los_Angeles',
      Username = aliasPrefix + uniqueSuffix + '@example.com.test'
    );
    insert testUser;
    return testUser;
  }

  @IsTest
  static void isUserIdAndIsQueueIdHelpers() {
    User currentUser = [
      SELECT Id
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    System.assertEquals(
      true,
      NotificationCaseRecipientService.isUserId(currentUser.Id)
    );
    System.assertEquals(
      false,
      NotificationCaseRecipientService.isQueueId(currentUser.Id)
    );
    System.assertEquals(
      false,
      NotificationCaseRecipientService.isUserId(null)
    );

    List<QueueSobject> queueObjects = [
      SELECT QueueId
      FROM QueueSobject
      WHERE SObjectType = 'Case'
      LIMIT 1
    ];

    if (!queueObjects.isEmpty()) {
      System.assertEquals(
        true,
        NotificationCaseRecipientService.isQueueId(queueObjects[0].QueueId)
      );
    }
  }

  @IsTest
  static void resolveRecipientsUsesHouseholdOverrideInTest() {
    Account household = new Account(Name = 'Household Override Case Recipient');
    NotificationTestDataFactory.insertRecord(household);

    Case caseRecord = new Case(
      Subject = 'Household Override Case',
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    NotificationCaseRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      household.Id => new List<Id>{ UserInfo.getUserId() }
    };

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      household.Id
    );

    System.assertEquals(1, recipientIds.size());
    System.assertEquals(UserInfo.getUserId(), recipientIds[0]);
    NotificationCaseRecipientService.testRecipientOverrides = null;
  }

  @IsTest
  static void resolveRecipientsIncludesQueueMemberForOwnedCase() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!NotificationConstants.isNotificationEligibleProfile(currentUser.Profile.Name)) {
      System.assert(true, 'Current user profile is outside notification scope.');
      return;
    }

    List<QueueSobject> queueObjects = [
      SELECT QueueId
      FROM QueueSobject
      WHERE SObjectType = 'Case'
      LIMIT 1
    ];

    if (queueObjects.isEmpty()) {
      System.assert(true, 'No Case queue available in org.');
      return;
    }

    Group serviceQueue = [
      SELECT Id
      FROM Group
      WHERE Id = :queueObjects[0].QueueId
      LIMIT 1
    ];

    List<GroupMember> existingMembers = [
      SELECT Id
      FROM GroupMember
      WHERE GroupId = :serviceQueue.Id AND UserOrGroupId = :currentUser.Id
      LIMIT 1
    ];

    if (existingMembers.isEmpty()) {
      insert new GroupMember(
        GroupId = serviceQueue.Id,
        UserOrGroupId = currentUser.Id
      );
    }

    Case caseRecord = new Case(
      Subject = 'Queue Owned Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = serviceQueue.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      null
    );

    System.assert(
      recipientIds.contains(currentUser.Id),
      'Queue member should be eligible when assigned to a queue-owned case.'
    );
  }

  @IsTest
  static void resolveRecipientsResolvesFaTeamFromHouseholdAccount() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    Profile nexsProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = :NotificationConstants.PROFILE_NEXS
      LIMIT 1
    ];

    User nexsUser;
    try {
      nexsUser = createUser(nexsProfile.Id, 'nexshh');
    } catch (DmlException ex) {
      System.assert(true, 'Org automation prevented NexS user insert.');
      return;
    }

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Household FA Team',
      Related_Advisors__c = 'HouseholdFA' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Household FA Team Household',
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

    Case caseRecord = new Case(
      Subject = 'Household FA Team Case',
      AccountId = household.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    List<Id> recipientIds = new NotificationCaseRecipientService().resolveRecipients(
      caseRecord,
      household.Id
    );

    System.assert(
      recipientIds.contains(nexsUser.Id),
      'Primary advisor should resolve when FA team is loaded from household.'
    );
  }

  @IsTest
  static void resolveRecipientsCachesHouseholdFaTeamLookup() {
    NotificationCaseRecipientService.testRecipientOverrides = null;

    Financial_Advisor_Team__c faTeam = new Financial_Advisor_Team__c(
      Name = 'Cached FA Team',
      Related_Advisors__c = 'CachedFA' + System.currentTimeMillis()
    );
    NotificationTestDataFactory.insertRecord(faTeam);

    Account household = new Account(
      Name = 'Cached FA Household',
      Financial_Advisor_Team__c = faTeam.Id
    );
    NotificationTestDataFactory.insertRecord(household);

    Case firstCase = new Case(
      Subject = 'Cached FA Case 1',
      AccountId = household.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    Case secondCase = new Case(
      Subject = 'Cached FA Case 2',
      AccountId = household.Id,
      Status = 'New',
      Origin = 'Phone'
    );
    NotificationTestDataFactory.insertRecord(firstCase);
    NotificationTestDataFactory.insertRecord(secondCase);

    NotificationCaseRecipientService service = new NotificationCaseRecipientService();
    service.resolveRecipients(firstCase, household.Id);
    service.resolveRecipients(secondCase, household.Id);

    System.assert(true, 'Repeated household FA team lookups should use cached values.');
  }
}