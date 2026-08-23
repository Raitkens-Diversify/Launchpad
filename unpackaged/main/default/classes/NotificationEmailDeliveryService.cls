/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-17
 *
 * Sends notification emails for immediate and digest delivery.
 */
public without sharing class NotificationEmailDeliveryService {
  @TestVisible
  private static Id orgWideEmailAddressIdOverride;

  @TestVisible
  private static Id cachedOrgWideEmailAddressId;

  @TestVisible
  private static final Pattern HTML_MARKUP_PATTERN = Pattern.compile(
    '(?i)<(table|a\\s|div|p|br\\s*/?|html|body|thead|tbody|tr|td|th|span|ul|ol|li|h[1-6])\\b'
  );

  public static void sendNotification(
    Id recipientId,
    String subject,
    String body
  ) {
    if (recipientId == null) {
      throw new NotificationEmailDeliveryException('Recipient Id is required.');
    }

    String toAddress = resolveDeliveryAddress(recipientId);

    if (String.isBlank(toAddress)) {
      throw new NotificationEmailDeliveryException(
        'No email delivery address is configured for this user.'
      );
    }

    Messaging.SingleEmailMessage email = buildEmailMessage(
      toAddress,
      subject,
      body,
      true
    );

    List<Messaging.SendEmailResult> results = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ email }
    );

    if (results.isEmpty() || !results[0].isSuccess()) {
      String errorMessage = 'Email delivery failed.';

      if (!results.isEmpty() && !results[0].getErrors().isEmpty()) {
        errorMessage = results[0].getErrors()[0].getMessage();
      }

      throw new NotificationEmailDeliveryException(errorMessage);
    }
  }

  public static void sendConsolidatedDigest(
    Id recipientId,
    String subject,
    String body
  ) {
    sendNotification(recipientId, subject, body);
  }

  public static String resolveDeliveryAddress(Id recipientId) {
    User userRecord = [
      SELECT Email
      FROM User
      WHERE Id = :recipientId
      LIMIT 1
    ];

    return userRecord.Email;
  }

  private static Messaging.SingleEmailMessage buildEmailMessage(
    String toAddress,
    String subject,
    String body,
    Boolean useHtml
  ) {
    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
    email.setToAddresses(new List<String>{ toAddress });
    email.setSubject(subject);
    email.setSaveAsActivity(false);
    email.setUseSignature(false);

    String normalizedBody = String.isBlank(body) ? '' : body;

    if (shouldSendAsHtml(useHtml, normalizedBody)) {
      email.setHtmlBody(normalizedBody);
      email.setPlainTextBody(stripHtml(normalizedBody));
    } else {
      email.setPlainTextBody(normalizedBody);
    }

    Id orgWideEmailAddressId = resolveOrgWideEmailAddressId();

    if (orgWideEmailAddressId != null) {
      email.setOrgWideEmailAddressId(orgWideEmailAddressId);
    }

    return email;
  }

  @TestVisible
  private static Id resolveOrgWideEmailAddressId() {
    if (orgWideEmailAddressIdOverride != null) {
      return orgWideEmailAddressIdOverride;
    }

    if (cachedOrgWideEmailAddressId != null) {
      return cachedOrgWideEmailAddressId;
    }

    List<OrgWideEmailAddress> orgWideEmailAddresses = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :NotificationConstants.ORG_WIDE_NOTIFICATION_EMAIL
      LIMIT 1
    ];

    if (!orgWideEmailAddresses.isEmpty()) {
      cachedOrgWideEmailAddressId = orgWideEmailAddresses[0].Id;
    }

    return cachedOrgWideEmailAddressId;
  }

  @TestVisible
  private static Boolean shouldSendAsHtml(Boolean useHtml, String body) {
    return useHtml == true || containsHtmlMarkup(body);
  }

  @TestVisible
  private static Boolean containsHtmlMarkup(String body) {
    if (String.isBlank(body)) {
      return false;
    }

    return HTML_MARKUP_PATTERN.matcher(body).find();
  }

  private static String stripHtml(String htmlBody) {
    if (String.isBlank(htmlBody)) {
      return '';
    }

    return htmlBody.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim();
  }

  public class NotificationEmailDeliveryException extends Exception {
  }
}