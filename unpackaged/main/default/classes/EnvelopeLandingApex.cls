public with sharing class EnvelopeLandingApex {
    @AuraEnabled
    public static List<Envelope__c> exgetWizEnvelopes() {
        // User currentUser = [SELECT Id, Email, FirstName, LastName FROM User WHERE Id = :UserInfo.getUserId()];
        // System.runAs(currentUser) {
        return [SELECT Id, Name, Status__c, LastModifiedDate,Household_Name__c  FROM Envelope__c WHERE Status__c In ('New', 'In Progress') WITH SECURITY_ENFORCED];
        // }
        // return null;
    }
    
    public class WizardDataWrapper {
        @AuraEnabled public List<Rep_Code__c> repCodes { get; set; }
        @AuraEnabled public List<Account> households { get; set; }
        @AuraEnabled public List<Envelope__c> envelopes { get; set; }
        @AuraEnabled public List<Envelope_Content__c> envelopeRecords { get; set; }
        @AuraEnabled public List<Financial_Advisor_Team__c> financialAdvisorTeams { get; set; }
        // Per-envelope metrics for the list's Action Items / Missing Items columns, extracted from
        // each envelope's saved state so the full Envelope_JSON__c blob is never shipped.
        @AuraEnabled public List<EnvelopeMetrics> envelopeMetrics { get; set; }
    }

    // The minimum an envelope contributes to the list columns: entity counts for the Action Items
    // summary, derived from the envelope's records, and the outstanding-input total for the Missing
    // Items count, read from the fields the wizard writes on every save.
    //
    // The total is stored rather than derived here because the inputs it counts are no longer
    // readable from one place: c/envelopeShellV2 strips every record-backed entity out of
    // Envelope_JSON__c (the records are their store), so the answers now sit on the Accounts,
    // Financial Accounts, Services and action-item Cases, and the counting rules — field visibility,
    // format validity, related-party requirements — live in c/envelopeFormSchema. The wizard already
    // evaluates all of it for its own screens, so it persists the number and the list reads it. It is
    // therefore as of that envelope's last wizard save: a record edited elsewhere is not reflected
    // until the envelope is opened and saved again.
    public class EnvelopeMetrics {
        @AuraEnabled public Id envelopeId { get; set; }
        @AuraEnabled public Boolean hasCounts { get; set; }
        @AuraEnabled public Integer members { get; set; }
        @AuraEnabled public Integer isas { get; set; }
        // Null until a save has computed one. The list renders that as 0 rather than a placeholder.
        @AuraEnabled public Integer missingItemsCount { get; set; }
        // Marks the count as a lower bound: an unfilled Key Point gates further unknown fields.
        @AuraEnabled public Boolean missingItemsHasPlus { get; set; }
    }

    // One envelope's entity counts for the Action Items summary.
    private class EntityCounts {
        Integer members = 0;
        Integer isas = 0;
    }

    // Everything one envelope needs from its Envelope_Content__c rows, collected in a single bulk
    // pass. The household is read from the junction row rather than from Envelope__c.Household__c:
    // only createWizEnvelopeV2 populates that field, while every create path inserts a household row.
    private class EnvelopeContents {
        Id householdId;
        Set<Id> linkedRecordIds = new Set<Id>();
        Set<Id> linkedMemberAccountIds = new Set<Id>();
        Set<Id> linkedFinancialAccountIds = new Set<Id>();
        Set<Id> linkedServiceIds = new Set<Id>();
    }

    @AuraEnabled
    public static WizardDataWrapper getWizEnvelopes() {
        WizardDataWrapper dto = new WizardDataWrapper();
        
        // 1. Get Team IDs for current User
        Set<Id> teamIds = new Set<Id>();
        for (Financial_Advisor_Team_Member__c tm : [
            SELECT Financial_Advisor_Team__c 
            FROM Financial_Advisor_Team_Member__c 
            WHERE User__c = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
        ]) {
            teamIds.add(tm.Financial_Advisor_Team__c);
        }
        
        /**
* Author: Mile Cacanovic
*
* Return the current user's teams so the new envelope modal can list them.
*/
        dto.financialAdvisorTeams = [
            SELECT Id, Name
            FROM Financial_Advisor_Team__c
            WHERE Id IN :teamIds
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ];
        
        Set<Id> parentEnvelopeIds = new Set<Id>();
        // 2. Get Household Accounts related to Teams
        // Filtering by RecordType DeveloperName 'HouseHold' and Submitted__c = true
        if (!teamIds.isEmpty()) {
            dto.households = [
                SELECT Id, Name, Type, Financial_Advisor_Team__c 
                FROM Account 
                WHERE Financial_Advisor_Team__c IN :teamIds
                AND RecordType.DeveloperName = 'Household'
                WITH SECURITY_ENFORCED
            ];
            dto.repCodes = [SELECT Id ,Name, Financial_Advisor_Team__c 
                            FROM Rep_Code__c 
                            WHERE Financial_Advisor_Team__c IN :teamIds
                            WITH SECURITY_ENFORCED];
            
            if (!dto.households.isEmpty()) {
                Set<Id> accountIds = new Map<Id, Account>(dto.households).keySet();
                
                // 3. Get Junction/Child Records
                dto.envelopeRecords = [
                    SELECT Id, Name, Account__c, Envelope__c 
                    FROM Envelope_Content__c 
                    WHERE Account__c IN :accountIds
                    AND Envelope__c != null
                    WITH SECURITY_ENFORCED
                ];
                
                for (Envelope_Content__c child : dto.envelopeRecords) {
                    parentEnvelopeIds.add(child.Envelope__c);
                }
            }
        }
        
        // 4. Get Parent Envelopes
        if (!parentEnvelopeIds.isEmpty()) {
            dto.envelopes = [
                SELECT Id, Name, Status__c, LastModifiedDate, Household_Name__c,
                CreatedDate, CreatedBy.Name, LastModifiedBy.Name, OwnerId
                FROM Envelope__c
                WHERE Status__c IN ('New', 'In Progress')
                AND (Id IN :parentEnvelopeIds OR OwnerId = :UserInfo.getUserId())
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
            ];
        } else {
            dto.envelopes = [
                SELECT Id, Name, Status__c, LastModifiedDate, Household_Name__c,
                CreatedDate, CreatedBy.Name, LastModifiedBy.Name, OwnerId
                FROM Envelope__c
                WHERE Status__c IN ('New', 'In Progress')
                AND OwnerId = :UserInfo.getUserId()
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
            ];
        }

        // Derive the list's Action Items / Missing Items metrics for the whole page. Entity counts
        // come from the envelopes' records (buildEntityCounts). The Missing Items total comes from
        // the pair of fields the wizard writes on every save (see EnvelopeMetrics), and the saved
        // state is still read alongside them because it is the only store for the entities no record
        // holds yet, which the Action Items summary counts on top of the record-derived totals.
        //
        // All three are read WITHOUT WITH SECURITY_ENFORCED — matching
        // WizardEnvelopeStateService.loadEnvelopeState — because they are the app's own internal state
        // with no FLS granted; record-level sharing still applies via this class's "with sharing", and
        // the envelope ids come from the security-enforced query above. A SOQL for-loop keeps only a
        // page of blobs in heap at a time.
        if (dto.envelopes != null && !dto.envelopes.isEmpty()) {
            Set<Id> envelopeIds = new Map<Id, Envelope__c>(dto.envelopes).keySet();

            // Guarded so a permission gap on the household records costs the Action Items column
            // rather than the whole list: hasCounts then stays false and the cell renders blank.
            Map<Id, EntityCounts> countsByEnvelope;
            try {
                countsByEnvelope = buildEntityCounts(envelopeIds);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Envelope entity counts failed: ' + e);
                countsByEnvelope = new Map<Id, EntityCounts>();
            }

            dto.envelopeMetrics = new List<EnvelopeMetrics>();
            for (Envelope__c state : [
                SELECT Id, Envelope_JSON__c,
                       Missing_Items_Count__c, Missing_Items_Has_Plus__c
                FROM Envelope__c
                WHERE Id IN :envelopeIds
            ]) {
                dto.envelopeMetrics.add(
                    buildEnvelopeMetrics(state, countsByEnvelope.get(state.Id))
                );
            }
        }
        System.debug('result :' + dto);
        return dto;
    }

    // ---------------------------------------------------------------------------------------------
    // V2 list page (c/envelopeListV2). getWizEnvelopes above shipped the user's entire household
    // list — ~4,000 Accounts for a many-team advisor in production-sized data — on every page load,
    // for a picker that needs a few dozen rows at a time, and then had the client join households
    // to teams for one column. The two methods below replace that for the V2 page: the list payload
    // carries the team name per envelope and no household list, and the Existing Household picker
    // searches server-side. getWizEnvelopes is left as it was for the legacy list (c/envelopeTable).
    // ---------------------------------------------------------------------------------------------

    public class EnvelopeListData {
        @AuraEnabled public List<EnvelopeRow> envelopes { get; set; }
        @AuraEnabled public List<Option> advisorTeamOptions { get; set; }
        @AuraEnabled public List<EnvelopeMetrics> envelopeMetrics { get; set; }
    }

    // One list row: the envelope plus the household and team its junction row resolves to, so the
    // client needs no lookup tables of its own.
    public class EnvelopeRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String householdName { get; set; }
        @AuraEnabled public Id householdId { get; set; }
        @AuraEnabled public String advisorTeamName { get; set; }
        @AuraEnabled public Id advisorTeamId { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String createdByName { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
        @AuraEnabled public String lastModifiedByName { get; set; }
    }

    // A `{ label, value }` pair, the shape every picker on the page binds to.
    public class Option {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // The Account record type a household is — the DeveloperName, matching the filter getWizEnvelopes
    // has always used. (HOUSEHOLD_RECORD_TYPE_NAME further down is the label, compared against the
    // junction row's Account_Record_Type__c text; the two happen to coincide in this org.)
    private static final String HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAME = 'Household';

    // Household picker page size: enough to make the first few characters useful, small enough that
    // the rows cost nothing to hand through the component tree.
    private static final Integer HOUSEHOLD_SEARCH_LIMIT = 50;
    private static final Integer HOUSEHOLD_SEARCH_MIN_CHARS = 2;

    // Defensive circuit breaker on the envelope list itself. Org-wide Envelope__c volume is 229
    // rows today, nowhere near this, but the query has no LIMIT otherwise -- this caps future
    // growth instead of letting the same "unbounded fetch" pattern getWizEnvelopes had reappear
    // here one object later.
    private static final Integer ENVELOPE_LIST_LIMIT = 2000;

    // The Financial Advisor Teams the running user is a member of.
    private static Set<Id> currentUserTeamIds() {
        Set<Id> teamIds = new Set<Id>();
        for (Financial_Advisor_Team_Member__c tm : [
            SELECT Financial_Advisor_Team__c
            FROM Financial_Advisor_Team_Member__c
            WHERE User__c = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
        ]) {
            if (tm.Financial_Advisor_Team__c != null) {
                teamIds.add(tm.Financial_Advisor_Team__c);
            }
        }
        return teamIds;
    }

    @AuraEnabled
    public static EnvelopeListData getEnvelopeListData() {
        EnvelopeListData data = new EnvelopeListData();
        data.envelopes = new List<EnvelopeRow>();
        data.advisorTeamOptions = new List<Option>();
        data.envelopeMetrics = new List<EnvelopeMetrics>();

        Set<Id> teamIds = currentUserTeamIds();

        for (Financial_Advisor_Team__c team : [
            SELECT Id, Name
            FROM Financial_Advisor_Team__c
            WHERE Id IN :teamIds
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ]) {
            data.advisorTeamOptions.add(new Option(team.Name, team.Id));
        }

        // The envelopes of the user's teams, reached through the junction rows of the teams'
        // households — a relationship filter, so the households themselves are never loaded. Each
        // envelope keeps its first household row; that row carries the team name for the column.
        Map<Id, Envelope_Content__c> householdRowByEnvelope = new Map<Id, Envelope_Content__c>();
        if (!teamIds.isEmpty()) {
            for (Envelope_Content__c row : [
                SELECT Envelope__c, Account__c,
                       Account__r.Financial_Advisor_Team__r.Name
                FROM Envelope_Content__c
                WHERE Envelope__c != null
                AND Account__r.RecordType.DeveloperName = :HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAME
                AND Account__r.Financial_Advisor_Team__c IN :teamIds
                WITH SECURITY_ENFORCED
            ]) {
                if (!householdRowByEnvelope.containsKey(row.Envelope__c)) {
                    householdRowByEnvelope.put(row.Envelope__c, row);
                }
            }
        }

        Set<Id> teamEnvelopeIds = householdRowByEnvelope.keySet();
        List<Envelope__c> envelopes = [
            SELECT Id, Name, Household_Name__c, Household__c,
                   CreatedDate, CreatedBy.Name, LastModifiedDate, LastModifiedBy.Name
            FROM Envelope__c
            WHERE Status__c IN ('New', 'In Progress')
            AND (Id IN :teamEnvelopeIds OR OwnerId = :UserInfo.getUserId())
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
            LIMIT :ENVELOPE_LIST_LIMIT
        ];
        if (envelopes.isEmpty()) {
            return data;
        }

        // Owned envelopes outside the user's teams still need a household row for the column; one
        // more query for just those, rather than widening the relationship filter above.
        Set<Id> unresolved = new Set<Id>();
        for (Envelope__c env : envelopes) {
            if (!householdRowByEnvelope.containsKey(env.Id)) {
                unresolved.add(env.Id);
            }
        }
        if (!unresolved.isEmpty()) {
            for (Envelope_Content__c row : [
                SELECT Envelope__c, Account__c,
                       Account__r.Financial_Advisor_Team__r.Name
                FROM Envelope_Content__c
                WHERE Envelope__c IN :unresolved
                AND Account__r.RecordType.DeveloperName = :HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAME
                WITH SECURITY_ENFORCED
            ]) {
                if (!householdRowByEnvelope.containsKey(row.Envelope__c)) {
                    householdRowByEnvelope.put(row.Envelope__c, row);
                }
            }
        }

        for (Envelope__c env : envelopes) {
            Envelope_Content__c householdRow = householdRowByEnvelope.get(env.Id);
            EnvelopeRow row = new EnvelopeRow();
            row.id = env.Id;
            row.name = env.Name;
            row.householdName = env.Household_Name__c;
            row.householdId = householdRow != null ? householdRow.Account__c : env.Household__c;
            row.advisorTeamName = householdRow != null
                && householdRow.Account__r != null
                && householdRow.Account__r.Financial_Advisor_Team__r != null
                ? householdRow.Account__r.Financial_Advisor_Team__r.Name
                : null;
            row.advisorTeamId = householdRow != null
                && householdRow.Account__r != null
                && householdRow.Account__r.Financial_Advisor_Team__r != null
                ? householdRow.Account__r.Financial_Advisor_Team__r.Id
                : null;
            row.createdDate = env.CreatedDate;
            row.createdByName = env.CreatedBy != null ? env.CreatedBy.Name : null;
            row.lastModifiedDate = env.LastModifiedDate;
            row.lastModifiedByName = env.LastModifiedBy != null ? env.LastModifiedBy.Name : null;
            data.envelopes.add(row);
        }

        // Same metrics, same caveats, as getWizEnvelopes (see the comment there).
        Set<Id> envelopeIds = new Map<Id, Envelope__c>(envelopes).keySet();
        Map<Id, EntityCounts> countsByEnvelope;
        try {
            countsByEnvelope = buildEntityCounts(envelopeIds);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Envelope entity counts failed: ' + e);
            countsByEnvelope = new Map<Id, EntityCounts>();
        }
        for (Envelope__c state : [
            SELECT Id, Envelope_JSON__c, Missing_Items_Count__c, Missing_Items_Has_Plus__c
            FROM Envelope__c
            WHERE Id IN :envelopeIds
        ]) {
            data.envelopeMetrics.add(buildEnvelopeMetrics(state, countsByEnvelope.get(state.Id)));
        }
        return data;
    }

    // Existing-household typeahead for the New Envelope dialog: the user's teams' households whose
    // name contains the term, first page only. Under two characters returns nothing rather than
    // the first 50 of thousands.
    @AuraEnabled
    public static List<Option> searchHouseholds(String term) {
        List<Option> results = new List<Option>();
        String needle = term == null ? '' : term.trim();
        if (needle.length() < HOUSEHOLD_SEARCH_MIN_CHARS) {
            return results;
        }
        Set<Id> teamIds = currentUserTeamIds();
        if (teamIds.isEmpty()) {
            return results;
        }
        // Bind variables are not interpolated, but LIKE still reads % and _ as wildcards, so a
        // literal search for either has to escape them.
        String pattern = '%' + needle.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
        for (Account household : [
            SELECT Id, Name
            FROM Account
            WHERE Financial_Advisor_Team__c IN :teamIds
            AND RecordType.DeveloperName = :HOUSEHOLD_RECORD_TYPE_DEVELOPER_NAME
            AND Name LIKE :pattern
            WITH SECURITY_ENFORCED
            ORDER BY Name
            LIMIT :HOUSEHOLD_SEARCH_LIMIT
        ]) {
            results.add(new Option(household.Name, household.Id));
        }
        return results;
    }

    // The four Household Outline groups on the envelope model, in render order, and the account-side
    // ("ISA") subset. Kept in sync with GROUP_IDS in c/envelopeFormSchema.
    private static final List<String> METRIC_GROUP_IDS = new List<String>{
        'householdMembers', 'accounts', 'dpisSponsor', 'serviceAgreements'
    };
    private static final Set<String> ISA_GROUP_IDS = new Set<String>{
        'accounts', 'dpisSponsor', 'serviceAgreements'
    };

    // Assemble one envelope's list metrics. The entity counts for the Action Items summary arrive
    // already derived from records; this adds the entities the saved model is still the only store
    // for, and carries the Missing Items total straight off the envelope's own fields.
    //
    // The total is not derived here on purpose. It counts inputs whose answers live on the records
    // (Accounts, Financial Accounts, Services, action-item Cases) under rules that live in
    // c/envelopeFormSchema, and c/envelopeShellV2 strips every record-backed entity out of the saved
    // model, so reading the model for it reported zero for every envelope that had ever been saved —
    // which is the bug this replaced. The wizard computes the number for its own screens and persists
    // it (WizardEnvelopeStateService.saveEnvelopeState); a null one means no save has computed it yet,
    // and the client renders that as 0.
    private static EnvelopeMetrics buildEnvelopeMetrics(
        Envelope__c envelope,
        EntityCounts counts
    ) {
        EnvelopeMetrics metrics = new EnvelopeMetrics();
        metrics.envelopeId = envelope.Id;
        metrics.hasCounts = counts != null;
        metrics.members = counts == null ? 0 : counts.members;
        metrics.isas = counts == null ? 0 : counts.isas;
        metrics.missingItemsCount = envelope.Missing_Items_Count__c == null
            ? null
            : envelope.Missing_Items_Count__c.intValue();
        metrics.missingItemsHasPlus = envelope.Missing_Items_Has_Plus__c == true;

        if (String.isBlank(envelope.Envelope_JSON__c)) {
            return metrics;
        }

        Map<String, Object> model;
        try {
            model = (Map<String, Object>) JSON.deserializeUntyped(envelope.Envelope_JSON__c);
        } catch (Exception e) {
            return metrics;
        }

        // The saved model is read for one thing only: the entities no record holds yet. Everything
        // else it once contributed now comes from the records or from the stored total above.
        if (!metrics.hasCounts) {
            return metrics;
        }
        for (String groupId : METRIC_GROUP_IDS) {
            List<Object> entities = model.get(groupId) instanceof List<Object>
                ? (List<Object>) model.get(groupId)
                : new List<Object>();

            for (Object entityObj : entities) {
                if (!(entityObj instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> entity = (Map<String, Object>) entityObj;

                // c/envelopeShellV2 strips every record-backed entity from the saved model, on save
                // and on load, because the records are their store. What is left here is only the
                // entities no record holds — a member type with no record-type mapping, or an
                // addition not yet persisted — and the outline shows those, so they are counted on
                // top of the record-derived totals. Testing the id the same way the shell strips by
                // also stops a model written by an older build from counting its record-backed
                // entities twice.
                if (isRecordId((String) entity.get('id'))) {
                    continue;
                }
                if (groupId == 'householdMembers') {
                    metrics.members++;
                } else if (ISA_GROUP_IDS.contains(groupId)) {
                    metrics.isas++;
                }
            }
        }
        return metrics;
    }

    // The Account record type whose junction row marks an envelope's household. This is the record
    // type label, not its DeveloperName, matching the filter WizardEnvelopeStateService uses when it
    // reads an envelope's non-household member accounts.
    private static final String HOUSEHOLD_RECORD_TYPE_NAME = 'Household';

    // Per-envelope entity counts for the Action Items column, derived from records rather than from
    // the saved model. c/envelopeShellV2 strips every record-backed entity from Envelope_JSON__c on
    // save and on load, because the records — the Accounts, Financial Accounts and Services linked
    // through Envelope_Content__c — are their store, so counting the model reports zero for every
    // envelope whose entities exist. The rule below is the one the wizard's Household Outline
    // renders (WizardEnvelopeStateService.getHouseholdMembersAndAccounts and
    // transformToHouseholdMembersAndAccounts), so the list and the outline cannot disagree: a record
    // belongs to an envelope when the envelope links it, or when it is submitted and so part of the
    // household's settled state that every envelope of that household shows.
    //
    // Seven queries for the whole page, none of them per-envelope: the junction rows are read once
    // for every listed envelope, and each household-wide read is grouped by household, so a
    // household with ten envelopes still costs one row per record.
    private static Map<Id, EntityCounts> buildEntityCounts(Set<Id> envelopeIds) {
        Map<Id, EntityCounts> countsByEnvelope = new Map<Id, EntityCounts>();
        if (envelopeIds == null || envelopeIds.isEmpty()) {
            return countsByEnvelope;
        }

        Map<Id, EnvelopeContents> contentsByEnvelope = new Map<Id, EnvelopeContents>();
        for (Id envelopeId : envelopeIds) {
            contentsByEnvelope.put(envelopeId, new EnvelopeContents());
        }

        // Every entity-bearing junction row of every listed envelope. Rows carrying only a Case or a
        // Required Document name no entity and are filtered out, which also drops the orphan rows
        // left behind when a Case is deleted without its link. No security clause, matching the
        // outline's own Envelope_Content__c reads: the object is controlled by its envelope parent,
        // so this class's "with sharing" already scopes it to the envelopes the user can see.
        for (Envelope_Content__c ec : [
            SELECT Envelope__c, Account__c, Account_Record_Type__c,
                   Wizard_Financial_Account__c, Service__c
            FROM Envelope_Content__c
            WHERE Envelope__c IN :envelopeIds
            AND (Account__c != null OR Wizard_Financial_Account__c != null OR Service__c != null)
        ]) {
            EnvelopeContents contents = contentsByEnvelope.get(ec.Envelope__c);
            if (contents == null) {
                continue;
            }
            if (ec.Account__c != null) {
                contents.linkedRecordIds.add(ec.Account__c);
                // Compared case-insensitively so this agrees with the outline, whose equivalent
                // filter is a SOQL string comparison.
                if (HOUSEHOLD_RECORD_TYPE_NAME.equalsIgnoreCase(ec.Account_Record_Type__c)) {
                    // First one wins, so a duplicate household row cannot make the count depend on
                    // the order the rows come back in.
                    if (contents.householdId == null) {
                        contents.householdId = ec.Account__c;
                    }
                } else {
                    contents.linkedMemberAccountIds.add(ec.Account__c);
                }
            }
            if (ec.Wizard_Financial_Account__c != null) {
                contents.linkedRecordIds.add(ec.Wizard_Financial_Account__c);
                contents.linkedFinancialAccountIds.add(ec.Wizard_Financial_Account__c);
            }
            if (ec.Service__c != null) {
                contents.linkedRecordIds.add(ec.Service__c);
                contents.linkedServiceIds.add(ec.Service__c);
            }
        }

        Set<Id> householdIds = new Set<Id>();
        Set<Id> linkedFinancialAccountIds = new Set<Id>();
        Set<Id> linkedServiceIds = new Set<Id>();
        for (EnvelopeContents contents : contentsByEnvelope.values()) {
            if (contents.householdId != null) {
                householdIds.add(contents.householdId);
            }
            linkedFinancialAccountIds.addAll(contents.linkedFinancialAccountIds);
            linkedServiceIds.addAll(contents.linkedServiceIds);
        }

        // household -> member account -> whether that member is submitted. Submitted is what decides
        // whether a member the envelope does not itself link still belongs to it.
        Map<Id, Map<Id, Boolean>> membersByHousehold = new Map<Id, Map<Id, Boolean>>();
        Map<Id, Set<Id>> submittedFinancialAccountsByHousehold = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> submittedServicesByHousehold = new Map<Id, Set<Id>>();

        if (!householdIds.isEmpty()) {
            for (AccountContactRelation acr : [
                SELECT AccountId, Contact.AccountId, Contact.Account.Submitted__c
                FROM AccountContactRelation
                WHERE AccountId IN :householdIds
                AND IsActive = TRUE
                WITH USER_MODE
            ]) {
                if (acr.Contact == null || acr.Contact.AccountId == null) {
                    continue;
                }
                addHouseholdMember(
                    membersByHousehold,
                    acr.AccountId,
                    acr.Contact.AccountId,
                    acr.Contact.Account != null && acr.Contact.Account.Submitted__c == true
                );
            }

            // Business and trust members hang off the household through
            // Account_Account_Relationship__c rather than AccountContactRelation.
            for (Account_Account_Relationship__c rel : [
                SELECT Account__c, Related_Account__c, Related_Account__r.Submitted__c
                FROM Account_Account_Relationship__c
                WHERE Account__c IN :householdIds
                AND Related_Account__c != NULL
                WITH USER_MODE
            ]) {
                if (rel.Related_Account__r == null) {
                    continue;
                }
                addHouseholdMember(
                    membersByHousehold,
                    rel.Account__c,
                    rel.Related_Account__c,
                    rel.Related_Account__r.Submitted__c == true
                );
            }

            // The household-wide side of the outline's Financial Account and Service reads, narrowed
            // to submitted records. An unsubmitted household record only belongs to an envelope that
            // links it, and the links are already in hand — so the narrowing is exact, and it keeps
            // the indexed lookup leading instead of the OR the outline can afford per envelope.
            for (Financial_Account__c fa : [
                SELECT Id, Household__c
                FROM Financial_Account__c
                WHERE Household__c IN :householdIds
                AND Submitted__c = TRUE
                WITH USER_MODE
            ]) {
                addToIdSet(submittedFinancialAccountsByHousehold, fa.Household__c, fa.Id);
            }

            for (Service__c svc : [
                SELECT Id, Household__c
                FROM Service__c
                WHERE Household__c IN :householdIds
                AND Submitted__c = TRUE
                WITH USER_MODE
            ]) {
                addToIdSet(submittedServicesByHousehold, svc.Household__c, svc.Id);
            }
        }

        // Financial Accounts are private, so an envelope can link a record this user cannot read:
        // the junction row is visible through its envelope parent while the record is not. The
        // outline drops such a record and so must the count. Services are read the same way so the
        // two paths stay identical if that object's sharing ever tightens.
        Set<Id> visibleFinancialAccountIds = linkedFinancialAccountIds.isEmpty()
            ? new Set<Id>()
            : new Map<Id, Financial_Account__c>([
                  SELECT Id
                  FROM Financial_Account__c
                  WHERE Id IN :linkedFinancialAccountIds
                  WITH USER_MODE
              ]).keySet();
        Set<Id> visibleServiceIds = linkedServiceIds.isEmpty()
            ? new Set<Id>()
            : new Map<Id, Service__c>([
                  SELECT Id
                  FROM Service__c
                  WHERE Id IN :linkedServiceIds
                  WITH USER_MODE
              ]).keySet();

        for (Id envelopeId : envelopeIds) {
            EnvelopeContents contents = contentsByEnvelope.get(envelopeId);
            EntityCounts counts = new EntityCounts();

            // Members: every household member the envelope admits — it already links the record, or
            // the record is submitted — plus every non-household Account the envelope links outright,
            // which is the outline's third, unconditional pass. Deduped by account id, because one
            // account is one outline row however many of the three sources name it.
            //
            // The household Account is in linkedRecordIds, and the two household passes do not
            // exclude it, so a Contact sitting directly on the household would make the household
            // count as one of its own members. That mirrors the outline, which has the same gap;
            // correcting one means correcting both.
            Set<Id> memberAccountIds = new Set<Id>(contents.linkedMemberAccountIds);
            Map<Id, Boolean> householdMembers = contents.householdId == null
                ? null
                : membersByHousehold.get(contents.householdId);
            if (householdMembers != null) {
                for (Id memberAccountId : householdMembers.keySet()) {
                    if (householdMembers.get(memberAccountId) == true
                        || contents.linkedRecordIds.contains(memberAccountId)) {
                        memberAccountIds.add(memberAccountId);
                    }
                }
            }
            counts.members = memberAccountIds.size();

            // ISAs: Financial Accounts and Service Agreements under the same rule. Deduped within
            // each object — a record the envelope links and the household also holds is one row —
            // but not across them, since one record is always one outline row.
            Set<Id> financialAccountIds = new Set<Id>();
            for (Id financialAccountId : contents.linkedFinancialAccountIds) {
                if (visibleFinancialAccountIds.contains(financialAccountId)) {
                    financialAccountIds.add(financialAccountId);
                }
            }
            Set<Id> serviceIds = new Set<Id>();
            for (Id serviceId : contents.linkedServiceIds) {
                if (visibleServiceIds.contains(serviceId)) {
                    serviceIds.add(serviceId);
                }
            }
            if (contents.householdId != null) {
                if (submittedFinancialAccountsByHousehold.containsKey(contents.householdId)) {
                    financialAccountIds.addAll(
                        submittedFinancialAccountsByHousehold.get(contents.householdId)
                    );
                }
                if (submittedServicesByHousehold.containsKey(contents.householdId)) {
                    serviceIds.addAll(submittedServicesByHousehold.get(contents.householdId));
                }
            }
            counts.isas = financialAccountIds.size() + serviceIds.size();

            countsByEnvelope.put(envelopeId, counts);
        }
        return countsByEnvelope;
    }

    // Record a household member, keeping submitted = true once any source reports it. The outline
    // evaluates its two household passes independently and admits the member if either succeeds, so
    // OR-ing here reaches the same result without depending on which pass sees the record first.
    private static void addHouseholdMember(
        Map<Id, Map<Id, Boolean>> membersByHousehold,
        Id householdId,
        Id memberAccountId,
        Boolean submitted
    ) {
        if (householdId == null || memberAccountId == null) {
            return;
        }
        Map<Id, Boolean> members = membersByHousehold.get(householdId);
        if (members == null) {
            members = new Map<Id, Boolean>();
            membersByHousehold.put(householdId, members);
        }
        members.put(memberAccountId, members.get(memberAccountId) == true || submitted == true);
    }

    private static void addToIdSet(Map<Id, Set<Id>> byKey, Id key, Id value) {
        if (key == null || value == null) {
            return;
        }
        if (!byKey.containsKey(key)) {
            byKey.put(key, new Set<Id>());
        }
        byKey.get(key).add(value);
    }

    // Mirrors isRecordId in c/envelopeShellV2 — the same test that decides which entities the shell
    // strips from the saved model, so what is counted from that model is exactly what survives in
    // it. Pattern.matches requires the whole string to match, as the anchors do on the client side.
    private static Boolean isRecordId(String value) {
        return value != null && Pattern.matches('[a-zA-Z0-9]{15,18}', value);
    }

    @AuraEnabled
    public static List<Envelope_Content__c> getWizEnvelopeRecords(Id wizardEnvelopeId) {
        return [SELECT Id, Name, Account__c, Case__c, Wizard_Financial_Account__c FROM Envelope_Content__c WHERE Envelope__c = :wizardEnvelopeId];
    }
    
    public class EnvelopeCreateResult {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public String createdByName { get; set; }
        // The envelope's household, resolved server-side. Populated by createWizEnvelopeV2 for
        // both household modes so the caller can open the envelope's detail screen without
        // re-querying; left null by createWizEnvelope.
        @AuraEnabled public Id householdId { get; set; }
        @AuraEnabled public String householdName { get; set; }
    }
    
    @AuraEnabled
    public static EnvelopeCreateResult createWizEnvelope(Id householdId, String householdName){
        Envelope__c wizEnvelope = new Envelope__c(
            Name = DateTime.now().format('M/d/yyyy') + ' - ' + householdName
        );
        insert wizEnvelope;
        Envelope_Content__c wizEnvelopeRecord = new Envelope_Content__c(
            Envelope__c = wizEnvelope.Id,
            Account__c = householdId
        );
        insert wizEnvelopeRecord;
        Envelope__c created = [SELECT Id, CreatedDate, CreatedBy.Name FROM Envelope__c WHERE Id = :wizEnvelope.Id LIMIT 1];
        EnvelopeCreateResult result = new EnvelopeCreateResult();
        result.id = created.Id;
        result.createdDate = created.CreatedDate;
        result.createdByName = created.CreatedBy.Name;
        System.debug('result: ' + result);
        return result;
    }
    
    // V2 create: sets the envelope Name from the user-typed title, and (in 'new'
    // household mode) creates the household Account with its advisor team before
    // linking. Returns the resolved household id and name so the caller can open the
    // envelope's detail screen directly. Kept separate from createWizEnvelope so the
    // v1 landing page is unaffected.
    @AuraEnabled
    public static EnvelopeCreateResult createWizEnvelopeV2(
        String title,
        String householdMode,
        Id householdId,
        String householdName,
        Id advisorTeamId
    ) {
        String trimmedTitle = title == null ? '' : title.trim();
        if (String.isBlank(trimmedTitle)) {
            throw new AuraHandledException('Envelope title cannot be empty.');
        }
        
        Id targetHouseholdId = householdId;
        // Resolved for both modes: the typed name when creating a household, the Account's own
        // name when reusing one. Stamped on the envelope and returned to the caller.
        String resolvedHouseholdName;

        if (householdMode == 'new') {
            if (String.isBlank(householdName)) {
                throw new AuraHandledException('Household name is required.');
            }
            if (advisorTeamId == null) {
                // Required so the new household passes the team filter in getWizEnvelopes.
                throw new AuraHandledException('Financial advisor team is required for a new household.');
            }
            if (!Schema.sObjectType.Account.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create households.');
            }
            resolvedHouseholdName = householdName.trim();
            Account household = new Account(
                Name = resolvedHouseholdName,
                RecordTypeId = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('Household').getRecordTypeId(),
                Financial_Advisor_Team__c = advisorTeamId
            );
            insert household;
            targetHouseholdId = household.Id;
        }

        if (targetHouseholdId == null) {
            throw new AuraHandledException('A household is required.');
        }

        if (resolvedHouseholdName == null) {
            // Existing household: read the name from the record rather than the request, which
            // carries no name in this mode.
            if (!Schema.sObjectType.Account.isAccessible()) {
                throw new AuraHandledException('You do not have access to households.');
            }
            List<Account> households = [SELECT Name FROM Account WHERE Id = :targetHouseholdId LIMIT 1];
            if (households.isEmpty()) {
                throw new AuraHandledException('The selected household could not be found.');
            }
            resolvedHouseholdName = households[0].Name;
        }

        if (!Schema.sObjectType.Envelope__c.isCreateable()
            || !Schema.sObjectType.Envelope_Content__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create envelopes.');
            }
        if(advisorTeamId == null){
            advisorTeamId = [SELECT Financial_Advisor_Team__c FROM  Account WHERE Id =:targetHouseholdId].Financial_Advisor_Team__c;
        }
        // Status 'New' is required for the envelope to appear in getWizEnvelopes,
        // which filters Status__c IN ('New','In Progress').
        Envelope__c wizEnvelope = new Envelope__c(Name = trimmedTitle, Status__c = 'New', Household__c = targetHouseholdId, 
                                                  Household_Name__c = resolvedHouseholdName, Financial_Advisor_Team__c = advisorTeamId);
        insert wizEnvelope;
        insert new Envelope_Content__c(
            Envelope__c = wizEnvelope.Id,
            Account__c = targetHouseholdId
        );
        
        Envelope__c created = [
            SELECT Id, CreatedDate, CreatedBy.Name
            FROM Envelope__c WHERE Id = :wizEnvelope.Id LIMIT 1
        ];
        EnvelopeCreateResult result = new EnvelopeCreateResult();
        result.id = created.Id;
        result.createdDate = created.CreatedDate;
        result.createdByName = created.CreatedBy.Name;
        result.householdId = targetHouseholdId;
        result.householdName = resolvedHouseholdName;
        return result;
    }
    
    @AuraEnabled
    public static void deleteWizEnvelope(Id wizardEnvelopeId) {
        if (wizardEnvelopeId == null) {
            return;
        }
        if (!Schema.sObjectType.Envelope__c.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete envelopes.');
        }
        
        // Only allow deletion of draft envelopes that appear on the landing page.
        Envelope__c env = [
            SELECT Id, Status__c
            FROM Envelope__c
            WHERE Id = :wizardEnvelopeId
            AND Status__c IN ('New', 'In Progress')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        delete env;
    }
    
    @AuraEnabled
    public static void renameWizEnvelope(Id wizardEnvelopeId, String name) {
        if (wizardEnvelopeId == null) {
            return;
        }
        String trimmed = name == null ? '' : name.trim();
        if (String.isBlank(trimmed)) {
            throw new AuraHandledException('Envelope name cannot be empty.');
        }
        if (!Schema.sObjectType.Envelope__c.fields.Name.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to rename envelopes.');
        }
        
        // Only allow renaming draft envelopes that appear on the landing page.
        Envelope__c env = [
            SELECT Id, Name, Status__c
            FROM Envelope__c
            WHERE Id = :wizardEnvelopeId
            AND Status__c IN ('New', 'In Progress')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        env.Name = trimmed;
        update env;
    }
    
    @AuraEnabled
    public static List<Account> getEligibleAccounts(Id householdId, String wizEnvRecords) {
        List<AccountContactRelation> acrList = [
            SELECT ContactId 
            FROM AccountContactRelation 
            WHERE AccountId = :householdId
        ];
        System.debug('wizEnvRecords' + wizEnvRecords);
        List<Envelope_Content__c> wizEnvRecordList = (List<Envelope_Content__c>) JSON.deserialize(wizEnvRecords, List<Envelope_Content__c>.class);
        System.debug('wizEnvRecordList ' + wizEnvRecordList);
        
        Set<Id> accountIds = new Set<Id>();
        for(Envelope_Content__c wizEnvRecord : wizEnvRecordList) {
            if (wizEnvRecord.Account__c != householdId) {
                accountIds.add(wizEnvRecord.Account__c);
            }
        }
        if(accountIds.isEmpty()) {
            return new List<Account>();
        }
        return [SELECT Id, Name FROM Account
                WHERE Id IN :accountIds]; 
    }
    private static void createCasesAndEnvelopeContents(
        List<Object> financialAccounts,
        List<Object> services,
        Id envelopeId
    ) {
        
        List<Case> casesToInsert = new List<Case>();

        // Every case raised under this envelope carries the envelope's household.
        Id householdId = EnvelopeHouseholdResolver.resolveHouseholdId(envelopeId);

        // Create Cases for Financial Accounts
        for (Object obj : financialAccounts) {
            Financial_Account__c fa = (Financial_Account__c)obj;
            Case c = new Case();
            c.Subject = 'Financial Account - ' + fa.Name;
            c.Status = 'New';
            c.Origin = 'Web';
            c.Household__c = householdId;
            c.Wizard_Financial_Account__c = fa.Id;
            c.Incomplete_Record__c = true;
            c.Custodian__c = fa.Custodian__c;
            c.Registration_Type__c = fa.Registration_Type__c;
            // Dummy mappings
            c.Description = 'Created from Financial Account';
            // c.AccountId = fa.Primary_Owner__c;   // Example if applicable
            
            casesToInsert.add(c);
        }
        
        // Create Cases for Services
        for (Object obj : services) {
            Service__c ser = (Service__c)obj;
            Case c = new Case();
            c.Origin = 'Wizard';
            c.Household__c = householdId;
            c.recordTypeId = [SELECT Id,Case_Account_Opening_Record_Type__c  FROM Wizard_Flow_Values__mdt].Case_Account_Opening_Record_Type__c;
            if(ser.type__c == 'Financial Planning'){
                c.Type = 'Financial Planning';
                //c.Subject = 'New Financial Planning & Consulting for {!varHousehold.Name}';   
            }else if(ser.type__c == 'Multi-Family Office'){
                c.Type = 'Multi-Family Office';
                //c.Subject = 'New Multi-Family Office Request for {!varHousehold.Name}';  
            }
            
            //c.AccountId = household.Id;
            c.Service_Start_Date__c = ser.Start_Date__c;
            
            casesToInsert.add(c);
        }
        
        if (casesToInsert.isEmpty()) {
            return;
        }
        
        insert casesToInsert;
        
        List<Envelope_Content__c> envelopeContents = new List<Envelope_Content__c>();
        
        for (Integer i = 0; i < casesToInsert.size(); i++) {
            
            Envelope_Content__c ec = new Envelope_Content__c();
            ec.Envelope__c = envelopeId;
            ec.Case__c = casesToInsert[i].Id;
            
            
            envelopeContents.add(ec);
        }
        
        if (!envelopeContents.isEmpty()) {
            insert envelopeContents;
        }
    }
}