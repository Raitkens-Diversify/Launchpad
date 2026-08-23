/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-24
 */
@IsTest
private class NotificationTrackedFieldRepoTest {
  @IsTest
  static void selectActiveTrackedFieldsReturnsTaskDefaults() {
    NotificationTrackedFieldRepository.resetCacheForTest();

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields(NotificationConstants.OBJECT_TYPE_TASK);

    System.assert(trackedFields.size() >= 4);

    Set<String> fieldApiNames = new Set<String>();
    for (
      NotificationChangeModels.TrackedFieldDefinition trackedField : trackedFields
    ) {
      fieldApiNames.add(trackedField.fieldApiName);
    }

    System.assert(fieldApiNames.contains('OwnerId'));
    System.assert(fieldApiNames.contains('Status'));
    System.assert(fieldApiNames.contains('ActivityDate'));
    System.assert(fieldApiNames.contains('Priority'));
  }

  @IsTest
  static void selectActiveTrackedFieldsReturnsCaseDefaults() {
    NotificationTrackedFieldRepository.resetCacheForTest();

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields(NotificationConstants.OBJECT_TYPE_CASE);

    System.assertEquals(2, trackedFields.size());

    Set<String> fieldApiNames = new Set<String>();
    for (
      NotificationChangeModels.TrackedFieldDefinition trackedField : trackedFields
    ) {
      fieldApiNames.add(trackedField.fieldApiName);
    }

    System.assert(fieldApiNames.contains('OwnerId'));
    System.assert(fieldApiNames.contains('Status'));
  }

  @IsTest
  static void selectActiveTrackedFieldsReturnsEmptyForUnknownObject() {
    NotificationTrackedFieldRepository.resetCacheForTest();

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields('Unknown_Object');

    System.assertEquals(0, trackedFields.size());
  }
}