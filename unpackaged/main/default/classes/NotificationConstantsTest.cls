/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-04
 */
@IsTest
private class NotificationConstantsTest {
  @IsTest
  static void allLogViewStatuses_returnsExpectedStatuses() {
    Set<String> statuses = NotificationConstants.allLogViewStatuses();

    System.assertEquals(5, statuses.size());
    System.assert(statuses.contains(NotificationConstants.STATUS_SENT));
    System.assert(statuses.contains(NotificationConstants.STATUS_FAILED));
  }

  @IsTest
  static void pitStopRecipientProfileNames_returnsBranchAndHomeOfficeProfiles() {
    Task branchTask = new Task(Branch_Pit_Stop__c = true);
    Set<String> branchProfiles = NotificationConstants.pitStopRecipientProfileNames(
      branchTask
    );

    System.assertEquals(3, branchProfiles.size());
    System.assert(branchProfiles.contains(UserInfoUtils.PROFILE_NEXS));
    System.assert(branchProfiles.contains('Arc Login'));
    System.assert(branchProfiles.contains(UserInfoUtils.PROFILE_ADVISOR));

    Task hoTask = new Task(Home_Office_Pit_Stop__c = true);
    Set<String> hoProfiles = NotificationConstants.pitStopRecipientProfileNames(
      hoTask
    );

    System.assertEquals(1, hoProfiles.size());
    System.assert(hoProfiles.contains(UserInfoUtils.PROFILE_HOME_OFFICE));
    System.assertEquals(0, NotificationConstants.pitStopRecipientProfileNames(null).size());
  }

  @IsTest
  static void isPitStopRecipientProfile_identifiesEligibleProfiles() {
    Task branchTask = new Task(Branch_Pit_Stop__c = true);

    System.assertEquals(
      true,
      NotificationConstants.isPitStopRecipientProfile(
        branchTask,
        UserInfoUtils.PROFILE_NEXS
      )
    );
    System.assertEquals(
      false,
      NotificationConstants.isPitStopRecipientProfile(branchTask, null)
    );

    Task hoTask = new Task(Home_Office_Pit_Stop__c = true);
    System.assertEquals(
      true,
      NotificationConstants.isPitStopRecipientProfile(
        hoTask,
        UserInfoUtils.PROFILE_HOME_OFFICE
      )
    );
  }

  @IsTest
  static void shouldResolveNormalTaskRecipientsForPitStopTask_skipsBranchPitStop() {
    System.assertEquals(
      false,
      NotificationConstants.shouldResolveNormalTaskRecipientsForPitStopTask(
        new Task(Branch_Pit_Stop__c = true)
      )
    );
    System.assertEquals(
      true,
      NotificationConstants.shouldResolveNormalTaskRecipientsForPitStopTask(
        new Task(Home_Office_Pit_Stop__c = true)
      )
    );
    System.assertEquals(
      true,
      NotificationConstants.shouldResolveNormalTaskRecipientsForPitStopTask(null)
    );
  }

  @IsTest
  static void shouldIncludeRecipientInNormalTaskNotifications_appliesPitStopRules() {
    Task branchTask = new Task(Branch_Pit_Stop__c = true);
    System.assertEquals(
      false,
      NotificationConstants.shouldIncludeRecipientInNormalTaskNotifications(
        branchTask,
        UserInfoUtils.PROFILE_NEXS
      )
    );

    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'HO Pit Stop Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    Task hoCaseTask = new Task(
      Home_Office_Pit_Stop__c = true,
      WhatId = caseRecord.Id
    );

    System.assertEquals(
      false,
      NotificationConstants.shouldIncludeRecipientInNormalTaskNotifications(
        hoCaseTask,
        UserInfoUtils.PROFILE_HOME_OFFICE
      )
    );
    System.assertEquals(
      false,
      NotificationConstants.shouldIncludeRecipientInNormalTaskNotifications(
        hoCaseTask,
        UserInfoUtils.PROFILE_NEXS
      )
    );
    System.assertEquals(
      true,
      NotificationConstants.shouldIncludeRecipientInNormalTaskNotifications(
        null,
        UserInfoUtils.PROFILE_NEXS
      )
    );
  }

  @IsTest
  static void isCaseRelatedTask_detectsCaseWhatId() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Related Case',
      AccountId = context.household.Id,
      Status = 'New'
    );
    NotificationTestDataFactory.insertRecord(caseRecord);

    System.assertEquals(
      true,
      NotificationConstants.isCaseRelatedTask(
        new Task(WhatId = caseRecord.Id)
      )
    );
    System.assertEquals(
      false,
      NotificationConstants.isCaseRelatedTask(
        new Task(WhatId = context.household.Id)
      )
    );
    System.assertEquals(false, NotificationConstants.isCaseRelatedTask(null));
  }

  @IsTest
  static void isFrequencyEnabledForChannel_respectsChannelRules() {
    System.assertEquals(
      true,
      NotificationConstants.isFrequencyEnabledForChannel(
        NotificationConstants.CHANNEL_EMAIL,
        NotificationConstants.FREQUENCY_DIGEST
      )
    );
    System.assertEquals(
      true,
      NotificationConstants.isFrequencyEnabledForChannel(
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_IMMEDIATE
      )
    );
    System.assertEquals(
      false,
      NotificationConstants.isFrequencyEnabledForChannel(
        NotificationConstants.CHANNEL_IN_APP,
        NotificationConstants.FREQUENCY_DIGEST
      )
    );
    System.assertEquals(
      false,
      NotificationConstants.isFrequencyEnabledForChannel(null, null)
    );
    System.assertEquals(
      true,
      NotificationConstants.isImmediateEnabledForChannel(
        NotificationConstants.CHANNEL_EMAIL
      )
    );
  }

  @IsTest
  static void isPitStopTask_detectsBranchOrHomeOfficeFlags() {
    System.assertEquals(
      true,
      NotificationConstants.isPitStopTask(new Task(Branch_Pit_Stop__c = true))
    );
    System.assertEquals(
      true,
      NotificationConstants.isPitStopTask(
        new Task(Home_Office_Pit_Stop__c = true)
      )
    );
    System.assertEquals(false, NotificationConstants.isPitStopTask(new Task()));
    System.assertEquals(false, NotificationConstants.isPitStopTask(null));
  }
}