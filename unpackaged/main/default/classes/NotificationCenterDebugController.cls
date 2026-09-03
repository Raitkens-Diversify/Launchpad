/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * AuraEnabled facade for notification center debug tooling.
 */
public with sharing class NotificationCenterDebugController {
  private static final NotificationCenterDebugService SERVICE = new NotificationCenterDebugService();

  @AuraEnabled
  public static List<NotificationCenterDebugModels.DebugDigestItem> getDigestPreview(
    String objectType
  ) {
    assertAdminAccess();
    return SERVICE.getDigestPreview(UserInfo.getUserId(), objectType);
  }

  @AuraEnabled
  public static NotificationCenterDebugModels.DigestTriggerResult triggerDigest(
    String objectType
  ) {
    assertAdminAccess();
    return SERVICE.triggerDigest(UserInfo.getUserId(), objectType);
  }

  private static void assertAdminAccess() {
    if (!UserInfoUtils.isCurrentUserSystemAdministrator()) {
      throw new AuraHandledException(
        'Only System Administrators can use Notification Center debug tooling.'
      );
    }
  }
}