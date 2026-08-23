/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class NotificationCenterDebugModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    NotificationCenterDebugModels.DebugDigestItem debugDigestItem = new NotificationCenterDebugModels.DebugDigestItem();
    NotificationCenterDebugModels.DigestTriggerResult digestTriggerResult = new NotificationCenterDebugModels.DigestTriggerResult();

    System.assertNotEquals(null, debugDigestItem);
    System.assertNotEquals(null, digestTriggerResult.items);
    System.assertEquals(0, digestTriggerResult.items.size());
  }
}