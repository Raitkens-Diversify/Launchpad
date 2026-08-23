/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Transaction-scoped cache for notification email content keyed by source record.
 */
public class NotificationEmailContentCache {
  private static Map<String, Object> contentBySourceKey = new Map<String, Object>();

  public static String buildSourceKey(String sourceType, String sourceRecordId) {
    return sourceType + ':' + sourceRecordId;
  }

  public static Object get(String sourceKey) {
    return contentBySourceKey.get(sourceKey);
  }

  public static void put(String sourceKey, Object content) {
    if (String.isBlank(sourceKey) || content == null) {
      return;
    }

    contentBySourceKey.put(sourceKey, content);
  }

  @TestVisible
  public static void clear() {
    contentBySourceKey.clear();
  }
}