/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-27
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
      includeExternalActivities == true,
      0
    );
  }

  @AuraEnabled(cacheable=true)
  public static ActivityTimelineModels.ActivityTimelineData getTimelineDataPage(
    Id recordId,
    Boolean includeExternalActivities,
    Integer pageNumber
  ) {
    return SERVICE.getTimelineData(
      recordId,
      includeExternalActivities == true,
      pageNumber
    );
  }
}