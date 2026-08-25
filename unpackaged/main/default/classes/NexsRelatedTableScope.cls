/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-11
 *
 * Row visibility scope for nexsRelatedTable.
 */
public with sharing class NexsRelatedTableScope {
  public enum Value {
    MINE,
    TEAM
  }

  public static Value fromValue(String rawValue) {
    if (String.isBlank(rawValue)) {
      return Value.MINE;
    }

    String normalized = rawValue.trim().toLowerCase();
    if (normalized == 'team') {
      return Value.TEAM;
    }

    return Value.MINE;
  }
}