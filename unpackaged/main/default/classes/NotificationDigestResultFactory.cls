/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 */
public with sharing class NotificationDigestResultFactory {
  public static NotificationDigestModels.DeliveryResult succeeded() {
    NotificationDigestModels.DeliveryResult result = new NotificationDigestModels.DeliveryResult();
    result.success = true;
    return result;
  }

  public static NotificationDigestModels.DeliveryResult suppressed(String reason) {
    NotificationDigestModels.DeliveryResult result = new NotificationDigestModels.DeliveryResult();
    result.success = false;
    result.suppressed = true;
    result.suppressionReason = reason;
    return result;
  }

  public static NotificationDigestModels.DeliveryResult failed(String message) {
    NotificationDigestModels.DeliveryResult result = new NotificationDigestModels.DeliveryResult();
    result.success = false;
    result.errorMessage = message;
    return result;
  }
}