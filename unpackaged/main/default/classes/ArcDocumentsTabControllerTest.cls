@IsTest
private class ArcDocumentsTabControllerTest {
  @IsTest
  static void everyProfileSeesTheTabInASandbox() {
    Assert.isTrue(ArcDocumentsTabController.resolve(true, 'Arc'));
    Assert.isTrue(ArcDocumentsTabController.resolve(true, null));
    Assert.isTrue(
      ArcDocumentsTabController.resolve(true, ArcDocumentsTabController.ADMIN_PROFILE_NAME)
    );
  }

  @IsTest
  static void onlySystemAdministratorsSeeTheTabInProduction() {
    Assert.isTrue(
      ArcDocumentsTabController.resolve(false, ArcDocumentsTabController.ADMIN_PROFILE_NAME)
    );
    Assert.isFalse(ArcDocumentsTabController.resolve(false, 'Arc'));
    Assert.isFalse(ArcDocumentsTabController.resolve(false, null));
    Assert.isFalse(ArcDocumentsTabController.resolve(null, 'Arc'));
  }

  @IsTest
  static void currentProfileNameIsTheRunningUsersProfile() {
    String expected = [
      SELECT Name
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
    ]
    .Name;

    Assert.areEqual(expected, ArcDocumentsTabController.currentProfileName());
  }

  @IsTest
  static void isDocumentsTabVisibleFollowsTheRunningOrgAndProfile() {
    Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    String profileName = [
      SELECT Name
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
    ]
    .Name;

    Test.startTest();
    Boolean visible = ArcDocumentsTabController.isDocumentsTabVisible();
    Test.stopTest();

    Assert.areEqual(
      ArcDocumentsTabController.resolve(isSandbox, profileName),
      visible
    );
  }
}