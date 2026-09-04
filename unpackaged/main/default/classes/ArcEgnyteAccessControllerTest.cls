/**
 * Tests for ArcEgnyteAccessController.
 *
 * The point of the class is that the URL is on the ORG domain rather than the
 * community's, so that is what these assert: the origin matches
 * Url.getOrgDomainUrl(), and the record id survives.
 */
@IsTest
private class ArcEgnyteAccessControllerTest {
  @IsTest
  static void pointsAtTheOrgDomainNotTheCommunity() {
    Test.startTest();
    String pageUrl = ArcEgnyteAccessController.getApprovalUrl(null);
    Test.stopTest();

    String origin = Url.getOrgDomainUrl().toExternalForm().removeEnd('/');
    Assert.isTrue(
      pageUrl.startsWith(origin),
      'The approval flow only works off the org domain, where no community CSP applies.'
    );
    Assert.isTrue(
      pageUrl.endsWith('/apex/Egnyte_integration_page'),
      'A blank record still needs to reach the approval prompt.'
    );
  }

  @IsTest
  static void carriesTheRecordId() {
    Account record = new Account(Name = 'Egnyte Access Test Account', Classification__c = 'Unclassified');
    insert record;

    Test.startTest();
    String pageUrl = ArcEgnyteAccessController.getApprovalUrl(record.Id);
    Test.stopTest();

    Assert.isTrue(
      pageUrl.contains('id=' + record.Id),
      'The page needs the record to know which documents to show.'
    );
  }

  @IsTest
  static void ignoresBlankAndWhitespaceIds() {
    Test.startTest();
    String blank = ArcEgnyteAccessController.getApprovalUrl('   ');
    Test.stopTest();

    Assert.isFalse(
      blank.contains('?id='),
      'Whitespace is not a record id and should not be sent as one.'
    );
  }
}