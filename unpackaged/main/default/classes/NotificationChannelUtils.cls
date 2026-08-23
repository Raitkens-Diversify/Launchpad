/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-03
 *
 * Helpers for notification channel multipicklist values.
 */
public with sharing class NotificationChannelUtils {
  private static final String CHANNEL_DELIMITER = ';';

  public static List<String> splitChannels(String channelsValue) {
    List<String> channels = new List<String>();
    if (String.isBlank(channelsValue)) {
      return channels;
    }

    for (String channelValue : channelsValue.split(CHANNEL_DELIMITER)) {
      String trimmedValue = channelValue.trim();
      if (!String.isBlank(trimmedValue)) {
        channels.add(trimmedValue);
      }
    }

    return channels;
  }

  public static String joinChannels(List<String> channels) {
    if (channels == null || channels.isEmpty()) {
      return null;
    }

    List<String> normalizedChannels = new List<String>();
    for (String channel : channels) {
      if (!String.isBlank(channel)) {
        normalizedChannels.add(channel.trim());
      }
    }

    return normalizedChannels.isEmpty()
      ? null
      : String.join(normalizedChannels, CHANNEL_DELIMITER);
  }

  public static String resolveSingleChannel(
    String channelsValue,
    String preferredChannel
  ) {
    List<String> channels = splitChannels(channelsValue);

    if (channels.isEmpty()) {
      return channelsValue;
    }

    if (
      !String.isBlank(preferredChannel) &&
      channels.contains(preferredChannel)
    ) {
      return preferredChannel;
    }

    return channels[0];
  }

  public static Boolean includesChannel(String channelsValue, String channelName) {
    return splitChannels(channelsValue).contains(channelName);
  }

  public static Integer getChannelSortIndex(String channelName) {
    if (String.isBlank(channelName)) {
      return NotificationConstants.CHANNEL_ORDER.size();
    }

    Integer sortIndex = NotificationConstants.CHANNEL_ORDER.indexOf(
      channelName.trim()
    );

    return sortIndex == -1
      ? NotificationConstants.CHANNEL_ORDER.size()
      : sortIndex;
  }

  public static List<String> sortChannels(List<String> channels) {
    if (channels == null || channels.isEmpty()) {
      return new List<String>();
    }

    List<String> normalizedChannels = new List<String>();
    Set<String> seenChannels = new Set<String>();

    for (String channel : channels) {
      if (String.isBlank(channel) || seenChannels.contains(channel)) {
        continue;
      }

      seenChannels.add(channel);
      normalizedChannels.add(channel.trim());
    }

    normalizedChannels.sort(new ChannelSortComparator());
    return normalizedChannels;
  }

  private class ChannelSortComparator implements Comparator<String> {
    public Integer compare(String left, String right) {
      Integer leftIndex = getChannelSortIndex(left);
      Integer rightIndex = getChannelSortIndex(right);

      if (leftIndex == rightIndex) {
        return left.compareTo(right);
      }

      return leftIndex - rightIndex;
    }
  }
}