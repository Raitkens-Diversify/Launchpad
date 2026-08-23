/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Governor-limit helpers for chunking notification preparation and DML.
 */
public class NotificationGovernorLimitService {
  @TestVisible
  private static Integer testRecipientChunkSizeOverride;

  @TestVisible
  private static List<String> loggedLimitMessages = new List<String>();

  @TestVisible
  private static Boolean testForceInsufficientDeliveryBudget;

  @TestVisible
  private static Boolean testForceDeferPrepareToAsync;

  @TestVisible
  private static Integer testRemainingQueueableBudgetOverride;

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

      return false;
    }

    return getRemainingSoqlBudget() <
      NotificationConstants.SOQL_PREPARE_DEFER_MIN_BUDGET ||
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
    return getRemainingSoqlBudget() >=
      NotificationConstants.SOQL_QUERIES_PER_RECIPIENT_PREPARE_CHUNK;
  }

  public static Boolean canProcessImmediateDelivery() {
    if (Test.isRunningTest() && testForceInsufficientDeliveryBudget == true) {
      return false;
    }

    return getRemainingSoqlBudget() >=
      NotificationConstants.SOQL_QUERIES_PER_IMMEDIATE_DELIVERY;
  }

  public static Integer getSoqlLimit() {
    return Limits.getLimitQueries();
  }

  public static Integer getRemainingSoqlBudget() {
    Integer remainingQueries = getSoqlLimit() - Limits.getQueries();
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
      getSoqlLimit();

    loggedLimitMessages.add(message);
    System.debug(LoggingLevel.ERROR, message);
  }

  @TestVisible
  public static void resetTestState() {
    testRecipientChunkSizeOverride = null;
    testForceInsufficientDeliveryBudget = false;
    testForceDeferPrepareToAsync = false;
    testRemainingQueueableBudgetOverride = null;
    loggedLimitMessages = new List<String>();
  }
}