public with sharing class EnvelopeDpiRepresentationsService {
  // The Financial_Account_Role__c roles whose holders are the owners the document is signed by.
  private static final Set<String> OWNER_ROLES = new Set<String>{
    'Primary Owner',
    'Joint Owner'
  };

  // The document a qualifying DPI gets, keyed by its Product_Type__c. Several product types can share
  // one document (Mutual Fund and 529), and a new product type is added here with its own name.
  private static final Map<String, String> DOC_NAME_BY_PRODUCT_TYPE = new Map<String, String>{
    'Mutual Fund' => 'Investment Representations and Agreements - Mutual Funds & 529',
    '529' => 'Investment Representations and Agreements - Mutual Funds & 529',
    'Variable Annuity' => 'Investment Representations and Agreements - Variable Annuities',
    'Alternative Investment' => 'Investment Representations and Agreements - Alternative Investments'
  };

  // How an entity owner contributes signers: a business or retirement plan through its Authorized
  // Persons, a trust through its Trustees. An individual owner signs directly and is not here.
  private static final Map<String, String> FIDUCIARY_ROLE_BY_RECORD_TYPE = new Map<String, String>{
    'Business' => 'Authorized Person',
    'Trust' => 'Trustee',
    'Retirement_Plan' => 'Authorized Person'
  };

  // Every document name this service manages. Public so refreshAccountSignees can recognise and skip
  // these: they hang off Financial_Account__c but their signees are the DPI's owners expanded to
  // their fiduciaries, not simply every owner, so they are owned here rather than there.
  public static Set<String> docNames() {
    return new Set<String>(DOC_NAME_BY_PRODUCT_TYPE.values());
  }

  // Brings an envelope's DPI Investment Representations documents into line with its DPIs. A DPI (a
  // Financial_Account__c with DPI__c = true) gets the document its Product_Type__c calls for — Mutual
  // Fund and 529 share one, Variable Annuity has its own — signed by its owners: an individual owner
  // directly (primary and joint), a business or retirement plan owner through its Authorized Persons,
  // a trust owner through its Trustees.
  //
  // Envelope-scoped, idempotent and reconciling. A document already handed to DocuSign
  // (DocuSign_Envelope__c set) is never removed or altered.
  public static void reconcile(Id envelopeId) {
    if (envelopeId == null) {
      return;
    }

    Map<Id, String> docNameByDpi = docNameByDpi(envelopeId);
    Map<Id, Set<Id>> signersByDpi = docNameByDpi.isEmpty()
      ? new Map<Id, Set<Id>>()
      : signersByDpi(docNameByDpi.keySet());

    List<Required_Documents__c> existing = docsInEnvelope(envelopeId);
    Map<Id, Set<Id>> signeesByDoc = signeesByDoc(existing);

    // Match each existing document to the DPI it belongs to, but only when its name is still the one
    // that DPI's product type calls for — a product type that changed (or a DPI that dropped out)
    // leaves a wrongly-named document, which is removed unless it has been sent.
    Map<Id, Required_Documents__c> docByDpi = new Map<Id, Required_Documents__c>();
    Set<Id> docIdsToDelete = new Set<Id>();
    for (Required_Documents__c doc : existing) {
      Id dpiId = doc.Financial_Account__c;
      String desiredName = dpiId == null ? null : docNameByDpi.get(dpiId);
      if (desiredName != null && doc.Name == desiredName) {
        if (!docByDpi.containsKey(dpiId)) {
          docByDpi.put(dpiId, doc);
        } else if (doc.DocuSign_Envelope__c == null) {
          docIdsToDelete.add(doc.Id);
        }
      } else if (doc.DocuSign_Envelope__c == null) {
        docIdsToDelete.add(doc.Id);
      }
    }

    for (Id dpiId : docNameByDpi.keySet()) {
      Set<Id> desired = signersByDpi.get(dpiId);
      if (desired == null) {
        desired = new Set<Id>();
      }
      Required_Documents__c doc = docByDpi.get(dpiId);
      if (doc != null) {
        reconcileDocSignees(doc.Id, desired, signeesByDoc.get(doc.Id));
      } else {
        createDoc(envelopeId, dpiId, docNameByDpi.get(dpiId), desired);
      }
    }

    deleteDocs(docIdsToDelete);
  }

  // Creates (or updates) the Alternative Investments document for one account in an envelope, outside
  // the product-type-driven scan — used when the wizard's "Purchase Alternative Investments" account
  // action is raised on a submitted account. The signees are the account's owners expanded to their
  // fiduciaries, exactly as the DPI-scan documents; create-once and idempotent.
  public static void ensureAlternativeInvestmentsDoc(
    Id financialAccountId,
    Id envelopeId
  ) {
    if (financialAccountId == null || envelopeId == null) {
      return;
    }
    String docName = DOC_NAME_BY_PRODUCT_TYPE.get('Alternative Investment');

    Set<Id> desired = signersByDpi(new Set<Id>{ financialAccountId })
      .get(financialAccountId);
    if (desired == null) {
      desired = new Set<Id>();
    }

    List<Required_Documents__c> existing = docsInEnvelope(envelopeId);
    Map<Id, Set<Id>> signeesByDoc = signeesByDoc(existing);
    Required_Documents__c target = null;
    for (Required_Documents__c doc : existing) {
      if (
        doc.Financial_Account__c == financialAccountId &&
        doc.Name == docName &&
        doc.DocuSign_Envelope__c == null
      ) {
        target = doc;
        break;
      }
    }

    if (target != null) {
      reconcileDocSignees(target.Id, desired, signeesByDoc.get(target.Id));
    } else {
      createDoc(envelopeId, financialAccountId, docName, desired);
    }
  }

  // ------------------------------------------------------------------------
  // Signers
  // ------------------------------------------------------------------------

  private static Map<Id, Set<Id>> signersByDpi(Set<Id> dpiIds) {
    Map<Id, List<Id>> ownersByDpi = new Map<Id, List<Id>>();
    Set<Id> allOwnerIds = new Set<Id>();
    for (Financial_Account_Role__c role : [
      SELECT Financial_Account__c, Account__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c IN :dpiIds
        AND Role__c IN :OWNER_ROLES
        AND Account__c != NULL
    ]) {
      if (!ownersByDpi.containsKey(role.Financial_Account__c)) {
        ownersByDpi.put(role.Financial_Account__c, new List<Id>());
      }
      ownersByDpi.get(role.Financial_Account__c).add(role.Account__c);
      allOwnerIds.add(role.Account__c);
    }

    Map<Id, String> recordTypeByOwner = new Map<Id, String>();
    Map<Id, Account> entityOwners = new Map<Id, Account>();
    for (Account owner : [
      SELECT Id, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :allOwnerIds
    ]) {
      recordTypeByOwner.put(owner.Id, owner.RecordType.DeveloperName);
      if (FIDUCIARY_ROLE_BY_RECORD_TYPE.containsKey(owner.RecordType.DeveloperName)) {
        entityOwners.put(owner.Id, owner);
      }
    }
    Map<Id, Set<Id>> partiesByEntity = fiduciaryPartiesByEntity(entityOwners);

    Map<Id, Set<Id>> signersByDpi = new Map<Id, Set<Id>>();
    for (Id dpiId : dpiIds) {
      Set<Id> signers = new Set<Id>();
      List<Id> owners = ownersByDpi.get(dpiId);
      if (owners != null) {
        for (Id ownerId : owners) {
          String recordType = recordTypeByOwner.get(ownerId);
          if (recordType == 'PersonAccount') {
            signers.add(ownerId);
          } else if (FIDUCIARY_ROLE_BY_RECORD_TYPE.containsKey(recordType)) {
            Set<Id> parties = partiesByEntity.get(ownerId);
            if (parties != null) {
              signers.addAll(parties);
            }
          }
        }
      }
      signersByDpi.put(dpiId, signers);
    }
    return signersByDpi;
  }

  private static Map<Id, Set<Id>> fiduciaryPartiesByEntity(
    Map<Id, Account> entityOwners
  ) {
    Map<Id, Set<Id>> partiesByEntity = new Map<Id, Set<Id>>();
    if (entityOwners.isEmpty()) {
      return partiesByEntity;
    }
    for (Account_Account_Relationship__c relation : [
      SELECT Account__c, Related_Account__c, Roles__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c IN :entityOwners.keySet()
        AND Related_Account__c != NULL
        AND Active__c = TRUE
    ]) {
      Account entity = entityOwners.get(relation.Account__c);
      if (entity == null) {
        continue;
      }
      String role = FIDUCIARY_ROLE_BY_RECORD_TYPE.get(
        entity.RecordType.DeveloperName
      );
      if (role == null || !rolesContain(relation.Roles__c, role)) {
        continue;
      }
      if (!partiesByEntity.containsKey(relation.Account__c)) {
        partiesByEntity.put(relation.Account__c, new Set<Id>());
      }
      partiesByEntity.get(relation.Account__c).add(relation.Related_Account__c);
    }
    return partiesByEntity;
  }

  // ------------------------------------------------------------------------
  // Queries
  // ------------------------------------------------------------------------

  // Each qualifying DPI in the envelope mapped to the document name its product type calls for.
  private static Map<Id, String> docNameByDpi(Id envelopeId) {
    Set<Id> accountIds = new Set<Id>();
    for (Envelope_Content__c ec : [
      SELECT Wizard_Financial_Account__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Wizard_Financial_Account__c != NULL
    ]) {
      accountIds.add(ec.Wizard_Financial_Account__c);
    }
    Map<Id, String> docNameByDpi = new Map<Id, String>();
    if (accountIds.isEmpty()) {
      return docNameByDpi;
    }
    Set<String> productTypes = DOC_NAME_BY_PRODUCT_TYPE.keySet();
    for (Financial_Account__c fa : [
      SELECT Id, Product_Type__c
      FROM Financial_Account__c
      WHERE
        Id IN :accountIds
        AND DPI__c = TRUE
        AND Product_Type__c IN :productTypes
    ]) {
      docNameByDpi.put(fa.Id, DOC_NAME_BY_PRODUCT_TYPE.get(fa.Product_Type__c));
    }
    return docNameByDpi;
  }

  private static List<Required_Documents__c> docsInEnvelope(Id envelopeId) {
    Set<Id> docIds = new Set<Id>();
    for (Envelope_Content__c ec : [
      SELECT Required_Document__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Required_Document__c != NULL
    ]) {
      docIds.add(ec.Required_Document__c);
    }
    if (docIds.isEmpty()) {
      return new List<Required_Documents__c>();
    }
    Set<String> names = docNames();
    return [
      SELECT Id, Name, Financial_Account__c, DocuSign_Envelope__c
      FROM Required_Documents__c
      WHERE Id IN :docIds AND Name IN :names
    ];
  }

  private static Map<Id, Set<Id>> signeesByDoc(
    List<Required_Documents__c> docs
  ) {
    Map<Id, Set<Id>> byDoc = new Map<Id, Set<Id>>();
    if (docs.isEmpty()) {
      return byDoc;
    }
    Set<Id> docIds = new Map<Id, Required_Documents__c>(docs).keySet();
    for (Signee__c signee : [
      SELECT Required_Document__c, Account__c
      FROM Signee__c
      WHERE Required_Document__c IN :docIds AND Account__c != NULL
    ]) {
      if (!byDoc.containsKey(signee.Required_Document__c)) {
        byDoc.put(signee.Required_Document__c, new Set<Id>());
      }
      byDoc.get(signee.Required_Document__c).add(signee.Account__c);
    }
    return byDoc;
  }

  // ------------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------------

  private static void createDoc(
    Id envelopeId,
    Id dpiId,
    String docName,
    Set<Id> signerIds
  ) {
    Required_Documents__c doc = new Required_Documents__c(
      Name = docName,
      Financial_Account__c = dpiId
    );
    insert doc;
    List<Signee__c> signees = new List<Signee__c>();
    for (Id signerId : signerIds) {
      signees.add(
        new Signee__c(Required_Document__c = doc.Id, Account__c = signerId)
      );
    }
    if (!signees.isEmpty()) {
      insert signees;
    }
    insert new Envelope_Content__c(
      Envelope__c = envelopeId,
      Required_Document__c = doc.Id
    );
  }

  private static void reconcileDocSignees(
    Id docId,
    Set<Id> desired,
    Set<Id> current
  ) {
    Set<Id> have = current == null ? new Set<Id>() : current;

    List<Signee__c> toInsert = new List<Signee__c>();
    for (Id personId : desired) {
      if (!have.contains(personId)) {
        toInsert.add(
          new Signee__c(Required_Document__c = docId, Account__c = personId)
        );
      }
    }
    Set<Id> toRemove = new Set<Id>(have);
    toRemove.removeAll(desired);

    if (!toInsert.isEmpty()) {
      insert toInsert;
    }
    if (!toRemove.isEmpty()) {
      delete [
        SELECT Id
        FROM Signee__c
        WHERE Required_Document__c = :docId AND Account__c IN :toRemove
      ];
    }
  }

  private static void deleteDocs(Set<Id> docIds) {
    if (docIds.isEmpty()) {
      return;
    }
    List<Signee__c> signees = [
      SELECT Id
      FROM Signee__c
      WHERE Required_Document__c IN :docIds
    ];
    List<Envelope_Content__c> links = [
      SELECT Id
      FROM Envelope_Content__c
      WHERE Required_Document__c IN :docIds
    ];
    if (!signees.isEmpty()) {
      delete signees;
    }
    if (!links.isEmpty()) {
      delete links;
    }
    delete [SELECT Id FROM Required_Documents__c WHERE Id IN :docIds];
  }

  private static Boolean rolesContain(String roles, String role) {
    if (String.isBlank(roles)) {
      return false;
    }
    for (String value : roles.split(';')) {
      if (value.trim() == role) {
        return true;
      }
    }
    return false;
  }
}