public with sharing class EnvelopeHouseholdMemberController {
  // Maps the member type sent by the LWC to the Account RecordType DeveloperName. Keys are
  // lowercase: the incoming token is lowercased before it is looked up here.
  private static final Map<String, String> RECORD_TYPE_BY_MEMBER_TYPE = new Map<String, String>{
    'client' => 'PersonAccount',
    'business' => 'Business',
    'trust' => 'Trust',
    'retirementplan' => 'Retirement_Plan'
  };

  // The Account_Account_Relationship__c record type that carries a related party's role on the
  // entity holding it (Authorized Person, Beneficial Owner, Control Person, Trustee, Grantor on a
  // Business or Trust; Trusted Contact on a person). Relationships of any other record type belong
  // to something else.
  private static final String RELATED_PARTY_RECORD_TYPE = 'Fiduciary_Legal';

  @AuraEnabled
  public static Id saveEntity(
    Map<String, Object> acc,
    Id envelopeId,
    Id relatedAccountId
  ) {
    if (acc == null || acc.isEmpty()) {
      throw new AuraHandledException('No account data provided');
    }

    // The LWC sends the member type ('client' | 'business' | 'trust') under the
    // 'RecordTypeId' key; we resolve it to a real RecordType Id below.
    String memberType = (String) acc.get('RecordTypeId');

    if (
      String.isBlank(memberType) ||
      !RECORD_TYPE_BY_MEMBER_TYPE.containsKey(memberType.toLowerCase())
    ) {
      throw new AuraHandledException('Invalid Record Type');
    }
    memberType = memberType.toLowerCase();

    Id recordTypeId = resolveRecordTypeId(memberType);

    // Determine if this is an insert or an update.
    Id recordId = acc.containsKey('Id') ? (Id) acc.get('Id') : null;
    Boolean isNewRecord = (recordId == null);

    Account accountRecord = (recordId != null)
      ? new Account(Id = recordId)
      : new Account();

    // Server-side backstop for the wizard's configured format rules (the client filters
    // format-invalid values out of autosave payloads before they get here).
    WizardFieldValidator.enforce('Account', acc);
    WizardFieldValidator.normalizeForStorage('Account', acc);

    // Map caller-provided fields onto the record (control keys handled separately).
    applyFields(accountRecord, acc);

    // Server-controlled values (set after the field loop so they always win).
    accountRecord.RecordTypeId = recordTypeId;
    accountRecord.put('BillingCountryCode', 'US');
    if (memberType == 'client') {
      accountRecord.put('PersonMailingCountryCode', 'US');
    }

    // For NEW members joining an envelope, look up the envelope's Household so we can
    // link the member to it by lookup (Household__c) and mark it a Prospect, and inherit
    // the household's Financial Advisor Team (clients only). Setting Household__c is what
    // creates the household -> member Account_Account_Relationship__c: the
    // AAR_Create_Relation_From_Household flow builds that relationship from the lookup, so
    // no AAR is inserted here.
    Envelope_Content__c householdEc = null;
    if (isNewRecord && envelopeId != null) {
      List<Envelope_Content__c> householdEcs = [
        SELECT Account__c, Account__r.Financial_Advisor_Team__c
        FROM Envelope_Content__c
        WHERE
          Envelope__c = :envelopeId
          AND Account__c != NULL
          AND Account__r.RecordType.Name = 'Household'
        LIMIT 1
      ];
      if (!householdEcs.isEmpty()) {
        householdEc = householdEcs[0];
        // Household lookup + Prospect for every member type (person, business, trust,
        // retirement plan). The flow turns Household__c into the household -> member AAR.
        accountRecord.Household__c = householdEc.Account__c;
        accountRecord.Type = 'Prospect';
        if (
          memberType == 'client' &&
          householdEc.Account__r.Financial_Advisor_Team__c != null
        ) {
          accountRecord.Financial_Advisor_Team__c = householdEc.Account__r.Financial_Advisor_Team__c;
        }
      }
    }

    //try {
      upsert accountRecord;

      // ---------------------------------------
      // Envelope Content Logic
      // ---------------------------------------
      if (envelopeId != null) {
        List<Envelope_Content__c> existingRecords = [
          SELECT Id
          FROM Envelope_Content__c
          WHERE Envelope__c = :envelopeId AND Account__c = :accountRecord.Id
          LIMIT 1
        ];

        if (existingRecords.isEmpty()) {
          insert new Envelope_Content__c(
            Envelope__c = envelopeId,
            Account__c = accountRecord.Id
          );
        }
      }

      // ---------------------------------------
      // Required Document / Signee Logic
      // Only for NEW members
      // ---------------------------------------
      if (isNewRecord) {
        // ------------------------------------------------------------------
        // Standalone Client
        // ------------------------------------------------------------------
        if (memberType == 'client' && relatedAccountId == null) {
          Required_Documents__c reqDoc = new Required_Documents__c();

          String fullName = ((accountRecord.FirstName != null
              ? accountRecord.FirstName + ' '
              : '') +
            (accountRecord.LastName != null ? accountRecord.LastName : ''))
            .trim();

          reqDoc.Name = fullName + ' - client profile';
          reqDoc.Person__c = accountRecord.Id;

          insert reqDoc;

          if (envelopeId != null) {
            insert new Envelope_Content__c(
              Envelope__c = envelopeId,
              Required_Document__c = reqDoc.Id
            );
          }

          insert new Signee__c(
            Required_Document__c = reqDoc.Id,
            Account__c = accountRecord.Id
          );
        } // ------------------------------------------------------------------
        // Business / Trust related Person
        // (Authorized Person, Beneficial Owner, Control Person,
        // Trustee, Grantor)
        // ------------------------------------------------------------------
        else if (memberType == 'client' && relatedAccountId != null) {
          Account relatedAccount = [
            SELECT Id, RecordType.DeveloperName
            FROM Account
            WHERE Id = :relatedAccountId
            LIMIT 1
          ];

          List<Required_Documents__c> docs;

          if (relatedAccount.RecordType.DeveloperName == 'Business') {
            docs = [
              SELECT Id
              FROM Required_Documents__c
              WHERE Business__c = :relatedAccountId
            ];
          } else if (relatedAccount.RecordType.DeveloperName == 'Trust') {
            docs = [
              SELECT Id
              FROM Required_Documents__c
              WHERE Trust__c = :relatedAccountId
            ];
          } else {
            docs = new List<Required_Documents__c>();
          }

          List<Signee__c> signees = new List<Signee__c>();

          for (Required_Documents__c doc : docs) {
            signees.add(
              new Signee__c(
                Required_Document__c = doc.Id,
                Account__c = accountRecord.Id
              )
            );
          }

          if (!signees.isEmpty()) {
            insert signees;
          }
        } // ------------------------------------------------------------------
        // Business
        // ------------------------------------------------------------------
        else if (memberType == 'business') {
          Required_Documents__c reqDoc = new Required_Documents__c(
            Name = accountRecord.Name + ' - Business Profile',
            Business__c = accountRecord.Id
          );

          insert reqDoc;

          if (envelopeId != null) {
            insert new Envelope_Content__c(
              Envelope__c = envelopeId,
              Required_Document__c = reqDoc.Id
            );
          }
        } // ------------------------------------------------------------------
        // Trust
        // ------------------------------------------------------------------
        else if (memberType == 'trust') {
          Required_Documents__c reqDoc = new Required_Documents__c(
            Name = accountRecord.Name + ' - Trust Profile',
            Trust__c = accountRecord.Id
          );

          insert reqDoc;

          if (envelopeId != null) {
            insert new Envelope_Content__c(
              Envelope__c = envelopeId,
              Required_Document__c = reqDoc.Id
            );
          }
        }
        // A retirement plan has no branch here on purpose: Required_Documents__c carries no lookup
        // to a plan, so it can hold no document profile for one.
      }
    /*} catch (DmlException e) {
        system.debug('DmlException Save' +e);
      throw new AuraHandledException(
        'Unable to save member: ' + e.getDmlMessage(0)
      );
    }*/
    return accountRecord.Id;
  }

  // Creates the household -> member Account_Account_Relationship__c unless one already
  // exists between the pair. Matches the dedup pattern previously used for business/trust.
  private static void linkMemberToHousehold(
    Id householdId,
    Id memberAccountId
  ) {
    List<Account_Account_Relationship__c> existingRelations = [
      SELECT Id
      FROM Account_Account_Relationship__c
      WHERE Account__c = :householdId AND Related_Account__c = :memberAccountId
      LIMIT 1
    ];
    if (existingRelations.isEmpty()) {
      insert new Account_Account_Relationship__c(
        Account__c = householdId,
        Related_Account__c = memberAccountId,
        Active__c = true
      );
    }
  }

  // Lightweight view of a household member for the envelope outline rail.
  public class MemberView {
    @AuraEnabled
    public Id id; // Member Account Id
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String typeLabel; // RecordType label (e.g. Individual, Trust, Business)
    // RecordType DeveloperName (e.g. PersonAccount, IndustriesBusiness). A stable key the
    // existing-member picker filters on, since labels can be renamed in Setup.
    @AuraEnabled
    public String recordType;
    // Custodian + last 4 of the account number from the member's most recent financial
    // account (Primary_Owner__c = member). Null when the member owns no account. A member
    // can own several accounts; only the most recent is surfaced on the row.
    @AuraEnabled
    public String custodian;
    @AuraEnabled
    public String accountLast4;
  }

  // Returns the members to display in the outline rail: every member account linked to the
  // envelope (added during the session) merged with the existing household roster (person
  // members plus related business/trust accounts), de-duplicated. The household account
  // itself is excluded. Either id may be null.
  @AuraEnabled(cacheable=true)
  public static List<MemberView> getMembers(Id envelopeId, Id householdId) {
    Set<Id> memberAccountIds = new Set<Id>();

    // Members linked to this envelope (any member account added to it).
    if (envelopeId != null) {
      for (Envelope_Content__c content : [
        SELECT Account__c
        FROM Envelope_Content__c
        WHERE Envelope__c = :envelopeId AND Account__c != NULL
      ]) {
        memberAccountIds.add(content.Account__c);
      }
    }

    // Existing household roster: every member account (person, business, trust) linked to the
    // household via Account_Account_Relationship__c.
    if (householdId != null) {
      for (Account_Account_Relationship__c relation : [
        SELECT Related_Account__c
        FROM Account_Account_Relationship__c
        WHERE
          Account__c = :householdId
          AND Active__c = TRUE
          AND Related_Account__c != NULL
      ]) {
        memberAccountIds.add(relation.Related_Account__c);
      }
      // The household is never a member of its own roster.
      memberAccountIds.remove(householdId);
    }

    return buildMemberViews(memberAccountIds);
  }

  // Returns every member account across all households in the current user's Financial Advisor
  // teams, deduplicated — the roster for the "Select existing member" picker, so an account owner
  // can be chosen no matter which household (or a brand-new one) the envelope was created against.
  // Scoped to the same households the New Envelope picker shows (EnvelopeLandingApex.getWizEnvelopes);
  // the household accounts themselves are excluded.
  @AuraEnabled(cacheable=true)
  public static List<MemberView> getAllMembers() {
    // Households the running user can see: same team scope as the New Envelope household picker.
    Set<Id> teamIds = new Set<Id>();
    for (Financial_Advisor_Team_Member__c teamMember : [
      SELECT Financial_Advisor_Team__c
      FROM Financial_Advisor_Team_Member__c
      WHERE User__c = :UserInfo.getUserId()
      WITH SECURITY_ENFORCED
    ]) {
      teamIds.add(teamMember.Financial_Advisor_Team__c);
    }
    if (teamIds.isEmpty()) {
      return new List<MemberView>();
    }

    Set<Id> householdIds = new Set<Id>();
    for (Account household : [
      SELECT Id
      FROM Account
      WHERE
        Financial_Advisor_Team__c IN :teamIds
        AND RecordType.DeveloperName = 'Household'
      WITH SECURITY_ENFORCED
    ]) {
      householdIds.add(household.Id);
    }
    if (householdIds.isEmpty()) {
      return new List<MemberView>();
    }

    // Gather every household roster into one set: every member account (person, business, trust)
    // linked via Account_Account_Relationship__c. A person in several households is de-duplicated
    // by the set.
    Set<Id> memberAccountIds = new Set<Id>();
    for (Account_Account_Relationship__c relation : [
      SELECT Related_Account__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c IN :householdIds
        AND Active__c = TRUE
        AND Related_Account__c != NULL
    ]) {
      memberAccountIds.add(relation.Related_Account__c);
    }
    // Households are never members of their own rosters.
    memberAccountIds.removeAll(householdIds);

    return buildMemberViews(memberAccountIds);
  }

  // The only member kinds this picker may ever offer as a Primary Owner: Individual, Business,
  // and Trust. Derived from RECORD_TYPE_BY_MEMBER_TYPE (excludes 'retirementplan') so the two
  // stay in lockstep rather than duplicating the developer names as separate literals.
  private static final Set<String> HOUSEHOLD_ROSTER_RECORD_TYPES = new Set<String>{
    RECORD_TYPE_BY_MEMBER_TYPE.get('client'),
    RECORD_TYPE_BY_MEMBER_TYPE.get('business'),
    RECORD_TYPE_BY_MEMBER_TYPE.get('trust')
  };

  // Returns every member account (person, business, or trust) already linked to the given
  // household's roster, and only that household — for pickers like an ISA's Primary Owner
  // "Select existing" dialog, which must offer only parties already tied to the specific
  // account/household the ISA belongs to, unlike getAllMembers()'s intentionally team-wide
  // search. Every member (person, business, trust) links via Account_Account_Relationship__c —
  // the same source getHouseholdMembersAndAccounts reads for
  // the outline rail, so this picker's roster always matches what the outline already shows,
  // including the same cross-envelope draft guard (belongsInEnvelope): an unsubmitted member
  // that belongs to a different, unrelated envelope must not leak in here either, even though it
  // is still linked to this household. Only Individual/Business/Trust record types are ever
  // offered (HOUSEHOLD_ROSTER_RECORD_TYPES) — a Retirement Plan or any other linked record type
  // is excluded, since it can't be a Primary Owner. The household itself is never offered as its
  // own member.
  //
  // Not cacheable, on purpose: a member can be added to the household mid-session, and this picker
  // must reflect that on its very next open rather than serving a stale result cached under the
  // same household+envelope key from before the member existed.
  @AuraEnabled(cacheable=false)
  public static List<MemberView> getHouseholdRoster(Id householdId, Id envelopeId) {
    if (householdId == null) {
      return new List<MemberView>();
    }

    Set<Id> existingRecordIds = new Set<Id>();
    if (envelopeId != null) {
      for (Envelope_Content__c ec : [
        SELECT Account__c
        FROM Envelope_Content__c
        WHERE Envelope__c = :envelopeId AND Account__c != NULL
      ]) {
        existingRecordIds.add(ec.Account__c);
      }
    }

    List<Account_Account_Relationship__c> accountRelations = [
      SELECT Related_Account__c, Related_Account__r.Submitted__c, Related_Account__r.RecordType.DeveloperName
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :householdId
        AND Active__c = TRUE
        AND Related_Account__c != NULL
    ];

    Set<Id> candidateAccountIds = new Set<Id>();
    for (Account_Account_Relationship__c relation : accountRelations) {
      if (relation.Related_Account__c != null) {
        candidateAccountIds.add(relation.Related_Account__c);
      }
    }

    Set<Id> linkedToAnyEnvelopeIds = new Set<Id>();
    if (!candidateAccountIds.isEmpty()) {
      for (Envelope_Content__c ec : [
        SELECT Account__c
        FROM Envelope_Content__c
        WHERE Account__c IN :candidateAccountIds
      ]) {
        if (ec.Account__c != null) {
          linkedToAnyEnvelopeIds.add(ec.Account__c);
        }
      }
    }

    Set<Id> memberAccountIds = new Set<Id>();
    for (Account_Account_Relationship__c relation : accountRelations) {
      if (!HOUSEHOLD_ROSTER_RECORD_TYPES.contains(relation.Related_Account__r.RecordType?.DeveloperName)) {
        continue;
      }
      if (!belongsInEnvelope(relation.Related_Account__c, relation.Related_Account__r.Submitted__c, existingRecordIds, linkedToAnyEnvelopeIds)) {
        continue;
      }
      memberAccountIds.add(relation.Related_Account__c);
    }
    memberAccountIds.remove(householdId);
    return buildMemberViews(memberAccountIds);
  }

  private static Boolean belongsInEnvelope(Id recordId, Boolean submitted, Set<Id> existingRecordIds, Set<Id> linkedToAnyEnvelopeIds) {
    return existingRecordIds.contains(recordId)
        || submitted == true
        || (!linkedToAnyEnvelopeIds.contains(recordId) && submitted != true);
  }

  // Builds the display views for a set of member accounts: a consistent name + type label (the
  // household record type filtered out), enriched with the custodian + last 4 of each member's
  // most recent financial account. Returns an empty list when the set is empty.
  private static List<MemberView> buildMemberViews(Set<Id> memberAccountIds) {
    if (memberAccountIds.isEmpty()) {
      return new List<MemberView>();
    }

    // Each member's most recent financial account, for the custodian + account-number
    // segment of the row. Ordered newest-first so the first row seen per owner wins.
    Map<Id, Financial_Account__c> latestAccountByOwner = new Map<Id, Financial_Account__c>();
    for (Financial_Account__c finAccount : [
      SELECT Primary_Owner__c, Custodian__c, Account_Number__c
      FROM Financial_Account__c
      WHERE Primary_Owner__c IN :memberAccountIds
      ORDER BY CreatedDate DESC
    ]) {
      if (!latestAccountByOwner.containsKey(finAccount.Primary_Owner__c)) {
        latestAccountByOwner.put(finAccount.Primary_Owner__c, finAccount);
      }
    }

    // Single uniform read so every member has a consistent name + type label, with the
    // household record type filtered out.
    List<MemberView> members = new List<MemberView>();
    for (Account account : [
      SELECT Id, Name, RecordType.Name, RecordType.DeveloperName
      FROM Account
      WHERE
        Id IN :memberAccountIds
        AND RecordType.DeveloperName != 'Household'
      ORDER BY Name
    ]) {
      MemberView member = new MemberView();
      member.id = account.Id;
      member.name = account.Name;
      member.typeLabel = account.RecordType == null
        ? null
        : account.RecordType.Name;
      member.recordType = account.RecordType == null
        ? null
        : account.RecordType.DeveloperName;

      Financial_Account__c finAccount = latestAccountByOwner.get(account.Id);
      if (finAccount != null) {
        member.custodian = finAccount.Custodian__c;
        member.accountLast4 = lastFour(finAccount.Account_Number__c);
      }
      members.add(member);
    }
    return members;
  }

  // Returns the last four characters of an account number for display, or null when blank.
  private static String lastFour(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.length() <= 4
      ? trimmed
      : trimmed.substring(trimmed.length() - 4);
  }

  // Dedup key for a Financial Account role: one record per person per role on an account. Entity
  // related parties do not use it — they hold all of a person's roles on one record (see
  // saveRelatedParties).
  private static String relatedPartyKey(Id relatedAccountId, String role) {
    return String.valueOf(relatedAccountId) + '|' + role;
  }

  // Parse the related parties the wizard sent as a JSON array (see RelatedPartyInput). A blank value is
  // an empty set rather than an error: it is how "every party removed" arrives. Malformed JSON is
  // reported, since it means the caller and this method disagree on the payload shape.
  private static List<RelatedPartyInput> parseRelatedParties(String partiesJson) {
    if (String.isBlank(partiesJson)) {
      return new List<RelatedPartyInput>();
    }
    try {
      List<RelatedPartyInput> parsed = (List<RelatedPartyInput>) JSON.deserialize(
        partiesJson,
        List<RelatedPartyInput>.class
      );
      return parsed == null ? new List<RelatedPartyInput>() : parsed;
    } catch (System.JSONException e) {
      throw new AuraHandledException(
        'Related parties could not be read: ' + e.getMessage()
      );
    }
  }

  // Parse a record id the wizard sent as a String (see RelatedPartyInput). Returns null for a blank or
  // malformed value so the caller can report it, rather than letting the cast raise a StringException.
  private static Id parseAccountId(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return (Id) value;
    } catch (System.StringException e) {
      return null;
    }
  }

  // The separator the multi-select Roles fields store their values with.
  private static final String ROLE_SEPARATOR = ';';

  // The roles held in a multi-select Roles value, in the order stored. Blank entries are dropped, so
  // a stray separator cannot produce an empty role.
  private static List<String> splitRoles(String roles) {
    List<String> values = new List<String>();
    if (String.isBlank(roles)) {
      return values;
    }
    for (String role : roles.split(ROLE_SEPARATOR)) {
      String trimmed = role == null ? null : role.trim();
      if (!String.isBlank(trimmed)) {
        values.add(trimmed);
      }
    }
    return values;
  }

  // A set of roles as a multi-select Roles value. Sorted so a record's value does not churn — and so
  // an update is only issued when the roles themselves changed — since a Set has no stable order.
  private static String joinRoles(Set<String> roles) {
    List<String> ordered = new List<String>(roles);
    ordered.sort();
    return String.join(ordered, ROLE_SEPARATOR);
  }

  // The roles on a relationship that the caller manages. Empty means the record belongs to something
  // else, which is what keeps a reconcile from touching a relationship the wizard did not create.
  private static Set<String> managedRolesOn(
    Account_Account_Relationship__c relation,
    Set<String> managed
  ) {
    Set<String> held = new Set<String>();
    for (String role : splitRoles(relation.Roles__c)) {
      if (managed.contains(role)) {
        held.add(role);
      }
    }
    return held;
  }

  // The active values of the relationship Roles picklist, which is restricted: a role outside this set
  // cannot be written. Read from Roles__c, the field the wizard writes — its value set is a copy of
  // the single-value Role__c one. Field-level values only — record-type picklist filtering is not
  // readable from Apex describe, so a value this set holds but the Fiduciary / Regulatory record type
  // excludes still fails at DML.
  private static Set<String> relatedPartyRoleValues() {
    Set<String> values = new Set<String>();
    for (
      Schema.PicklistEntry entry : Account_Account_Relationship__c.Roles__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        values.add(entry.getValue());
      }
    }
    return values;
  }

  // Resolves the relationship RecordType Id the wizard writes related parties under, throwing a
  // clear error instead of an NPE when the record type is missing from the org.
  private static Id resolveRelatedPartyRecordTypeId() {
    Schema.RecordTypeInfo info = Schema.SObjectType.Account_Account_Relationship__c
      .getRecordTypeInfosByDeveloperName()
      .get(RELATED_PARTY_RECORD_TYPE);
    if (info == null) {
      throw new AuraHandledException(
        'Relationship record type not found: ' + RELATED_PARTY_RECORD_TYPE
      );
    }
    return info.getRecordTypeId();
  }

  // Links accounts to an envelope unless they are already linked. Related parties need this so the
  // Household Outline lists them: the outline is built from the envelope's contents, not only from
  // the household roster.
  private static void linkAccountsToEnvelope(
    Id envelopeId,
    Set<Id> accountIds
  ) {
    if (envelopeId == null || accountIds == null || accountIds.isEmpty()) {
      return;
    }
    Set<Id> alreadyLinked = new Set<Id>();
    for (Envelope_Content__c content : [
      SELECT Account__c
      FROM Envelope_Content__c
      WHERE Envelope__c = :envelopeId AND Account__c IN :accountIds
    ]) {
      alreadyLinked.add(content.Account__c);
    }
    List<Envelope_Content__c> newContent = new List<Envelope_Content__c>();
    for (Id accountId : accountIds) {
      if (!alreadyLinked.contains(accountId)) {
        newContent.add(
          new Envelope_Content__c(
            Envelope__c = envelopeId,
            Account__c = accountId
          )
        );
      }
    }
    if (!newContent.isEmpty()) {
      insert newContent;
    }
  }

  // Resolves the Account RecordType Id for a validated member type, throwing a
  // clear error instead of an NPE when the record type is missing from the org.
  private static Id resolveRecordTypeId(String memberType) {
    String developerName = RECORD_TYPE_BY_MEMBER_TYPE.get(memberType);

    List<RecordType> recordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SobjectType = 'Account' AND DeveloperName = :developerName
      LIMIT 1
    ];

    if (recordTypes.isEmpty()) {
      throw new AuraHandledException(
        'Account record type not found for: ' + memberType
      );
    }
    return recordTypes[0].Id;
  }

  // Copies caller-supplied fields onto the Account, skipping control keys. Values arrive as
  // deserialized JSON, so strings are coerced to the field's real type (dates, numbers,
  // checkboxes) — without this, a Date of Birth string would silently never save. Assignment
  // failures collect and throw before DML: with the format rules enforced up front, a key that
  // still fails here is a real defect the caller must see, not debug-log noise.
  private static void applyFields(
    Account accountRecord,
    Map<String, Object> acc
  ) {
    Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
    List<String> failedKeys = new List<String>();
    for (String key : acc.keySet()) {
      if (key == 'Id' || key == 'RecordTypeId') {
        continue;
      }
      try {
        accountRecord.put(
          key,
          coerceForField(accountFields.get(key.toLowerCase()), acc.get(key))
        );
      } catch (Exception e) {
        System.debug(
          LoggingLevel.WARN,
          'saveEntity: could not set field ' + key + ': ' + e.getMessage()
        );
        failedKeys.add(key);
      }
    }
    if (!failedKeys.isEmpty()) {
      throw new AuraHandledException(
        'These fields could not be saved: ' + String.join(failedKeys, ', ')
      );
    }
  }

  // Converts a string value to the target field's Apex type. Non-string values (real booleans,
  // numbers) and unknown fields pass through untouched; a blank string means "cleared" and
  // becomes null so it can empty any field type without an assignment error.
  private static Object coerceForField(
    Schema.SObjectField field,
    Object value
  ) {
    if (field == null || !(value instanceof String)) {
      return value;
    }
    String text = (String) value;
    if (String.isBlank(text)) {
      return null;
    }
    switch on field.getDescribe().getType() {
      when DATE {
        return Date.valueOf(text);
      }
      when DATETIME {
        return (Object) Datetime.valueOfGmt(
          text.replace('T', ' ').replace('Z', '')
        );
      }
      when BOOLEAN {
        return Boolean.valueOf(text);
      }
      when DOUBLE, CURRENCY, PERCENT {
        return Decimal.valueOf(text);
      }
      when INTEGER {
        return Integer.valueOf(text);
      }
      when else {
        return value;
      }
    }
  }

  @AuraEnabled(cacheable=true)
  public static Map<String, List<PicklistOption>> getPicklistValues(
    String type
  ) {
    Map<String, List<PicklistOption>> results = new Map<String, List<PicklistOption>>();

    if (String.isBlank(type)) {
      return results;
    }

    List<String> otherFields = new List<String>{
      'Time_Horizon__c',
      'Liquidity_Needs__c',
      'Risk_Tolerance__c'
    };

    List<String> commonFields = new List<String>{
      'BillingStateCode',
      'PersonMailingStateCode'
    };

    Map<String, List<String>> typeFields = new Map<String, List<String>>{
      'client' => new List<String>{
        'Employment_Status__c',
        'Employer_State__c',
        'Employed_by_Sec_Industry_Regulator__c',
        'Officer__c',
        'Senior_Military_Governmental_Political__c',
        'Name_of_Country__c'
      },
      'business' => new List<String>{
        'Entity_Type__c',
        'Entity_Jurisdiction__c'
      },
      'trust' => new List<String>{
        'Entity_Type__c',
        'Trust_Type__c',
        'Entity_Jurisdiction__c',
        'FinServ__TimeHorizon__c',
        'FinServ__RiskTolerance__c',
        'FinServ__InvestmentObjectives__c',
        'Liquidity_Needs__c',
        'Approximate_Highest_Tax_Bracket__c'
      }
    };

    List<String> fieldsToFetch = new List<String>(commonFields);
    fieldsToFetch.addAll(otherFields);
    if (typeFields.containsKey(type)) {
      fieldsToFetch.addAll(typeFields.get(type));
    }

    Schema.SObjectType accountType = Schema.getGlobalDescribe().get('Account');
    if (accountType == null) {
      return results;
    }

    Map<String, Schema.SObjectField> fieldMap = accountType.getDescribe()
      .fields.getMap();

    for (String fieldName : fieldsToFetch) {
      String fieldKey = fieldName.toLowerCase();
      if (!fieldMap.containsKey(fieldKey)) {
        continue;
      }

      Schema.DescribeFieldResult dfr = fieldMap.get(fieldKey).getDescribe();
      if (
        dfr.getType() != Schema.DisplayType.Picklist &&
        dfr.getType() != Schema.DisplayType.MultiPicklist
      ) {
        continue;
      }

      List<PicklistOption> options = new List<PicklistOption>();
      for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
        if (entry.isActive()) {
          // Filter Entity_Type__c based on entity type (business vs trust)
          if (fieldName == 'Entity_Type__c') {
            String val = entry.getValue();
            if (type == 'business') {
              // Only include business types
              Set<String> businessTypes = new Set<String>{
                'LLC',
                'Limited Liability Company',
                'C-Corp',
                'S-Corp',
                'Partnership',
                'Sole Proprietorship',
                'Corporation',
                'Unincorporated Business'
              };
              if (businessTypes.contains(val)) {
                options.add(new PicklistOption(entry.getLabel(), val));
              }
            } else if (type == 'trust') {
              // Only include trust types
              Set<String> trustTypes = new Set<String>{
                'Revocable Trust',
                'Irrevocable Trust'
              };
              if (trustTypes.contains(val)) {
                options.add(new PicklistOption(entry.getLabel(), val));
              }
            } else {
              options.add(new PicklistOption(entry.getLabel(), val));
            }
          } else {
            options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
          }
        }
      }
      results.put(fieldName, options);
    }
    return results;
  }

  // Links a person member to the Household via Account_Account_Relationship__c. Called
  // directly by the envelopeRelatedMemberForm LWC when creating a related member;
  // primaryAccountId is the Household/Bussiness/Trust account.
  @AuraEnabled
  public static void createAccountAccountRelationship(
    String primaryAccountId,
    String relatedAccountId
  ) {
    if (String.isBlank(primaryAccountId) || String.isBlank(relatedAccountId)) {
      throw new AuraHandledException('Account Ids are required.');
    }
    linkMemberToHousehold(primaryAccountId, relatedAccountId);
  }

  // One related party the wizard holds for an entity: the person Account and the role it plays.
  //
  // Populated by JSON.deserialize from the `partiesJson` argument, not by passing this type as the
  // parameter itself: an @AuraEnabled Apex class used as a method parameter comes back from an LWC call
  // with its properties unset, so every party arrived empty and the whole save wrote nothing. Every other
  // structured input in this codebase takes Map<String, Object> or a JSON String for the same reason.
  // RelatedPartyOutput keeps its Id fields — the problem is input; return values serialize fine.
  //
  // relatedAccountId is a String so a malformed value can be reported rather than raising a
  // StringException on assignment; parseAccountId converts and validates it.
  public class RelatedPartyInput {
    @AuraEnabled
    public String relatedAccountId;
    @AuraEnabled
    public String role;
  }

  // A persisted related-party link, kept flat so the wizard can group the rows under its own
  // requirement keys (one role can serve more than one requirement).
  public class RelatedPartyOutput {
    @AuraEnabled
    public Id entityAccountId;
    @AuraEnabled
    public Id relatedAccountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String role;
  }

  // Reconciles the related parties of a single entity — a Business or Trust holding its fiduciary
  // roles, or a person holding a trusted contact. The entity is whatever `entityAccountId` names;
  // nothing here reads its record type. A person holds one relationship per entity, and every role
  // they play on it lives in that record's Roles__c multi-select — so the flat (person, role) pairs
  // in `partiesJson` are grouped by person here and joined into one value. Each party is also linked
  // to the envelope, which is what puts it on the Household Outline next to the members added
  // directly; that link is written before the reconcile so it does not depend on it.
  //
  // The scope is deliberately narrow, because this object is shared with the FSC relationship
  // feature: only the Fiduciary / Regulatory record type is considered, and only the roles in
  // `managedRoles` are added or removed. A role outside that list — one someone set through the
  // relationship modal, say — is carried through untouched, and a relationship is deleted only once
  // nothing is left on it. Relationships of another record type are never even read.
  //
  // Roles are stored only in Roles__c. The single-value Role__c field is deliberately not written:
  // it cannot express more than one role, nothing else in the org maintains it (the relationship
  // modal writes Roles__c alone), and keeping both in step by hand is what let them drift apart.
  //
  // The parties arrive as a JSON array rather than a typed list: see RelatedPartyInput. A blank value
  // is an empty set, which is a real case — the user removed the last party, and the reconcile below
  // still has to strip the roles that are no longer held.
  //
  // Returns the roles that were rejected because the restricted Roles picklist has no such value,
  // distinct and in the order first seen; empty when every party was written. A role the caller and the
  // picklist disagree on is a wiring problem rather than a user one, and it is reported as a return
  // value instead of an exception so it cannot take the parties in the other roles down with it — the
  // same DML carries them all, and a throw would roll back a save that is otherwise correct.
  @AuraEnabled
  public static List<String> saveRelatedParties(
    Id entityAccountId,
    List<String> managedRoles,
    String partiesJson,
    Id envelopeId
  ) {
    if (entityAccountId == null) {
      throw new AuraHandledException(
        'An entity account is required to save related parties.'
      );
    }
    List<RelatedPartyInput> parties = parseRelatedParties(partiesJson);
    Id recordTypeId = resolveRelatedPartyRecordTypeId();

    // person -> every role the payload gives them on this entity. A repeated (person, role) pair
    // collapses into the set, and a person named in several roles ends up with one entry holding all
    // of them — which is exactly one relationship record.
    Map<Id, Set<String>> desiredByPerson = new Map<Id, Set<String>>();
    Set<Id> partyAccountIds = new Set<Id>();
    List<String> unusableParties = new List<String>();
    List<String> rejectedRoles = new List<String>();
    Set<String> roleValues = relatedPartyRoleValues();
    for (Integer i = 0; i < parties.size(); i++) {
      RelatedPartyInput party = parties[i];
      // A null party leaves partyAccountId null, so role is never read for one.
      Id partyAccountId = party == null
        ? null
        : parseAccountId(party.relatedAccountId);
      if (partyAccountId == null || String.isBlank(party.role)) {
        // Recorded rather than skipped: a party the wizard holds but cannot link is a data integrity
        // problem, and dropping it quietly turns a total failure into a silent success. Reported below,
        // before anything is written, so the save is all-or-nothing. The position and what did arrive
        // are named so a payload problem diagnoses itself.
        unusableParties.add(
          'index ' +
            String.valueOf(i) +
            ' (account: ' +
            (party == null ? 'none' : String.valueOf(party.relatedAccountId)) +
            ', role: ' +
            (party == null ? 'none' : String.valueOf(party.role)) +
            ')'
        );
        continue;
      }
      partyAccountIds.add(partyAccountId);
      if (!roleValues.contains(party.role)) {
        // The restricted picklist has no such value, so this role cannot be written whatever else the
        // payload holds. Left out of the DML rather than allowed to fail it, so the roles that do
        // exist are still saved, and the value is reported to the caller instead. The party is already
        // in partyAccountIds, so it keeps its envelope link and its outline row — the same treatment a
        // role the wizard could not resolve at all gets.
        if (!rejectedRoles.contains(party.role)) {
          rejectedRoles.add(party.role);
        }
        continue;
      }
      if (!desiredByPerson.containsKey(partyAccountId)) {
        desiredByPerson.put(partyAccountId, new Set<String>());
      }
      desiredByPerson.get(partyAccountId).add(party.role);
    }
    if (!unusableParties.isEmpty()) {
      throw new AuraHandledException(
        'Related parties could not be saved. Each one needs an account and a role, but ' +
          String.valueOf(unusableParties.size()) +
          ' did not: ' +
          String.join(unusableParties, '; ')
      );
    }

    // Written before the role reconcile below so that a party the wizard holds always reaches the
    // Household Outline, which is built from the envelope's contents. The reconcile is the part
    // that can come to nothing — an empty `managedRoles` returns just below, and a role that
    // resolved to nothing leaves the party out of the payload — and neither should cost the party
    // its outline row. A relationship DML failure further down still rolls this link back with the
    // rest of the transaction; the ordering removes the silent no-ops, it does not make the link
    // outlive an error.
    try {
      linkAccountsToEnvelope(envelopeId, partyAccountIds);
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Unable to link related parties to the envelope: ' + e.getDmlMessage(0)
      );
    }

    // Nothing for the wizard to reconcile: the parties are linked above, and every relationship on
    // this entity belongs to a role it does not own.
    if (managedRoles == null || managedRoles.isEmpty()) {
      return rejectedRoles;
    }
    Set<String> managed = new Set<String>(managedRoles);

    // Every relationship this entity carries in the wizard's record type, whatever roles it holds.
    // Neither the roles nor Active__c narrow the query, deliberately:
    //   - a person's record has to be found by person, so the roles it currently holds can be read
    //     and rewritten in place rather than a second record being created alongside it;
    //   - an inactive record would otherwise be invisible here but also excluded by
    //     getRelatedParties, so its party would read as missing while every save left it alone.
    //     Reactivated below when the party is still held.
    // Reciprocal_Role__c is read only to recognise a record the relationship map owns, which must
    // survive even once none of the wizard's roles are left on it.
    Map<Id, List<Account_Account_Relationship__c>> existingByPerson = new Map<Id, List<Account_Account_Relationship__c>>();
    for (Account_Account_Relationship__c existing : [
      SELECT Id, Related_Account__c, Roles__c, Active__c, Reciprocal_Role__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c = :entityAccountId
        AND RecordTypeId = :recordTypeId
        AND Related_Account__c != NULL
    ]) {
      if (!existingByPerson.containsKey(existing.Related_Account__c)) {
        existingByPerson.put(
          existing.Related_Account__c,
          new List<Account_Account_Relationship__c>()
        );
      }
      existingByPerson.get(existing.Related_Account__c).add(existing);
    }

    List<Account_Account_Relationship__c> toInsert = new List<Account_Account_Relationship__c>();
    List<Account_Account_Relationship__c> toUpdate = new List<Account_Account_Relationship__c>();
    List<Account_Account_Relationship__c> toDelete = new List<Account_Account_Relationship__c>();
    // The parties this entity no longer holds in any role. Collected here rather than diffed from the
    // payload so a party kept by an unmanaged role, or named again under a different role, is never
    // counted as dropped. Taken out of the envelope after the DML below.
    Set<Id> droppedParties = new Set<Id>();

    for (Id personId : existingByPerson.keySet()) {
      List<Account_Account_Relationship__c> held = existingByPerson.get(personId);
      Set<String> desired = desiredByPerson.get(personId);

      // Which of this person's records the wizard has a claim on. A record carrying none of the
      // managed roles was written by something else — the relationship map, or a role set through
      // the relationship modal — and is left exactly as it is unless the payload names this person.
      Account_Account_Relationship__c target = null;
      for (Account_Account_Relationship__c relation : held) {
        if (!managedRolesOn(relation, managed).isEmpty()) {
          target = relation;
          break;
        }
      }
      if (target == null) {
        if (desired == null) {
          // Nothing of the wizard's here and nothing being added: not ours to touch.
          continue;
        }
        // The pair already has a record, so the roles join it rather than starting a second one.
        target = held[0];
      }

      // Earlier builds stored one record per role, and nothing enforces uniqueness on the pair. The
      // managed roles are stripped from every record except the target and rewritten onto it below,
      // which collapses those duplicates without needing a migration. A record is only deleted once
      // it carries nothing at all.
      for (Account_Account_Relationship__c relation : held) {
        if (relation.Id == target.Id) {
          continue;
        }
        if (managedRolesOn(relation, managed).isEmpty()) {
          // Carries none of the wizard's roles — leave it alone.
          continue;
        }
        Set<String> remainder = new Set<String>();
        for (String role : splitRoles(relation.Roles__c)) {
          if (!managed.contains(role)) {
            remainder.add(role);
          }
        }
        if (remainder.isEmpty()) {
          if (relation.Reciprocal_Role__c == null) {
            toDelete.add(relation);
          } else {
            relation.Roles__c = null;
            toUpdate.add(relation);
          }
        } else {
          relation.Roles__c = joinRoles(remainder);
          toUpdate.add(relation);
        }
      }

      // The roles the target carries that the wizard does not manage stay on it — they belong to
      // whoever set them. Only the managed ones are replaced by what the payload asks for.
      Set<String> finalRoles = new Set<String>();
      for (String role : splitRoles(target.Roles__c)) {
        if (!managed.contains(role)) {
          finalRoles.add(role);
        }
      }
      if (desired != null) {
        finalRoles.addAll(desired);
      }

      if (finalRoles.isEmpty()) {
        // The wizard held every role on this record and now holds none. Nothing is left to carry,
        // unless the relationship map owns the record — then it keeps the record and loses only the
        // roles.
        if (target.Reciprocal_Role__c == null) {
          toDelete.add(target);
        } else {
          target.Roles__c = null;
          toUpdate.add(target);
        }
        droppedParties.add(personId);
        continue;
      }
      String joined = joinRoles(finalRoles);
      Boolean shouldActivate = desired != null && target.Active__c != true;
      if (target.Roles__c != joined || shouldActivate) {
        target.Roles__c = joined;
        if (shouldActivate) {
          target.Active__c = true;
        }
        toUpdate.add(target);
      }
    }

    for (Id personId : desiredByPerson.keySet()) {
      if (existingByPerson.containsKey(personId)) {
        continue;
      }
      toInsert.add(
        new Account_Account_Relationship__c(
          Account__c = entityAccountId,
          Related_Account__c = personId,
          Roles__c = joinRoles(desiredByPerson.get(personId)),
          RecordTypeId = recordTypeId,
          Active__c = true
        )
      );
    }

    try {
      if (!toInsert.isEmpty()) {
        insert toInsert;
      }
      if (!toUpdate.isEmpty()) {
        update toUpdate;
      }
      if (!toDelete.isEmpty()) {
        delete toDelete;
      }
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Unable to save related parties: ' + e.getDmlMessage(0)
      );
    }

    // A party this entity no longer holds also leaves the envelope, so the Household Outline — which
    // is built from the envelope's contents — stops showing it. Run after the DML above so the record
    // is judged on the relationships that remain. A party still serving this envelope keeps its link,
    // and the record itself is deleted only when nothing anywhere references it.
    WizardEnvelopeStateService.unlinkDroppedPartiesAndDeleteIfUnused(
      droppedParties,
      envelopeId
    );
    return rejectedRoles;
  }

  // The related parties currently linked to the given entities, one row per (person, role). A person
  // holds all their roles on an entity in a single relationship's Roles__c multi-select, so that
  // value is split here and each role becomes its own row: the wizard maps a role back to the
  // requirement it belongs to, and keeping the output flat lets it do that without knowing how the
  // roles are stored.
  @AuraEnabled(cacheable=false)
  public static List<RelatedPartyOutput> getRelatedParties(
    List<Id> entityAccountIds
  ) {
    List<RelatedPartyOutput> parties = new List<RelatedPartyOutput>();
    if (entityAccountIds == null || entityAccountIds.isEmpty()) {
      return parties;
    }
    for (Account_Account_Relationship__c relation : [
      SELECT Account__c, Related_Account__c, Related_Account__r.Name, Roles__c
      FROM Account_Account_Relationship__c
      WHERE
        Account__c IN :entityAccountIds
        AND RecordType.DeveloperName = :RELATED_PARTY_RECORD_TYPE
        AND Active__c = TRUE
        AND Related_Account__c != NULL
        AND Roles__c != NULL
      ORDER BY Related_Account__r.Name
    ]) {
      for (String role : splitRoles(relation.Roles__c)) {
        RelatedPartyOutput party = new RelatedPartyOutput();
        party.entityAccountId = relation.Account__c;
        party.relatedAccountId = relation.Related_Account__c;
        party.name = relation.Related_Account__r.Name;
        party.role = role;
        parties.add(party);
      }
    }
    return parties;
  }

  // The Financial_Account_Role__c roles whose holders sign the account's paperwork. Beneficiaries and
  // the roles the wizard does not yet own are deliberately absent — they are recorded on the account
  // but do not become Signee__c rows.
  private static final Set<String> SIGNING_ACCOUNT_ROLES = new Set<String>{
    'Primary Owner',
    'Joint Owner'
  };

  // One role the wizard holds on a Financial Account: the person Account and the role it plays.
  // Deserialized from the `rolesJson` argument rather than passed as a typed parameter, for the same
  // reason as RelatedPartyInput above — an @AuraEnabled class used as a method parameter arrives from
  // an LWC call with its properties unset.
  public class AccountRoleInput {
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public String role;
  }

  // A persisted Financial Account role, kept flat so the wizard can group the rows under its own
  // requirement slots, mirroring RelatedPartyOutput.
  public class AccountRoleOutput {
    @AuraEnabled
    public Id financialAccountId;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String role;
  }

  // saveRelatedParties' counterpart for a Financial Account: reconciles the account's owners and
  // beneficiaries into Financial_Account_Role__c. Every (person, role) pair in `rolesJson` ends up
  // linked, and any row the account still carries in one of `managedRoles` that is no longer sent is
  // removed — so a role created outside the wizard, or one the wizard does not own, is never touched.
  // Each party is linked to the envelope first, which is what puts it on the Household Outline, so a
  // party keeps its outline row even when the reconcile below comes to nothing.
  //
  // `roleLimitsJson` maps a role to the most rows it may hold ({"Joint Owner": 5}); a role absent from
  // the map is unbounded. The ceilings come from the client because the registration rules live there
  // and duplicating them here would let the two drift. This is a backstop against a client path that
  // forgets to check rather than a security boundary — the Review Missing Items screen has no ceiling
  // of its own, and without this a joint account could be pushed past its limit from that screen.
  // Minimums are deliberately NOT enforced: an account is saved continuously while its owners are
  // still being added, so a below-minimum set is a normal intermediate state. Minimums gate submit,
  // which the client already owns.
  //
  // Returns the roles rejected because the restricted picklist has no such value, distinct and in the
  // order first seen — reported rather than thrown so one bad role cannot take the others down with it.
  @AuraEnabled
  public static List<String> saveAccountRoles(
    Id financialAccountId,
    List<String> managedRoles,
    String rolesJson,
    String roleLimitsJson,
    Id envelopeId
  ) {
    if (financialAccountId == null) {
      throw new AuraHandledException(
        'A financial account is required to save its related parties.'
      );
    }
    List<AccountRoleInput> roles = parseAccountRoles(rolesJson);

    // Keyed so a repeated (person, role) pair collapses to a single record.
    Map<String, Financial_Account_Role__c> toInsert = new Map<String, Financial_Account_Role__c>();
    Set<Id> partyAccountIds = new Set<Id>();
    List<String> unusableRoles = new List<String>();
    List<String> rejectedRoles = new List<String>();
    Map<String, Integer> countByRole = new Map<String, Integer>();
    Set<String> roleValues = accountRoleValues();
    for (Integer i = 0; i < roles.size(); i++) {
      AccountRoleInput entry = roles[i];
      // A null entry leaves partyAccountId null, so role is never read for one.
      Id partyAccountId = entry == null ? null : parseAccountId(entry.accountId);
      if (partyAccountId == null || String.isBlank(entry.role)) {
        // Recorded rather than skipped: a party the wizard holds but cannot link is a data integrity
        // problem, and dropping it quietly turns a total failure into a silent success.
        unusableRoles.add(
          'index ' +
            String.valueOf(i) +
            ' (account: ' +
            (entry == null ? 'none' : String.valueOf(entry.accountId)) +
            ', role: ' +
            (entry == null ? 'none' : String.valueOf(entry.role)) +
            ')'
        );
        continue;
      }
      partyAccountIds.add(partyAccountId);
      if (!roleValues.contains(entry.role)) {
        if (!rejectedRoles.contains(entry.role)) {
          rejectedRoles.add(entry.role);
        }
        continue;
      }
      String key = relatedPartyKey(partyAccountId, entry.role);
      if (toInsert.containsKey(key)) {
        continue;
      }
      Integer held = countByRole.containsKey(entry.role)
        ? countByRole.get(entry.role)
        : 0;
      countByRole.put(entry.role, held + 1);
      toInsert.put(
        key,
        new Financial_Account_Role__c(
          Financial_Account__c = financialAccountId,
          Account__c = partyAccountId,
          Role__c = entry.role
        )
      );
    }
    if (!unusableRoles.isEmpty()) {
      throw new AuraHandledException(
        'Related parties could not be saved. Each one needs an account and a role, but ' +
          String.valueOf(unusableRoles.size()) +
          ' did not: ' +
          String.join(unusableRoles, '; ')
      );
    }
    enforceAccountRoleLimits(countByRole, roleLimitsJson);

    // Written before the reconcile so a party the wizard holds always reaches the Household Outline,
    // which is built from the envelope's contents. A DML failure below still rolls this back with the
    // rest of the transaction; the ordering removes the silent no-ops, it does not outlive an error.
    try {
      linkAccountsToEnvelope(envelopeId, partyAccountIds);
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Unable to link related parties to the envelope: ' + e.getDmlMessage(0)
      );
    }

    // Nothing for the wizard to reconcile: the parties are linked above, and every role on this
    // account belongs to one it does not own.
    if (managedRoles == null || managedRoles.isEmpty()) {
      return rejectedRoles;
    }

    List<Financial_Account_Role__c> toDelete = new List<Financial_Account_Role__c>();
    // The people whose role on this account is being removed. One person can hold several roles here,
    // so this is only a candidate list — it is narrowed to those left holding none once the rows are
    // written.
    Set<Id> removedOwners = new Set<Id>();
    for (Financial_Account_Role__c existing : [
      SELECT Id, Account__c, Role__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c = :financialAccountId
        AND Role__c IN :managedRoles
        AND Account__c != NULL
    ]) {
      String key = relatedPartyKey(existing.Account__c, existing.Role__c);
      if (toInsert.containsKey(key)) {
        // Already linked - keep the record as it is.
        toInsert.remove(key);
      } else {
        toDelete.add(existing);
        removedOwners.add(existing.Account__c);
      }
    }

    try {
      if (!toInsert.isEmpty()) {
        insert toInsert.values();
      }
      if (!toDelete.isEmpty()) {
        delete toDelete;
      }
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Unable to save related parties: ' + e.getDmlMessage(0)
      );
    }

    // Both derive from the rows just written, so they run after the DML and read it back rather than
    // reasoning about the payload — that way a row the reconcile left alone counts too.
    syncAccountOwnerLookups(financialAccountId);
    refreshAccountSignees(financialAccountId);

    // An owner left holding no role on this account also leaves the envelope, so the Household
    // Outline stops showing it. Read back rather than diffed from the payload, for the same reason as
    // above: a person removed from one role but still holding another is not a removal. A party still
    // serving this envelope keeps its link; the record is deleted only when nothing references it.
    if (!removedOwners.isEmpty()) {
      for (Financial_Account_Role__c remaining : [
        SELECT Account__c
        FROM Financial_Account_Role__c
        WHERE
          Financial_Account__c = :financialAccountId
          AND Account__c IN :removedOwners
      ]) {
        removedOwners.remove(remaining.Account__c);
      }
      WizardEnvelopeStateService.unlinkDroppedPartiesAndDeleteIfUnused(
        removedOwners,
        envelopeId
      );
    }
    return rejectedRoles;
  }

  // The roles currently held on the given Financial Accounts, one row per role. The wizard maps each
  // role back to the requirement slot it belongs to, so the rows stay flat rather than grouped here.
  @AuraEnabled(cacheable=false)
  public static List<AccountRoleOutput> getAccountRoles(
    List<Id> financialAccountIds
  ) {
    List<AccountRoleOutput> roles = new List<AccountRoleOutput>();
    if (financialAccountIds == null || financialAccountIds.isEmpty()) {
      return roles;
    }
    for (Financial_Account_Role__c row : [
      SELECT Financial_Account__c, Account__c, Account__r.Name, Role__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c IN :financialAccountIds
        AND Account__c != NULL
        AND Role__c != NULL
      ORDER BY Account__r.Name
    ]) {
      AccountRoleOutput role = new AccountRoleOutput();
      role.financialAccountId = row.Financial_Account__c;
      role.accountId = row.Account__c;
      role.name = row.Account__r.Name;
      role.role = row.Role__c;
      roles.add(role);
    }
    return roles;
  }

  private static List<AccountRoleInput> parseAccountRoles(String rolesJson) {
    if (String.isBlank(rolesJson)) {
      return new List<AccountRoleInput>();
    }
    try {
      List<AccountRoleInput> parsed = (List<AccountRoleInput>) JSON.deserialize(
        rolesJson,
        List<AccountRoleInput>.class
      );
      return parsed == null ? new List<AccountRoleInput>() : parsed;
    } catch (System.JSONException e) {
      throw new AuraHandledException(
        'Related parties could not be read: ' + e.getMessage()
      );
    }
  }

  // Identity of a signature request: one signee per (person, document).
  private static String signeeKey(Id accountId, Id requiredDocumentId) {
    return String.valueOf(accountId) + '|' + String.valueOf(requiredDocumentId);
  }

  private static Set<String> accountRoleValues() {
    Set<String> values = new Set<String>();
    for (
      Schema.PicklistEntry entry : Financial_Account_Role__c.Role__c.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        values.add(entry.getValue());
      }
    }
    return values;
  }

  // Reject the whole save when a role holds more parties than its registration allows. Thrown rather
  // than trimmed: silently dropping the last party added would look like the save worked.
  private static void enforceAccountRoleLimits(
    Map<String, Integer> countByRole,
    String roleLimitsJson
  ) {
    if (String.isBlank(roleLimitsJson) || countByRole.isEmpty()) {
      return;
    }
    Map<String, Object> limits;
    try {
      limits = (Map<String, Object>) JSON.deserializeUntyped(roleLimitsJson);
    } catch (System.JSONException e) {
      throw new AuraHandledException(
        'Related party limits could not be read: ' + e.getMessage()
      );
    }
    List<String> exceeded = new List<String>();
    for (String role : countByRole.keySet()) {
      Object rawLimit = limits.get(role);
      // A role with no ceiling (absent, or null for "unbounded") is skipped rather than treated as 0.
      Integer maxAllowed;
      if (rawLimit instanceof Integer) {
        maxAllowed = (Integer) rawLimit;
      } else if (rawLimit instanceof Decimal) {
        maxAllowed = ((Decimal) rawLimit).intValue();
      } else {
        continue;
      }
      if (countByRole.get(role) > maxAllowed) {
        exceeded.add(
          role +
            ' (' +
            String.valueOf(countByRole.get(role)) +
            ' of max ' +
            String.valueOf(maxAllowed) +
            ')'
        );
      }
    }
    if (!exceeded.isEmpty()) {
      throw new AuraHandledException(
        'This account allows fewer related parties than were sent: ' +
          String.join(exceeded, '; ')
      );
    }
  }

  // Mirror the account's owner roles onto the two Financial_Account__c lookups, which the ISA signer
  // list, the Case contact, the household rollup and the member picker all still read. A joint
  // registration writes only Joint Owner rows, so there may be no Primary Owner to map: the first
  // owner takes the primary lookup and the second the joint one. Two lookups cannot represent more
  // than two owners — the roles are the complete picture, these are a cache for existing readers.
  private static void syncAccountOwnerLookups(Id financialAccountId) {
    List<Id> primaryIds = new List<Id>();
    List<Id> jointIds = new List<Id>();
    for (Financial_Account_Role__c row : [
      SELECT Account__c, Role__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c = :financialAccountId
        AND Role__c IN :SIGNING_ACCOUNT_ROLES
        AND Account__c != NULL
      ORDER BY CreatedDate
    ]) {
      if (row.Role__c == 'Primary Owner') {
        primaryIds.add(row.Account__c);
      } else {
        jointIds.add(row.Account__c);
      }
    }
    // A Primary Owner always takes the primary lookup; a joint registration has none, so its earliest
    // Joint Owner does instead and the next one fills the joint lookup.
    List<Id> ownerIds = new List<Id>();
    ownerIds.addAll(primaryIds);
    ownerIds.addAll(jointIds);
    try {
      update new Financial_Account__c(
        Id = financialAccountId,
        Primary_Owner__c = ownerIds.size() > 0 ? ownerIds[0] : null,
        Joint_Owner__c = ownerIds.size() > 1 ? ownerIds[1] : null
      );
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Unable to update the account owners: ' + e.getDmlMessage(0)
      );
    }
  }

  // Rebuild the account's document signees from its owner roles. Previously these were created once,
  // at account creation, from the two owner lookups — which V2 never wrote, so the documents got no
  // signees at all, and which could never have covered more than two owners anyway. Driving them off
  // the roles means the signee list follows every owner change, including removals.
  private static void refreshAccountSignees(Id financialAccountId) {
    List<Required_Documents__c> docs = [
      SELECT Id
      FROM Required_Documents__c
      WHERE Financial_Account__c = :financialAccountId
    ];
    if (docs.isEmpty()) {
      return;
    }
    Set<Id> signerIds = new Set<Id>();
    for (Financial_Account_Role__c row : [
      SELECT Account__c
      FROM Financial_Account_Role__c
      WHERE
        Financial_Account__c = :financialAccountId
        AND Role__c IN :SIGNING_ACCOUNT_ROLES
        AND Account__c != NULL
    ]) {
      signerIds.add(row.Account__c);
    }

    Set<Id> docIds = new Map<Id, Required_Documents__c>(docs).keySet();
    List<Signee__c> toDelete = new List<Signee__c>();
    Set<String> alreadySigning = new Set<String>();
    for (Signee__c signee : [
      SELECT Id, Account__c, Required_Document__c
      FROM Signee__c
      WHERE Required_Document__c IN :docIds
    ]) {
      if (signee.Account__c != null && signerIds.contains(signee.Account__c)) {
        alreadySigning.add(
          signeeKey(signee.Account__c, signee.Required_Document__c)
        );
      } else {
        // No longer an owner (or never resolved to one) — the document should not still ask for a
        // signature from them.
        toDelete.add(signee);
      }
    }

    List<Signee__c> toInsert = new List<Signee__c>();
    for (Required_Documents__c doc : docs) {
      for (Id signerId : signerIds) {
        if (!alreadySigning.contains(signeeKey(signerId, doc.Id))) {
          toInsert.add(
            new Signee__c(Required_Document__c = doc.Id, Account__c = signerId)
          );
        }
      }
    }

    try {
      if (!toInsert.isEmpty()) {
        insert toInsert;
      }
      if (!toDelete.isEmpty()) {
        delete toDelete;
      }
    } catch (DmlException e) {
      throw new AuraHandledException(
        'Unable to update the document signees: ' + e.getDmlMessage(0)
      );
    }
  }

  @AuraEnabled
  public static List<Required_Documents__c> getRequiredDocuments(
    Id envelopeId
  ) {
    return [
      SELECT Id, Name, Status__c, EnvelopeId__c
      FROM Required_Documents__c
      WHERE EnvelopeId__c = :envelopeId
      ORDER BY CreatedDate
    ];
  }

  public class PicklistOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public PicklistOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }
}