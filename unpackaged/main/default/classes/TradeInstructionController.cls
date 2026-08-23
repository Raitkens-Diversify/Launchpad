/**
 * TradeInstructionController — Apex for the envelope wizard's Trade Instructions section.
 *
 * Sleeve rows carry an advisor-chosen funding basis (Order__c.Funding_Basis__c): Dollar rows are
 * fixed carve-outs from the Expected Account Value; Percent rows describe the actively traded
 * remainder and total 100% across the ticket. Dollar rows also stamp
 * Total_Initial_Funding_Amount__c, the marker legacy consumers (FlowCreateMultipleController et al.)
 * already read as "this row is dollar-based".
 *
 * Transport is Map<String, Object>/List<Object> throughout — @AuraEnabled custom-type parameters
 * arrive null org-wide (see repo notes), so no wrapper classes.
 */
public with sharing class TradeInstructionController {
    private static final String BASIS_DOLLAR = 'Dollar';
    private static final String BASIS_PERCENT = 'Percent';

    // The LWC basis vocabulary (c/envelopeFormSchema STRATEGY_BASIS) → Funding_Basis__c values.
    private static final Map<String, String> BASIS_BY_TOKEN = new Map<String, String>{
        'fixed-dollar' => BASIS_DOLLAR,
        'fixed-percentage' => BASIS_PERCENT
    };
    private static final Map<String, String> TOKEN_BY_BASIS = new Map<String, String>{
        BASIS_DOLLAR => 'fixed-dollar',
        BASIS_PERCENT => 'fixed-percentage'
    };

    // Sleeve_Basis_Rule__mdt Allowed Funding Basis values (mirror of c/envelopeFormSchema
    // ALLOWED_BASIS). The reserved Default rule covers a strategy whose classification is blank or
    // has no rule of its own.
    private static final String ALLOWED_DOLLAR_ONLY = 'Dollar Only';
    private static final String ALLOWED_PERCENT_ONLY = 'Percent Only';
    private static final String ALLOWED_EITHER = 'Either';
    private static final String DEFAULT_RULE_KEY = 'Default';

    private static Map<String, String> basisRules;

    /**
     * Allowed Funding Basis by sleeve classification, from the Sleeve_Basis_Rule__mdt rule table.
     * Queried without a WHERE clause because custom metadata SOQL rejects disjunctions and the table
     * is a handful of rows; matched in Apex instead.
     */
    private static Map<String, String> rules() {
        if (basisRules == null) {
            basisRules = new Map<String, String>();
            for (Sleeve_Basis_Rule__mdt rule : [
                SELECT Sleeve_Classification__c, Allowed_Funding_Basis__c FROM Sleeve_Basis_Rule__mdt
            ]) {
                if (String.isNotBlank(rule.Sleeve_Classification__c)) {
                    basisRules.put(rule.Sleeve_Classification__c, rule.Allowed_Funding_Basis__c);
                }
            }
        }
        return basisRules;
    }

    /**
     * The basis a strategy of this classification may be funded on. An unclassified strategy, or one
     * whose classification has no rule, follows the Default rule — Percent Only unless configured
     * otherwise, which is how every strategy behaved before the classification existed.
     */
    private static String allowedBasisFor(String classification) {
        Map<String, String> configured = rules();
        String allowed = String.isBlank(classification) ? null : configured.get(classification);
        if (String.isBlank(allowed)) {
            allowed = configured.get(DEFAULT_RULE_KEY);
        }
        return String.isBlank(allowed) ? ALLOWED_PERCENT_ONLY : allowed;
    }

    /**
     * Selectable strategies for the sleeve pickers, each carrying the basis it may be funded on so
     * the client can offer it in the matching list only. Retired strategies are excluded, but a
     * strategy with no Status is kept: blank means never curated rather than retired, and several
     * live strategies — including the Fee-Based Alternative Investments sleeve this feature exists
     * for — carry no Status at all.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getStrategyOptions() {
        System.debug('getStrategyOptions');
        List<Map<String, Object>> options = new List<Map<String, Object>>();
        for (Strategy__c strategy : [
            SELECT Id, Name, Strategy_Code__c, Sleeve_Classification__c
            FROM Strategy__c
            WHERE Status__c != 'Inactive'
            ORDER BY Name
        ]) {
            options.add(new Map<String, Object>{
                'id' => strategy.Id,
                'name' => strategy.Name,
                'strategyCode' => strategy.Strategy_Code__c,
                'classification' => strategy.Sleeve_Classification__c,
                'allowedBasis' => allowedBasisFor(strategy.Sleeve_Classification__c)
            });
        }
        return options;
    }

    /**
     * The account's current trade instructions, shaped for the Trade Instructions section value:
     * { expectedAccountValue, strategies: [{ strategy, type, fundingAmount, fundingPercent }] }.
     * Reads the current Allocation__c snapshot (the allocation of record) and falls back to the
     * newest Order_Ticket__c's rows for an account whose first request hasn't completed into an
     * allocation yet. Rows older than Funding_Basis__c infer dollar from the legacy marker
     * (amount without percent).
     */
    @AuraEnabled
    public static Map<String, Object> getCurrentTradeInstructions(Id financialAccountId) {
        if (financialAccountId == null) {
            throw new AuraHandledException('financialAccountId is required.');
        }
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Decimal expected = null;

        List<Allocation__c> current = [
            SELECT Id, Request_Allocation_Originated_From__r.Expected_Account_Value__c
            FROM Allocation__c
            WHERE Wizard_Financial_Account__c = :financialAccountId AND Current_Allocation__c = true
            ORDER BY Date_Implemented__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 1
        ];
        if (!current.isEmpty()) {
            Id currentAllocationId = current[0].Id;
            // The expected value comes from the ticket that produced this allocation, not from a
            // snapshot row: Total_Initial_Funding_Amount__c is stamped on dollar rows only, so an
            // all-percentage allocation would otherwise read back with no expected value at all.
            expected = current[0].Request_Allocation_Originated_From__r.Expected_Account_Value__c;
            for (Allocation_Strategy__c snap : [
                SELECT Strategy__c, Funding_Basis__c, Initial_Funding_Amount__c,
                    Initial_Funding_Percentage__c, Total_Initial_Funding_Amount__c
                FROM Allocation_Strategy__c
                WHERE Allocation__c = :currentAllocationId
                ORDER BY Strategy__r.Name
            ]) {
                rows.add(shapeRow(snap.Strategy__c, snap.Funding_Basis__c,
                    snap.Initial_Funding_Amount__c, snap.Initial_Funding_Percentage__c));
                if (expected == null) {
                    expected = snap.Total_Initial_Funding_Amount__c;
                }
            }
        } else {
            List<Order_Ticket__c> tickets = [
                SELECT Id, Expected_Account_Value__c
                FROM Order_Ticket__c
                WHERE Wizard_Financial_Account__c = :financialAccountId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!tickets.isEmpty()) {
                expected = tickets[0].Expected_Account_Value__c;
                Id latestTicketId = tickets[0].Id;
                for (Order__c row : [
                    SELECT Strategy__c, Funding_Basis__c, Initial_Funding_Amount__c,
                        Initial_Funding_Percentage__c
                    FROM Order__c
                    WHERE Order_Ticket__c = :latestTicketId
                    ORDER BY Strategy__r.Name
                ]) {
                    rows.add(shapeRow(row.Strategy__c, row.Funding_Basis__c,
                        row.Initial_Funding_Amount__c, row.Initial_Funding_Percentage__c));
                }
            }
        }
        return new Map<String, Object>{
            'expectedAccountValue' => expected,
            'strategies' => rows
        };
    }

    /**
     * Persist one interview's trade instructions as an Order_Ticket__c with one Order__c per sleeve.
     * Idempotent per (envelopeId, financialAccountId, caseId): a re-submit updates the still-New
     * ticket's header and replaces its sleeve rows instead of stacking a duplicate request.
     *
     * A payload with no caseId (a new account/DPI's trade instructions) resolves to that account's
     * own Account Opening Case via resolveAccountOpeningCaseId — see its comment — rather than
     * leaving the ticket permanently unlinked.
     *
     * payload: { envelopeId, financialAccountId, caseId?, typeOfRequest, expectedAccountValue,
     *            advisorNotes, strategies: [{ strategyId, basis, value }] } — basis accepts the LWC
     * tokens (fixed-dollar/fixed-percentage) or the picklist values (Dollar/Percent).
     */
    @AuraEnabled
    public static Id saveTradeInstructions(Map<String, Object> payload) {
        if (payload == null) {
            throw new AuraHandledException('Trade instruction payload is required.');
        }
        Id faId = idFrom(payload.get('financialAccountId'), 'financialAccountId');
        Id envelopeId = idFrom(payload.get('envelopeId'), 'envelopeId');
        Id caseId = payload.get('caseId') == null ? null : idFrom(payload.get('caseId'), 'caseId');
        if (caseId == null) {
            caseId = resolveAccountOpeningCaseId(faId);
        }
        String typeOfRequest = (String) payload.get('typeOfRequest');
        Decimal expected = decimalFrom(payload.get('expectedAccountValue'), 'expectedAccountValue');
        String advisorNotes = (String) payload.get('advisorNotes');
        List<Object> strategies = (List<Object>) payload.get('strategies');
        if (strategies == null || strategies.isEmpty()) {
            throw new AuraHandledException('At least one strategy sleeve is required.');
        }

        // Shape every row before any DML so a bad payload fails whole.
        List<Order__c> rows = new List<Order__c>();
        List<Map<String, Object>> shaped = new List<Map<String, Object>>();
        Set<Id> strategyIds = new Set<Id>();
        for (Object raw : strategies) {
            // A row nested inside the untyped `payload` map comes back from the Aura boundary as
            // Map<Object,Object> rather than Map<String,Object> — the outer map is typed correctly
            // because the method signature says so, but nothing types the objects nested inside it.
            // A direct cast throws "Invalid conversion from runtime type Map<ANY,ANY> to
            // Map<String,ANY>" regardless of the row's content. Round-tripping through JSON forces a
            // fresh, correctly-typed parse.
            Map<String, Object> row = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(raw));
            String basis = normalizeBasis((String) row.get('basis'));
            Decimal value = decimalFrom(row.get('value'), 'sleeve value');
            if (value == null || value <= 0) {
                throw new AuraHandledException('Each sleeve needs a positive value.');
            }
            Id strategyId = idFrom(row.get('strategyId'), 'strategyId');
            strategyIds.add(strategyId);
            shaped.add(new Map<String, Object>{
                'strategyId' => strategyId,
                'basis' => basis,
                'value' => value
            });
        }

        // Re-check the configured lock server-side. The client only offers a strategy in the list its
        // rule allows, so a violation here means a stale or hand-built payload — the rule is the
        // system of record for how a sleeve may be funded, so it is enforced on the way in too.
        Map<Id, Strategy__c> byId = new Map<Id, Strategy__c>([
            SELECT Id, Name, Sleeve_Classification__c FROM Strategy__c WHERE Id IN :strategyIds
        ]);
        for (Map<String, Object> row : shaped) {
            Id strategyId = (Id) row.get('strategyId');
            String basis = (String) row.get('basis');
            Strategy__c strategy = byId.get(strategyId);
            if (strategy == null) {
                throw new AuraHandledException('A selected strategy no longer exists.');
            }
            String allowed = allowedBasisFor(strategy.Sleeve_Classification__c);
            Boolean permitted = allowed == ALLOWED_EITHER ||
                (basis == BASIS_DOLLAR && allowed == ALLOWED_DOLLAR_ONLY) ||
                (basis == BASIS_PERCENT && allowed == ALLOWED_PERCENT_ONLY);
            if (!permitted) {
                throw new AuraHandledException(
                    strategy.Name + ' can only be funded as ' + allowed.toLowerCase() +
                    ', not as a ' + basis.toLowerCase() + ' sleeve.'
                );
            }
            Order__c sleeve = new Order__c(
                Strategy__c = strategyId,
                Funding_Basis__c = basis
            );
            Decimal value = (Decimal) row.get('value');
            if (basis == BASIS_DOLLAR) {
                sleeve.Initial_Funding_Amount__c = value;
                sleeve.Total_Initial_Funding_Amount__c = expected;
            } else {
                sleeve.Initial_Funding_Percentage__c = value;
            }
            rows.add(sleeve);
        }

        List<Order_Ticket__c> existing = [
            SELECT Id
            FROM Order_Ticket__c
            WHERE Flow_Interview_ID__c = :String.valueOf(envelopeId)
                AND Wizard_Financial_Account__c = :faId
                AND Case__c = :caseId
                AND Status__c = 'New'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Order_Ticket__c ticket = existing.isEmpty() ? new Order_Ticket__c() : existing[0];
        ticket.Wizard_Financial_Account__c = faId;
        ticket.Case__c = caseId;
        ticket.Flow_Interview_ID__c = String.valueOf(envelopeId);
        ticket.Type_of_Request__c = typeOfRequest;
        ticket.Expected_Account_Value__c = expected;
        ticket.Advisor_Notes__c = advisorNotes;
        ticket.Status__c = 'New';
        ticket.Incomplete_Record__c = false;
        upsert ticket;

        if (!existing.isEmpty()) {
            delete [SELECT Id FROM Order__c WHERE Order_Ticket__c = :ticket.Id];
        }
        for (Order__c sleeve : rows) {
            sleeve.Order_Ticket__c = ticket.Id;
        }
        insert rows;
        return ticket.Id;
    }

    private static Map<String, Object> shapeRow(Id strategyId, String basis, Decimal amount, Decimal percent) {
        Boolean isDollar = basis == BASIS_DOLLAR || (basis == null && amount != null && percent == null);
        return new Map<String, Object>{
            'strategy' => strategyId,
            'type' => isDollar ? TOKEN_BY_BASIS.get(BASIS_DOLLAR) : TOKEN_BY_BASIS.get(BASIS_PERCENT),
            'fundingAmount' => isDollar ? amount : null,
            'fundingPercent' => isDollar ? null : percent
        };
    }

    private static String normalizeBasis(String raw) {
        String basis = BASIS_BY_TOKEN.containsKey(raw) ? BASIS_BY_TOKEN.get(raw) : raw;
        if (basis != BASIS_DOLLAR && basis != BASIS_PERCENT) {
            throw new AuraHandledException('Each sleeve needs a basis of Dollar or Percent.');
        }
        return basis;
    }

    // A new account/DPI's trade instructions arrive with no Case Id: the wizard hardcodes
    // caseId: null (c/envelopeShellV2 _collectTradeSources) because it never learns the Account
    // Opening Case's Id — EnvelopeISAController creates that Case alongside the new Financial
    // Account but only ever returns the account's Id back to the client. Left unresolved, the
    // ticket writes Case__c = null permanently, and the Case's own Order_Tickets__c flag never
    // gets set, so neither record can find the other.
    //
    // Resolve it the same way WizardEnvelopeStateService.saveAccountCaseInfo already locates that
    // Case for its own writes — by (Wizard_Financial_Account__c, Origin, Type) — so both paths
    // agree on which Case a given account's Account Opening Case is. Scoped to that exact Type so
    // an action item's Case (which never carries this Type) can never be picked up by mistake if
    // a caller passes no caseId for some other reason. An account with no such Case (data that
    // predates this Case being created, or created outside the wizard) resolves to null, same as
    // before this method existed.
    private static Id resolveAccountOpeningCaseId(Id faId) {
        List<Case> cases = [
            SELECT Id, Order_Tickets__c
            FROM Case
            WHERE Wizard_Financial_Account__c = :faId
                AND Origin = :WizardEnvelopeStateService.WIZARD_CASE_ORIGIN
                AND Type = :WizardEnvelopeStateService.ACCOUNT_OPENING_CASE_TYPE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            return null;
        }
        if (cases[0].Order_Tickets__c != true) {
            update new Case(Id = cases[0].Id, Order_Tickets__c = true);
        }
        return cases[0].Id;
    }

    private static Id idFrom(Object raw, String label) {
        if (raw == null) {
            throw new AuraHandledException(label + ' is required.');
        }
        try {
            return (Id) String.valueOf(raw);
        } catch (System.StringException e) {
            throw new AuraHandledException(label + ' is not a valid Id.');
        }
    }

    // Numbers cross the Aura boundary as Integer/Long/Double/Decimal depending on their shape —
    // a bare (Decimal) cast throws on some of them, so route through String.
    private static Decimal decimalFrom(Object raw, String label) {
        if (raw == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(raw));
        } catch (Exception e) {
            throw new AuraHandledException(label + ' is not a valid number.');
        }
    }
}