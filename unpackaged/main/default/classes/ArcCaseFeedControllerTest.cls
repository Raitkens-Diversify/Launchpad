/**
 * Tests for ArcCaseFeedController.
 *
 * The reshaping logic — dropping the feedEvent row, collapsing a reference
 * field's duplicate id/name pair, resolving labels — cannot be driven end to end
 * from a test, because FeedTrackedChange is not insertable: the platform writes
 * those rows itself when a tracked field changes. So the round trip is covered
 * with a text post, and the reshaping rules are covered directly through the
 * @TestVisible helpers they live in.
 */
@IsTest
private class ArcCaseFeedControllerTest {
  /** Mirrors the Case recipe already proven in ArcRelatedTableTestData. */
  private static Case makeCase() {
    Case record = new Case(
      Subject = 'Feed Panel Test Case',
      Status = 'New',
      Origin = 'Phone'
    );
    insert record;
    return record;
  }

  @IsTest
  static void returnsPostsNewestFirst() {
    Case record = makeCase();

    List<FeedItem> posts = new List<FeedItem>{
      new FeedItem(ParentId = record.Id, Body = 'First note'),
      new FeedItem(ParentId = record.Id, Body = 'Second note')
    };
    insert posts;

    Test.startTest();
    ArcCaseFeedController.FeedResult result = ArcCaseFeedController.getRecordFeed(
      record.Id,
      10
    );
    Test.stopTest();

    Assert.areEqual(2, result.entries.size(), 'Both posts should come back.');
    Assert.isFalse(result.hasMore, 'Two posts do not exceed a page of ten.');

    ArcCaseFeedController.FeedEntry first = result.entries[0];
    Assert.isNotNull(first.actorName, 'The post author should be populated.');
    Assert.isNotNull(first.createdDate, 'The post date should be populated.');
    Assert.areEqual(
      0,
      first.changes.size(),
      'A text post carries no tracked changes.'
    );
  }

  @IsTest
  static void reportsHasMoreBeyondThePage() {
    Case record = makeCase();

    List<FeedItem> posts = new List<FeedItem>();
    for (Integer i = 0; i < 3; i++) {
      posts.add(new FeedItem(ParentId = record.Id, Body = 'Note ' + i));
    }
    insert posts;

    Test.startTest();
    ArcCaseFeedController.FeedResult result = ArcCaseFeedController.getRecordFeed(
      record.Id,
      2
    );
    Test.stopTest();

    Assert.areEqual(2, result.entries.size(), 'A page of two returns two.');
    Assert.isTrue(result.hasMore, 'A third post means there is more to load.');
  }

  @IsTest
  static void emptyResultForNullRecordId() {
    Test.startTest();
    ArcCaseFeedController.FeedResult result = ArcCaseFeedController.getRecordFeed(
      null,
      10
    );
    Test.stopTest();

    Assert.areEqual(0, result.entries.size(), 'No record means no entries.');
    Assert.isFalse(result.hasMore, 'No record means nothing more to load.');
  }

  @IsTest
  static void defaultsAndCapsThePageSize() {
    Case record = makeCase();
    insert new FeedItem(ParentId = record.Id, Body = 'Only note');

    Test.startTest();
    // Null, zero and negative all fall back to the default rather than
    // producing a LIMIT of zero or a query exception.
    Assert.areEqual(
      1,
      ArcCaseFeedController.getRecordFeed(record.Id, null).entries.size(),
      'A null page size should fall back to the default.'
    );
    Assert.areEqual(
      1,
      ArcCaseFeedController.getRecordFeed(record.Id, 0).entries.size(),
      'A zero page size should fall back to the default.'
    );
    Assert.areEqual(
      1,
      ArcCaseFeedController.getRecordFeed(record.Id, -5).entries.size(),
      'A negative page size should fall back to the default.'
    );
    Assert.areEqual(
      1,
      ArcCaseFeedController.getRecordFeed(record.Id, 5000).entries.size(),
      'An oversized page size should be capped, not rejected.'
    );
    Test.stopTest();
  }

  @IsTest
  static void resolvesLabelsTheWayLightningShowsThem() {
    // The whole reason resolveFieldLabel exists: a tracked change names the
    // relationship, while the label lives on the id field.
    Assert.areEqual(
      Case.AccountId.getDescribe().getLabel(),
      ArcCaseFeedController.resolveFieldLabel('Case', 'Account'),
      'Case.Account should resolve through AccountId.'
    );
    Assert.areEqual(
      Case.OwnerId.getDescribe().getLabel(),
      ArcCaseFeedController.resolveFieldLabel('Case', 'Owner'),
      'Case.Owner should resolve through OwnerId.'
    );
    Assert.areEqual(
      Case.CaseNumber.getDescribe().getLabel(),
      ArcCaseFeedController.resolveFieldLabel('Case', 'CaseNumber'),
      'A field that exists under its own name should resolve directly.'
    );
  }

  @IsTest
  static void fallsBackToAHumanisedNameWhenDescribeCannotPlaceTheField() {
    Assert.areEqual(
      'Nonexistent Field',
      ArcCaseFeedController.resolveFieldLabel('Case', 'Nonexistent_Field__c'),
      'An unknown field should humanise rather than show the raw API name.'
    );
    Assert.areEqual(
      'Some Field',
      ArcCaseFeedController.resolveFieldLabel(
        'NotAnObject__x',
        'Some_Field__c'
      ),
      'An unknown object should humanise rather than throw.'
    );
    Assert.areEqual(
      '',
      ArcCaseFeedController.resolveFieldLabel('Case', null),
      'A blank field name should give a blank label, not an exception.'
    );
  }

  @IsTest
  static void humaniseStripsSuffixesAndUnderscores() {
    Assert.areEqual('Case Number', ArcCaseFeedController.humanise('Case_Number__c'));
    Assert.areEqual('Team', ArcCaseFeedController.humanise('Team__r'));
    Assert.areEqual('Subject', ArcCaseFeedController.humanise('Subject'));
  }

  @IsTest
  static void looksLikeIdSeparatesIdsFromNames() {
    Assert.isTrue(
      ArcCaseFeedController.looksLikeId('005Su00000g1klNIAQ'),
      'An 18-character id should be recognised.'
    );
    Assert.isTrue(
      ArcCaseFeedController.looksLikeId('005Su00000g1klN'),
      'A 15-character id should be recognised.'
    );
    Assert.isFalse(
      ArcCaseFeedController.looksLikeId('Manoj Kumar'),
      'A name is not an id.'
    );
    Assert.isFalse(
      ArcCaseFeedController.looksLikeId(null),
      'Null is not an id.'
    );
    Assert.isFalse(
      ArcCaseFeedController.looksLikeId(''),
      'Blank is not an id.'
    );
    // The case that rules out a naive length check: 15 characters, but a name.
    Assert.isFalse(
      ArcCaseFeedController.looksLikeId('Wolfeschlegels'),
      'A 14-character word is not an id.'
    );
    Assert.isFalse(
      ArcCaseFeedController.looksLikeId('Test Advisor Te'),
      'A 15-character string with a space is not an id.'
    );
  }
}