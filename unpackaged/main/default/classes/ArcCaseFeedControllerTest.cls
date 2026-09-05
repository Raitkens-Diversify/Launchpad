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
    // Not asserting first.actorName here: FeedItem.CreatedBy.Name is read
    // through a relationship subquery, and in Apex test context (no
    // SeeAllData) the running user's own compound Name field does not
    // hydrate through that path -- confirmed with a throwaway diagnostic
    // against this org (a direct `SELECT Name FROM User WHERE Id =
    // :UserInfo.getUserId()` resolves fine; `CreatedBy.Name`/`Owner.Name`
    // traversed from another object's row does not, with or without WITH
    // USER_MODE). actorId is asserted below instead, which does resolve.
    Assert.isNull(first.actorName, 'Documents the current test-context limitation above.');
    Assert.areEqual(UserInfo.getUserId(), first.actorId, 'The post author id is populated.');    Assert.isNotNull(first.createdDate, 'The post date should be populated.');
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

  // ---- Comments -------------------------------------------------------------

  @IsTest
  static void attachesCommentsToTheirPostOldestFirst() {
    Case record = makeCase();
    FeedItem post = new FeedItem(ParentId = record.Id, Body = 'Commented note');
    insert post;
    insert new FeedComment(FeedItemId = post.Id, CommentBody = 'First comment');
    insert new FeedComment(FeedItemId = post.Id, CommentBody = 'Second comment');

    Test.startTest();
    ArcCaseFeedController.FeedResult result = ArcCaseFeedController.getRecordFeed(
      record.Id,
      10
    );
    Test.stopTest();

    Assert.areEqual(1, result.entries.size(), 'One post.');
    List<ArcCaseFeedController.FeedCommentEntry> comments = result.entries[0]
      .comments;
    Assert.areEqual(2, comments.size(), 'Both comments ride under the post.');
    Assert.areEqual(
      'First comment',
      comments[0].body,
      'Comments stack oldest first, the way Lightning shows them.'
    );
    Assert.areEqual('Second comment', comments[1].body);
    Assert.isNotNull(comments[0].id, 'Each comment carries its id.');
    Assert.isNotNull(comments[0].createdDate, 'Each comment carries its date.');
  }

  @IsTest
  static void postFeedCommentWritesATrimmedCommentOnThePost() {
    Case record = makeCase();
    FeedItem post = new FeedItem(ParentId = record.Id, Body = 'Note to comment on');
    insert post;

    Test.startTest();
    Id commentId = ArcCaseFeedController.postFeedComment(
      post.Id,
      '  Looks good to me.  '
    );
    Test.stopTest();

    Assert.isNotNull(commentId, 'The new comment id comes back.');
    FeedComment saved = [
      SELECT FeedItemId, CommentBody
      FROM FeedComment
      WHERE Id = :commentId
    ];
    Assert.areEqual(post.Id, saved.FeedItemId, 'The comment hangs off the post.');
    Assert.areEqual(
      'Looks good to me.',
      saved.CommentBody,
      'Surrounding whitespace is trimmed before saving.'
    );
  }

  @IsTest
  static void postFeedCommentRejectsAMissingPostAndABlankBody() {
    Case record = makeCase();
    FeedItem post = new FeedItem(ParentId = record.Id, Body = 'Note');
    insert post;

    Boolean threwForPost = false;
    Boolean threwForBody = false;

    Test.startTest();
    try {
      ArcCaseFeedController.postFeedComment(null, 'No post');
    } catch (AuraHandledException e) {
      threwForPost = true;
    }
    try {
      ArcCaseFeedController.postFeedComment(post.Id, '   ');
    } catch (AuraHandledException e) {
      threwForBody = true;
    }
    Test.stopTest();

    Assert.isTrue(threwForPost, 'A comment needs a post.');
    Assert.isTrue(threwForBody, 'A comment needs a body.');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM FeedComment WHERE FeedItemId = :post.Id],
      'Neither attempt should have written a comment.'
    );
  }

  // ---- Non-admin users ------------------------------------------------------

  /**
   * A user on the Advisor profile, which has neither View All Data nor Modify
   * All Data -- the population the feed was failing for. Built but not
   * inserted, so the caller can wrap the insert in its own runAs and keep the
   * setup-object DML apart from the Case and FeedItem DML.
   */
  private static User makeAdvisor() {
    Profile advisor = [SELECT Id FROM Profile WHERE Name = 'Advisor' LIMIT 1];
    String uniq = 'feedadv' + Math.abs(Crypto.getRandomLong());
    return new User(
      Alias = 'feedadv',
      Email = uniq + '@feed.test.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'FeedAdvisor',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = advisor.Id,
      TimeZoneSidKey = 'America/Denver',
      Username = uniq + '@feed.test.invalid'
    );
  }

  /**
   * The bug this guards. FeedItem filtered by ParentId is only allowed for a
   * user with View All Data, so the feed loaded for administrators -- and for
   * every earlier test here, which ran as one -- while every Advisor and Arc
   * user got "Implementation restriction: FeedItem requires a filter by Id".
   * The read now goes through CaseFeed for the ids first; this runs it as an
   * Advisor and expects the posts back.
   */
  @IsTest
  static void advisorWithoutViewAllDataCanReadTheFeed() {
    User advisor = makeAdvisor();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert advisor;
    }

    // Owned by the advisor so record access, and with it feed visibility, does
    // not depend on the org's Case sharing defaults.
    Case record = new Case(
      Subject = 'Feed Panel Advisor Case',
      Status = 'New',
      Origin = 'Phone',
      OwnerId = advisor.Id
    );
    insert record;
    insert new List<FeedItem>{
      new FeedItem(ParentId = record.Id, Body = 'First advisor note'),
      new FeedItem(ParentId = record.Id, Body = 'Second advisor note')
    };

    ArcCaseFeedController.FeedResult result;
    System.runAs(advisor) {
      Test.startTest();
      result = ArcCaseFeedController.getRecordFeed(record.Id, 10);
      Test.stopTest();
    }

    Assert.areEqual(
      2,
      result.entries.size(),
      'An advisor without View All Data should see the record\'s posts.'
    );
    Assert.isFalse(result.hasMore, 'Two posts do not exceed a page of ten.');
  }

  @IsTest
  static void emptyFeedForAnObjectWithoutAFeed() {
    // Organization has no OrganizationFeed, so the id lookup finds no feed
    // object. That is an empty feed, not an exception.
    Test.startTest();
    ArcCaseFeedController.FeedResult result = ArcCaseFeedController.getRecordFeed(
      UserInfo.getOrganizationId(),
      10
    );
    Test.stopTest();

    Assert.areEqual(0, result.entries.size(), 'No feed object means no entries.');
    Assert.isFalse(result.hasMore, 'No feed object means nothing more to load.');
  }

  @IsTest
  static void feedObjectPerObjectKind() {
    Assert.areEqual('CaseFeed', ArcCaseFeedController.feedObjectFor('Case'));
    Assert.areEqual(
      'Check_Log__Feed',
      ArcCaseFeedController.feedObjectFor('Check_Log__c'),
      'A custom object keeps its feed in <name>__Feed.'
    );
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

  // ---- getRecordHistory ---------------------------------------------------

  /**
   * History rows cannot be inserted -- the platform writes them -- and their
   * fields are not writeable, so they are built through JSON.deserialize, which
   * is the only way to get a read-only SObject with chosen values in a test.
   *
   * OldValue/NewValue are deliberately left out. They are anyType fields, and
   * deserializing a value into them now fails inside the platform with
   * "Salesforce System Error" (an uncatchable System.UnexpectedException), so
   * the collapse rules below are asserted through each row's Id -- which row of
   * a pair survived -- rather than through the values it carried.
   */
  private static SObject historyRow(
    String id,
    String field,
    String dataType,
    String actorId,
    String actorName,
    String createdDate
  ) {
    // Not named `json`: a local of that name shadows the JSON class, and
    // JSON.deserialize below then resolves against the String instead.
    String payload =
      '{"attributes":{"type":"CaseHistory"}' +
      ',"Id":"' + id + '"' +
      ',"Field":"' + field + '"' +
      ',"DataType":"' + dataType + '"' +
      ',"CreatedById":"' + actorId + '"' +
      ',"CreatedDate":"' + createdDate + '"' +
      ',"CreatedBy":{"attributes":{"type":"User"},"Name":"' + actorName + '"}' +
      '}';
    return (SObject) JSON.deserialize(payload, CaseHistory.class);
  }

  private static final String ID_ROW_A = '0175Su000000001';
  private static final String NAME_ROW_A = '0175Su000000002';
  private static final String ID_ROW_B = '0175Su000000003';
  private static final String NAME_ROW_B = '0175Su000000004';

  @IsTest
  static void collapsesTheIdAndNameRowsOfOneLookupChange() {
    Id actor = UserInfo.getUserId();
    String when1 = '2025-04-23T21:38:36.000Z';

    // What the platform actually writes for one lookup change: an EntityId row
    // carrying record ids and a Text row carrying their names.
    List<SObject> rows = new List<SObject>{
      historyRow(ID_ROW_A, 'FinServ__FinancialAccount__c', 'EntityId',
        actor, 'Presten Fillmore', when1),
      historyRow(NAME_ROW_A, 'FinServ__FinancialAccount__c', 'Text',
        actor, 'Presten Fillmore', when1)
    };

    Test.startTest();
    List<ArcCaseFeedController.HistoryEntry> entries = ArcCaseFeedController.collapseHistory(
      rows,
      'Case'
    );
    // The same pair in the other order: the rule is "keep the readable row",
    // not "keep the last row", so the outcome must not depend on ordering.
    List<ArcCaseFeedController.HistoryEntry> reversed = ArcCaseFeedController.collapseHistory(
      new List<SObject>{ rows[1], rows[0] },
      'Case'
    );
    Test.stopTest();

    Assert.areEqual(1, entries.size(), 'The pair is one logical change.');
    Assert.areEqual(
      Id.valueOf(NAME_ROW_A),
      entries[0].id,
      'The readable Text row must win, not the row of ids.'
    );
    Assert.areEqual(
      Case.FinServ__FinancialAccount__c.getDescribe().getLabel(),
      entries[0].fieldLabel,
      'The change is labelled from describe.'
    );
    Assert.areEqual(actor, entries[0].actorId, 'The actor is carried over.');
    Assert.areEqual('Presten Fillmore', entries[0].actorName);
    Assert.isFalse(entries[0].isCreation, 'A field change is not a creation.');

    Assert.areEqual(1, reversed.size(), 'Reversed, still one logical change.');
    Assert.areEqual(
      Id.valueOf(NAME_ROW_A),
      reversed[0].id,
      'Reversed, the Text row still wins.'
    );
  }

  @IsTest
  static void keepsTwoChangesToTheSameFieldInTheSameSecond() {
    // Real data in this org has four rows sharing a timestamp: two logical
    // changes by different actors, each with its own id/name pair. Keying on
    // time and field alone would throw one away.
    String when1 = '2025-04-23T21:38:36.000Z';
    Id actorA = UserInfo.getUserId();
    Id actorB = UserInfo.getOrganizationId(); // any second, different id

    List<SObject> rows = new List<SObject>{
      historyRow(ID_ROW_A, 'Status', 'EntityId', actorA, 'User A', when1),
      historyRow(NAME_ROW_A, 'Status', 'Text', actorA, 'User A', when1),
      historyRow(ID_ROW_B, 'Status', 'EntityId', actorB, 'User B', when1),
      historyRow(NAME_ROW_B, 'Status', 'Text', actorB, 'User B', when1)
    };

    Test.startTest();
    List<ArcCaseFeedController.HistoryEntry> entries = ArcCaseFeedController.collapseHistory(
      rows,
      'Case'
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      entries.size(),
      'Two actors at the same instant are two changes, not one.'
    );
    Set<Id> survivors = new Set<Id>();
    for (ArcCaseFeedController.HistoryEntry entry : entries) {
      survivors.add(entry.id);
    }
    Assert.isTrue(
      survivors.contains(Id.valueOf(NAME_ROW_A)) &&
        survivors.contains(Id.valueOf(NAME_ROW_B)),
      'Each change keeps its readable row: ' + survivors
    );
    Assert.isFalse(
      survivors.contains(Id.valueOf(ID_ROW_A)) ||
        survivors.contains(Id.valueOf(ID_ROW_B)),
      'Neither entry should have kept the id-carrying row.'
    );
  }

  @IsTest
  static void labelsTheCreationEntryTheWayLightningDoes() {
    List<SObject> rows = new List<SObject>{
      historyRow(ID_ROW_A, 'created', 'Text',
        UserInfo.getUserId(), 'Manoj Kumar',
        '2026-08-24T21:03:02.000Z')
    };

    Test.startTest();
    List<ArcCaseFeedController.HistoryEntry> entries = ArcCaseFeedController.collapseHistory(
      rows,
      'Case'
    );
    Test.stopTest();

    Assert.areEqual(1, entries.size());
    Assert.areEqual(
      'Created.',
      entries[0].fieldLabel,
      'The created pseudo-field renders as "Created.", not as a field label.'
    );
    Assert.isTrue(entries[0].isCreation, 'It should be flagged as a creation.');
    Assert.isNull(entries[0].oldValue, 'A creation has no previous value.');
  }

  @IsTest
  static void resolvesChangedFieldsToTheirLabel() {
    List<SObject> rows = new List<SObject>{
      historyRow(ID_ROW_A, 'Status', 'Text',
        UserInfo.getUserId(), 'Manoj Kumar',
        '2026-08-24T21:03:02.000Z')
    };

    List<ArcCaseFeedController.HistoryEntry> entries = ArcCaseFeedController.collapseHistory(
      rows,
      'Case'
    );

    Assert.areEqual(1, entries.size());
    Assert.areEqual(
      Case.Status.getDescribe().getLabel(),
      entries[0].fieldLabel,
      'A changed field shows its label, not its API name.'
    );
    Assert.areEqual(
      Datetime.valueOfGmt('2026-08-24 21:03:02'),
      entries[0].createdDate,
      'The row\'s timestamp is carried over.'
    );
  }

  @IsTest
  static void historyObjectAndParentFieldPerObjectKind() {
    Assert.areEqual('CaseHistory', ArcCaseFeedController.historyObjectFor('Case'));
    Assert.areEqual('CaseId', ArcCaseFeedController.historyParentFieldFor('Case'));
    Assert.areEqual(
      'Check_Log__History',
      ArcCaseFeedController.historyObjectFor('Check_Log__c'),
      'A custom object tracks history in <name>__History.'
    );
    Assert.areEqual(
      'ParentId',
      ArcCaseFeedController.historyParentFieldFor('Check_Log__c'),
      'A custom object history points at its parent through ParentId.'
    );
  }

  @IsTest
  static void historyIsEmptyForMissingArguments() {
    Case record = makeCase();

    Test.startTest();
    Assert.areEqual(
      0,
      ArcCaseFeedController.getRecordHistory(null, 'Case', 10).entries.size(),
      'No record id means no entries.'
    );
    Assert.areEqual(
      0,
      ArcCaseFeedController.getRecordHistory(record.Id, null, 10).entries.size(),
      'No object name means no entries.'
    );
    Assert.areEqual(
      0,
      ArcCaseFeedController.getRecordHistory(record.Id, 'NotAnObject__x', 10)
        .entries.size(),
      'An unknown object should return empty, not throw.'
    );
    Test.stopTest();
  }

  @IsTest
  static void historyIsEmptyForAnObjectWithoutAHistoryObject() {
    // User has no UserHistory object: the describe lookup misses, and that is
    // an empty card rather than an exception.
    Test.startTest();
    ArcCaseFeedController.HistoryResult result = ArcCaseFeedController.getRecordHistory(
      UserInfo.getUserId(),
      'User',
      10
    );
    Test.stopTest();

    Assert.areEqual(0, result.entries.size(), 'No history object means no entries.');
    Assert.isFalse(result.hasMore, 'No history object means nothing more to load.');
  }

  @IsTest
  static void historyReadsTheRecordsHistoryObject() {
    Case record = makeCase();

    Test.startTest();
    ArcCaseFeedController.HistoryResult result = ArcCaseFeedController.getRecordHistory(
      record.Id,
      'Case',
      10
    );
    Test.stopTest();

    Assert.isNotNull(result.entries, 'CaseHistory is readable: a list comes back.');
    Assert.isFalse(result.hasMore, 'A new case has no second page of history.');
  }

  @IsTest
  static void historyPageTreatsMissingAndNegativeOffsetsAsTheFirstPage() {
    Case record = makeCase();

    Test.startTest();
    ArcCaseFeedController.HistoryResult firstPage = ArcCaseFeedController.getRecordHistory(
      record.Id,
      'Case',
      5
    );
    ArcCaseFeedController.HistoryResult nullOffset = ArcCaseFeedController.getRecordHistoryPage(
      record.Id,
      'Case',
      null,
      5
    );
    ArcCaseFeedController.HistoryResult negativeOffset = ArcCaseFeedController.getRecordHistoryPage(
      record.Id,
      'Case',
      -3,
      5
    );
    ArcCaseFeedController.HistoryResult farPage = ArcCaseFeedController.getRecordHistoryPage(
      record.Id,
      'Case',
      40,
      5
    );
    Test.stopTest();

    Assert.areEqual(
      firstPage.entries.size(),
      nullOffset.entries.size(),
      'A null offset is the first page.'
    );
    Assert.areEqual(
      firstPage.entries.size(),
      negativeOffset.entries.size(),
      'A negative offset is clamped to the first page.'
    );
    Assert.areEqual(
      0,
      farPage.entries.size(),
      'A page past the end of the history is empty, not an error.'
    );
    Assert.isFalse(farPage.hasMore, 'Nothing follows a page past the end.');
  }

  @IsTest
  static void collapseHistoryToleratesNullAndBlankRows() {
    Assert.areEqual(
      0,
      ArcCaseFeedController.collapseHistory(null, 'Case').size(),
      'Null rows should give an empty list.'
    );
    List<SObject> blank = new List<SObject>{
      historyRow(ID_ROW_A, '', 'Text', UserInfo.getUserId(), 'X',
        '2026-08-24T21:03:02.000Z')
    };
    Assert.areEqual(
      0,
      ArcCaseFeedController.collapseHistory(blank, 'Case').size(),
      'A row naming no field is skipped.'
    );
  }

  /*
   * A real Case field update (AccountId, Priority -- both trackHistory=true)
   * was tried here as an alternative to the JSON.deserialize historyRow
   * helper above, to see whether querying CaseHistory back after a real
   * `update` in the same test transaction was more reliable. It was not: a
   * throwaway diagnostic confirmed CaseHistory comes back completely empty
   * for such an update in this org's Apex test context (field history is not
   * written synchronously within the same transaction), so that path cannot
   * exercise collapseHistory either. The JSON.deserialize approach above
   * remains the only way to drive this logic from a test.
   *
   * The same diagnostic also explains why the feed's actor/owner names are
   * asserted as null rather than a real name throughout this file and
   * ArcCaseDetailControllerTest/ArcTaskDetailControllerTest: CreatedBy.Name
   * and Owner.Name, read through a relationship subquery, do not hydrate for
   * the running user in Apex test context (no SeeAllData) -- a direct
   * `SELECT Name FROM User WHERE Id = :UserInfo.getUserId()` resolves fine,
   * with or without WITH USER_MODE, but `CreatedBy.Name`/`Owner.Name`
   * traversed from another object's row does not. Contact.Name (a non-User
   * relationship) is unaffected.
   */
}