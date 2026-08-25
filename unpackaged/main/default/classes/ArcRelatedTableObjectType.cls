/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Object mode for arcRelatedTable.
 */
public with sharing class ArcRelatedTableObjectType {
  public enum Value {
    ENVELOPE,
    WORK
  }

  public static Value fromValue(String rawValue) {
    if (String.isBlank(rawValue)) {
      return Value.ENVELOPE;
    }

    String normalized = rawValue.trim().toLowerCase();
    if (normalized == 'work') {
      return Value.WORK;
    }

    return Value.ENVELOPE;
  }
}