/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class NotificationRuleLogModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    NotificationRuleLogModels.ProcessRecipientRequest processRecipientRequest = new NotificationRuleLogModels.ProcessRecipientRequest();
    NotificationRuleLogModels.ProcessRecipientResult processRecipientResult = new NotificationRuleLogModels.ProcessRecipientResult();

    System.assertNotEquals(null, processRecipientRequest);
    System.assertNotEquals(null, processRecipientResult.logs);
    System.assertNotEquals(null, processRecipientResult.immediateLogs);
    System.assertEquals(0, processRecipientResult.logs.size());
    System.assertEquals(0, processRecipientResult.immediateLogs.size());
  }
}