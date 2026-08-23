/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-14
 *
 * Org-local timezone helpers for digest scheduling and batch execution.
 */
public without sharing class NotificationDigestTimezoneService {
  public static String getOrgTimezoneSidKey() {
    try {
      return [
        SELECT TimeZoneSidKey
        FROM Organization
        LIMIT 1
      ]
      .TimeZoneSidKey;
    } catch (Exception ex) {
      return UserInfo.getTimeZone().getID();
    }
  }

  public static Date getOrgLocalDate() {
    return Date.valueOf(
      Datetime.now().format('yyyy-MM-dd', getOrgTimezoneSidKey())
    );
  }

  public static Integer getOrgLocalHour() {
    return Integer.valueOf(
      Datetime.now().format('H', getOrgTimezoneSidKey())
    );
  }

  public static Integer getOrgLocalMinute() {
    return Integer.valueOf(
      Datetime.now().format('m', getOrgTimezoneSidKey())
    );
  }

  public static Datetime toGmtFromOrgLocal(Date orgDate, Integer hour, Integer minute) {
    String orgTimezoneSidKey = getOrgTimezoneSidKey();
    Datetime orgWallClockAsGmt = Datetime.newInstanceGmt(
      orgDate.year(),
      orgDate.month(),
      orgDate.day(),
      hour,
      minute,
      0
    );
    Integer offsetMilliseconds = TimeZone.getTimeZone(orgTimezoneSidKey)
      .getOffset(orgWallClockAsGmt);

    return orgWallClockAsGmt.addSeconds(-offsetMilliseconds / 1000);
  }

  public static String currentDigestHourValue() {
    return String.valueOf(getOrgLocalHour());
  }

  public static String getDigestTimezoneAbbreviation() {
    return Datetime.now().format('z', getOrgTimezoneSidKey());
  }

  public static String getDigestTimezoneLabel() {
    String timezoneSidKey = getOrgTimezoneSidKey();
    TimeZone timezone = TimeZone.getTimeZone(timezoneSidKey);
    String longName = timezone.getDisplayName();
    String shortName = Datetime.now().format('z', timezoneSidKey);

    if (String.isBlank(shortName) || shortName == longName) {
      return longName + ' (' + timezoneSidKey + ')';
    }

    return longName + ' (' + shortName + ')';
  }
}