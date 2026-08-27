/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 *
 * Invocable preparation for Notification Center Event delivery.
 * Always hops to a Queueable from Flow/PE so this transaction cannot hit
 * uncatchable SOQL 101. Prepare is query-heavy (recipients, household, rules).
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
    if (inputs == null || inputs.isEmpty()) {
      return outputs;
    }

    List<NotificationPrepareStartQueueable.PrepareRequest> prepareRequests = new List<NotificationPrepareStartQueueable.PrepareRequest>();

    for (EventInput input : inputs) {
      PrepareOutput output = new PrepareOutput();
      output.deliveryLogIds = new List<String>();
      outputs.add(output);

      if (input == null || String.isBlank(input.sourceType) || String.isBlank(input.sourceId)) {
        continue;
      }

      prepareRequests.add(
        new NotificationPrepareStartQueueable.PrepareRequest(
          input.sourceType,
          input.sourceId,
          input.changeContext,
          input.sourceType == NotificationConstants.OBJECT_TYPE_NOTIFICATION_LOG
        )
      );
    }

    if (prepareRequests.isEmpty()) {
      return outputs;
    }

    for (NotificationPrepareStartQueueable.PrepareRequest prepareRequest : prepareRequests) {
      NotificationPrepareStartQueueable.enqueueRequests(
        new List<NotificationPrepareStartQueueable.PrepareRequest>{ prepareRequest }
      );
    }
    return outputs;
  }
}