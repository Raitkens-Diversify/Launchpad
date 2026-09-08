@isTest
private class EnvelopeDpiRepresentationsServiceTest {
  private static final String MF_DOC_NAME = 'Investment Representations and Agreements - Mutual Funds & 529';
  private static final String VA_DOC_NAME = 'Investment Representations and Agreements - Variable Annuities';
  private static final String AI_DOC_NAME = 'Investment Representations and Agreements - Alternative Investments';

  private static Id rtId(String dev) {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get(dev)
      .getRecordTypeId();
  }

  private static Boolean rtAvailable(String dev) {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get(dev);
    return info != null && info.isAvailable();
  }

  private static Id fiduciaryRtId() {
    return Schema.SObjectType.Account_Account_Relationship__c.getRecordTypeInfosByDeveloperName()
      .get('Fiduciary_Legal')
      .getRecordTypeId();
  }

  private static Id newHousehold() {
    Account hh = new Account(Name = 'HH', RecordTypeId = rtId('Household'));
    insert hh;
    return hh.Id;
  }

  private static Account newPerson(String first, String last) {
    Account p = new Account(
      FirstName = first,
      LastName = last,
      Type = 'Prospect',
      RecordTypeId = rtId('PersonAccount')
    );
    insert p;
    return p;
  }

  private static Account newEntity(String name, String dev) {
    Account e = new Account(Name = name, Type = 'Prospect', RecordTypeId = rtId(dev));
    insert e;
    return e;
  }

  private static Envelope__c newEnvelope() {
    Envelope__c env = new Envelope__c(Name = 'Env');
    insert env;
    return env;
  }

  private static Id newDpi(
    Id envelopeId,
    String name,
    String productType,
    Boolean isDpi,
    List<Id> ownerIds
  ) {
    Financial_Account__c fa = new Financial_Account__c(
      Name = name,
      DPI__c = isDpi,
      Product_Type__c = productType,
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
          Role__c = roles.isEmpty() ? 'Primary Owner' : 'Joint Owner'
        )
      );
    }
    if (!roles.isEmpty()) {
      insert roles;
    }
    return fa.Id;
  }

  private static void makeParty(Id entityId, Id personId, String role) {
    insert new Account_Account_Relationship__c(
      Account__c = entityId,
      Related_Account__c = personId,
      Roles__c = role,
      RecordTypeId = fiduciaryRtId(),
      Active__c = true
    );
  }

  private static Integer docsForDpi(Id dpiId, String docName) {
    return [
      SELECT COUNT()
      FROM Required_Documents__c
      WHERE Financial_Account__c = :dpiId AND Name = :docName
    ];
  }

  private static Integer signeesForDpi(Id dpiId, String docName) {
    return [
      SELECT COUNT()
      FROM Signee__c
      WHERE
        Required_Document__r.Financial_Account__c = :dpiId
        AND Required_Document__r.Name = :docName
    ];
  }

  // A Mutual Fund DPI with an individual primary + joint owner gets one Mutual Funds & 529 document
  // signed by both.
  @isTest
  static void testMutualFundIndividualPrimaryAndJoint() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Account bob = newPerson('Bob', 'Roe');
    Id dpi = newDpi(env.Id, 'Fund DPI', 'Mutual Fund', true, new List<Id>{ jane.Id, bob.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, docsForDpi(dpi, MF_DOC_NAME), 'One Mutual Funds & 529 document.');
    System.assertEquals(2, signeesForDpi(dpi, MF_DOC_NAME), 'Primary and joint owner both sign.');
  }

  // A 529 DPI shares the Mutual Funds & 529 document.
  @isTest
  static void test529SharesMutualFundDoc() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id dpi = newDpi(env.Id, '529 DPI', '529', true, new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, docsForDpi(dpi, MF_DOC_NAME), 'A 529 DPI gets the Mutual Funds & 529 doc.');
  }

  // A Variable Annuity DPI gets its own Variable Annuities document.
  @isTest
  static void testVariableAnnuityGetsOwnDoc() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id dpi = newDpi(env.Id, 'VA DPI', 'Variable Annuity', true, new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, docsForDpi(dpi, VA_DOC_NAME), 'One Variable Annuities document.');
    System.assertEquals(0, docsForDpi(dpi, MF_DOC_NAME), 'Not the Mutual Funds & 529 document.');
    System.assertEquals(1, signeesForDpi(dpi, VA_DOC_NAME), 'The owner signs it.');
  }

  // An Alternative Investment DPI gets its own Alternative Investments document.
  @isTest
  static void testAlternativeInvestmentGetsOwnDoc() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id dpi = newDpi(env.Id, 'Alt DPI', 'Alternative Investment', true, new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, docsForDpi(dpi, AI_DOC_NAME), 'One Alternative Investments document.');
    System.assertEquals(1, signeesForDpi(dpi, AI_DOC_NAME), 'The owner signs it.');
  }

  // A non-qualifying product type gets no document.
  @isTest
  static void testOtherProductTypeIgnored() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id dpi = newDpi(env.Id, 'VLI DPI', 'Variable Life Insurance', true, new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, docsForDpi(dpi, MF_DOC_NAME), 'No Mutual Funds & 529 doc.');
    System.assertEquals(0, docsForDpi(dpi, VA_DOC_NAME), 'No Variable Annuities doc.');
    System.assertEquals(0, docsForDpi(dpi, AI_DOC_NAME), 'No Alternative Investments doc.');
  }

  // A Mutual Fund account that is NOT a DPI gets no document.
  @isTest
  static void testNonDpiIgnored() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id acct = newDpi(env.Id, 'Fund Acct', 'Mutual Fund', false, new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, docsForDpi(acct, MF_DOC_NAME), 'A non-DPI account gets no document.');
  }

  // A business owner is signed by its Authorized Persons; a trust owner by its Trustees.
  @isTest
  static void testEntityOwnersExpandToFiduciaries() {
    if (!rtAvailable('Business') || !rtAvailable('Trust')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account acme = newEntity('Acme', 'Business');
    Account ap = newPerson('Auth', 'Person');
    makeParty(acme.Id, ap.Id, 'Authorized Person');
    Id bizDpi = newDpi(env.Id, 'Biz DPI', 'Mutual Fund', true, new List<Id>{ acme.Id });

    Account trust = newEntity('Family Trust', 'Trust');
    Account tr = newPerson('Trust', 'Ee');
    makeParty(trust.Id, tr.Id, 'Trustee');
    Id trustDpi = newDpi(env.Id, 'Trust DPI', 'Variable Annuity', true, new List<Id>{ trust.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(1, signeesForDpi(bizDpi, MF_DOC_NAME), 'Business DPI signed by its Authorized Person.');
    System.assertEquals(1, signeesForDpi(trustDpi, VA_DOC_NAME), 'Trust VA DPI signed by its Trustee.');
  }

  // Signees reconcile as parties change, and the document is removed if the product type becomes
  // non-qualifying.
  @isTest
  static void testReconcileAndRemoval() {
    if (!rtAvailable('Business')) {
      return;
    }
    Envelope__c env = newEnvelope();
    Account acme = newEntity('Acme', 'Business');
    Account ap1 = newPerson('A', 'One');
    makeParty(acme.Id, ap1.Id, 'Authorized Person');
    Id dpi = newDpi(env.Id, 'Biz DPI', 'Mutual Fund', true, new List<Id>{ acme.Id });

    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    System.assertEquals(1, signeesForDpi(dpi, MF_DOC_NAME), 'One signee to start.');

    Account ap2 = newPerson('B', 'Two');
    makeParty(acme.Id, ap2.Id, 'Authorized Person');
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    System.assertEquals(2, signeesForDpi(dpi, MF_DOC_NAME), 'Both Authorized Persons sign.');

    // Move to a non-qualifying product type; the document is removed.
    update new Financial_Account__c(Id = dpi, Product_Type__c = 'Variable Life Insurance');

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, docsForDpi(dpi, MF_DOC_NAME), 'Document removed once the DPI no longer qualifies.');
  }

  // Changing product type from Mutual Fund to Variable Annuity swaps the document.
  @isTest
  static void testProductTypeChangeSwapsDocument() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id dpi = newDpi(env.Id, 'DPI', 'Mutual Fund', true, new List<Id>{ jane.Id });
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    System.assertEquals(1, docsForDpi(dpi, MF_DOC_NAME), 'Mutual Funds & 529 doc first.');

    update new Financial_Account__c(Id = dpi, Product_Type__c = 'Variable Annuity');

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    Test.stopTest();

    System.assertEquals(0, docsForDpi(dpi, MF_DOC_NAME), 'Old document removed.');
    System.assertEquals(1, docsForDpi(dpi, VA_DOC_NAME), 'Variable Annuities document created.');
  }

  @isTest
  static void testIdempotentAndNullNoOp() {
    Envelope__c env = newEnvelope();
    Account jane = newPerson('Jane', 'Doe');
    Id dpi = newDpi(env.Id, 'Fund DPI', 'Mutual Fund', true, new List<Id>{ jane.Id });

    Test.startTest();
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    EnvelopeDpiRepresentationsService.reconcile(env.Id);
    EnvelopeDpiRepresentationsService.reconcile(null);
    Test.stopTest();

    System.assertEquals(1, docsForDpi(dpi, MF_DOC_NAME), 'No duplicate on re-run; null is a no-op.');
    System.assertEquals(1, signeesForDpi(dpi, MF_DOC_NAME), 'Single signee, not duplicated.');
  }
}