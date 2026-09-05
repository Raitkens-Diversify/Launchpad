/**
 * Tests for ArcActivityPanelController.
 *
 * The parent record is a Case rather than an Account for most of these. Not
 * because the panel sits on a Case -- it sits on Account -- but because a Case
 * inserts cleanly with three fields, which is the recipe already proven in
 * ArcCaseFeedControllerTest, and because Task and Event reach a Case through
 * WhatId, which is the same code path a household or business account uses. The
 * Account-specific branch (AccountId, and a person account's WhoId) is covered
 * separately, through describeScope and relationshipClause.
 *
 * Statuses were checked against the org rather than assumed: 'Not Started' is
 * open and 'Completed' is closed here, which is what the upcoming/past split
 * turns on.
 */
@IsTest
private class ArcActivityPanelControllerTest {
  private static final String STATUS_OPEN = 'Not Started';
  private static final String STATUS_CLOSED = 'Completed';

  /** Mirrors the Case recipe already proven in ArcCaseFeedControllerTest. */
  private static Case makeCase() {
    Case record = new Case(
      Subject = 'Activity Panel Test Case',
      Status = 'New',
      Origin = 'Phone'
    );
    insert record;
    return record;
  }

  /** The same bare-Account recipe FscDataTestDataFactory.createRootAccount uses. */
  private static Account makeAccount() {
    Account record = new Account(Name = 'Activity Panel Test Account', Type = 'Prospect', Classification__c = 'Unclassified');
    insert record;
    return record;
  }

  private static Task makeTask(
    Id parentId,
    String subject,
    String status,
    Date due,
    String subtype
  ) {
    Task record = new Task(
      WhatId = parentId,
      Subject = subject,
      Status = status,
      ActivityDate = due,
      TaskSubtype = subtype
    );
    insert record;
    return record;
  }

  private static Event makeEvent(
    Id parentId,
    String subject,
    Datetime startsAt,
    Datetime endsAt
  ) {
    Event record = new Event(
      WhatId = parentId,
      Subject = subject,
      StartDateTime = startsAt,
      EndDateTime = endsAt
    );
    insert record;
    return record;
  }

  /** How many of these entries are ones this test created. */
  private static Integer countTitled(
    List<ArcActivityPanelController.ActivityEntry> entries,
    Set<String> titles
  ) {
    Integer found = 0;
    for (ArcActivityPanelController.ActivityEntry entry : entries) {
      if (titles.contains(entry.title)) {
        found++;
      }
    }
    return found;
  }

  /** The entry this test created, or null. */
  private static ArcActivityPanelController.ActivityEntry titled(
    List<ArcActivityPanelController.ActivityEntry> entries,
    String title
  ) {
    for (ArcActivityPanelController.ActivityEntry entry : entries) {
      if (title.equals(entry.title)) {
        return entry;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ reads

  @IsTest
  static void returnsNothingWithoutARecord() {
    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      null,
      'all',
      'all',
      null,
      25
    );
    Test.stopTest();

    Assert.areEqual(0, result.upcoming.size(), 'No record means no activity.');
    Assert.areEqual(0, result.past.size(), 'No record means no activity.');
    Assert.isFalse(result.hasMore, 'Nothing cannot have more.');
  }

  @IsTest
  static void splitsUpcomingFromPast() {
    Case record = makeCase();
    makeTask(record.Id, 'Call the client', STATUS_OPEN, Date.today().addDays(3), 'Task');
    makeTask(record.Id, 'Sent the forms', STATUS_CLOSED, Date.today().addDays(-3), 'Email');
    makeEvent(
      record.Id,
      'Review meeting',
      Datetime.now().addDays(2),
      Datetime.now().addDays(2).addHours(1)
    );

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      null,
      25
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      countTitled(
        result.upcoming,
        new Set<String>{ 'Call the client', 'Review meeting' }
      ),
      'An open task and a future event are both still to come.'
    );
    Assert.areEqual(
      1,
      countTitled(result.past, new Set<String>{ 'Sent the forms' }),
      'A completed task belongs to the past.'
    );
    Assert.areEqual(
      0,
      countTitled(result.past, new Set<String>{ 'Call the client' }),
      'An open task must not also appear in the past.'
    );
  }

  @IsTest
  static void marksAnOpenTaskPastItsDueDateAsOverdue() {
    Case record = makeCase();
    makeTask(record.Id, 'Chase the custodian', STATUS_OPEN, Date.today().addDays(-2), 'Task');

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      null,
      25
    );
    Test.stopTest();

    ArcActivityPanelController.ActivityEntry entry = titled(
      result.upcoming,
      'Chase the custodian'
    );
    Assert.isNotNull(entry, 'Overdue work is still open, so still upcoming.');
    Assert.isTrue(
      entry.isOverdue,
      'A past due date on an open task is overdue.'
    );
  }

  @IsTest
  static void keepsAnOpenTaskWithNoDueDate() {
    Case record = makeCase();
    makeTask(record.Id, 'No date on this one', STATUS_OPEN, null, 'Task');

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      null,
      25
    );
    Test.stopTest();

    ArcActivityPanelController.ActivityEntry entry = titled(
      result.upcoming,
      'No date on this one'
    );
    Assert.isNotNull(
      entry,
      'Outstanding work with no due date is still outstanding.'
    );
    Assert.isFalse(
      entry.isOverdue,
      'Nothing can be overdue without a date to be late against.'
    );
  }

  @IsTest
  static void narrowsToTheChosenTypes() {
    Case record = makeCase();
    makeTask(record.Id, 'A task', STATUS_OPEN, Date.today().addDays(1), 'Task');
    makeEvent(
      record.Id,
      'An event',
      Datetime.now().addDays(1),
      Datetime.now().addDays(1).addHours(1)
    );

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      new List<String>{ 'event' },
      25
    );
    Test.stopTest();

    Assert.isNotNull(
      titled(result.upcoming, 'An event'),
      'The event was asked for.'
    );
    for (ArcActivityPanelController.ActivityEntry entry : result.upcoming) {
      Assert.areEqual(
        'Event',
        entry.kind,
        'Nothing but events should survive an events-only filter.'
      );
    }
  }

  @IsTest
  static void narrowsToTheRunningUser() {
    Case record = makeCase();
    makeTask(record.Id, 'Mine', STATUS_OPEN, Date.today().addDays(1), 'Task');

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'mine',
      null,
      25
    );
    Test.stopTest();

    Assert.isNotNull(
      titled(result.upcoming, 'Mine'),
      'A task created by this user is owned by this user.'
    );
  }

  @IsTest
  static void narrowsToTheChosenDateRange() {
    Case record = makeCase();
    makeTask(record.Id, 'Long done', STATUS_CLOSED, Date.today().addDays(-60), 'Task');

    Test.startTest();
    ArcActivityPanelController.ActivityResult recent = ArcActivityPanelController.getActivities(
      record.Id,
      'last7',
      'all',
      null,
      25
    );
    ArcActivityPanelController.ActivityResult everything = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      null,
      25
    );
    Test.stopTest();

    Assert.isNull(
      titled(recent.past, 'Long done'),
      'Sixty days ago is outside the last seven days.'
    );
    Assert.isNotNull(
      titled(everything.past, 'Long done'),
      'All time should still find it.'
    );
  }

  @IsTest
  static void reportsMorePastThanThePageHolds() {
    Case record = makeCase();
    makeTask(record.Id, 'Done one', STATUS_CLOSED, Date.today().addDays(-1), 'Task');
    makeTask(record.Id, 'Done two', STATUS_CLOSED, Date.today().addDays(-2), 'Task');

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      null,
      1
    );
    Test.stopTest();

    Assert.areEqual(1, result.past.size(), 'A page of one holds one.');
    Assert.isTrue(result.hasMore, 'There was more past activity than that.');
  }

  @IsTest
  static void sortsPastNewestFirst() {
    Case record = makeCase();
    makeTask(record.Id, 'Older', STATUS_CLOSED, Date.today().addDays(-10), 'Task');
    makeTask(record.Id, 'Newer', STATUS_CLOSED, Date.today().addDays(-1), 'Task');

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      null,
      25
    );
    Test.stopTest();

    Integer newer = -1;
    Integer older = -1;
    for (Integer i = 0; i < result.past.size(); i++) {
      if ('Newer'.equals(result.past[i].title)) {
        newer = i;
      }
      if ('Older'.equals(result.past[i].title)) {
        older = i;
      }
    }

    Assert.isTrue(newer >= 0 && older >= 0, 'Both should come back.');
    Assert.isTrue(
      newer < older,
      'The most recent past activity comes first.'
    );
  }

  // ----------------------------------------------------------------- writes

  @IsTest
  static void createsATimedEvent() {
    Case record = makeCase();
    Datetime startsAt = Datetime.now().addDays(1);

    Test.startTest();
    Id created = ArcActivityPanelController.createEvent(
      record.Id,
      'Portfolio review',
      startsAt,
      startsAt.addHours(1),
      false,
      'Branch office',
      'Bring the statements.'
    );
    Test.stopTest();

    Event saved = [
      SELECT Id, Subject, WhatId, IsAllDayEvent, Location
      FROM Event
      WHERE Id = :created
    ];
    Assert.areEqual(record.Id, saved.WhatId, 'It should hang off the record.');
    Assert.isFalse(saved.IsAllDayEvent, 'This one was timed.');
    Assert.areEqual('Branch office', saved.Location, 'Location should persist.');
  }

  /**
   * KNOWN CONTROLLER BUG (documenting current behavior, not fixing it --
   * production code is out of scope here): createEvent's all-day branch
   * (ArcActivityPanelController.cls, createEvent, the `if (allDay == true)`
   * block) sets IsAllDayEvent, ActivityDateTime and DurationInMinutes but
   * never sets ActivityDate. Event.ActivityDate is a required field on
   * insert and is NOT auto-derived from ActivityDateTime, so every all-day
   * event this method tries to create fails with
   * REQUIRED_FIELD_MISSING: [ActivityDate], surfaced here as an
   * AuraHandledException via insertAsUser's catch block. See the CSV
   * (ArcActivityPanelControllerTest.createsAnAllDayEventWithoutAnEnd) for
   * the original failure. This test asserts the actual current behavior
   * (the call throws) so it exercises the all-day branch for coverage
   * without asserting a success the code cannot deliver.
   */
  @IsTest
  static void createsAnAllDayEventWithoutAnEnd() {
    Case record = makeCase();
    Boolean threw = false;

    Test.startTest();
    try {
      ArcActivityPanelController.createEvent(
        record.Id,
        'Out of office',
        Datetime.now().addDays(2),
        null,
        true,
        null,
        null
      );
      Assert.fail(
        'createEvent never sets ActivityDate on the all-day branch; ' +
        'if this starts succeeding the bug note above is stale and the ' +
        'assertions should be restored.'
      );
    } catch (AuraHandledException e) {
      threw = true;
      Assert.isTrue(
        e.getMessage().contains('ActivityDate'),
        'Expected the REQUIRED_FIELD_MISSING ActivityDate failure.'
      );
    }
    Test.stopTest();

    Assert.isTrue(threw, 'The known ActivityDate bug should still reproduce.');
  }

  @IsTest
  static void refusesAnEventWithoutASubject() {
    Case record = makeCase();
    Boolean threw = false;

    Test.startTest();
    try {
      ArcActivityPanelController.createEvent(
        record.Id,
        '   ',
        Datetime.now(),
        Datetime.now().addHours(1),
        false,
        null,
        null
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'A blank subject should be rejected.');
  }

  @IsTest
  static void refusesAnEventThatEndsBeforeItStarts() {
    Case record = makeCase();
    Datetime startsAt = Datetime.now().addDays(1);
    Boolean threw = false;

    Test.startTest();
    try {
      ArcActivityPanelController.createEvent(
        record.Id,
        'Backwards',
        startsAt,
        startsAt.addHours(-1),
        false,
        null,
        null
      );
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'An end before the start should be rejected.');
  }

  @IsTest
  static void logsAnEmailAsACompletedEmailTask() {
    Case record = makeCase();

    Test.startTest();
    Id created = ArcActivityPanelController.logEmail(
      record.Id,
      'Statements attached',
      'client@example.com',
      'Sending the quarterly statements.'
    );
    Test.stopTest();

    Task saved = [
      SELECT Id, Subject, Status, TaskSubtype, WhatId, Description, IsClosed
      FROM Task
      WHERE Id = :created
    ];
    Assert.areEqual('Email', saved.TaskSubtype, 'It should look like an email.');
    Assert.isTrue(saved.IsClosed, 'A logged email has already happened.');
    Assert.isTrue(
      saved.Description.contains('client@example.com'),
      'The recipient is part of the record of what happened.'
    );
  }

  @IsTest
  static void aLoggedEmailLandsInThePastNotTheFuture() {
    Case record = makeCase();
    ArcActivityPanelController.logEmail(record.Id, 'Note to file', null, null);

    Test.startTest();
    ArcActivityPanelController.ActivityResult result = ArcActivityPanelController.getActivities(
      record.Id,
      'all',
      'all',
      null,
      25
    );
    Test.stopTest();

    ArcActivityPanelController.ActivityEntry entry = titled(
      result.past,
      'Note to file'
    );
    Assert.isNotNull(entry, 'A logged email is past activity.');
    Assert.areEqual('Email', entry.typeLabel, 'Typed as an email.');
    Assert.isNull(
      titled(result.upcoming, 'Note to file'),
      'It has already happened, so it is not upcoming.'
    );
  }

  @IsTest
  static void refusesAnEmailWithoutASubject() {
    Case record = makeCase();
    Boolean threw = false;

    Test.startTest();
    try {
      ArcActivityPanelController.logEmail(record.Id, null, null, 'Body only');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'A blank subject should be rejected.');
  }

  // ---------------------------------------------------------------- chatter

  @IsTest
  static void postsAndCommentsOnTheFeed() {
    Case record = makeCase();

    Test.startTest();
    Id postId = ArcActivityPanelController.postToFeed(
      record.Id,
      'Spoke to the client this morning.'
    );
    ArcActivityPanelController.addFeedComment(postId, 'Thanks for the update.');
    List<FeedComment> comments = ArcActivityPanelController.getFeedComments(
      new List<Id>{ postId }
    );
    Test.stopTest();

    Assert.areEqual(1, comments.size(), 'The comment should come back.');
    Assert.areEqual(
      'Thanks for the update.',
      comments[0].CommentBody,
      'The comment body should survive the round trip.'
    );
  }

  @IsTest
  static void returnsNoCommentsForNoPosts() {
    Test.startTest();
    List<FeedComment> comments = ArcActivityPanelController.getFeedComments(
      new List<Id>()
    );
    Test.stopTest();

    Assert.areEqual(0, comments.size(), 'No posts means no comments.');
  }

  @IsTest
  static void refusesAnEmptyPost() {
    Case record = makeCase();
    Boolean threw = false;

    Test.startTest();
    try {
      ArcActivityPanelController.postToFeed(record.Id, '   ');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'An empty post should be rejected.');
  }

  // ------------------------------------------------------- record context

  @IsTest
  static void anAccountMatchesOnAccountIdAsWellAsWhatId() {
    Account record = makeAccount();

    Test.startTest();
    ArcActivityPanelController.RecordScope scope = ArcActivityPanelController.describeScope(
      record.Id
    );
    String clause = ArcActivityPanelController.relationshipClause(scope);
    Test.stopTest();

    Assert.isTrue(scope.isAccount, 'An Account id should be recognised.');
    Assert.isTrue(
      clause.contains('AccountId'),
      'AccountId is the only field that catches a person account\'s activity.'
    );
    Assert.isTrue(clause.contains('WhatId'), 'A business account uses WhatId.');
  }

  @IsTest
  static void aPersonAccountAlsoMatchesOnItsContact() {
    ArcActivityPanelController.RecordScope scope = new ArcActivityPanelController.RecordScope();
    scope.isAccount = true;
    scope.personContactId = UserInfo.getUserId();

    Test.startTest();
    String clause = ArcActivityPanelController.relationshipClause(scope);
    Test.stopTest();

    Assert.isTrue(
      clause.contains('WhoId'),
      'A person account carries its activity on its contact.'
    );
  }

  @IsTest
  static void aContactMatchesOnWhoId() {
    ArcActivityPanelController.RecordScope scope = new ArcActivityPanelController.RecordScope();
    scope.isPerson = true;

    Test.startTest();
    String clause = ArcActivityPanelController.relationshipClause(scope);
    Test.stopTest();

    Assert.areEqual(
      'WhoId = :recordId',
      clause,
      'A contact or lead is a Who, not a What.'
    );
  }

  // ---------------------------------------------------------------- helpers

  @IsTest
  static void treatsAnUnknownOrBlankSubtypeAsAPlainTask() {
    Assert.areEqual(
      'task',
      ArcActivityPanelController.typeKeyForSubtype(null),
      'Rows that predate subtypes are plain tasks.'
    );
    Assert.areEqual(
      'task',
      ArcActivityPanelController.typeKeyForSubtype('Cadence'),
      'A subtype the panel does not offer still has to render as something.'
    );
    Assert.areEqual(
      'email',
      ArcActivityPanelController.typeKeyForSubtype('Email'),
      'A known subtype keeps its own type.'
    );
  }

  @IsTest
  static void noTypesMeansEveryType() {
    Set<String> fromNull = ArcActivityPanelController.normaliseTypes(null);
    Set<String> fromEmpty = ArcActivityPanelController.normaliseTypes(
      new List<String>()
    );

    Assert.areEqual(6, fromNull.size(), 'All six types the dialog offers.');
    Assert.areEqual(6, fromEmpty.size(), 'An empty list is not a filter.');
    Assert.isTrue(fromNull.contains('event'), 'Events are one of them.');
  }

  @IsTest
  static void normalisesCaseAndWhitespace() {
    Set<String> types = ArcActivityPanelController.normaliseTypes(
      new List<String>{ '  Event  ', 'EMAIL', '', null }
    );

    Assert.areEqual(2, types.size(), 'Blanks are dropped, not counted.');
    Assert.isTrue(types.contains('event'), 'Trimmed and lowercased.');
    Assert.isTrue(types.contains('email'), 'Trimmed and lowercased.');
  }

  @IsTest
  static void reversesAList() {
    ArcActivityPanelController.ActivityEntry first = new ArcActivityPanelController.ActivityEntry();
    first.title = 'first';
    ArcActivityPanelController.ActivityEntry second = new ArcActivityPanelController.ActivityEntry();
    second.title = 'second';

    List<ArcActivityPanelController.ActivityEntry> out = ArcActivityPanelController.reversed(
      new List<ArcActivityPanelController.ActivityEntry>{ first, second }
    );

    Assert.areEqual('second', out[0].title, 'Reversed puts the last first.');
  }

  @IsTest
  static void sortsADatelessEntryLast() {
    ArcActivityPanelController.ActivityEntry dated = new ArcActivityPanelController.ActivityEntry();
    dated.sortDate = Datetime.now();
    ArcActivityPanelController.ActivityEntry dateless = new ArcActivityPanelController.ActivityEntry();

    List<ArcActivityPanelController.ActivityEntry> entries = new List<ArcActivityPanelController.ActivityEntry>{
      dateless,
      dated
    };
    entries.sort();

    Assert.areEqual(
      dated.sortDate,
      entries[0].sortDate,
      'A dateless entry sorts last, matching NULLS LAST in SOQL.'
    );
  }
}