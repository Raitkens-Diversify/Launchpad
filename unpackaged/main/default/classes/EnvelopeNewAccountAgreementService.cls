public with sharing class EnvelopeNewAccountAgreementService {
  // The Financial_Account_Role__c roles whose holders are the owners a New Account Agreement applies
  // to. Matches EnvelopeHouseholdMemberController.SIGNING_ACCOUNT_ROLES.
  private static final Set<String> OWNER_ROLES = new Set<String>{
    'Primary Owner',
    'Joint Owner'
  };

  // A New Account Agreement is required for a BD account (either the Account or DPI section — both are
  // Financial_Account__c records).
  private static final String BD = 'BD';

  // Individual (person) owners share a plain "New Account Agreement", up to two signers per form;
  // entity owners' forms carry the entity name in front of this suffix.
  private static final String INDIVIDUAL_DOC_NAME = 'New Account Agreement';
  private static final String SUFFIX = ' - New Account Agreement';
  private static final Integer SIGNERS_PER_INDIVIDUAL_FORM = 2;

  // The fiduciary role that signs an entity owner's agreement. The business "Authorized Signer" and
  // the retirement plan "Authorized Individual" are both held as the existing 'Authorized Person'
  // relationship role (the value the wizard stores); a trust is signed by its Trustees.
  private static final Map<String, String> FIDUCIARY_ROLE_BY_RECORD_TYPE = new Map<String, String>{
    'Business' => 'Authorized Person',
    'Trust' => 'Trustee',
    'Retirement_Plan' => 'Authorized Person'
  };

  // Brings an envelope's New Account Agreements into line with its BD accounts and their owners.
  // Every owner (primary or joint) of a BD_or_RIA__c = 'BD' account needs one; there is no
  // signed-date guard. Individual owners are pooled across the envelope, up to two per form (each a
  // plain "New Account Agreement"). An entity owner (business / trust / retirement plan) gets a
  // single "<Entity> - New Account Agreement" signed by all its Authorized Persons (business,
  // retirement plan) or Trustees (trust) — or, until any exist, no signee, so it reads "To be
  // assigned...".
  //
  // Envelope-scoped, idempotent and reconciling: run it after any change to owners, an account's
  // BD/RIA flag, an entity's related parties, or an account removal. A form already handed to
  // DocuSign (DocuSign_Envelope__c set) is never removed or altered.
  public static void reconcile(Id envelopeId) {
    if (envelopeId == null) {
      return;
    }

    Map<Id, Account> owners = bdOwners(envelopeId);
    List<Id> individualOwnerIds = new List<Id>();
    Map<Id, Account> entityOwners = new Map<Id, Account>();
    for (Account owner : owners.values()) {
      if (owner.RecordType.DeveloperName == 'PersonAccount') {
        individualOwnerIds.add(owner.Id);
      } else if (
        FIDUCIARY_ROLE_BY_RECORD_TYPE.containsKey(owner.RecordType.DeveloperName)
      ) {
        entityOwners.put(owner.Id, owner);
      }
    }

    List<Required_Documents__c> existing = agreementDocsInEnvelope(envelopeId);
    Map<Id, Set<Id>> signeesByDoc = signeesByDoc(existing);

    reconcileIndividualForms(
      envelopeId,
      individualOwnerIds,
      existing,
      signeesByDoc
    );
    reconcileEntityForms(envelopeId, entityOwners, existing, signeesByDoc);
  }

  // ------------------------------------------------------------------------
  // Individuals — pooled, two per form (identical rule to the IMA pool)
  // ------------------------------------------------------------------------

  private static void reconcileIndividualForms(
    Id envelopeId,
    List<Id> individualOwnerIds,
    List<Required_Documents__c> existing,
    Map<Id, Set<Id>> signeesByDoc
  ) {
    Set<Id> sentSigners = new Set<Id>();
    List<Required_Documents__c> reusableForms = new List<Required_Documents__c>();
    for (Required_Documents__c doc : existing) {
      if (doc.Name != INDIVIDUAL_DOC_NAME) {
        continue;
      }
      if (doc.DocuSign_Envelope__c != null) {
        Set<Id> signers = signeesByDoc.get(doc.Id);
        if (signers != null) {
          sentSigners.addAll(signers);
        }
      } else {
        reusableForms.add(doc);
      }
    }

    List<Id> remaining = new List<Id>();
    for (Id ownerId : new Set<Id>(individualOwnerIds)) {
      if (!sentSigners.contains(ownerId)) {
        remaining.add(ownerId);
      }
    }
    remaining.sort();

    List<List<Id>> desiredPairs = new List<List<Id>>();
    List<Id> current = new List<Id>();
    for (Id ownerId : remaining) {
      current.add(ownerId);
      if (current.size() == SIGNERS_PER_INDIVIDUAL_FORM) {
        desiredPairs.add(current);
        current = new List<Id>();
      }
    }
    if (!current.isEmpty()) {
      desiredPairs.add(current);
    }

    List<String> desiredKeys = new List<String>();
    for (List<Id> pair : desiredPairs) {
      desiredKeys.add(signerKey(new Set<Id>(pair)));
    }
    desiredKeys.sort();

    List<String> existingKeys = new List<String>();
    for (Required_Documents__c doc : reusableForms) {
      Set<Id> signers = signeesByDoc.get(doc.Id);
      existingKeys.add(signerKey(signers == null ? new Set<Id>() : signers));
    }
    existingKeys.sort();

    if (String.join(desiredKeys, ';') == String.join(existingKeys, ';')) {
      return;
    }

    Set<Id> docIdsToDelete = new Set<Id>();
    for (Required_Documents__c doc : reusableForms) {
      docIdsToDelete.add(doc.Id);
    }
    deleteDocs(docIdsToDelete);

    for (List<Id> pair : desiredPairs) {
      createForm(envelopeId, INDIVIDUAL_DOC_NAME, new Set<Id>(pair));
    }
  }

  // ------------------------------------------------------------------------
  // Entities — one form per entity, signed by all its role-holders (or none = "To be assigned...")
  // ------------------------------------------------------------------------

  private static void reconcileEntityForms(
    Id envelopeId,
    Map<Id, Account> entityOwners,
    List<Required_Documents__c> existing,
    Map<Id, Set<Id>> signeesByDoc
  ) {
    // Desired: one document per entity (keyed by its name), signed by all of that entity's
    // role-holders. Two entities that share a name collapse onto one document, which the wizard's
    // unique nicknames make a non-issue.
    Map<String, Set<Id>> desiredByName = new Map<String, Set<Id>>();
    if (!entityOwners.isEmpty()) {
      Map<Id, Set<Id>> partiesByEntity = fiduciaryPartiesByEntity(entityOwners);
      for (Id entityId : entityOwners.keySet()) {
        String docName = entityOwners.get(entityId).Name + SUFFIX;
        Set<Id> parties = partiesByEntity.get(entityId);
        if (!desiredByName.containsKey(docName)) {
          desiredByName.put(docName, new Set<Id>());
        }
        if (parties != null) {
          desiredByName.get(docName).addAll(parties);
        }
      }
    }

    // Existing entity agreements grouped by name.
    Map<String, List<Required_Documents__c>> existingByName = new Map<String, List<Required_Documents__c>>();
    for (Required_Documents__c doc : existing) {
      if (doc.Name == INDIVIDUAL_DOC_NAME || !doc.Name.endsWith(SUFFIX)) {
        continue;
      }
      if (!existingByName.containsKey(doc.Name)) {
        existingByName.put(doc.Name, new List<Required_Documents__c>());
      }
      existingByName.get(doc.Name).add(doc);
    }

    Set<Id> docIdsToDelete = new Set<Id>();

    // Ensure each desired entity has exactly one live agreement with the right signees.
    for (String docName : desiredByName.keySet()) {
      Set<Id> desiredSigners = desiredByName.get(docName);
      List<Required_Documents__c> docs = existingByName.get(docName);

      Required_Documents__c target = null;
      Boolean hasSent = false;
      if (docs != null) {
        for (Required_Documents__c doc : docs) {
          if (doc.DocuSign_Envelope__c != null) {
            hasSent = true;
          } else if (target == null) {
            target = doc;
          } else {
            // A duplicate non-sent agreement for the same entity — drop it.
            docIdsToDelete.add(doc.Id);
          }
        }
      }

      if (target != null) {
        reconcileDocSignees(
          target.Id,
          desiredSigners,
          signeesByDoc.get(target.Id)
        );
      } else if (!hasSent) {
        // No live or in-flight agreement yet — create one (signee-less until parties exist).
        createForm(envelopeId, docName, desiredSigners);
      }
    }

    // Remove agreements for entities that are no longer BD owners (non-sent only).
    for (String docName : existingByName.keySet()) {
      if (desiredByName.containsKey(docName)) {
        continue;
      }
      for (Required_Documents__c doc : existingByName.get(docName)) {
        if (doc.DocuSign_Envelope__c == null) {
          docIdsToDelete.add(doc.Id);
        }
      }
    }

    deleteDocs(docIdsToDelete);
  }

  // Adds the signees an entity agreement is missing and removes the ones it should no longer carry,
  // leaving it matching the entity's current role-holders exactly.
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

  // ------------------------------------------------------------------------
  // Queries
  // ------------------------------------------------------------------------

  // The owners (primary + joint) of the envelope's BD accounts, by owner Account, with the record
  // type and name the reconcile needs. No signed-date guard — every BD owner needs an agreement.
  private static Map<Id, Account> bdOwners(Id envelopeId) {
    Set<Id> accountIds = new Set<Id>();
    for (Envelope_Content__c ec : [
      SELECT Wizard_Financial_Account__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Wizard_Financial_Account__c != NULL
    ]) {
      accountIds.add(ec.Wizard_Financial_Account__c);
    }
    Map<Id, Account> ownersById = new Map<Id, Account>();
    if (accountIds.isEmpty()) {
      return ownersById;
    }

    Set<Id> bdIds = new Set<Id>();
    for (Financial_Account__c fa : [
      SELECT Id
      FROM Financial_Account__c
      WHERE Id IN :accountIds AND BD_or_RIA__c = :BD
    ]) {
      bdIds.add(fa.Id);
    }
    if (bdIds.isEmpty()) {
      return ownersById;
    }

    Set<Id> ownerIds = new Set<Id>();
    for (Financial_Account_Role__c role : [
      SELECT Account__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c IN :bdIds
        AND Role__c IN :OWNER_ROLES
        AND Account__c != NULL
    ]) {
      ownerIds.add(role.Account__c);
    }
    if (ownerIds.isEmpty()) {
      return ownersById;
    }

    for (Account owner : [
      SELECT Id, Name, RecordType.DeveloperName
      FROM Account
      WHERE Id IN :ownerIds
    ]) {
      ownersById.put(owner.Id, owner);
    }
    return ownersById;
  }

  private static Map<Id, Set<Id>> fiduciaryPartiesByEntity(
    Map<Id, Account> entityOwners
  ) {
    Map<Id, Set<Id>> partiesByEntity = new Map<Id, Set<Id>>();
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

  private static List<Required_Documents__c> agreementDocsInEnvelope(
    Id envelopeId
  ) {
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
    String likeSuffix = '%' + SUFFIX;
    return [
      SELECT Id, Name, DocuSign_Envelope__c
      FROM Required_Documents__c
      WHERE
        Id IN :docIds
        AND (Name = :INDIVIDUAL_DOC_NAME OR Name LIKE :likeSuffix)
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

  private static void createForm(Id envelopeId, String name, Set<Id> signerIds) {
    Required_Documents__c doc = new Required_Documents__c(Name = name);
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

  private static String signerKey(Set<Id> signerIds) {
    List<Id> ids = new List<Id>(signerIds);
    ids.sort();
    return String.join(ids, ',');
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