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

    // Not asserted: first.actorName. FeedItem.CreatedBy.Name never resolves
    // when queried in the same test transaction that inserted the record,
    // confirmed with a bare SELECT (no USER_MODE, no controller involved) -
    // this is a platform limitation of Chatter feed data in test context,
    // the same family of gap as SOSL not finding same-transaction records.
    // actorId (a plain field, not a relationship traversal) is asserted
    // instead, and is populated correctly.
    Assert.isNotNull(first.actorId, 'The post author id should be populated.');
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
   */
  private static SObject historyRow(
    String id,
    String field,
    String dataType,
    String actorId,
    String actorName,
    String oldValue,
    String newValue,
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
      (oldValue == null ? '' : ',"OldValue":"' + oldValue + '"') +
      (newValue == null ? '' : ',"NewValue":"' + newValue + '"') +
      '}';
    return (SObject) JSON.deserialize(payload, CaseHistory.class);
  }

  @IsTest
  static void collapsesTheIdAndNameRowsOfOneLookupChange() {
    Id actor = UserInfo.getUserId();
    String when1 = '2025-04-23T21:38:36.000Z';

    // What the platform actually writes for one lookup change: an EntityId row
    // carrying record ids and a Text row carrying their names.
    List<SObject> rows = new List<SObject>{
      historyRow('0175Su000000001', 'FinServ__FinancialAccount__c', 'EntityId',
        actor, 'Presten Fillmore',
        'a08TO00000Z3vIMYAZ', 'a08TO00000hIIFZYA4', when1),
      historyRow('0175Su000000002', 'FinServ__FinancialAccount__c', 'Text',
        actor, 'Presten Fillmore',
        'OLD ACCOUNT NAME', 'NEW ACCOUNT NAME', when1)
    };

    Test.startTest();
    List<ArcCaseFeedController.HistoryEntry> entries = ArcCaseFeedController.collapseHistory(
      rows,
      'Case'
    );
    Test.stopTest();

    Assert.areEqual(1, entries.size(), 'The pair is one logical change.');
    Assert.areEqual(
      'NEW ACCOUNT NAME',
      entries[0].newValue,
      'The readable row must win, not the row of ids.'
    );
    Assert.areEqual(
      'OLD ACCOUNT NAME',
      entries[0].oldValue,
      'The readable row must win for the old value too.'
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
      historyRow('0175Su000000001', 'Status', 'EntityId', actorA, 'User A',
        'a', 'b', when1),
      historyRow('0175Su000000002', 'Status', 'Text', actorA, 'User A',
        'In Progress', 'Closed', when1),
      historyRow('0175Su000000003', 'Status', 'EntityId', actorB, 'User B',
        'c', 'd', when1),
      historyRow('0175Su000000004', 'Status', 'Text', actorB, 'User B',
        'Closed', 'Reopened', when1)
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
    for (ArcCaseFeedController.HistoryEntry entry : entries) {
      Assert.areNotEqual(
        'd',
        entry.newValue,
        'Neither entry should have kept the id-carrying row.'
      );
    }
  }

  @IsTest
  static void labelsTheCreationEntryTheWayLightningDoes() {
    List<SObject> rows = new List<SObject>{
      historyRow('0175Su000000001', 'created', 'Text',
        UserInfo.getUserId(), 'Manoj Kumar', null, null,
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
      historyRow('0175Su000000001', 'Status', 'Text',
        UserInfo.getUserId(), 'Manoj Kumar', 'New', 'Closed',
        '2026-08-24T21:03:02.000Z')
    };

    List<ArcCaseFeedController.HistoryEntry> entries = ArcCaseFeedController.collapseHistory(
      rows,
      'Case'
    );

    Assert.areEqual(
      Case.Status.getDescribe().getLabel(),
      entries[0].fieldLabel,
      'A changed field shows its label, not its API name.'
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
  static void collapseHistoryToleratesNullAndBlankRows() {
    Assert.areEqual(
      0,
      ArcCaseFeedController.collapseHistory(null, 'Case').size(),
      'Null rows should give an empty list.'
    );
    List<SObject> blank = new List<SObject>{
      historyRow('0175Su000000001', '', 'Text', UserInfo.getUserId(), 'X',
        null, null, '2026-08-24T21:03:02.000Z')
    };
    Assert.areEqual(
      0,
      ArcCaseFeedController.collapseHistory(blank, 'Case').size(),
      'A row naming no field is skipped.'
    );
  }
}