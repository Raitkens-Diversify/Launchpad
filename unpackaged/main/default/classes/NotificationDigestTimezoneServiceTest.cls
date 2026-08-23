/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-14
 */
@IsTest
private class NotificationDigestTimezoneServiceTest {
  @IsTest
  static void getOrgTimezoneSidKeyReturnsValue() {
    System.assertNotEquals(
      null,
      NotificationDigestTimezoneService.getOrgTimezoneSidKey()
    );
  }

  @IsTest
  static void getDigestTimezoneLabelReturnsValue() {
    System.assertNotEquals(
      null,
      NotificationDigestTimezoneService.getDigestTimezoneLabel()
    );
  }

  @IsTest
  static void getDigestTimezoneAbbreviationReturnsValue() {
    System.assertNotEquals(
      null,
      NotificationDigestTimezoneService.getDigestTimezoneAbbreviation()
    );
  }

  @IsTest
  static void currentDigestHourValueReturnsNumericString() {
    String hourValue = NotificationDigestTimezoneService.currentDigestHourValue();

    System.assertNotEquals(null, hourValue);
    System.assertEquals(
      String.valueOf(Integer.valueOf(hourValue)),
      hourValue
    );
  }
}