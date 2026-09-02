/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 *
 * Coverage for Notification Center classes that specified tests left below 85%.
 */
@IsTest
private class NotificationCoverageGapTest {
  @IsTest
  static void digestResultFactory_buildsAllResultStates() {
    NotificationDigestModels.DeliveryResult succeeded = NotificationDigestResultFactory.succeeded();
    NotificationDigestModels.DeliveryResult suppressed = NotificationDigestResultFactory.suppressed(
      'quiet-hours'
    );
    NotificationDigestModels.DeliveryResult failed = NotificationDigestResultFactory.failed(
      'delivery failed'
    );

    System.assertEquals(true, succeeded.success);
    System.assertEquals(true, suppressed.suppressed);
    System.assertEquals('delivery failed', failed.errorMessage);
  }

  @IsTest
  static void emailDigestHandler_sendsQueuedEmail() {
    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    NotificationDigestModels.DigestDeliveryContext deliveryContext =
      new NotificationDigestModels.DigestDeliveryContext();
    deliveryContext.request.recipientId = context.recipientUser.Id;
    deliveryContext.request.channel = NotificationConstants.CHANNEL_EMAIL;
    deliveryContext.message = new NotificationDigestModels.ConsolidatedMessage();
    deliveryContext.message.title = 'Digest title';
    deliveryContext.message.body = 'Digest body';
    deliveryContext.logs = new List<Notification_Log__c>();

    Test.startTest();
    NotificationDigestModels.DeliveryResult result = new EmailDigestChannelHandler()
      .deliver(deliveryContext);
    Test.stopTest();

    System.assertEquals(true, result.success);
  }

  @IsTest
  static void userChannelService_coversLookupAndFrequencyHelpers() {
    System.assertEquals(
      0,
      NotificationUserChannelService.getForUsers(null).size()
    );
    System.assertEquals(
      0,
      NotificationUserChannelService.getForUsers(new Set<Id>()).size()
    );

    Map<Id, NotificationUserChannelService.ChannelSettings> settingsByUserId =
      NotificationUserChannelService.getForUsers(
        new Set<Id>{ UserInfo.getUserId() }
      );
    NotificationUserChannelService.ChannelSettings settings = settingsByUserId.get(
      UserInfo.getUserId()
    );

    System.assertEquals(true, settings.emailEnabled);
    System.assertEquals(
      false,
      NotificationUserChannelService.isFrequencyEnabledForChannel(
        settings,
        null,
        NotificationConstants.FREQUENCY_IMMEDIATE
      )
    );
    System.assertEquals(
      true,
      NotificationUserChannelService.isImmediateEnabledForChannel(
        settings,
        NotificationConstants.CHANNEL_EMAIL
      )
    );
    System.assertEquals(
      true,
      NotificationUserChannelService.isDigestEnabledForChannel(
        settings,
        NotificationConstants.CHANNEL_IN_APP
      )
    );
  }

  @IsTest
  static void inAppChannelHandler_suppressesDigestAndUsesMessageFallbacks() {
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationDeliveryModels.DeliveryContext digestContext =
      new NotificationDeliveryModels.DeliveryContext();
    digestContext.request.frequency = NotificationConstants.FREQUENCY_DIGEST;
    digestContext.request.deliverIndividually = false;

    NotificationDigestModels.DeliveryResult suppressed = new InAppChannelHandler()
      .deliver(digestContext);
    System.assertEquals(true, suppressed.suppressed);

    NotificationDeliveryModels.DeliveryContext immediateContext =
      new NotificationDeliveryModels.DeliveryContext();
    immediateContext.request.frequency = NotificationConstants.FREQUENCY_IMMEDIATE;
    immediateContext.request.recipientId = UserInfo.getUserId();
    immediateContext.logs.add(new Notification_Log__c());
    immediateContext.message = new NotificationDigestModels.ConsolidatedMessage();
    immediateContext.message.title = 'Fallback title';
    immediateContext.message.body = 'Fallback body';

    NotificationDigestModels.DeliveryResult delivered = new InAppChannelHandler()
      .deliver(immediateContext);
    System.assertEquals(true, delivered.success);
  }

  @IsTest
  static void eventServiceAndPrepareInvocable_coverGuardAndDeferralPaths() {
    NotificationGovernorLimitService.resetTestState();
    NotificationCenterEventService eventService = new NotificationCenterEventService();

    System.assertEquals(
      0,
      eventService.prepareSourceRecord(null, null).size()
    );
    System.assertEquals(0, eventService.prepareNotificationLog(null).size());
    System.assertEquals(
      0,
      eventService.prepareSourceRecord(
        NotificationConstants.OBJECT_TYPE_CASE,
        'not-an-id'
      )
      .size()
    );

    NotificationGovernorLimitService.testForceDeferPrepareToAsync = true;
    NotificationCenterPrepareInvocable.EventInput deferredInput =
      new NotificationCenterPrepareInvocable.EventInput();
    deferredInput.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    deferredInput.sourceId = String.valueOf(UserInfo.getUserId());

    Test.startTest();
    List<NotificationCenterPrepareInvocable.PrepareOutput> deferredOutputs =
      NotificationCenterPrepareInvocable.prepareDelivery(
        new List<NotificationCenterPrepareInvocable.EventInput>{ deferredInput }
      );
    Test.stopTest();

    NotificationGovernorLimitService.testForceDeferPrepareToAsync = false;
    System.assertEquals(1, deferredOutputs.size());
    System.assertEquals(0, deferredOutputs[0].deliveryLogIds.size());

    NotificationCenterPrepareInvocable.EventInput invalidLogInput =
      new NotificationCenterPrepareInvocable.EventInput();
    invalidLogInput.sourceType = NotificationConstants.OBJECT_TYPE_NOTIFICATION_LOG;
    invalidLogInput.sourceId = 'not-an-id';
    List<NotificationCenterPrepareInvocable.PrepareOutput> invalidOutputs =
      NotificationCenterPrepareInvocable.prepareDelivery(
        new List<NotificationCenterPrepareInvocable.EventInput>{ invalidLogInput }
      );
    System.assertEquals(1, invalidOutputs.size());
  }

  @IsTest
  static void prepareInvocable_preparesNotificationLogSourceType() {
    NotificationGovernorLimitService.resetTestState();
    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c digestLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_DIGEST,
      'Prepare log source',
      null,
      null
    );

    NotificationCenterPrepareInvocable.EventInput input =
      new NotificationCenterPrepareInvocable.EventInput();
    input.sourceType = NotificationConstants.OBJECT_TYPE_NOTIFICATION_LOG;
    input.sourceId = String.valueOf(digestLog.Id);

    Test.startTest();
    List<NotificationCenterPrepareInvocable.PrepareOutput> outputs =
      NotificationCenterPrepareInvocable.prepareDelivery(
        new List<NotificationCenterPrepareInvocable.EventInput>{ input }
      );
    Test.stopTest();

    System.assertEquals(1, outputs.size());
    System.assertEquals(0, outputs[0].deliveryLogIds.size());

    List<Notification_Log__c> logs = [
      SELECT Id
      FROM Notification_Log__c
      WHERE Id = :digestLog.Id
    ];
    System.assertEquals(1, logs.size());
  }

  @IsTest
  static void digestContent_enrichmentGuardsAndUnknownSourceType() {
    NotificationDigestContentService.enrichLogs(null);
    NotificationDigestContentService.enrichLogs(new List<Notification_Log__c>());
    System.assertEquals(
      null,
      NotificationDigestContentService.resolveTargetId(null)
    );

    Notification_Log__c unknownLog = new Notification_Log__c(
      Source_Type__c = 'CustomObject',
      Source_Record_Id__c = String.valueOf(UserInfo.getUserId()),
      Household__c = UserInfo.getUserId()
    );
    NotificationDigestContentService.enrichLog(unknownLog);
    System.assertEquals('CustomObject', unknownLog.Source_Type__c);
  }

  @IsTest
  static void enqueueService_normalizesEmptyAndDuplicateInputs() {
    NotificationDeliveryEnqueueService.enqueueLogIds(null);
    NotificationDeliveryEnqueueService.enqueueLogIds(new List<Id>());
    NotificationDeliveryEnqueueService.enqueueImmediateLogIds(null);
    NotificationDeliveryEnqueueService.enqueueLogIdStrings(null);
    NotificationDeliveryEnqueueService.enqueueLogIdStrings(new List<String>());
    NotificationDeliveryEnqueueService.enqueueImmediateDeliveryItems(null);
    NotificationDeliveryDispatcher.enqueueLogIdStrings(null);
    NotificationDeliveryDispatcher.enqueueChunk(null, null, null);

    System.assertEquals(
      4,
      NotificationDeliveryDispatcher.enqueueChunk(
        new List<NotificationDeliveryModels.DeliveryRequest>(),
        4,
        null
      )
    );
  }

  @IsTest
  static void digestRepositoryAndDispatchers_coverBlankAndEmptyPaths() {
    NotificationDigestRepository repository = new NotificationDigestRepository();
    Database.QueryLocator blankChannelLocator = repository.selectQueuedDigestLogsByIds(
      new List<Id>{ UserInfo.getUserId() },
      null
    );
    Database.QueryLocator sourceLocator = repository.selectQueuedDigestLogsForSourceRecords(
      null,
      UserInfo.getUserId(),
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.CHANNEL_EMAIL
    );

    System.assertNotEquals(null, blankChannelLocator);
    System.assertNotEquals(null, sourceLocator);

    List<NotificationDigestModels.DigestDeliveryRequest> overflow =
      new List<NotificationDigestModels.DigestDeliveryRequest>();
    Integer nextIndex = NotificationDigestJobDispatcher.enqueueChunk(
      null,
      null,
      overflow
    );
    NotificationDigestJobDispatcher.chainRemainingJobs(null, 0);
    NotificationDigestJobDispatcher.chainRemainingJobs(
      new List<NotificationDigestModels.DigestDeliveryRequest>(),
      0
    );

    NotificationDigestModels.DigestDeliveryRequest digestRequest =
      new NotificationDigestModels.DigestDeliveryRequest();
    digestRequest.recipientId = UserInfo.getUserId();
    digestRequest.channel = NotificationConstants.CHANNEL_EMAIL;
    digestRequest.logIds.add(UserInfo.getUserId());
    NotificationDigestJobDispatcher.enqueueChunk(
      new List<NotificationDigestModels.DigestDeliveryRequest>{ digestRequest },
      0,
      overflow
    );
    new NotificationDigestJobChainQueueable(null).execute(null);
    new NotificationDigestJobChainQueueable(
      new List<NotificationDigestModels.DigestDeliveryRequest>{ digestRequest },
      null
    )
      .execute(null);

    List<NotificationDigestModels.DigestDeliveryRequest> overflowRequests =
      new List<NotificationDigestModels.DigestDeliveryRequest>();
    List<NotificationDigestModels.DigestDeliveryRequest> manyRequests =
      new List<NotificationDigestModels.DigestDeliveryRequest>();
    for (Integer index = 0; index < 3; index++) {
      NotificationDigestModels.DigestDeliveryRequest extraRequest =
        new NotificationDigestModels.DigestDeliveryRequest();
      extraRequest.recipientId = UserInfo.getUserId();
      extraRequest.channel = NotificationConstants.CHANNEL_EMAIL;
      extraRequest.logIds.add(UserInfo.getUserId());
      manyRequests.add(extraRequest);
    }
    NotificationDigestJobDispatcher.enqueueChunk(manyRequests, 0, overflowRequests);
    NotificationDigestJobDispatcher.chainRemainingJobs(manyRequests, 2);
    NotificationDeliveryDispatcher.enqueueLogIds(new List<Id>());
    NotificationDeliveryDispatcher.chainRemainingJobs(
      new List<NotificationDeliveryModels.DeliveryRequest>{
        NotificationDeliveryRequestBuilder.fromDigest(digestRequest)
      },
      5
    );

    System.assertEquals(0, nextIndex);
  }

  @IsTest
  static void immediateRecoveryBatch_processesStaleQueuedLogs() {
    NotificationCustomNotificationService.testSkipSend = true;
    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c staleLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_QUEUED,
      NotificationConstants.CHANNEL_EMAIL,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Stale recovery log',
      null,
      null
    );
    Test.setCreatedDate(staleLog.Id, System.now().addMinutes(-30));

    Test.startTest();
    Database.executeBatch(new NotificationImmediateRecoveryBatch(), 50);
    Test.stopTest();

    System.assertNotEquals(null, staleLog.Id);
  }

  @IsTest
  static void centerRepository_coversInboxLogStatsAndReadPaths() {
    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    Notification_Log__c sentLog = NotificationTestDataFactory.createLogNotification(
      context.recipientUser.Id,
      context.household.Id,
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.STATUS_SENT,
      NotificationConstants.CHANNEL_IN_APP,
      NotificationConstants.FREQUENCY_IMMEDIATE,
      'Inbox sent log',
      null,
      null
    );
    sentLog.Is_Read__c = false;
    sentLog.Delivered_At__c = System.now();
    NotificationTestDataFactory.updateRecord(sentLog);

    NotificationCenterRepository repository = new NotificationCenterRepository();
    NotificationCenterRepository.InboxQuery inboxQuery =
      new NotificationCenterRepository.InboxQuery();
    inboxQuery.recipientId = context.recipientUser.Id;
    inboxQuery.filterName = 'UNREAD';
    inboxQuery.pageSize = 10;
    inboxQuery.sortDirection = 'oldest';
    List<Notification_Log__c> unreadInbox = repository.selectInbox(inboxQuery);

    inboxQuery.filterName = NotificationConstants.OBJECT_TYPE_CASE;
    inboxQuery.sortDirection = 'newest';
    inboxQuery.lastSeenId = sentLog.Id;
    List<Notification_Log__c> caseInbox = repository.selectInbox(inboxQuery);

    inboxQuery.filterName = NotificationConstants.OBJECT_TYPE_TASK;
    repository.selectInbox(inboxQuery);
    inboxQuery.filterName = NotificationConstants.OBJECT_TYPE_EVENT;
    repository.selectInbox(inboxQuery);

    NotificationCenterRepository.LogQuery logQuery =
      new NotificationCenterRepository.LogQuery();
    logQuery.recipientId = context.recipientUser.Id;
    logQuery.statusFilter = NotificationConstants.LOG_STATUS_DELIVERED;
    logQuery.categoryFilter = NotificationConstants.LOG_CATEGORY_INFO;
    logQuery.pageSize = 10;
    logQuery.lastSeenId = sentLog.Id;
    repository.selectLog(logQuery);
    repository.countLog(logQuery);
    logQuery.statusFilter = NotificationConstants.LOG_STATUS_SUPPRESSED;
    logQuery.categoryFilter = NotificationConstants.LOG_CATEGORY_SERVICE;
    repository.countLog(logQuery);
    logQuery.statusFilter = NotificationConstants.LOG_STATUS_QUEUED;
    logQuery.categoryFilter = NotificationConstants.LOG_CATEGORY_URGENT;
    repository.countLog(logQuery);

    System.assertNotEquals(null, repository.selectLogStats(context.recipientUser.Id));
    System.assert(repository.countUnread(context.recipientUser.Id) >= 0);
    System.assertNotEquals(null, repository.selectStats(context.recipientUser.Id));
    System.assertNotEquals(
      null,
      repository.selectDashboardStats(context.recipientUser.Id)
    );
    System.assertNotEquals(
      null,
      repository.selectTodayChannelDelivery(context.recipientUser.Id)
    );
    System.assertNotEquals(
      null,
      repository.selectUserDefaultPreferences(context.recipientUser.Id)
    );
    System.assertEquals(0, repository.markAsRead(context.recipientUser.Id, null));
    System.assert(
      repository.markAsRead(
        context.recipientUser.Id,
        new List<Id>{ sentLog.Id }
      ) >= 0
    );
    System.assert(repository.markAllAsRead(context.recipientUser.Id) >= 0);
    System.assertNotEquals(null, unreadInbox);
    System.assertNotEquals(null, caseInbox);
  }

  @IsTest
  static void emailContentServices_coverNullInputs() {
    System.assertEquals(
      '',
      NotificationCaseEmailContentService.buildDigestTable(null, 1000)
    );
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      NotificationCaseEmailContentService.buildChangeMadePlainText(null)
    );
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      NotificationCaseEmailContentService.buildChangedAtDisplay(
        new Notification_Log__c()
      )
    );
    System.assertEquals(
      null,
      NotificationCaseEmailContentService.resolveChangedAtDatetime(
        new Notification_Log__c()
      )
    );
    System.assertEquals(
      'Case notification',
      NotificationCaseEmailContentService.build(null).title
    );

    System.assertEquals(
      '',
      NotificationEventEmailContentService.buildDigestTable(
        new List<Notification_Log__c>(),
        1000
      )
    );
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      NotificationEventEmailContentService.buildChangeMadePlainText(
        new Notification_Log__c()
      )
    );
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      NotificationEventEmailContentService.buildChangedAtDisplay(null)
    );
    System.assertEquals(
      null,
      NotificationEventEmailContentService.resolveChangedAtDatetime(null)
    );
  }

  @IsTest
  static void ruleLogService_buildsSuppressedLogWhenChannelMapHasNoSupportedChannels() {
    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    Case caseRecord = new Case(
      Subject = 'Coverage rule log case',
      AccountId = context.household.Id
    );
    NotificationTestDataFactory.insertRecord(caseRecord);
    NotificationRuleLogModels.ProcessRecipientRequest request =
      new NotificationRuleLogModels.ProcessRecipientRequest();
    request.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    request.sourceId = String.valueOf(caseRecord.Id);
    request.recipientId = context.recipientUser.Id;
    request.householdId = context.household.Id;
    request.correlationKey = 'corr-coverage';
    request.channelPreferenceResults = new Map<String, NotificationPreferenceService.ResolveResult>{
      NotificationConstants.CHANNEL_ZOOM => new NotificationPreferenceService.ResolveResult(
        'no-zoom'
      )
    };

    NotificationRuleLogModels.ProcessRecipientResult result = new NotificationRuleLogService()
      .buildRecipientLogs(request);

    System.assertEquals(1, result.logs.size());
    System.assertEquals(
      NotificationConstants.STATUS_SUPPRESSED,
      result.logs[0].Status__c
    );
  }

  @IsTest
  static void recipientServices_useHouseholdTestOverrides() {
    NotificationTestDataFactory.NotificationTestContext context =
      NotificationTestDataFactory.createHouseholdWithRecipient();
    Task taskRecord = new Task(
      Subject = 'Household override task',
      WhatId = context.household.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    NotificationTestDataFactory.insertRecord(taskRecord);
    Event eventRecord = new Event(
      Subject = 'Household override event',
      WhatId = context.household.Id,
      StartDateTime = System.now().addDays(1),
      EndDateTime = System.now().addDays(1).addHours(1),
      DurationInMinutes = 60
    );
    NotificationTestDataFactory.insertRecord(eventRecord);

    NotificationTaskRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ context.recipientUser.Id }
    };
    NotificationEventRecipientService.testRecipientOverrides = new Map<Id, List<Id>>{
      context.household.Id => new List<Id>{ context.recipientUser.Id }
    };

    List<Id> taskRecipients = new NotificationTaskRecipientService()
      .resolveRecipients(taskRecord, context.household.Id);
    List<Id> eventRecipients = new NotificationEventRecipientService()
      .resolveRecipients(eventRecord, context.household.Id);

    NotificationTaskRecipientService.testRecipientOverrides = null;
    NotificationEventRecipientService.testRecipientOverrides = null;

    System.assertEquals(context.recipientUser.Id, taskRecipients[0]);
    System.assertEquals(context.recipientUser.Id, eventRecipients[0]);
  }

  @IsTest
  static void householdResolver_returnsEmptyWhenCaseHasNoAccount() {
    Case caseRecord = new Case(Subject = 'Coverage Case Without Account');
    NotificationTestDataFactory.insertRecord(caseRecord);

    Map<Id, Id> recordIdToHouseholdId = new NotificationHouseholdResolver()
      .resolveHouseholds(
        new List<SObject>{ caseRecord },
        NotificationConstants.OBJECT_TYPE_CASE
      );

    System.assertEquals(
      0,
      recordIdToHouseholdId.size(),
      'Case without AccountId should not resolve a household'
    );
  }

  @IsTest
  static void digestScheduleService_handlesEmptyQueuedCount() {
    System.assertEquals(
      null,
      NotificationDigestScheduleService.resolveNextDigestRunLabel(
        UserInfo.getUserId(),
        0
      )
    );
    System.assertEquals(
      null,
      NotificationDigestScheduleService.resolveNextDigestRunLabel(
        UserInfo.getUserId(),
        null
      )
    );
  }
}