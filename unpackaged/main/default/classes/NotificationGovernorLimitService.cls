/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-26
 *
 * Governor-limit helpers for chunking notification preparation, DML, and email send.
 */
public class NotificationGovernorLimitService {
  @TestVisible
  private static Integer testRecipientChunkSizeOverride;

  @TestVisible
  private static List<String> loggedLimitMessages = new List<String>();

  @TestVisible
  private static Boolean testForceInsufficientDeliveryBudget;

  @TestVisible
  private static Boolean testForceInsufficientEmailBudget;

  @TestVisible
  private static Boolean testForceDeferPrepareToAsync;

  @TestVisible
  private static Integer testRemainingQueueableBudgetOverride;

  @TestVisible
  private static Integer testRemainingEmailInvocationBudgetOverride;

  @TestVisible
  private static Integer testRemainingSoqlBudgetOverride;

  public static Boolean shouldDeferPrepareToAsync() {
    if (System.isQueueable() || System.isBatch()) {
      return false;
    }

    if (Test.isRunningTest()) {
      if (testForceDeferPrepareToAsync == true) {
        return true;
      }

      if (
        testRemainingQueueableBudgetOverride != null &&
        testRemainingQueueableBudgetOverride <
        NotificationConstants.MIN_QUEUEABLE_BUDGET_FOR_SYNC_PREPARE
      ) {
        return true;
      }

      if (testRemainingSoqlBudgetOverride != null) {
        return !canAffordPrepareSourceRecord();
      }

      return false;
    }

    return !canAffordPrepareSourceRecord() ||
      getRemainingQueueableBudget() <
      NotificationConstants.MIN_QUEUEABLE_BUDGET_FOR_SYNC_PREPARE;
  }

  public static Integer getQueueableLimit() {
    return Limits.getLimitQueueableJobs();
  }

  public static Integer getRemainingQueueableBudget() {
    if (Test.isRunningTest() && testRemainingQueueableBudgetOverride != null) {
      return Math.max(0, testRemainingQueueableBudgetOverride);
    }

    return Math.max(0, getQueueableLimit() - Limits.getQueueableJobs());
  }

  public static Boolean canEnqueueQueueableJob() {
    return getRemainingQueueableBudget() > 0;
  }

  public static Integer resolveMaxDeliveryEnqueueJobs() {
    if (System.isBatch() || System.isQueueable()) {
      return 1;
    }

    Integer remainingBudget = getRemainingQueueableBudget();
    Integer chainReserve = NotificationConstants.QUEUEABLE_CHAIN_RESERVE_SLOTS;
    Integer safeBudget = Math.max(0, remainingBudget - chainReserve);

    return Math.min(
      NotificationConstants.MAX_DIGEST_JOBS_PER_TRANSACTION,
      safeBudget
    );
  }

  public static Boolean canProcessAnotherRecipientChunk() {
    return canAffordSoql(
      NotificationConstants.SOQL_QUERIES_PER_RECIPIENT_PREPARE_CHUNK
    );
  }

  public static Boolean canProcessImmediateDelivery() {
    if (Test.isRunningTest() && testForceInsufficientDeliveryBudget == true) {
      return false;
    }

    return canAffordSoql(NotificationConstants.SOQL_QUERIES_PER_IMMEDIATE_DELIVERY);
  }

  public static Boolean canAffordPrepareSourceRecord() {
    return canAffordSoql(NotificationConstants.SOQL_QUERIES_PER_PREPARE_SOURCE) &&
      getRemainingSoqlBudget() >= NotificationConstants.SOQL_PREPARE_DEFER_MIN_BUDGET;
  }

  public static Boolean canAffordSoql(Integer estimatedQueries) {
    Integer safeEstimate = estimatedQueries == null || estimatedQueries < 1
      ? 1
      : estimatedQueries;

    return getRawRemainingSoqlQueries() >
      safeEstimate + NotificationConstants.SOQL_HARD_STOP_BUFFER;
  }

  public static Integer getRawRemainingSoqlQueries() {
    if (Test.isRunningTest() && testRemainingSoqlBudgetOverride != null) {
      return Math.max(0, testRemainingSoqlBudgetOverride);
    }

    return Math.max(0, getSoqlLimit() - Limits.getQueries());
  }

  public static Boolean isSoqlLimitMessage(String errorMessage) {
    if (String.isBlank(errorMessage)) {
      return false;
    }

    return errorMessage.contains('Too many SOQL queries') ||
      errorMessage == NotificationConstants.ERROR_SOQL_QUERY_LIMIT;
  }

  public static Boolean canInvokeSendEmail() {
    return getRemainingEmailInvocationBudget() > 0;
  }

  public static Integer getEmailInvocationLimit() {
    return Limits.getLimitEmailInvocations();
  }

  public static Integer getRemainingEmailInvocationBudget() {
    if (Test.isRunningTest() && testForceInsufficientEmailBudget == true) {
      return 0;
    }

    if (
      Test.isRunningTest() &&
      testRemainingEmailInvocationBudgetOverride != null
    ) {
      return Math.max(0, testRemainingEmailInvocationBudgetOverride);
    }

    Integer remainingInvocations =
      getEmailInvocationLimit() - Limits.getEmailInvocations();
    return Math.max(
      0,
      remainingInvocations - NotificationConstants.EMAIL_INVOCATION_SAFETY_BUFFER
    );
  }

  public static Boolean isEmailInvocationLimitMessage(String errorMessage) {
    if (String.isBlank(errorMessage)) {
      return false;
    }

    return errorMessage.contains('Too many Email Invocations') ||
      errorMessage == NotificationConstants.ERROR_EMAIL_INVOCATION_LIMIT;
  }

  public static Integer getSoqlLimit() {
    return Limits.getLimitQueries();
  }

  public static Integer getRemainingSoqlBudget() {
    Integer remainingQueries = getRawRemainingSoqlQueries();
    return Math.max(0, remainingQueries - NotificationConstants.SOQL_SAFETY_BUFFER);
  }

  public static Integer resolveRecipientChunkSize(Integer remainingRecipients) {
    if (remainingRecipients == null || remainingRecipients <= 0) {
      return 0;
    }

    Integer configuredChunkSize = NotificationConstants.MAX_RECIPIENTS_PER_PREPARE_CHUNK;

    if (Test.isRunningTest() && testRecipientChunkSizeOverride != null) {
      configuredChunkSize = testRecipientChunkSizeOverride;
    }

    Integer budgetChunkSize = resolveBudgetBasedRecipientChunkSize();
    configuredChunkSize = Math.min(configuredChunkSize, budgetChunkSize);

    return Math.min(configuredChunkSize, remainingRecipients);
  }

  @TestVisible
  private static Integer resolveBudgetBasedRecipientChunkSize() {
    Integer queriesPerRecipient = NotificationConstants.SOQL_QUERIES_PER_RECIPIENT_PREPARE_CHUNK;

    if (queriesPerRecipient <= 0) {
      return NotificationConstants.MAX_RECIPIENTS_PER_PREPARE_CHUNK;
    }

    Integer budgetChunkSize = getRemainingSoqlBudget() / queriesPerRecipient;

    return Math.max(
      budgetChunkSize,
      NotificationConstants.MIN_RECIPIENTS_PER_PREPARE_CHUNK
    );
  }

  public static Integer shrinkRecipientChunkSize(Integer currentChunkSize) {
    Integer safeChunkSize = currentChunkSize == null
      ? NotificationConstants.MAX_RECIPIENTS_PER_PREPARE_CHUNK
      : currentChunkSize;
    Integer nextChunkSize = safeChunkSize / 2;

    return Math.max(
      nextChunkSize,
      NotificationConstants.MIN_RECIPIENTS_PER_PREPARE_CHUNK
    );
  }

  public static List<Id> sliceIds(List<Id> values, Integer startIndex, Integer endIndex) {
    List<Id> sliceValues = new List<Id>();

    if (values == null || values.isEmpty() || startIndex == null || endIndex == null) {
      return sliceValues;
    }

    Integer safeStartIndex = Math.max(0, startIndex);
    Integer safeEndIndex = Math.min(endIndex, values.size());

    for (Integer index = safeStartIndex; index < safeEndIndex; index++) {
      sliceValues.add(values[index]);
    }

    return sliceValues;
  }

  public static void insertInChunks(List<SObject> records) {
    if (records == null || records.isEmpty()) {
      return;
    }

    Integer chunkSize = NotificationConstants.MAX_LOGS_PER_DML_CHUNK;

    for (
      Integer startIndex = 0;
      startIndex < records.size();
      startIndex += chunkSize
    ) {
      Integer endIndex = Math.min(startIndex + chunkSize, records.size());
      List<SObject> chunkRecords = new List<SObject>();

      for (Integer index = startIndex; index < endIndex; index++) {
        chunkRecords.add(records[index]);
      }

      insert chunkRecords;
    }
  }

  public static Boolean isLimitException(Exception error) {
    return error instanceof LimitException;
  }

  public static void logLimitException(String context, Exception error) {
    if (error == null) {
      return;
    }

    String message =
      context +
      ': ' +
      error.getTypeName() +
      ' - ' +
      error.getMessage() +
      ' | SOQL ' +
      Limits.getQueries() +
      '/' +
      getSoqlLimit() +
      ' | Email ' +
      Limits.getEmailInvocations() +
      '/' +
      getEmailInvocationLimit();

    loggedLimitMessages.add(message);
    System.debug(LoggingLevel.ERROR, message);
  }

  @TestVisible
  public static void resetTestState() {
    testRecipientChunkSizeOverride = null;
    testForceInsufficientDeliveryBudget = false;
    testForceInsufficientEmailBudget = false;
    testForceDeferPrepareToAsync = false;
    testRemainingQueueableBudgetOverride = null;
    testRemainingEmailInvocationBudgetOverride = null;
    testRemainingSoqlBudgetOverride = null;
    loggedLimitMessages = new List<String>();

    if (Test.isRunningTest()) {
      NotificationEmailDeliveryService.resetTestState();
    }
  }
}