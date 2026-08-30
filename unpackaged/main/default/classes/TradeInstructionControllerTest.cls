/**
 * Tests for TradeInstructionController: the wizard's strategy-sleeve write-through
 * (Order_Ticket__c + basis-carrying Order__c rows), the current-instructions read-back that seeds
 * an Update DMS Instructions interview, and the active-strategy options query. Also exercises the
 * Allocation_TriggerHandler snapshot copy of Funding_Basis__c.
 */
@isTest
private class TradeInstructionControllerTest {
    @testSetup
    static void setup() {
        // Funding_Basis__c's FLS is granted only through the wizard permset (no profile carries
        // it), so the tests hold the same grant their subject depends on. Both classes are pinned
        // below API v67 — v67 runs Apex in user mode by default, and without this FLS every read
        // or write of the field fails ("fields being inaccessible" / tmpVar1 QueryException).
        // runAs keeps the setup-object DML clear of the data DML below.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet wizardPermSet = [
                SELECT Id FROM PermissionSet WHERE Name = 'Envelope_Wizard_Community' LIMIT 1
            ];
            List<PermissionSetAssignment> existing = [
                SELECT Id FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :wizardPermSet.Id
            ];
            if (existing.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = UserInfo.getUserId(),
                    PermissionSetId = wizardPermSet.Id
                );
            }
        }
        insert new Financial_Account__c(Name = 'Wizard FA');
        insert new Envelope__c(Name = 'Test Envelope', Status__c = 'In Progress');
        // Classifications drive which basis each strategy may be funded on, through the
        // Sleeve_Basis_Rule__mdt rule table: Model Allocation → Percent Only, Structured Note →
        // Dollar Only, Model Exclusion → Either. 'Unclassified' is left blank on purpose to cover
        // the Default rule, and 'Blank Status' covers a live strategy that carries no Status at all —
        // several real ones don't, including the alternative sleeve this feature exists for.
        insert new List<Strategy__c>{
            new Strategy__c(
                Name = 'Core Equity',
                Status__c = 'Active',
                Strategy_Code__c = 'CE',
                Sleeve_Classification__c = 'Model Allocation'
            ),
            new Strategy__c(
                Name = 'Structured Note A',
                Status__c = 'Active',
                Strategy_Code__c = 'SN',
                Structured_Note__c = true,
                Sleeve_Classification__c = 'Structured Note'
            ),
            new Strategy__c(
                Name = 'Model Exclusion Sleeve',
                Status__c = 'Active',
                Strategy_Code__c = 'EX',
                Sleeve_Classification__c = 'Model Exclusion'
            ),
            new Strategy__c(Name = 'Unclassified Sleeve', Status__c = 'Active', Strategy_Code__c = 'UC'),
            new Strategy__c(Name = 'Blank Status Sleeve', Strategy_Code__c = 'BS'),
            new Strategy__c(Name = 'Retired Strategy', Status__c = 'Inactive', Strategy_Code__c = 'RS')
        };
    }

    private static Id faId() {
        return [SELECT Id FROM Financial_Account__c LIMIT 1].Id;
    }

    private static Id envelopeId() {
        return [SELECT Id FROM Envelope__c LIMIT 1].Id;
    }

    private static Id strategyId(String code) {
        return [SELECT Id FROM Strategy__c WHERE Strategy_Code__c = :code LIMIT 1].Id;
    }

    private static Map<String, Object> row(Id strategy, String basis, Decimal value) {
        return new Map<String, Object>{ 'strategyId' => strategy, 'basis' => basis, 'value' => value };
    }

    private static Map<String, Object> payload(Id caseId, List<Object> rows) {
        return new Map<String, Object>{
            'envelopeId' => envelopeId(),
            'financialAccountId' => faId(),
            'caseId' => caseId,
            'typeOfRequest' => caseId == null ? 'New DMS Instructions' : 'Update DMS Instructions',
            'expectedAccountValue' => 100000,
            'advisorNotes' => 'Structured note is a fixed carve-out.',
            'strategies' => rows
        };
    }

    /**
     * Seed the rule table this class asserts against.
     *
     * Custom metadata cannot be inserted in a test, so a test left to itself reads whatever
     * Sleeve_Basis_Rule__mdt happens to say in the org it runs in — which is live configuration that
     * this feature exists to let people change. Every basis assertion below is written against this
     * map, so restricting or unrestricting a real sleeve can no longer break the suite.
     */
    private static void seedRules() {
        TradeInstructionController.basisRules = new Map<String, String>{
            'Model Allocation' => 'Percent Only',
            'Structured Note' => 'Dollar Only',
            'Model Exclusion' => 'Either',
            'Default' => 'Percent Only'
        };
        TradeInstructionController.exclusionRules = new Map<String, Boolean>{
            'Model Exclusion' => true
        };
    }

    @isTest
    static void getStrategyOptionsKeepsBlankStatusAndResolvesTheAllowedBasis() {
        seedRules();
        Test.startTest();
        List<Map<String, Object>> options = TradeInstructionController.getStrategyOptions();
        Test.stopTest();

        Map<String, Map<String, Object>> byName = new Map<String, Map<String, Object>>();
        for (Map<String, Object> option : options) {
            byName.put((String) option.get('name'), option);
        }
        Assert.isFalse(
            byName.containsKey('Retired Strategy'),
            'An explicitly Inactive strategy must not be offered.'
        );
        Assert.isTrue(
            byName.containsKey('Blank Status Sleeve'),
            'A strategy with no Status is live, not retired, and must still be offered.'
        );
        Assert.areEqual('Percent Only', byName.get('Core Equity').get('allowedBasis'));
        Assert.areEqual('Dollar Only', byName.get('Structured Note A').get('allowedBasis'));
        Assert.areEqual('Either', byName.get('Model Exclusion Sleeve').get('allowedBasis'));
        Assert.areEqual(
            'Percent Only',
            byName.get('Unclassified Sleeve').get('allowedBasis'),
            'An unclassified strategy follows the Default rule.'
        );
        // The exclusion flag rides the same rule table: configured classifications read true,
        // everything else — including the Default fallback with no exclusion rule — reads false.
        Assert.areEqual(true, byName.get('Model Exclusion Sleeve').get('excluded'));
        Assert.areEqual(false, byName.get('Core Equity').get('excluded'));
        Assert.areEqual(
            false,
            byName.get('Unclassified Sleeve').get('excluded'),
            'With no Default exclusion rule, an unclassified strategy is not excluded.'
        );
    }

    @isTest
    static void rejectsARowWhoseStrategyForbidsThatBasis() {
        seedRules();
        // A structured note is Dollar Only, so it cannot be filed as a percentage sleeve...
        try {
            TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
                row(strategyId('SN'), 'fixed-percentage', 100)
            }));
            Assert.fail('A percentage row for a Dollar Only strategy must be rejected.');
        } catch (AuraHandledException expected) {
        }
        // ...and a model allocation is Percent Only, so it cannot be filed as a dollar sleeve.
        try {
            TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
                row(strategyId('CE'), 'fixed-dollar', 25000)
            }));
            Assert.fail('A dollar row for a Percent Only strategy must be rejected.');
        } catch (AuraHandledException expected) {
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Order_Ticket__c],
            'Nothing persists from a payload the rule forbids.');
    }

    @isTest
    static void acceptsEitherStrategyOnBothBases() {
        seedRules();
        Test.startTest();
        Id dollarTicket = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('EX'), 'fixed-dollar', 25000),
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Test.stopTest();

        List<Order__c> sleeves = [
            SELECT Funding_Basis__c FROM Order__c WHERE Order_Ticket__c = :dollarTicket
        ];
        Assert.areEqual(2, sleeves.size(), 'An Either strategy is accepted as a dollar sleeve.');
    }

    @isTest
    static void saveCreatesTicketWithBasisRows() {
        seedRules();
        Test.startTest();
        Id ticketId = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('SN'), 'fixed-dollar', 25000),
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Test.stopTest();

        Order_Ticket__c ticket = [
            SELECT Type_of_Request__c, Status__c, Incomplete_Record__c, Expected_Account_Value__c,
                Advisor_Notes__c, Flow_Interview_ID__c, Wizard_Financial_Account__c, Case__c
            FROM Order_Ticket__c
            WHERE Id = :ticketId
        ];
        Assert.areEqual('New DMS Instructions', ticket.Type_of_Request__c);
        Assert.areEqual('New', ticket.Status__c);
        Assert.isFalse(ticket.Incomplete_Record__c);
        Assert.areEqual(100000, ticket.Expected_Account_Value__c);
        Assert.areEqual(String.valueOf(envelopeId()), ticket.Flow_Interview_ID__c);
        Assert.areEqual(faId(), ticket.Wizard_Financial_Account__c);
        Assert.isNull(ticket.Case__c);

        // Ordered by strategy name: Core Equity (percent) then Structured Note A (dollar).
        List<Order__c> sleeves = [
            SELECT Strategy__c, Funding_Basis__c, Initial_Funding_Amount__c,
                Initial_Funding_Percentage__c, Total_Initial_Funding_Amount__c
            FROM Order__c
            WHERE Order_Ticket__c = :ticketId
            ORDER BY Strategy__r.Name
        ];
        Assert.areEqual(2, sleeves.size());
        // Percent sleeve: percentage of the remainder only.
        Assert.areEqual('Percent', sleeves[0].Funding_Basis__c);
        Assert.areEqual(100, sleeves[0].Initial_Funding_Percentage__c);
        Assert.isNull(sleeves[0].Initial_Funding_Amount__c);
        Assert.isNull(sleeves[0].Total_Initial_Funding_Amount__c);
        // Dollar sleeve: amount + the legacy dollar-basis marker, no percentage.
        Assert.areEqual('Dollar', sleeves[1].Funding_Basis__c);
        Assert.areEqual(25000, sleeves[1].Initial_Funding_Amount__c);
        Assert.areEqual(100000, sleeves[1].Total_Initial_Funding_Amount__c);
        Assert.isNull(sleeves[1].Initial_Funding_Percentage__c);
    }

    @isTest
    static void resaveReplacesRowsOnTheSameTicket() {
        seedRules();
        Id first = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('SN'), 'fixed-dollar', 25000),
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));

        Map<String, Object> second = payload(null, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        });
        second.put('expectedAccountValue', 200000);

        Test.startTest();
        Id resaved = TradeInstructionController.saveTradeInstructions(second);
        Test.stopTest();

        Assert.areEqual(first, resaved, 'A re-submit must reuse the still-New ticket.');
        Assert.areEqual(1, [SELECT COUNT() FROM Order_Ticket__c]);
        List<Order__c> sleeves = [SELECT Funding_Basis__c FROM Order__c WHERE Order_Ticket__c = :resaved];
        Assert.areEqual(1, sleeves.size(), 'Sleeve rows are replaced, not stacked.');
        Assert.areEqual(200000, [SELECT Expected_Account_Value__c FROM Order_Ticket__c WHERE Id = :resaved].Expected_Account_Value__c);
    }

    @isTest
    static void caseLinkedTicketIsKeyedApartFromTheAccountTicket() {
        seedRules();
        Case dmsCase = new Case(Subject = 'Update Trade Instructions', Origin = 'Wizard');
        insert dmsCase;

        Test.startTest();
        Id accountTicket = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Id caseTicket = TradeInstructionController.saveTradeInstructions(payload(dmsCase.Id, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Test.stopTest();

        Assert.areNotEqual(accountTicket, caseTicket, 'The case request is its own ticket.');
        Order_Ticket__c ticket = [SELECT Case__c, Type_of_Request__c FROM Order_Ticket__c WHERE Id = :caseTicket];
        Assert.areEqual(dmsCase.Id, ticket.Case__c);
        Assert.areEqual('Update DMS Instructions', ticket.Type_of_Request__c);
    }

    @isTest
    static void resolvesTheAccountOpeningCaseWhenNoCaseIdIsGiven() {
        seedRules();
        Case openingCase = new Case(
            Wizard_Financial_Account__c = faId(),
            Origin = 'Wizard',
            Type = 'Account Opening',
            Subject = 'New Financial Account',
            Status = 'New'
        );
        insert openingCase;

        Test.startTest();
        Id ticketId = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Test.stopTest();

        Assert.areEqual(openingCase.Id, [SELECT Case__c FROM Order_Ticket__c WHERE Id = :ticketId].Case__c,
            'A new account/DPI ticket must link to its own Account Opening Case when the client sends no caseId.');
        Assert.isTrue([SELECT Order_Tickets__c FROM Case WHERE Id = :openingCase.Id].Order_Tickets__c,
            'The Account Opening Case must be flagged once its ticket is linked, so its related-ticket surface lights up.');
    }

    @isTest
    static void resubmitWithNoCaseIdReusesTheSameResolvedTicket() {
        seedRules();
        Case openingCase = new Case(
            Wizard_Financial_Account__c = faId(),
            Origin = 'Wizard',
            Type = 'Account Opening',
            Subject = 'New Financial Account',
            Status = 'New'
        );
        insert openingCase;

        Id first = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));

        Test.startTest();
        Id resaved = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Test.stopTest();

        Assert.areEqual(first, resaved,
            'A retried submit must resolve the same Case every time and update the same still-New ticket, not stack a duplicate.');
        Assert.areEqual(1, [SELECT COUNT() FROM Order_Ticket__c]);
    }

    @isTest
    static void leavesTheTicketUnlinkedWhenTheAccountHasNoAccountOpeningCase() {
        seedRules();
        // A Case of a different Type on the same account (e.g. an unrelated servicing request)
        // must never be picked up in place of the Account Opening Case.
        insert new Case(
            Wizard_Financial_Account__c = faId(),
            Origin = 'Wizard',
            Type = 'Third Party Money Movement',
            Status = 'New'
        );

        Test.startTest();
        Id ticketId = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Test.stopTest();

        Assert.isNull([SELECT Case__c FROM Order_Ticket__c WHERE Id = :ticketId].Case__c,
            'An account with no Account Opening Case must resolve to no Case, same as before this method existed.');
    }

    @isTest
    static void anExplicitCaseIdIsNeverOverriddenByTheResolvedAccountOpeningCase() {
        seedRules();
        Case openingCase = new Case(
            Wizard_Financial_Account__c = faId(),
            Origin = 'Wizard',
            Type = 'Account Opening',
            Subject = 'New Financial Account',
            Status = 'New'
        );
        insert openingCase;
        Case dmsCase = new Case(Subject = 'Update Trade Instructions', Origin = 'Wizard');
        insert dmsCase;

        Test.startTest();
        Id ticketId = TradeInstructionController.saveTradeInstructions(payload(dmsCase.Id, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        Test.stopTest();

        Assert.areEqual(dmsCase.Id, [SELECT Case__c FROM Order_Ticket__c WHERE Id = :ticketId].Case__c,
            'An explicit caseId from the client is authoritative and must win over the account\'s own Account Opening Case.');
    }

    @isTest
    static void rejectsBadPayloads() {
        seedRules();
        try {
            TradeInstructionController.saveTradeInstructions(null);
            Assert.fail('A null payload must throw.');
        } catch (AuraHandledException expected) {
        }
        try {
            TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>()));
            Assert.fail('An empty sleeve list must throw.');
        } catch (AuraHandledException expected) {
        }
        try {
            TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
                row(strategyId('CE'), 'per-share', 100)
            }));
            Assert.fail('An unknown basis must throw.');
        } catch (AuraHandledException expected) {
        }
        try {
            TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
                row(strategyId('CE'), 'fixed-percentage', 0)
            }));
            Assert.fail('A non-positive value must throw.');
        } catch (AuraHandledException expected) {
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Order_Ticket__c], 'Nothing persists from a rejected payload.');
    }

    @isTest
    static void readsBackFromTheLatestTicketThenTheAllocationSnapshot() {
        seedRules();
        Id ticketId = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('SN'), 'fixed-dollar', 25000),
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));

        // No allocation yet — the newest ticket's rows seed the interview.
        Map<String, Object> fromTicket = TradeInstructionController.getCurrentTradeInstructions(faId());
        Assert.areEqual(100000, fromTicket.get('expectedAccountValue'));
        Assert.areEqual(2, ((List<Map<String, Object>>) fromTicket.get('strategies')).size());

        // Completing the request snapshots the rows (Allocation_TriggerHandler) — basis included.
        insert new Allocation__c(
            Wizard_Financial_Account__c = faId(),
            Current_Allocation__c = true,
            Request_Allocation_Originated_From__c = ticketId
        );

        Test.startTest();
        Map<String, Object> fromSnapshot = TradeInstructionController.getCurrentTradeInstructions(faId());
        Test.stopTest();

        List<Map<String, Object>> rows = (List<Map<String, Object>>) fromSnapshot.get('strategies');
        Assert.areEqual(100000, fromSnapshot.get('expectedAccountValue'),
            'Expected value reads back from the ticket that produced the allocation.');
        Assert.areEqual(2, rows.size());
        // Ordered by strategy name: Core Equity (percent) then Structured Note A (dollar).
        Assert.areEqual('fixed-percentage', rows[0].get('type'));
        Assert.areEqual(100, rows[0].get('fundingPercent'));
        Assert.areEqual('fixed-dollar', rows[1].get('type'));
        Assert.areEqual(25000, rows[1].get('fundingAmount'));
    }

    @isTest
    static void recoversTheExpectedValueForAnAllPercentageAllocation() {
        seedRules();
        // No dollar rows, so no row carries Total_Initial_Funding_Amount__c — the expected value has
        // to come from the originating ticket or the seeded interview opens without one.
        Id ticketId = TradeInstructionController.saveTradeInstructions(payload(null, new List<Object>{
            row(strategyId('CE'), 'fixed-percentage', 100)
        }));
        insert new Allocation__c(
            Wizard_Financial_Account__c = faId(),
            Current_Allocation__c = true,
            Request_Allocation_Originated_From__c = ticketId
        );

        Test.startTest();
        Map<String, Object> current = TradeInstructionController.getCurrentTradeInstructions(faId());
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Allocation_Strategy__c WHERE Initial_Funding_Amount__c = null],
            'The snapshot row carries no dollar marker.');
        Assert.areEqual(100000, current.get('expectedAccountValue'),
            'Expected value still reads back, from the originating ticket.');
    }

    @isTest
    static void legacyRowsWithoutABasisInferDollarFromTheMarkerShape() {
        seedRules();
        Order_Ticket__c ticket = new Order_Ticket__c(
            Wizard_Financial_Account__c = faId(),
            Status__c = 'New',
            Expected_Account_Value__c = 50000
        );
        insert ticket;
        insert new Order__c(
            Order_Ticket__c = ticket.Id,
            Strategy__c = strategyId('SN'),
            Initial_Funding_Amount__c = 50000,
            Total_Initial_Funding_Amount__c = 50000
        );

        Test.startTest();
        Map<String, Object> current = TradeInstructionController.getCurrentTradeInstructions(faId());
        Test.stopTest();

        List<Map<String, Object>> rows = (List<Map<String, Object>>) current.get('strategies');
        Assert.areEqual('fixed-dollar', rows[0].get('type'),
            'A pre-basis row carrying an amount and no percentage reads as dollar.');
    }
}