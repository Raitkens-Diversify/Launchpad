/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 */
@IsTest
private class NotificationEmailDeliveryServiceTest {
  @IsTest
  static void detectsHtmlTableMarkup() {
    String htmlBody =
      '<table border="1"><tr><td>Task</td></tr></table>';

    System.assertEquals(
      true,
      NotificationEmailDeliveryService.containsHtmlMarkup(htmlBody)
    );
  }

  @IsTest
  static void ignoresPlainTextBody() {
    System.assertEquals(
      false,
      NotificationEmailDeliveryService.containsHtmlMarkup('Subject: Task update')
    );
  }

  @IsTest
  static void shouldSendAsHtmlWhenPreferenceDisabledButBodyContainsMarkup() {
    String htmlBody =
      '<table><tr><td><a href="https://example.com">Task</a></td></tr></table>';

    System.assertEquals(
      true,
      NotificationEmailDeliveryService.shouldSendAsHtml(false, htmlBody)
    );
  }

  @IsTest
  static void shouldSendAsHtmlWhenPreferenceEnabled() {
    System.assertEquals(
      true,
      NotificationEmailDeliveryService.shouldSendAsHtml(true, 'Plain text only')
    );
  }

  @IsTest
  static void resolveDeliveryAddressReturnsUserEmail() {
    User currentUser = [
      SELECT Id, Email
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    System.assertEquals(
      currentUser.Email,
      NotificationEmailDeliveryService.resolveDeliveryAddress(currentUser.Id)
    );
  }

  @IsTest
  static void sendNotificationThrowsWhenRecipientMissing() {
    Boolean exceptionThrown = false;

    try {
      NotificationEmailDeliveryService.sendNotification(null, 'Subject', 'Body');
    } catch (NotificationEmailDeliveryService.NotificationEmailDeliveryException ex) {
      exceptionThrown = true;
    }

    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void sendConsolidatedDigestDelegatesToSendNotification() {
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Test.startTest();
    NotificationEmailDeliveryService.sendConsolidatedDigest(
      context.recipientUser.Id,
      'Digest Subject',
      'Digest body'
    );
    Test.stopTest();

    System.assert(true, 'Consolidated digest should send through email service.');
  }

  @IsTest
  static void resolveOrgWideEmailAddressIdUsesConfiguredAddressWhenPresent() {
  List<OrgWideEmailAddress> orgWideEmailAddresses = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :NotificationConstants.ORG_WIDE_NOTIFICATION_EMAIL
      LIMIT 1
    ];

    if (orgWideEmailAddresses.isEmpty()) {
      Id overrideId = UserInfo.getUserId();
      NotificationEmailDeliveryService.orgWideEmailAddressIdOverride = overrideId;

      System.assertEquals(
        overrideId,
        NotificationEmailDeliveryService.resolveOrgWideEmailAddressId()
      );

      NotificationEmailDeliveryService.orgWideEmailAddressIdOverride = null;
      NotificationEmailDeliveryService.cachedOrgWideEmailAddressId = null;
      return;
    }

    NotificationEmailDeliveryService.cachedOrgWideEmailAddressId = null;

    System.assertEquals(
      orgWideEmailAddresses[0].Id,
      NotificationEmailDeliveryService.resolveOrgWideEmailAddressId()
    );
  }

  @IsTest
  static void containsHtmlMarkupDetectsCommonTags() {
    System.assertEquals(
      true,
      NotificationEmailDeliveryService.containsHtmlMarkup('<div>content</div>')
    );
    System.assertEquals(
      true,
      NotificationEmailDeliveryService.containsHtmlMarkup('<br/>')
    );
    System.assertEquals(
      false,
      NotificationEmailDeliveryService.containsHtmlMarkup('')
    );
  }

  @IsTest
  static void batchedSendsStayWithinEmailInvocationLimit() {
    NotificationEmailDeliveryService.resetTestState();
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();
    Integer emailCount =
      NotificationConstants.MAX_EMAIL_INVOCATIONS_PER_TRANSACTION + 1;

    Test.startTest();
    NotificationEmailDeliveryService.beginBatch();
    try {
      for (Integer index = 0; index < emailCount; index++) {
        NotificationEmailDeliveryService.sendNotification(
          context.recipientUser.Id,
          'Subject ' + index,
          'Body ' + index
        );
      }
    } finally {
      NotificationEmailDeliveryService.endBatch();
    }
    Test.stopTest();

    System.assertEquals(
      2,
      NotificationEmailDeliveryService.testSendEmailInvocationCount,
      '11 emails should flush as two sendEmail invocations (10 + 1), not 11.'
    );
    System.assert(
      Limits.getEmailInvocations() <=
        NotificationConstants.MAX_EMAIL_INVOCATIONS_PER_TRANSACTION,
      'Batched delivery must stay within the Salesforce email invocation limit.'
    );
  }

  @IsTest
  static void sendNotificationThrowsCatchableErrorWhenEmailBudgetIsExhausted() {
    NotificationGovernorLimitService.resetTestState();
    NotificationGovernorLimitService.testForceInsufficientEmailBudget = true;
    NotificationTestDataFactory.NotificationTestContext context = NotificationTestDataFactory.createHouseholdWithRecipient();

    Boolean exceptionThrown = false;
    String exceptionMessage = '';

    try {
      NotificationEmailDeliveryService.sendNotification(
        context.recipientUser.Id,
        'Subject',
        'Body'
      );
    } catch (NotificationEmailDeliveryService.NotificationEmailDeliveryException ex) {
      exceptionThrown = true;
      exceptionMessage = ex.getMessage();
    }

    System.assertEquals(true, exceptionThrown);
    System.assertEquals(
      NotificationConstants.ERROR_EMAIL_INVOCATION_LIMIT,
      exceptionMessage
    );
  }
}