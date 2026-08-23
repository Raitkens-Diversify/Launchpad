/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-16
 *
 * Resolves per-user notification delivery context from standard User fields only.
 * Email and In App channels are always treated as enabled for immediate and digest delivery.
 */
public without sharing class NotificationUserChannelService {
  public ChannelSettings getForCurrentUser() {
    return mapToSettings(selectUser(UserInfo.getUserId()));
  }

  public static Map<Id, ChannelSettings> getForUsers(Set<Id> userIds) {
    Map<Id, ChannelSettings> settingsByUserId = new Map<Id, ChannelSettings>();

    if (userIds == null || userIds.isEmpty()) {
      return settingsByUserId;
    }

    for (User userRecord : [
      SELECT Id, Email
      FROM User
      WHERE Id IN :userIds
    ]) {
      settingsByUserId.put(userRecord.Id, mapToSettings(userRecord));
    }

    return settingsByUserId;
  }

  public static Boolean isFrequencyEnabledForChannel(
    ChannelSettings settings,
    String channel,
    String frequency
  ) {
    if (String.isBlank(channel) || String.isBlank(frequency)) {
      return false;
    }

    return channel == NotificationConstants.CHANNEL_IN_APP ||
      channel == NotificationConstants.CHANNEL_EMAIL;
  }

  public static Boolean isImmediateEnabledForChannel(
    ChannelSettings settings,
    String channel
  ) {
    return isFrequencyEnabledForChannel(
      settings,
      channel,
      NotificationConstants.FREQUENCY_IMMEDIATE
    );
  }

  public static Boolean isDigestEnabledForChannel(
    ChannelSettings settings,
    String channel
  ) {
    return isFrequencyEnabledForChannel(
      settings,
      channel,
      NotificationConstants.FREQUENCY_DIGEST
    );
  }

  private static User selectUser(Id userId) {
    return [
      SELECT Id, Email
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];
  }

  private static ChannelSettings mapToSettings(User userRecord) {
    ChannelSettings settings = new ChannelSettings();
    settings.emailEnabled = true;
    settings.emailImmediate = true;
    settings.emailDigest = true;
    settings.inAppImmediate = true;
    settings.inAppDigest = true;
    settings.zoomEnabled = false;
    settings.zoomImmediate = false;
    settings.zoomDigest = false;
    settings.emailDeliveryAddress = null;
    settings.emailHtmlFormatted = true;
    settings.zoomUsername = null;
    settings.zoomRespectDnd = true;
    settings.userEmail = userRecord.Email;
    return settings;
  }

  public class ChannelSettings {
    @AuraEnabled
    public Boolean emailEnabled { get; set; }
    @AuraEnabled
    public Boolean emailImmediate { get; set; }
    @AuraEnabled
    public Boolean emailDigest { get; set; }
    @AuraEnabled
    public Boolean zoomEnabled { get; set; }
    @AuraEnabled
    public Boolean zoomImmediate { get; set; }
    @AuraEnabled
    public Boolean zoomDigest { get; set; }
    @AuraEnabled
    public Boolean inAppImmediate { get; set; }
    @AuraEnabled
    public Boolean inAppDigest { get; set; }
    @AuraEnabled
    public String emailDeliveryAddress { get; set; }
    @AuraEnabled
    public Boolean emailHtmlFormatted { get; set; }
    @AuraEnabled
    public String zoomUsername { get; set; }
    @AuraEnabled
    public Boolean zoomRespectDnd { get; set; }
    @AuraEnabled
    public String userEmail { get; set; }
  }

  public class NotificationUserChannelException extends Exception {}
}