/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Reads notification channel options from the Channel__c picklist metadata.
 */
public with sharing class NotificationChannelService {
  private static final Schema.SObjectField CHANNEL_FIELD = Notification_Rule__c.Channel__c;

  public class ChannelOption {
    @AuraEnabled
    public String label { get; private set; }
    @AuraEnabled
    public String value { get; private set; }
    @AuraEnabled
    public Boolean isDefault { get; private set; }

    public ChannelOption(String label, String value, Boolean isDefault) {
      this.label = label;
      this.value = value;
      this.isDefault = isDefault;
    }
  }

  public static List<ChannelOption> getChannelOptions() {
    List<ChannelOption> options = new List<ChannelOption>();

    for (Schema.PicklistEntry entry : CHANNEL_FIELD.getDescribe().getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }

      options.add(
        new ChannelOption(entry.getLabel(), entry.getValue(), entry.isDefaultValue())
      );
    }

    options.sort(new ChannelOptionSortComparator());
    return options;
  }

  private class ChannelOptionSortComparator implements Comparator<ChannelOption> {
    public Integer compare(ChannelOption left, ChannelOption right) {
      Integer leftIndex = NotificationChannelUtils.getChannelSortIndex(left.value);
      Integer rightIndex = NotificationChannelUtils.getChannelSortIndex(
        right.value
      );

      if (leftIndex == rightIndex) {
        return left.label.compareTo(right.label);
      }

      return leftIndex - rightIndex;
    }
  }

  public static String getDefaultChannelApiName() {
    for (Schema.PicklistEntry entry : CHANNEL_FIELD.getDescribe().getPicklistValues()) {
      if (entry.isActive() && entry.isDefaultValue()) {
        return entry.getValue();
      }
    }

    for (Schema.PicklistEntry entry : CHANNEL_FIELD.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        return entry.getValue();
      }
    }

    return null;
  }

  public static Set<String> getActiveChannelApiNames() {
    Set<String> channelApiNames = new Set<String>();

    for (Schema.PicklistEntry entry : CHANNEL_FIELD.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        channelApiNames.add(entry.getValue());
      }
    }

    return channelApiNames;
  }
}