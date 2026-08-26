/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 *
 * Sends notification emails for immediate and digest delivery.
 * Batches Messaging.sendEmail so one transaction stays within the
 * 10-invocation governor limit (see Salesforce article 000385111).
 */
public without sharing class NotificationEmailDeliveryService {
  @TestVisible
  private static Id orgWideEmailAddressIdOverride;

  @TestVisible
  private static Id cachedOrgWideEmailAddressId;

  @TestVisible
  private static Integer batchDepth = 0;

  @TestVisible
  private static Integer testSendEmailInvocationCount = 0;

  @TestVisible
  private static final Pattern HTML_MARKUP_PATTERN = Pattern.compile(
    '(?i)<(table|a\\s|div|p|br\\s*/?|html|body|thead|tbody|tr|td|th|span|ul|ol|li|h[1-6])\\b'
  );

  private static List<PendingEmail> pendingEmails = new List<PendingEmail>();

  public static void beginBatch() {
    batchDepth++;
  }

  public static void endBatch() {
    if (batchDepth > 0) {
      batchDepth--;
    }

    if (batchDepth == 0) {
      flush();
    }
  }

  public static Boolean isBatchMode() {
    return batchDepth > 0;
  }

  public static void sendNotification(
    Id recipientId,
    String subject,
    String body
  ) {
    sendNotification(recipientId, subject, body, null);
  }

  public static void sendNotification(
    Id recipientId,
    String subject,
    String body,
    List<Notification_Log__c> logs
  ) {
    if (recipientId == null) {
      throw new NotificationEmailDeliveryException('Recipient Id is required.');
    }

    pendingEmails.add(new PendingEmail(recipientId, subject, body, logs));

    if (batchDepth == 0) {
      flush();
    }
  }

  public static void sendConsolidatedDigest(
    Id recipientId,
    String subject,
    String body
  ) {
    sendNotification(recipientId, subject, body);
  }

  public static void flush() {
    if (pendingEmails.isEmpty()) {
      return;
    }

    List<PendingEmail> emailsToSend = pendingEmails;
    pendingEmails = new List<PendingEmail>();

    Map<Id, String> recipientIdToAddress = resolveDeliveryAddresses(
      collectRecipientIds(emailsToSend)
    );

    List<Messaging.SingleEmailMessage> chunkMessages = new List<Messaging.SingleEmailMessage>();
    List<PendingEmail> chunkEmails = new List<PendingEmail>();
    List<Notification_Log__c> sentLogs = new List<Notification_Log__c>();
    List<String> failureMessages = new List<String>();
    Boolean hitInvocationLimit = false;

    for (PendingEmail pendingEmail : emailsToSend) {
      String toAddress = recipientIdToAddress.get(pendingEmail.recipientId);

      if (String.isBlank(toAddress)) {
        failureMessages.add(
          'No email delivery address is configured for this user.'
        );
        continue;
      }

      chunkMessages.add(
        buildEmailMessage(toAddress, pendingEmail.subject, pendingEmail.body, true)
      );
      chunkEmails.add(pendingEmail);

      if (
        chunkMessages.size() >=
        NotificationConstants.MAX_EMAILS_PER_SEND_EMAIL_INVOCATION
      ) {
        SendChunkResult chunkResult = sendChunk(chunkMessages, chunkEmails);
        sentLogs.addAll(chunkResult.sentLogs);
        failureMessages.addAll(chunkResult.failureMessages);
        hitInvocationLimit =
          hitInvocationLimit || chunkResult.hitInvocationLimit;
        chunkMessages = new List<Messaging.SingleEmailMessage>();
        chunkEmails = new List<PendingEmail>();

        if (chunkResult.hitInvocationLimit) {
          break;
        }
      }
    }

    if (!chunkMessages.isEmpty() && !hitInvocationLimit) {
      SendChunkResult chunkResult = sendChunk(chunkMessages, chunkEmails);
      sentLogs.addAll(chunkResult.sentLogs);
      failureMessages.addAll(chunkResult.failureMessages);
      hitInvocationLimit = chunkResult.hitInvocationLimit;
    }

    if (!sentLogs.isEmpty()) {
      NotificationLogDeliveryService.markSent(sentLogs);
    }

    if (hitInvocationLimit && sentLogs.isEmpty()) {
      throw new NotificationEmailDeliveryException(
        NotificationConstants.ERROR_EMAIL_INVOCATION_LIMIT
      );
    }

    if (!failureMessages.isEmpty() && sentLogs.isEmpty()) {
      throw new NotificationEmailDeliveryException(failureMessages[0]);
    }
  }

  public static String resolveDeliveryAddress(Id recipientId) {
    Map<Id, String> recipientIdToAddress = resolveDeliveryAddresses(
      new Set<Id>{ recipientId }
    );
    return recipientIdToAddress.get(recipientId);
  }

  @TestVisible
  public static void resetTestState() {
    pendingEmails = new List<PendingEmail>();
    batchDepth = 0;
    testSendEmailInvocationCount = 0;
  }

  private static SendChunkResult sendChunk(
    List<Messaging.SingleEmailMessage> messages,
    List<PendingEmail> chunkEmails
  ) {
    SendChunkResult chunkResult = new SendChunkResult();

    if (messages == null || messages.isEmpty()) {
      return chunkResult;
    }

    if (!NotificationGovernorLimitService.canInvokeSendEmail()) {
      chunkResult.hitInvocationLimit = true;
      return chunkResult;
    }

    List<Messaging.SendEmailResult> results = Messaging.sendEmail(
      messages,
      false
    );
    testSendEmailInvocationCount++;

    for (Integer index = 0; index < chunkEmails.size(); index++) {
      PendingEmail pendingEmail = chunkEmails[index];
      Boolean isSuccess =
        results != null &&
        index < results.size() &&
        results[index].isSuccess();

      if (isSuccess) {
        chunkResult.sentLogs.addAll(safeLogs(pendingEmail));
        continue;
      }

      String errorMessage = 'Email delivery failed.';

      if (
        results != null &&
        index < results.size() &&
        results[index].getErrors() != null &&
        !results[index].getErrors().isEmpty()
      ) {
        errorMessage = results[index].getErrors()[0].getMessage();
      }

      chunkResult.failureMessages.add(errorMessage);
    }

    return chunkResult;
  }

  private static Map<Id, String> resolveDeliveryAddresses(Set<Id> recipientIds) {
    Map<Id, String> recipientIdToAddress = new Map<Id, String>();

    if (recipientIds == null || recipientIds.isEmpty()) {
      return recipientIdToAddress;
    }

    for (User userRecord : [
      SELECT Id, Email
      FROM User
      WHERE Id IN :recipientIds
    ]) {
      recipientIdToAddress.put(userRecord.Id, userRecord.Email);
    }

    return recipientIdToAddress;
  }

  private static Set<Id> collectRecipientIds(List<PendingEmail> emails) {
    Set<Id> recipientIds = new Set<Id>();

    for (PendingEmail pendingEmail : emails) {
      if (pendingEmail.recipientId != null) {
        recipientIds.add(pendingEmail.recipientId);
      }
    }

    return recipientIds;
  }

  private static List<Notification_Log__c> safeLogs(PendingEmail pendingEmail) {
    if (pendingEmail == null || pendingEmail.logs == null) {
      return new List<Notification_Log__c>();
    }

    List<Notification_Log__c> logsWithIds = new List<Notification_Log__c>();

    for (Notification_Log__c logRecord : pendingEmail.logs) {
      if (logRecord != null && logRecord.Id != null) {
        logsWithIds.add(logRecord);
      }
    }

    return logsWithIds;
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

  private class PendingEmail {
    public Id recipientId;
    public String subject;
    public String body;
    public List<Notification_Log__c> logs;

    public PendingEmail(
      Id recipientId,
      String subject,
      String body,
      List<Notification_Log__c> logs
    ) {
      this.recipientId = recipientId;
      this.subject = subject;
      this.body = body;
      this.logs = logs;
    }
  }

  private class SendChunkResult {
    public List<Notification_Log__c> sentLogs = new List<Notification_Log__c>();
    public List<String> failureMessages = new List<String>();
    public Boolean hitInvocationLimit = false;
  }

  public class NotificationEmailDeliveryException extends Exception {
  }
}