@isTest
private class EnvelopeAccountAddendumServiceTest {
  private static Id personRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();
  }

  private static Account newOwner(String first, String last) {
    Account owner = new Account(
      FirstName = first,
      LastName = last,
      Type = 'Prospect',
      RecordTypeId = personRecordTypeId()
    );
    insert owner;
    return owner;
  }

  private static Id newHousehold() {
    Account household = new Account(
      Name = 'Test Household',
      RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Household')
        .getRecordTypeId()
    );
    insert household;
    return household.Id;
  }

  private static Financial_Account__c newAccount(String platform) {
    // A Household is required: the Financial_Account_Trigger stamps the household for DMS platforms
    // and updates it, which fails on a household-less account.
    Financial_Account__c fa = new Financial_Account__c(
      Name = 'Acct 1',
      BD_or_RIA__c = 'RIA',
      Managed_Account_Platform__c = platform,
      Household__c = newHousehold()
    );
    insert fa;
    return fa;
  }

  private static void addOwner(Id faId, Id ownerId, String role) {
    insert new Financial_Account_Role__c(
      Financial_Account__c = faId,
      Account__c = ownerId,
      Role__c = role
    );
  }

  private static Envelope__c newEnvelope() {
    Envelope__c env = new Envelope__c(Name = 'Test Envelope');
    insert env;
    return env;
  }

  private static List<Required_Documents__c> addenda(Id faId, String suffix) {
    return [
      SELECT Id, Name
      FROM Required_Documents__c
      WHERE Financial_Account__c = :faId AND Name LIKE :('%' + suffix)
    ];
  }

  // An RIA/DMS account with an unsigned owner earns a DMS Addendum named from the account, hung off
  // the account, linked to the envelope, and signed by that owner.
  @isTest
  static void testCreatesAddendumForUnsignedOwner() {
    Financial_Account__c fa = newAccount('DMS');
    Account owner = newOwner('Jane', 'Doe');
    addOwner(fa.Id, owner.Id, 'Primary Owner');
    Envelope__c env = newEnvelope();

    Test.startTest();
    EnvelopeAccountAddendumService.reconcile(fa.Id, env.Id);
    Test.stopTest();

    List<Required_Documents__c> docs = addenda(fa.Id, ' - DMS Addendum');
    System.assertEquals(1, docs.size(), 'A DMS Addendum should be created.');
    System.assertEquals('Acct 1 - DMS Addendum', docs[0].Name, 'Named from the account.');
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Signee__c
        WHERE Required_Document__c = :docs[0].Id AND Account__c = :owner.Id
      ],
      'The unsigned owner signs the addendum.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Required_Document__c = :docs[0].Id
      ],
      'The addendum is linked to the envelope.'
    );
  }

  // Only owners with a null signed-date sign: a joint owner who has already signed is not a signee.
  @isTest
  static void testOnlyUnsignedOwnersSign() {
    Financial_Account__c fa = newAccount('DMS');
    Account unsigned = newOwner('Jane', 'Doe');
    Account signed = newOwner('John', 'Roe');
    signed.DMS_Addendum_Signed_Date__c = Date.today();
    update signed;
    addOwner(fa.Id, unsigned.Id, 'Primary Owner');
    addOwner(fa.Id, signed.Id, 'Joint Owner');

    Test.startTest();
    EnvelopeAccountAddendumService.reconcile(fa.Id, null);
    Test.stopTest();

    Id docId = addenda(fa.Id, ' - DMS Addendum')[0].Id;
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Signee__c WHERE Required_Document__c = :docId],
      'Exactly one signee — the unsigned owner.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Signee__c
        WHERE Required_Document__c = :docId AND Account__c = :unsigned.Id
      ],
      'The signee is the unsigned owner.'
    );
  }

  // When every owner has signed, no addendum is created.
  @isTest
  static void testNoAddendumWhenAllSigned() {
    Financial_Account__c fa = newAccount('AMS');
    Account owner = newOwner('Jane', 'Doe');
    owner.AMS_Addendum_Signed_Date__c = Date.today();
    update owner;
    addOwner(fa.Id, owner.Id, 'Primary Owner');

    Test.startTest();
    EnvelopeAccountAddendumService.reconcile(fa.Id, null);
    Test.stopTest();

    System.assertEquals(
      0,
      addenda(fa.Id, ' - AMS Addendum').size(),
      'No addendum when all owners have signed.'
    );
  }

  // A BD account gets no addendum even with a platform set.
  @isTest
  static void testBdAccountGetsNoAddendum() {
    // Brokerage + account number set to avoid an unrelated after-insert trigger path
    // (setReportAcctNumber_AfterInsert) that mutates read-only records for BD accounts without them.
    Financial_Account__c fa = new Financial_Account__c(
      Name = 'Acct 1',
      BD_or_RIA__c = 'BD',
      Managed_Account_Platform__c = 'DMS',
      Brokerage__c = true,
      Account_Number__c = '00012345',
      Household__c = newHousehold()
    );
    insert fa;
    Account owner = newOwner('Jane', 'Doe');
    addOwner(fa.Id, owner.Id, 'Primary Owner');

    Test.startTest();
    EnvelopeAccountAddendumService.reconcile(fa.Id, null);
    Test.stopTest();

    System.assertEquals(
      0,
      addenda(fa.Id, ' - DMS Addendum').size(),
      'A BD account earns no platform addendum.'
    );
  }

  // A platform change removes the stale addendum and creates the new one.
  @isTest
  static void testPlatformChangeSwapsAddendum() {
    Financial_Account__c fa = newAccount('DMS');
    Account owner = newOwner('Jane', 'Doe');
    addOwner(fa.Id, owner.Id, 'Primary Owner');
    EnvelopeAccountAddendumService.reconcile(fa.Id, null);
    System.assertEquals(1, addenda(fa.Id, ' - DMS Addendum').size(), 'DMS created first.');

    fa.Managed_Account_Platform__c = 'AMS';
    update fa;

    Test.startTest();
    EnvelopeAccountAddendumService.reconcile(fa.Id, null);
    Test.stopTest();

    System.assertEquals(
      0,
      addenda(fa.Id, ' - DMS Addendum').size(),
      'The stale DMS addendum is removed.'
    );
    System.assertEquals(
      1,
      addenda(fa.Id, ' - AMS Addendum').size(),
      'The AMS addendum is created.'
    );
  }

  // An addendum already handed to DocuSign is not removed when the platform changes.
  @isTest
  static void testSentAddendumIsPreserved() {
    Financial_Account__c fa = newAccount('DMS');
    Account owner = newOwner('Jane', 'Doe');
    addOwner(fa.Id, owner.Id, 'Primary Owner');
    EnvelopeAccountAddendumService.reconcile(fa.Id, null);

    // Simulate the addendum having been sent.
    dfsle__Envelope__c dse = new dfsle__Envelope__c();
    insert dse;
    Required_Documents__c doc = addenda(fa.Id, ' - DMS Addendum')[0];
    doc.DocuSign_Envelope__c = dse.Id;
    update doc;

    fa.Managed_Account_Platform__c = 'OMS';
    update fa;

    Test.startTest();
    EnvelopeAccountAddendumService.reconcile(fa.Id, null);
    Test.stopTest();

    System.assertEquals(
      1,
      addenda(fa.Id, ' - DMS Addendum').size(),
      'A sent addendum is left in place.'
    );
  }

  @isTest
  static void testNullAccountIsNoOp() {
    Test.startTest();
    EnvelopeAccountAddendumService.reconcile(null, null);
    Test.stopTest();
    System.assertEquals(
      0,
      [SELECT COUNT() FROM Required_Documents__c],
      'Null input creates nothing.'
    );
  }
}