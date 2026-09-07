@isTest
private class EnvelopeCourtesyAgreementServiceTest {
  private static final String DOC_NAME = 'Courtesy Account Services Agreement';

  private static Id personRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();
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

  private static Envelope__c newEnvelope() {
    Envelope__c env = new Envelope__c(Name = 'Test Envelope');
    insert env;
    return env;
  }

  // A Courtesy account linked to the envelope, owned by the given owners (all as Primary Owner for
  // simplicity — the service groups by the owner set, not the role).
  private static Id newCourtesyAccount(
    Id envelopeId,
    String name,
    List<Id> ownerIds
  ) {
    return newAccount(envelopeId, name, 'Courtesy Account', ownerIds);
  }

  private static Id newAccount(
    Id envelopeId,
    String name,
    String platform,
    List<Id> ownerIds
  ) {
    Financial_Account__c fa = new Financial_Account__c(
      Name = name,
      Managed_Account_Platform__c = platform,
      Household__c = newHousehold()
    );
    insert fa;
    insert new Envelope_Content__c(
      Envelope__c = envelopeId,
      Wizard_Financial_Account__c = fa.Id
    );
    List<Financial_Account_Role__c> roles = new List<Financial_Account_Role__c>();
    for (Id ownerId : ownerIds) {
      roles.add(
        new Financial_Account_Role__c(
          Financial_Account__c = fa.Id,
          Account__c = ownerId,
          Role__c = 'Primary Owner'
        )
      );
    }
    if (!roles.isEmpty()) {
      insert roles;
    }
    return fa.Id;
  }

  private static Integer agreementCount() {
    return [SELECT COUNT() FROM Required_Documents__c WHERE Name = :DOC_NAME];
  }

  // One Courtesy account earns one agreement, signed by its owners.
  @isTest
  static void testSingleAccountCreatesAgreement() {
    Envelope__c env = newEnvelope();
    Account o1 = newOwner('Jane', 'Doe');
    Account o2 = newOwner('John', 'Roe');
    newCourtesyAccount(env.Id, 'Acct 1', new List<Id>{ o1.Id, o2.Id });

    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, agreementCount(), 'One agreement for one Courtesy account.');
    Id docId = [SELECT Id FROM Required_Documents__c WHERE Name = :DOC_NAME].Id;
    System.assertEquals(
      2,
      [SELECT COUNT() FROM Signee__c WHERE Required_Document__c = :docId],
      'Both owners sign the agreement.'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Envelope_Content__c
        WHERE Envelope__c = :env.Id AND Required_Document__c = :docId
      ],
      'The agreement is linked to the envelope.'
    );
  }

  // Up to three accounts with the same owners share one agreement; a fourth adds a second.
  @isTest
  static void testThreeShareOneFourthAddsSecond() {
    Envelope__c env = newEnvelope();
    Account o1 = newOwner('Jane', 'Doe');
    Account o2 = newOwner('John', 'Roe');
    List<Id> owners = new List<Id>{ o1.Id, o2.Id };
    newCourtesyAccount(env.Id, 'Acct 1', owners);
    newCourtesyAccount(env.Id, 'Acct 2', owners);
    newCourtesyAccount(env.Id, 'Acct 3', owners);

    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    System.assertEquals(1, agreementCount(), 'Three accounts share one agreement.');

    newCourtesyAccount(env.Id, 'Acct 4', owners);

    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(2, agreementCount(), 'A fourth account with the same owners adds a second agreement.');
  }

  // Accounts with different owners get their own agreements.
  @isTest
  static void testDifferentOwnersGetSeparateAgreements() {
    Envelope__c env = newEnvelope();
    Account o1 = newOwner('Jane', 'Doe');
    Account o2 = newOwner('John', 'Roe');
    newCourtesyAccount(env.Id, 'Acct 1', new List<Id>{ o1.Id });
    newCourtesyAccount(env.Id, 'Acct 2', new List<Id>{ o2.Id });

    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(2, agreementCount(), 'Two owner sets, two agreements.');
  }

  // A non-Courtesy account earns no agreement.
  @isTest
  static void testNonCourtesyAccountIgnored() {
    Envelope__c env = newEnvelope();
    Account o1 = newOwner('Jane', 'Doe');
    newAccount(env.Id, 'Acct 1', 'AMS', new List<Id>{ o1.Id });

    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, agreementCount(), 'A non-Courtesy account gets no agreement.');
  }

  // A Courtesy account with no owners yet earns no agreement.
  @isTest
  static void testNoOwnersNoAgreement() {
    Envelope__c env = newEnvelope();
    newCourtesyAccount(env.Id, 'Acct 1', new List<Id>());

    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, agreementCount(), 'No owners means no agreement.');
  }

  // Removing an account drops the group back below the three-account boundary and removes the extra
  // agreement.
  @isTest
  static void testRemovalShrinksAgreements() {
    Envelope__c env = newEnvelope();
    Account o1 = newOwner('Jane', 'Doe');
    List<Id> owners = new List<Id>{ o1.Id };
    newCourtesyAccount(env.Id, 'Acct 1', owners);
    newCourtesyAccount(env.Id, 'Acct 2', owners);
    newCourtesyAccount(env.Id, 'Acct 3', owners);
    Id fourth = newCourtesyAccount(env.Id, 'Acct 4', owners);
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    System.assertEquals(2, agreementCount(), 'Four accounts need two agreements.');

    // Simulate the fourth account being removed from the envelope.
    delete [
      SELECT Id
      FROM Envelope_Content__c
      WHERE Wizard_Financial_Account__c = :fourth
    ];

    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, agreementCount(), 'Back to three accounts, one agreement.');
  }

  // A sent agreement is never removed, even once its accounts are gone.
  @isTest
  static void testSentAgreementPreserved() {
    Envelope__c env = newEnvelope();
    Account o1 = newOwner('Jane', 'Doe');
    Id acct = newCourtesyAccount(env.Id, 'Acct 1', new List<Id>{ o1.Id });
    EnvelopeCourtesyAgreementService.reconcile(env.Id);

    dfsle__Envelope__c dse = new dfsle__Envelope__c();
    insert dse;
    Required_Documents__c doc = [SELECT Id FROM Required_Documents__c WHERE Name = :DOC_NAME];
    doc.DocuSign_Envelope__c = dse.Id;
    update doc;

    // Remove the account so the owner group would otherwise drop to zero agreements.
    delete [
      SELECT Id
      FROM Envelope_Content__c
      WHERE Wizard_Financial_Account__c = :acct
    ];

    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, agreementCount(), 'A sent agreement is left in place.');
  }

  @isTest
  static void testNullEnvelopeIsNoOp() {
    Test.startTest();
    EnvelopeCourtesyAgreementService.reconcile(null);
    Test.stopTest();
    System.assertEquals(0, agreementCount(), 'Null envelope creates nothing.');
  }
}