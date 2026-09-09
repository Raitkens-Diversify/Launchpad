@IsTest
private class ArcAccountFilesControllerTest {
  private static Id linkFile(Id accountId, String title, String pathOnClient) {
    ContentVersion version = new ContentVersion(
      Title = title,
      PathOnClient = pathOnClient,
      VersionData = Blob.valueOf('test-bytes')
    );
    insert version;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      LinkedEntityId = accountId,
      ContentDocumentId = documentId,
      ShareType = 'V'
    );
    return documentId;
  }

  @IsTest
  static void getFilesReturnsOnlyTheFilesLinkedToTheRecord() {
    Account account = new Account(Name = 'Files Account', Type = 'Prospect');
    Account other = new Account(Name = 'Other Account', Type = 'Prospect');
    insert new List<Account>{ account, other };

    Id statementId = linkFile(account.Id, 'Statement', 'statement.pdf');
    Id noteId = linkFile(account.Id, 'Meeting notes', 'notes.txt');
    linkFile(other.Id, 'Not this one', 'other.pdf');

    Test.startTest();
    List<ArcAccountFilesController.FileInfo> files = ArcAccountFilesController.getFiles(
      account.Id
    );
    Test.stopTest();

    Assert.areEqual(2, files.size(), 'Only the record\'s own files come back');
    Map<Id, ArcAccountFilesController.FileInfo> byId = new Map<Id, ArcAccountFilesController.FileInfo>();
    for (ArcAccountFilesController.FileInfo file : files) {
      byId.put(file.contentDocumentId, file);
    }
    Assert.isTrue(byId.containsKey(statementId));
    Assert.isTrue(byId.containsKey(noteId));
    Assert.areEqual('Statement', byId.get(statementId).title);
    Assert.areEqual('pdf', byId.get(statementId).fileExtension);
    Assert.areEqual('txt', byId.get(noteId).fileExtension);
    Assert.isNotNull(byId.get(statementId).contentModifiedDate);
  }

  @IsTest
  static void getFilesReturnsNothingForARecordWithoutFiles() {
    Account account = new Account(Name = 'Empty Account', Type = 'Prospect');
    insert account;

    Test.startTest();
    List<ArcAccountFilesController.FileInfo> files = ArcAccountFilesController.getFiles(
      account.Id
    );
    Test.stopTest();

    Assert.areEqual(0, files.size());
  }

  @IsTest
  static void getFilesReturnsNothingForANullId() {
    Test.startTest();
    List<ArcAccountFilesController.FileInfo> files = ArcAccountFilesController.getFiles(
      null
    );
    Test.stopTest();

    Assert.areEqual(0, files.size());
  }
}