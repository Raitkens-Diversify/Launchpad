/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
 */
@IsTest
private class NotificationChangeSummaryBuilderTest {
  @IsTest
  static void buildPlainTextSummary_coversInsertUpdateAndEmptyPaths() {
    System.assertEquals(
      NotificationConstants.DISPLAY_NOT_APPLICABLE,
      NotificationChangeSummaryBuilder.buildPlainTextSummary(null, null)
    );

    NotificationChangeModels.ChangeContext insertContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_TASK,
      NotificationConstants.CHANGE_TYPE_INSERT
    );
    System.assertEquals(
      'Task created',
      NotificationChangeSummaryBuilder.buildPlainTextSummary(insertContext, 'Task')
    );

    NotificationChangeModels.ChangeContext emptyUpdateContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_CASE,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    System.assertEquals(
      'Record updated',
      NotificationChangeSummaryBuilder.buildPlainTextSummary(emptyUpdateContext, null)
    );

    NotificationChangeModels.ChangeContext fieldUpdateContext = new NotificationChangeModels.ChangeContext(
      NotificationConstants.OBJECT_TYPE_EVENT,
      NotificationConstants.CHANGE_TYPE_UPDATE
    );
    fieldUpdateContext.changedFields.add(
      new NotificationChangeModels.FieldChange(
        'Subject',
        'Subject',
        'Old',
        'New',
        'Old Subject',
        'New Subject'
      )
    );

    String summary = NotificationChangeSummaryBuilder.buildPlainTextSummary(
      fieldUpdateContext,
      'Event'
    );

    System.assert(summary.contains('Subject'));
    System.assert(summary.contains('Old Subject'));
    System.assert(summary.contains('New Subject'));
  }
}