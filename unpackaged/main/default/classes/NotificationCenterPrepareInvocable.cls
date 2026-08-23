/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Invocable preparation for Notification Center Event delivery.
 */
public without sharing class NotificationCenterPrepareInvocable {
  public class EventInput {
    @InvocableVariable(label='Source Type' required=true)
    public String sourceType;

    @InvocableVariable(label='Source Id' required=true)
    public String sourceId;

    @InvocableVariable(label='Change Context')
    public String changeContext;
  }

  public class PrepareOutput {
    @InvocableVariable(label='Delivery Log Ids')
    public List<String> deliveryLogIds;
  }

  @InvocableMethod(
    label='Prepare Notification Center Delivery'
    description='Creates notification logs and enqueues unified delivery jobs.'
    category='Notification Center'
  )
  public static List<PrepareOutput> prepareDelivery(
    List<EventInput> inputs
  ) {
    List<PrepareOutput> outputs = new List<PrepareOutput>();
    NotificationCenterEventService service = new NotificationCenterEventService();

    for (EventInput input : inputs) {
      PrepareOutput output = new PrepareOutput();
      output.deliveryLogIds = new List<String>();

      try {
        if (NotificationGovernorLimitService.shouldDeferPrepareToAsync()) {
          NotificationPrepareStartQueueable.enqueue(
            input.sourceType,
            input.sourceId,
            input.changeContext,
            input.sourceType ==
              NotificationConstants.OBJECT_TYPE_NOTIFICATION_LOG
          );
          outputs.add(output);
          continue;
        }

        List<NotificationCenterDeliveryItem> deliveryItems = new List<NotificationCenterDeliveryItem>();

        if (
          input.sourceType == NotificationConstants.OBJECT_TYPE_NOTIFICATION_LOG
        ) {
          deliveryItems = service.prepareNotificationLog(input.sourceId);
        } else {
          deliveryItems = service.prepareSourceRecord(
            input.sourceType,
            input.sourceId,
            input.changeContext
          );
        }

        for (NotificationCenterDeliveryItem deliveryItem : deliveryItems) {
          output.deliveryLogIds.add(String.valueOf(deliveryItem.logId));
        }

        NotificationDeliveryEnqueueService.enqueueImmediateDeliveryItems(
          deliveryItems
        );
      } catch (Exception error) {
        NotificationGovernorLimitService.logLimitException(
          'NotificationCenterPrepareInvocable.prepareDelivery',
          error
        );
      }

      outputs.add(output);
    }

    return outputs;
  }
}