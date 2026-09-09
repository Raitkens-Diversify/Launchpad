/**
 * Visibility gate for the Documents tab -- the Egnyte embed -- on the
 * contact detail page (arcHouseholdDetail).
 *
 * In a sandbox every profile sees the tab, so the integration can be
 * exercised end to end on launchpad. In production only the System
 * Administrator profile does. Same code in both orgs; the org decides.
 *
 * The sandbox check is answered without touching Profile, so an external
 * (community) user's visibility in a sandbox never depends on whether their
 * profile can read the Profile object.
 */
public with sharing class ArcDocumentsTabController {
  @TestVisible
  private static final String ADMIN_PROFILE_NAME = 'System Administrator';

  @AuraEnabled(cacheable=true)
  public static Boolean isDocumentsTabVisible() {
    Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    return resolve(isSandbox, isSandbox == true ? null : currentProfileName());
  }

  @TestVisible
  private static Boolean resolve(Boolean isSandbox, String profileName) {
    return isSandbox == true || profileName == ADMIN_PROFILE_NAME;
  }

  @TestVisible
  private static String currentProfileName() {
    return [
      SELECT Name
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
      LIMIT 1
    ]
    .Name;
  }
}