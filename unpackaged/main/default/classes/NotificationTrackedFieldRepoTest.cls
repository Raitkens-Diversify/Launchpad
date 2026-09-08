/**
 * Author: Hoang Long Vu To
 * Date: 2026-09-07
 */
@IsTest
private class NotificationTrackedFieldRepoTest {
  @IsTest
  static void selectActiveTrackedFieldsReturnsTaskDefaults() {
    NotificationTrackedFieldRepository.resetCacheForTest();

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields(NotificationConstants.OBJECT_TYPE_TASK);

    System.assertEquals(1, trackedFields.size());

    Set<String> fieldApiNames = new Set<String>();
    for (
      NotificationChangeModels.TrackedFieldDefinition trackedField : trackedFields
    ) {
      fieldApiNames.add(trackedField.fieldApiName);
    }

    System.assert(fieldApiNames.contains('OwnerId'));
    System.assertEquals(false, fieldApiNames.contains('Status'));
    System.assertEquals(false, fieldApiNames.contains('ActivityDate'));
    System.assertEquals(false, fieldApiNames.contains('Priority'));

    List<NotificationChangeModels.TrackedFieldDefinition> cachedTrackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields(NotificationConstants.OBJECT_TYPE_TASK);
    System.assertEquals(1, cachedTrackedFields.size());
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
  static void selectActiveTrackedFieldsReturnsEventDefaults() {
    NotificationTrackedFieldRepository.resetCacheForTest();

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields(NotificationConstants.OBJECT_TYPE_EVENT);

    Set<String> fieldApiNames = new Set<String>();
    for (
      NotificationChangeModels.TrackedFieldDefinition trackedField : trackedFields
    ) {
      fieldApiNames.add(trackedField.fieldApiName);
    }

    System.assert(fieldApiNames.contains('OwnerId'));
    System.assert(fieldApiNames.contains('Subject'));
    System.assert(fieldApiNames.contains('StartDateTime'));
    System.assert(fieldApiNames.contains('EndDateTime'));
    System.assert(fieldApiNames.contains('WhoId'));
    System.assert(fieldApiNames.contains('WhatId'));
    System.assert(fieldApiNames.contains('Description'));
    System.assert(fieldApiNames.contains('Location'));
    System.assert(fieldApiNames.contains('IsArchived'));
  }

  @IsTest
  static void selectActiveTrackedFieldsReturnsEmptyForBlankObjectType() {
    NotificationTrackedFieldRepository.resetCacheForTest();

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields('');

    System.assertEquals(0, trackedFields.size());
  }

  @IsTest
  static void selectActiveTrackedFieldsReturnsEmptyForUnknownObject() {
    NotificationTrackedFieldRepository.resetCacheForTest();

    List<NotificationChangeModels.TrackedFieldDefinition> trackedFields = new NotificationTrackedFieldRepository()
      .selectActiveTrackedFields('Unknown_Object');

    System.assertEquals(0, trackedFields.size());
  }
}