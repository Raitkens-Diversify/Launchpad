/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-08
 *
 * Aura-enabled facade for Activity Timeline reads.
 */
public with sharing class ActivityTimelineController {
  private static final ActivityTimelineService SERVICE = new ActivityTimelineService();

  @AuraEnabled(cacheable=true)
  public static ActivityTimelineModels.ActivityTimelineData getTimelineData(
    Id recordId,
    Boolean includeExternalActivities
  ) {
    return SERVICE.getTimelineData(
      recordId,
      includeExternalActivities == true
    );
  }
}