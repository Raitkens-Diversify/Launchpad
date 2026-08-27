/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class NotificationRecipientPrepareModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    NotificationRecipientPrepareModels.SourcePrepareContext sourcePrepareContext = new NotificationRecipientPrepareModels.SourcePrepareContext();
    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest = new NotificationRecipientPrepareModels.ContinuationRequest();
    NotificationRecipientPrepareModels.ProcessChunkResult processChunkResult = new NotificationRecipientPrepareModels.ProcessChunkResult();

    System.assertNotEquals(null, sourcePrepareContext.pitStopBypassRecipientIds);
    System.assertEquals(0, sourcePrepareContext.pitStopBypassRecipientIds.size());
    System.assertEquals(null, continuationRequest.startIndex);
    System.assertNotEquals(null, processChunkResult.deliveryItems);
    System.assertEquals(0, processChunkResult.deliveryItems.size());
    System.assertEquals(false, processChunkResult.limitReached);
    System.assertEquals(null, processChunkResult.caughtException);
  }

  @IsTest
  static void dtoFields_roundTripAssignedValues() {
    Id userId = UserInfo.getUserId();
    NotificationRecipientPrepareModels.SourcePrepareContext sourcePrepareContext = new NotificationRecipientPrepareModels.SourcePrepareContext();
    sourcePrepareContext.sourceType = NotificationConstants.OBJECT_TYPE_TASK;
    sourcePrepareContext.sourceId = String.valueOf(userId);
    sourcePrepareContext.householdId = userId;
    sourcePrepareContext.correlationKey = 'corr-1';
    sourcePrepareContext.changeContextJson = '{"triggerType":"Insert"}';
    sourcePrepareContext.enrichedChangeContextJson = '{"triggerType":"Insert"}';
    sourcePrepareContext.recipientIds = new List<Id>{ userId };
    sourcePrepareContext.pitStopBypassRecipientIds.add(userId);

    NotificationRecipientPrepareModels.ContinuationRequest continuationRequest = new NotificationRecipientPrepareModels.ContinuationRequest();
    continuationRequest.sourceType = NotificationConstants.OBJECT_TYPE_CASE;
    continuationRequest.sourceId = String.valueOf(userId);
    continuationRequest.correlationKey = 'corr-2';
    continuationRequest.changeContextJson = '{"triggerType":"Update"}';
    continuationRequest.startIndex = 5;
    continuationRequest.chunkSize = 25;
    continuationRequest.attemptNumber = 1;

    NotificationRecipientPrepareModels.ProcessChunkResult processChunkResult = new NotificationRecipientPrepareModels.ProcessChunkResult();
    processChunkResult.nextStartIndex = 30;
    processChunkResult.limitReached = true;
    processChunkResult.caughtException = new NotificationDeliveryService.NotificationDeliveryException(
      'chunk limit'
    );
    processChunkResult.deliveryItems.add(new NotificationCenterDeliveryItem());

    System.assertEquals(NotificationConstants.OBJECT_TYPE_TASK, sourcePrepareContext.sourceType);
    System.assertEquals(1, sourcePrepareContext.recipientIds.size());
    System.assertEquals(true, sourcePrepareContext.pitStopBypassRecipientIds.contains(userId));
    System.assertEquals(5, continuationRequest.startIndex);
    System.assertEquals(25, continuationRequest.chunkSize);
    System.assertEquals(true, processChunkResult.limitReached);
    System.assertEquals(1, processChunkResult.deliveryItems.size());
    System.assertEquals('chunk limit', processChunkResult.caughtException.getMessage());
  }
}