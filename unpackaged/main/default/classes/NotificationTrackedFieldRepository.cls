/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-27
 *
 * Code-defined tracked fields for notification change detection by object type.
 */
public with sharing class NotificationTrackedFieldRepository {
  private static Map<String, List<NotificationChangeModels.TrackedFieldDefinition>> cachedDefinitionsByObjectType;

  public List<NotificationChangeModels.TrackedFieldDefinition> selectActiveTrackedFields(
    String objectType
  ) {
    if (String.isBlank(objectType)) {
      return new List<NotificationChangeModels.TrackedFieldDefinition>();
    }

    if (
      cachedDefinitionsByObjectType != null &&
      cachedDefinitionsByObjectType.containsKey(objectType)
    ) {
      return cachedDefinitionsByObjectType.get(objectType);
    }

    List<NotificationChangeModels.TrackedFieldDefinition> definitions = trackedFieldDefinitions(
      objectType
    );

    if (cachedDefinitionsByObjectType == null) {
      cachedDefinitionsByObjectType = new Map<String, List<NotificationChangeModels.TrackedFieldDefinition>>();
    }

    cachedDefinitionsByObjectType.put(objectType, definitions);
    return definitions;
  }

  @TestVisible
  static void resetCacheForTest() {
    cachedDefinitionsByObjectType = null;
  }

  private static List<NotificationChangeModels.TrackedFieldDefinition> trackedFieldDefinitions(
    String objectType
  ) {
    if (objectType == NotificationConstants.OBJECT_TYPE_TASK) {
      return new List<NotificationChangeModels.TrackedFieldDefinition>{
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'OwnerId',
          'Assigned To',
          10,
          true,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'Status',
          'Status',
          20,
          false,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'ActivityDate',
          'Due Date',
          30,
          false,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'Priority',
          'Priority',
          40,
          false,
          false
        )
      };
    }

    if (objectType == NotificationConstants.OBJECT_TYPE_CASE) {
      return new List<NotificationChangeModels.TrackedFieldDefinition>{
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'OwnerId',
          'Assigned To',
          10,
          true,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'Status',
          'Status',
          20,
          false,
          false
        )
      };
    }

    if (objectType == NotificationConstants.OBJECT_TYPE_EVENT) {
      return new List<NotificationChangeModels.TrackedFieldDefinition>{
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'OwnerId',
          'Assigned to',
          10,
          true,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'Subject',
          'Subject',
          20,
          false,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'StartDateTime',
          'Start Date/Time',
          30,
          false,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'EndDateTime',
          'End Date/Time',
          40,
          false,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'WhoId',
          'Name',
          50,
          false,
          true
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'WhatId',
          'Related To',
          60,
          false,
          true
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'Description',
          'Description',
          70,
          false,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'Location',
          'Location',
          80,
          false,
          false
        ),
        new NotificationChangeModels.TrackedFieldDefinition(
          objectType,
          'IsArchived',
          'Cancelled',
          90,
          false,
          false
        )
      };
    }

    return new List<NotificationChangeModels.TrackedFieldDefinition>();
  }
}