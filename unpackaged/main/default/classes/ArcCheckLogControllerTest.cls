/**
 * Tests for ArcCheckLogController and (through it) ArcFinServAccountLabels.
 *
 * The FinServ financial account is created and linked so the system-mode
 * label resolver's stitching is what the assertions actually exercise —
 * name and account number arriving on rows whose lookup targets an object
 * the generic USER_MODE pipeline cannot read for portal users.
 */
@IsTest
private class ArcCheckLogControllerTest {
  @TestSetup
  static void setup() {
    Account client = new Account(Name = 'Kelby Test Client', Type = 'Prospect', Classification__c = 'Unclassified');
    insert client;

    FinServ__FinancialAccount__c account = new FinServ__FinancialAccount__c(
      Name = 'Kelby Test Client - Trust - 655-000111',
      FinServ__FinancialAccountNumber__c = '655-000111',
      FinServ__PrimaryOwner__c = client.Id
    );
    insert account;

    Case supportCase = new Case(Subject = 'Deposit a check', Status = 'New');
    insert supportCase;

    Check_Log__c checkLog = new Check_Log__c(
      Status__c = 'Received',
      Amount__c = 1234.56,
      Method_of_Forwarding__c = 'Remote Deposit',
      Client__c = client.Id,
      Case__c = supportCase.Id,
      Financial_Account__c = account.Id,
      Received_Date__c = Date.newInstance(2026, 8, 1)
    );
    insert checkLog;

    insert new Check_Deposit__c(
      Check__c = checkLog.Id,
      Financial_Account__c = account.Id,
      Amount__c = 1234.56
    );

    ContentVersion version = new ContentVersion(
      Title = 'Deposit slip',
      PathOnClient = 'deposit-slip.pdf',
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
      LinkedEntityId = checkLog.Id,
      ContentDocumentId = documentId,
      ShareType = 'V'
    );
  }

  @IsTest
  static void contextCarriesIdentityAndFinServAccountLabels() {
    Check_Log__c checkLog = [SELECT Id, Name FROM Check_Log__c LIMIT 1];

    Test.startTest();
    ArcCheckLogController.CheckLogContext context = ArcCheckLogController.getCheckLogContext(
      checkLog.Id
    );
    Test.stopTest();

    System.assertEquals(checkLog.Name, context.name);
    System.assertEquals('Received', context.status);
    System.assertEquals(1234.56, context.amount);
    System.assertEquals('Kelby Test Client', context.clientName);
    System.assert(String.isNotBlank(context.caseNumber), 'Case number resolves');
    System.assertEquals(
      'Kelby Test Client - Trust - 655-000111',
      context.financialAccountName,
      'FinServ account name comes from the system-mode resolver'
    );
    System.assertEquals('655-000111', context.financialAccountNumber);
  }

  @IsTest
  static void nullAndUnknownIdsReturnEmptyContext() {
    ArcCheckLogController.CheckLogContext context = ArcCheckLogController.getCheckLogContext(
      null
    );
    System.assertEquals(null, context.name);
  }

  @IsTest
  static void depositsCarryFinServAccountNameAndNumber() {
    Check_Log__c checkLog = [SELECT Id FROM Check_Log__c LIMIT 1];

    Test.startTest();
    List<ArcCheckLogController.CheckDepositInfo> deposits = ArcCheckLogController.getCheckDeposits(
      checkLog.Id
    );
    Test.stopTest();

    System.assertEquals(1, deposits.size());
    System.assertEquals(1234.56, deposits[0].amount);
    System.assertEquals(
      'Kelby Test Client - Trust - 655-000111',
      deposits[0].financialAccountName
    );
    System.assertEquals('655-000111', deposits[0].financialAccountNumber);
  }

  @IsTest
  static void nullCheckLogIdReturnsEmptyDepositsAndFiles() {
    Test.startTest();
    List<ArcCheckLogController.CheckDepositInfo> deposits = ArcCheckLogController.getCheckDeposits(
      null
    );
    List<ArcCheckLogController.FileInfo> files = ArcCheckLogController.getCheckLogFiles(
      null
    );
    Test.stopTest();

    System.assertEquals(0, deposits.size(), 'A null id has no deposits');
    System.assertEquals(0, files.size(), 'A null id has no files');
  }

  @IsTest
  static void depositDetailCarriesEveryPopupField() {
    Check_Deposit__c deposit = [SELECT Id, Name FROM Check_Deposit__c LIMIT 1];

    Test.startTest();
    ArcCheckLogController.CheckDepositDetail detail = ArcCheckLogController.getCheckDeposit(
      deposit.Id
    );
    Test.stopTest();

    System.assertEquals(deposit.Name, detail.name);
    System.assertEquals(1234.56, detail.amount);
    System.assert(String.isNotBlank(detail.checkLogName), 'Parent name resolves');
    System.assertEquals('655-000111', detail.financialAccountNumber);
    System.assert(String.isNotBlank(detail.createdByName));
    System.assertEquals(null, ArcCheckLogController.getCheckDeposit(null));
  }

  @IsTest
  static void fileDataCarriesBytesAndMimeForTheViewer() {
    Check_Log__c checkLog = [SELECT Id FROM Check_Log__c LIMIT 1];
    List<ArcCheckLogController.FileInfo> files = ArcCheckLogController.getCheckLogFiles(
      checkLog.Id
    );

    Test.startTest();
    ArcFileViewerController.FilePayload payload = ArcFileViewerController.getFileData(
      files[0].contentDocumentId
    );
    Test.stopTest();

    System.assertEquals('application/pdf', payload.mimeType);
    System.assertEquals(false, payload.tooLarge);
    System.assertEquals(
      'test-bytes',
      EncodingUtil.base64Decode(payload.base64Data).toString(),
      'The payload must round-trip the file bytes'
    );
  }

  @IsTest
  static void fileDataThrowsForANullId() {
    Test.startTest();
    try {
      ArcFileViewerController.getFileData(null);
      System.assert(false, 'Expected an exception for a null id');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
    Test.stopTest();
  }

  @IsTest
  static void fileDataThrowsWhenTheFileIsMissing() {
    // A syntactically valid id that simply does not point at any
    // ContentDocument -- any other object's real id works, since the
    // controller only ever compares it against ContentVersion.ContentDocumentId.
    Check_Log__c checkLog = [SELECT Id FROM Check_Log__c LIMIT 1];

    Test.startTest();
    try {
      ArcFileViewerController.getFileData(checkLog.Id);
      System.assert(false, 'Expected an exception when no file matches');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
    Test.stopTest();
  }

  @IsTest
  static void unknownExtensionMapsToOctetStream() {
    ContentVersion version = new ContentVersion(
      Title = 'Notes',
      PathOnClient = 'notes.txt',
      VersionData = Blob.valueOf('plain text notes')
    );
    insert version;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;

    Test.startTest();
    ArcFileViewerController.FilePayload payload = ArcFileViewerController.getFileData(
      documentId
    );
    Test.stopTest();

    System.assertEquals(
      'application/octet-stream',
      payload.mimeType,
      'An extension outside the known map falls back to a generic mime type'
    );
  }

  @IsTest
  static void tooLargeFileReturnsNoDataButStillReportsMetadata() {
    // One byte past MAX_FILE_PREVIEW_BYTES (3 * 1024 * 1024), matching the
    // controller's own @TestVisible constant so this stays correct if that
    // cap ever changes.
    Integer oversized = ArcFileViewerController.MAX_FILE_PREVIEW_BYTES + 1;
    ContentVersion version = new ContentVersion(
      Title = 'Big File',
      PathOnClient = 'bigfile.pdf',
      VersionData = Blob.valueOf('x'.repeat(oversized))
    );
    insert version;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;

    Test.startTest();
    ArcFileViewerController.FilePayload payload = ArcFileViewerController.getFileData(
      documentId
    );
    Test.stopTest();

    System.assertEquals(true, payload.tooLarge, 'The file exceeds the cap');
    System.assertEquals(
      null,
      payload.base64Data,
      'No bytes should be sent for an oversized file'
    );
    System.assertEquals(
      'Big File',
      payload.title,
      'Metadata still comes back even when the bytes do not'
    );
  }

  @IsTest
  static void filesListTheAttachedDocuments() {
    Check_Log__c checkLog = [SELECT Id FROM Check_Log__c LIMIT 1];

    Test.startTest();
    List<ArcCheckLogController.FileInfo> files = ArcCheckLogController.getCheckLogFiles(
      checkLog.Id
    );
    Test.stopTest();

    System.assertEquals(1, files.size());
    System.assertEquals('Deposit slip', files[0].title);
    System.assertEquals('pdf', files[0].fileExtension);
    System.assert(files[0].contentDocumentId != null);
  }
}