public with sharing class EnvelopeAccountAddendumService {
  // The Financial_Account_Role__c roles whose holders are the primary and joint owners an addendum
  // applies to. Matches EnvelopeHouseholdMemberController.SIGNING_ACCOUNT_ROLES.
  private static final Set<String> OWNER_ROLES = new Set<String>{
    'Primary Owner',
    'Joint Owner'
  };

  // Only an RIA account carries a managed-account-platform addendum.
  private static final String RIA = 'RIA';

  // One platform's addendum: the owner Account field whose null value means that owner still owes a
  // signature, and the suffix the document's name carries. Keyed by Managed_Account_Platform__c
  // value; several values share one addendum (a plain platform and its Wrap variant).
  //
  // 'AF2' has no Managed_Account_Platform__c picklist value yet, so its rule cannot fire until one is
  // added; it is kept here so the behavior is in place the moment the value exists.
  private class AddendumSpec {
    String signedDateField;
    String nameSuffix;
    AddendumSpec(String signedDateField, String nameSuffix) {
      this.signedDateField = signedDateField;
      this.nameSuffix = nameSuffix;
    }
  }

  private static final Map<String, AddendumSpec> SPEC_BY_PLATFORM = new Map<String, AddendumSpec>{
    'DMS' => new AddendumSpec('DMS_Addendum_Signed_Date__c', ' - DMS Addendum'),
    'DMS (Wrap)' => new AddendumSpec('DMS_Addendum_Signed_Date__c', ' - DMS Addendum'),
    'AMS' => new AddendumSpec('AMS_Addendum_Signed_Date__c', ' - AMS Addendum'),
    'AMS (Wrap)' => new AddendumSpec('AMS_Addendum_Signed_Date__c', ' - AMS Addendum'),
    'OMS' => new AddendumSpec('OMS_Addendum_Signed_Date__c', ' - OMS Addendum'),
    'AF2' => new AddendumSpec(
      'American_Funds_F2_Addendum_Signed_Date__c',
      ' - American Funds F2 Addendum'
    )
  };

  // Every addendum suffix, so an account's other required documents (its account-opening doc) can be
  // told apart from an addendum by name: refreshAccountSignees manages those, this service owns
  // these, and the two must not fight over the same document's signees.
  public static Set<String> addendumSuffixes() {
    Set<String> suffixes = new Set<String>();
    for (AddendumSpec spec : SPEC_BY_PLATFORM.values()) {
      suffixes.add(spec.nameSuffix);
    }
    return suffixes;
  }

  // Brings the account's managed-account-platform addendum into line with its current platform and
  // owners. An RIA account on a platform with an addendum gets one — named from the account,
  // hung off the account, linked to the envelope — while any owner (primary or joint) still has a
  // null signed-date for that platform; the signees are exactly those owners. When the platform
  // changes, the stale addendum is removed and the new one created; when every owner has signed, or
  // the account stops being an RIA managed-platform account, the addendum is removed. An addendum
  // already handed to DocuSign (DocuSign_Envelope__c set) is never removed — it is in flight.
  //
  // Called after the ownership save (saveAccountRoles) and after the account-field save
  // (saveAccountInfo), the two inputs it depends on, so it is written to be run repeatedly.
  public static void reconcile(Id financialAccountId, Id envelopeId) {
    if (financialAccountId == null) {
      return;
    }

    List<Financial_Account__c> accounts = [
      SELECT Id, Name, BD_or_RIA__c, Managed_Account_Platform__c
      FROM Financial_Account__c
      WHERE Id = :financialAccountId
    ];
    if (accounts.isEmpty()) {
      return;
    }
    Financial_Account__c account = accounts[0];

    AddendumSpec spec = account.BD_or_RIA__c == RIA
      ? SPEC_BY_PLATFORM.get(account.Managed_Account_Platform__c)
      : null;

    // The account's existing addendum documents, told apart from its other required documents by
    // name. At most one matches the current platform; a platform change can leave a stale one, which
    // is removed below.
    Set<String> suffixes = addendumSuffixes();
    List<Required_Documents__c> existingAddenda = new List<Required_Documents__c>();
    for (Required_Documents__c doc : [
      SELECT Id, Name, DocuSign_Envelope__c
      FROM Required_Documents__c
      WHERE Financial_Account__c = :financialAccountId
    ]) {
      if (doc.Name != null && endsWithAny(doc.Name, suffixes)) {
        existingAddenda.add(doc);
      }
    }

    // The owners (primary + joint) of this account, each carrying every addendum signed-date field
    // so whichever the current platform needs can be read without a dynamic query.
    Map<Id, Account> ownersById = ownerAccounts(financialAccountId);

    // Who still owes a signature for the current platform. Empty when the account is not an RIA
    // managed-platform account, or every owner has already signed.
    Set<Id> neededSigners = new Set<Id>();
    if (spec != null) {
      for (Account owner : ownersById.values()) {
        if (owner.get(spec.signedDateField) == null) {
          neededSigners.add(owner.Id);
        }
      }
    }
    Boolean wantDoc = spec != null && !neededSigners.isEmpty();

    // Remove any addendum that should no longer exist: a stale platform's, or the current platform's
    // once no owner still needs it. One already sent to DocuSign is left in place.
    List<Required_Documents__c> toDeleteDocs = new List<Required_Documents__c>();
    Required_Documents__c currentDoc = null;
    for (Required_Documents__c doc : existingAddenda) {
      Boolean isCurrent = wantDoc && doc.Name.endsWith(spec.nameSuffix);
      if (isCurrent && currentDoc == null) {
        currentDoc = doc;
      } else if (doc.DocuSign_Envelope__c == null) {
        toDeleteDocs.add(doc);
      }
    }
    if (!toDeleteDocs.isEmpty()) {
      deleteDocsWithChildren(toDeleteDocs);
    }

    if (!wantDoc) {
      return;
    }

    // Create the addendum if it does not exist yet; either way make sure it is linked to the envelope.
    if (currentDoc == null) {
      currentDoc = new Required_Documents__c(
        Name = account.Name + spec.nameSuffix,
        Financial_Account__c = financialAccountId
      );
      insert currentDoc;
    }
    linkDocToEnvelope(currentDoc.Id, envelopeId);

    // The signees are exactly the owners that still owe a signature: add the missing ones, and drop
    // any that have since signed or are no longer an owner.
    reconcileSignees(currentDoc.Id, neededSigners);
  }

  // The primary and joint owners of the account, each loaded with every addendum signed-date field.
  private static Map<Id, Account> ownerAccounts(Id financialAccountId) {
    Set<Id> ownerIds = new Set<Id>();
    for (Financial_Account_Role__c role : [
      SELECT Account__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c = :financialAccountId
        AND Role__c IN :OWNER_ROLES
        AND Account__c != NULL
    ]) {
      ownerIds.add(role.Account__c);
    }
    Map<Id, Account> ownersById = new Map<Id, Account>();
    if (ownerIds.isEmpty()) {
      return ownersById;
    }
    for (Account owner : [
      SELECT
        Id,
        DMS_Addendum_Signed_Date__c,
        AMS_Addendum_Signed_Date__c,
        OMS_Addendum_Signed_Date__c,
        American_Funds_F2_Addendum_Signed_Date__c
      FROM Account
      WHERE Id IN :ownerIds
    ]) {
      ownersById.put(owner.Id, owner);
    }
    return ownersById;
  }

  // Reconciles a document's signees to exactly the given owners, inserting the missing and deleting
  // the rest — so an owner who has signed since the last run, or is no longer on the account, stops
  // being asked to sign.
  private static void reconcileSignees(Id docId, Set<Id> ownerIds) {
    List<Signee__c> toDelete = new List<Signee__c>();
    Set<Id> alreadySigning = new Set<Id>();
    for (Signee__c signee : [
      SELECT Id, Account__c
      FROM Signee__c
      WHERE Required_Document__c = :docId
    ]) {
      if (signee.Account__c != null && ownerIds.contains(signee.Account__c)) {
        alreadySigning.add(signee.Account__c);
      } else {
        toDelete.add(signee);
      }
    }

    List<Signee__c> toInsert = new List<Signee__c>();
    for (Id ownerId : ownerIds) {
      if (!alreadySigning.contains(ownerId)) {
        toInsert.add(
          new Signee__c(Required_Document__c = docId, Account__c = ownerId)
        );
      }
    }

    if (!toInsert.isEmpty()) {
      insert toInsert;
    }
    if (!toDelete.isEmpty()) {
      delete toDelete;
    }
  }

  // Links the document to the envelope unless it already is. A blank envelopeId leaves it unlinked.
  private static void linkDocToEnvelope(Id docId, Id envelopeId) {
    if (envelopeId == null || docId == null) {
      return;
    }
    List<Envelope_Content__c> existing = [
      SELECT Id
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Required_Document__c = :docId
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      insert new Envelope_Content__c(
        Envelope__c = envelopeId,
        Required_Document__c = docId
      );
    }
  }

  // Deletes the given documents along with their signees and envelope links.
  private static void deleteDocsWithChildren(List<Required_Documents__c> docs) {
    Set<Id> docIds = new Map<Id, Required_Documents__c>(docs).keySet();
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
    delete docs;
  }

  private static Boolean endsWithAny(String value, Set<String> suffixes) {
    for (String suffix : suffixes) {
      if (value.endsWith(suffix)) {
        return true;
      }
    }
    return false;
  }
}