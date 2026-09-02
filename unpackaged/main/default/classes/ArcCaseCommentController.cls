/**
 * Add Comment for the ARC site's case page — the launchpad Case.Add_Comment
 * quick action's behavior (a Create action targeting CaseComment with a
 * single CommentBody field), done imperatively so the LWR page can run it.
 */
public with sharing class ArcCaseCommentController {
  @AuraEnabled
  public static void addComment(Id caseId, String body) {
    if (caseId == null || String.isBlank(body)) {
      throw new AuraHandledException('A comment is required.');
    }
    insert new CaseComment(ParentId = caseId, CommentBody = body);
  }
}