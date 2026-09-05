/**
 * Tests for ArcCaseCommentController: the ARC site's Add Comment action.
 */
@IsTest
private class ArcCaseCommentControllerTest {
  private static Case makeCase() {
    Case record = new Case(
      Subject = 'Comment Test Case',
      Status = 'New',
      Origin = 'Phone'
    );
    insert record;
    return record;
  }

  @IsTest
  static void addCommentWritesACaseCommentOnTheCase() {
    Case record = makeCase();

    Test.startTest();
    ArcCaseCommentController.addComment(record.Id, 'Called the client back.');
    Test.stopTest();

    List<CaseComment> comments = [
      SELECT CommentBody, ParentId
      FROM CaseComment
      WHERE ParentId = :record.Id
    ];
    Assert.areEqual(1, comments.size(), 'One comment should be written to the case.');
    Assert.areEqual(
      'Called the client back.',
      comments[0].CommentBody,
      'The body should be stored as typed.'
    );
  }

  @IsTest
  static void addCommentRejectsANullCaseId() {
    Boolean threw = false;

    Test.startTest();
    try {
      ArcCaseCommentController.addComment(null, 'Orphan comment');
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'A comment needs a case to hang off.');
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM CaseComment],
      'Nothing should be written without a case.'
    );
  }

  @IsTest
  static void addCommentRejectsABlankBody() {
    Case record = makeCase();
    Integer thrown = 0;

    Test.startTest();
    for (String body : new List<String>{ null, '', '   ' }) {
      try {
        ArcCaseCommentController.addComment(record.Id, body);
      } catch (AuraHandledException e) {
        thrown++;
      }
    }
    Test.stopTest();

    Assert.areEqual(
      3,
      thrown,
      'Null, empty and whitespace-only bodies are all rejected.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM CaseComment WHERE ParentId = :record.Id],
      'No comment should be written for a blank body.'
    );
  }
}