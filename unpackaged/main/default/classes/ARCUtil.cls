/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-16
 *
 * Shared utility methods for Arc Experience Cloud controllers.
 */
public class ARCUtil {
  public static String buildLookupCacheKey(
    String primaryObjectApiName,
    String relatedObjectApiName
  ) {
    return primaryObjectApiName +
      ARCConstants.LOOKUP_CACHE_KEY_SEPARATOR +
      relatedObjectApiName;
  }

  public static String formatNoRelatedRecordLinkedMessage(
    String relatedObjectApiName,
    String primaryObjectApiName
  ) {
    return ARCConstants.ERROR_NO_RELATED_RECORD_LINKED +
      relatedObjectApiName +
      ARCConstants.ERROR_RELATED_RECORD_LINKED_MIDDLE +
      primaryObjectApiName +
      ARCConstants.ERROR_RELATED_RECORD_LINKED_SUFFIX;
  }

  public static ARCConstants.RelatedTableScope relatedTableScopeFromValue(
    String rawValue
  ) {
    if (String.isBlank(rawValue)) {
      return ARCConstants.RelatedTableScope.MINE;
    }

    String normalized = rawValue.trim().toLowerCase();
    if (normalized == 'team') {
      return ARCConstants.RelatedTableScope.TEAM;
    }

    return ARCConstants.RelatedTableScope.MINE;
  }
}