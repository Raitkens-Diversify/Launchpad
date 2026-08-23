/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Flow-compatible delivery item for Notification Center Event handling.
 */
@JsonAccess(serializable='always' deserializable='always')
public class NotificationCenterDeliveryItem {
  @InvocableVariable(label='Log Id')
  public Id logId;

  @InvocableVariable(label='Log Ids CSV')
  public String logIdsCsv;

  @InvocableVariable(label='Recipient Id')
  public Id recipientId;

  @InvocableVariable(label='Channel')
  public String channel;

  @InvocableVariable(label='Frequency')
  public String frequency;

  @InvocableVariable(label='Source Type')
  public String sourceType;

  @InvocableVariable(label='Source Record Id')
  public String sourceRecordId;

  public static NotificationCenterDeliveryItem fromLog(
    Notification_Log__c logRecord
  ) {
    if (logRecord == null) {
      return null;
    }

    NotificationCenterDeliveryItem item = new NotificationCenterDeliveryItem();
    item.logId = logRecord.Id;
    item.recipientId = logRecord.Recipient__c;
    item.channel = logRecord.Channel__c;
    item.frequency = logRecord.Frequency__c;
    item.sourceType = logRecord.Source_Type__c;
    item.sourceRecordId = logRecord.Source_Record_Id__c;
    return item;
  }

  public static NotificationCenterDeliveryItem fromLogs(
    List<Notification_Log__c> logRecords
  ) {
    if (logRecords == null || logRecords.isEmpty()) {
      return null;
    }

    NotificationCenterDeliveryItem item = fromLog(logRecords[0]);
    List<String> logIds = new List<String>();

    for (Notification_Log__c logRecord : logRecords) {
      if (logRecord?.Id != null) {
        logIds.add(String.valueOf(logRecord.Id));
      }
    }

    item.logIdsCsv = String.join(logIds, ',');
    return item;
  }
}