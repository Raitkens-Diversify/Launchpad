/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-06
 *
 * Builds plain-text change summaries for notification log and email surfaces.
 */
public with sharing class NotificationChangeSummaryBuilder {
  public static String buildPlainTextSummary(
    NotificationChangeModels.ChangeContext changeContext,
    String objectLabel
  ) {
    String resolvedObjectLabel = String.isBlank(objectLabel)
      ? 'Record'
      : objectLabel;

    if (changeContext == null) {
      return NotificationConstants.DISPLAY_NOT_APPLICABLE;
    }

    if (changeContext.triggerType == NotificationConstants.CHANGE_TYPE_INSERT) {
      return resolvedObjectLabel + ' created';
    }

    if (
      changeContext.changedFields == null ||
      changeContext.changedFields.isEmpty()
    ) {
      return resolvedObjectLabel + ' updated';
    }

    List<String> summaries = new List<String>();

    for (
      NotificationChangeModels.FieldChange fieldChange : changeContext.changedFields
    ) {
      summaries.add(buildFieldChangeSummary(fieldChange));
    }

    return String.join(summaries, '\n\n');
  }

  private static String buildFieldChangeSummary(
    NotificationChangeModels.FieldChange fieldChange
  ) {
    return fieldChange.label +
      '\nOld: ' +
      fieldChange.oldDisplay +
      '\nNew: ' +
      fieldChange.newDisplay;
  }
}