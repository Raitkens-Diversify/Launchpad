/**
 * Tests for EnvelopeActionCaseController's action-case routers — one create case per action type the
 * envelope wizard's cases group can raise, plus the generic update path the metadata-driven interview
 * writes through. Covers both parents: saveAccountActionCase for the actions raised on a submitted
 * Financial Account, and saveMemberActionCase for the change requests raised on a submitted household
 * member. Relies on the org's Wizard_Flow_Values__mdt row for the account-servicing Case record type
 * and on the Account Servicing Principal Review record type for the member cases.
 */
@isTest
private class EnvelopeActionCaseControllerTest {
    @testSetup
    static void setup() {
        // An account on a non-DMS platform, so a Change Management Style case has a previous style
        // distinct from the DMS the trade-instruction seed sets.
        insert new Financial_Account__c(Name = 'Wizard FA', Managed_Account_Platform__c = 'AMS');
        insert new Envelope__c(Name = 'Test Envelope', Status__c = 'In Progress');
        // A member carrying values the original snapshot can pick up.
        insert new Account(Name = 'Wizard Member', BillingCity = 'Old Town', Classification__c = 'Unclassified');
    }

    private static Id faId() {
        return [SELECT Id FROM Financial_Account__c LIMIT 1].Id;
    }

    private static Id envelopeId() {
        return [SELECT Id FROM Envelope__c LIMIT 1].Id;
    }

    @isTest
    static void dmsInstructionCaseIsAttributedAndLinked() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Manage DMS Instructions');
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(caseId), 'The router must create and return a Case.');
        Case created = [
            SELECT Type, Subject, Description, Origin, Status, Order_Tickets__c,
                Management_Style__c, Wizard_Financial_Account__c, RecordTypeId
            FROM Case
            WHERE Id = :caseId
        ];
        Assert.areEqual('Update DMS Instructions', created.Type);
        Assert.areEqual('Update Trade Instructions for Wizard FA', created.Subject);
        Assert.areEqual('Wizard', created.Origin);
        Assert.areEqual('New', created.Status);
        Assert.isTrue(created.Order_Tickets__c, 'The DMS case flags its order-ticket workload.');
        Assert.areEqual('DMS', created.Management_Style__c);
        Assert.areEqual(faId(), created.Wizard_Financial_Account__c);
        Assert.isNotNull(created.RecordTypeId, 'Record type comes from Wizard_Flow_Values__mdt.');

        List<Envelope_Content__c> links = [
            SELECT Envelope__c FROM Envelope_Content__c WHERE Case__c = :caseId
        ];
        Assert.areEqual(1, links.size(), 'The case joins the envelope through Envelope_Content__c.');
        Assert.areEqual(envelopeId(), links[0].Envelope__c);
    }

    @isTest
    static void dmsInstructionUpdateReturnsTheExistingCase() {
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Manage DMS Instructions');

        Test.startTest();
        String updated = EnvelopeActionCaseController.saveAccountActionCase(
            faId(),
            new Map<String, Object>{ 'Id' => caseId },
            envelopeId(),
            'Manage DMS Instructions'
        );
        Test.stopTest();

        Assert.areEqual(caseId, updated, 'An update call round-trips the existing id.');
        Assert.areEqual(1, [SELECT COUNT() FROM Case WHERE Type = 'Update DMS Instructions'],
            'No duplicate case is created on update.');
        Assert.areEqual(1, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId],
            'No duplicate envelope link is created on update.');
    }

    // Additional Funding used to insert a bare Case: no record type, no account, no envelope link.
    @isTest
    static void additionalFundingCaseIsAttributedAndLinked() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Additional Funding');
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(caseId), 'The router must create and return a Case.');
        Case created = [
            SELECT Type, Subject, Origin, Status, Wizard_Financial_Account__c, RecordTypeId
            FROM Case
            WHERE Id = :caseId
        ];
        Assert.areEqual('Additional Funding', created.Type);
        Assert.areEqual('Additional Funding', created.Subject);
        Assert.areEqual('Wizard', created.Origin);
        Assert.areEqual('New', created.Status);
        Assert.areEqual(faId(), created.Wizard_Financial_Account__c,
            'The case points back at the account it services.');
        Assert.isNotNull(created.RecordTypeId, 'Record type comes from Wizard_Flow_Values__mdt.');

        List<Envelope_Content__c> links = [
            SELECT Envelope__c FROM Envelope_Content__c WHERE Case__c = :caseId
        ];
        Assert.areEqual(1, links.size(), 'The case joins the envelope through Envelope_Content__c.');
        Assert.areEqual(envelopeId(), links[0].Envelope__c);
    }

    // Third Party Money Movement was removed from ACTION_CASE_SPECS (it is no longer one of the
    // four registered account action types), so it now falls through the same unrouted path as any
    // other unrecognized sourceId. This replaces the old assertion that a Case was created for it,
    // which stopped being true once the spec was retired and started failing with a
    // "List has no rows for assignment to SObject" query error on the now-empty caseId.
    @isTest
    static void thirdPartyMoneyMovementIsNoLongerARoutableAction() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Third Party Money Movement');
        Test.stopTest();

        Assert.areEqual('', caseId,
            'Third Party Money Movement is no longer a registered action case spec.');
    }

    // The closure reason is an interview answer, not create-time input. The create path used to read
    // it from formData, which the wizard never sends, so the subject read 'Account Closure - null'.
    @isTest
    static void accountClosureCaseIsCreatedWithoutInterviewAnswers() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Account Closure');
        Test.stopTest();

        Case created = [
            SELECT Type, Subject, Origin, Status, Account_Closure_Reason__c,
                Wizard_Financial_Account__c, RecordTypeId
            FROM Case
            WHERE Id = :caseId
        ];
        Assert.areEqual('Account Closure', created.Type);
        Assert.areEqual('Account Closure', created.Subject,
            'The subject must not carry a null reason.');
        Assert.areEqual('Wizard', created.Origin);
        Assert.areEqual('New', created.Status);
        Assert.isNull(created.Account_Closure_Reason__c,
            'The reason arrives later, through the metadata-driven update.');
        Assert.areEqual(faId(), created.Wizard_Financial_Account__c);
        Assert.isNotNull(created.RecordTypeId, 'Record type comes from Wizard_Flow_Values__mdt.');

        Assert.areEqual(1, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId],
            'The case joins the envelope through Envelope_Content__c.');
    }

    @isTest
    static void changeManagementStyleCaseRecordsThePreviousPlatform() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Change Management Style');
        Test.stopTest();

        Case created = [
            SELECT Type, Subject, Origin, Status, Order_Tickets__c, Management_Style__c,
                Previous_Management_Style__c, Wizard_Financial_Account__c, RecordTypeId
            FROM Case
            WHERE Id = :caseId
        ];
        Assert.areEqual('Change Management Style', created.Type);
        Assert.areEqual('Change Management Style for Wizard FA', created.Subject);
        Assert.areEqual('Wizard', created.Origin);
        Assert.areEqual('New', created.Status);
        Assert.isTrue(created.Order_Tickets__c, 'The case flags its order-ticket workload.');
        Assert.areEqual('AMS', created.Previous_Management_Style__c,
            'The account moves off its current platform, so the case records what it was.');
        Assert.areEqual('DMS', created.Management_Style__c,
            'DMS is the create-time default; a configured interview answer overwrites it.');
        Assert.areEqual(faId(), created.Wizard_Financial_Account__c);
        Assert.isNotNull(created.RecordTypeId, 'Record type comes from Wizard_Flow_Values__mdt.');

        Assert.areEqual(1, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId],
            'The case joins the envelope through Envelope_Content__c.');
    }

    // The update path is type-agnostic: the same call writes any Case field the metadata configures,
    // whichever action type raised the case.
    @isTest
    static void interviewAnswerWritesToANonAdditionalFundingType() {
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Account Closure');

        Test.startTest();
        EnvelopeActionCaseController.saveAccountActionCase(
            faId(),
            new Map<String, Object>{ 'Id' => caseId, 'Account_Closure_Reason__c' => 'Other' },
            envelopeId(),
            'Account Closure'
        );
        Test.stopTest();

        Assert.areEqual('Other',
            [SELECT Account_Closure_Reason__c FROM Case WHERE Id = :caseId].Account_Closure_Reason__c,
            'A schema-configured answer reaches the Case for every action type.');
    }

    // The interview's answers arrive keyed by real Case field API names. A payload carrying an Id is
    // an update and never reaches the per-type create branches.
    @isTest
    static void payloadWithIdUpdatesTheCaseByFieldApiName() {
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Additional Funding');

        Test.startTest();
        String returned = EnvelopeActionCaseController.saveAccountActionCase(
            faId(),
            new Map<String, Object>{ 'Id' => caseId, 'Description' => 'Interview answer' },
            envelopeId(),
            'Additional Funding'
        );
        Test.stopTest();

        Assert.areEqual(caseId, returned, 'An update round-trips the existing id.');
        Assert.areEqual('Interview answer',
            [SELECT Description FROM Case WHERE Id = :caseId].Description);
        Assert.areEqual(1, [SELECT COUNT() FROM Case WHERE Type = 'Additional Funding'],
            'No second case is created on update.');
        Assert.areEqual(1, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId],
            'No duplicate envelope link is created on update.');
    }

    // Keys that are not Case fields (the interview's composite draft keys) are ignored rather than
    // failing the write.
    @isTest
    static void updateIgnoresKeysThatAreNotCaseFields() {
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Additional Funding');

        Test.startTest();
        EnvelopeActionCaseController.saveAccountActionCase(
            faId(),
            new Map<String, Object>{
                'Id' => caseId,
                'Description' => 'Kept',
                'tradeInstructions' => 'dropped'
            },
            envelopeId(),
            'Additional Funding'
        );
        Test.stopTest();

        Assert.areEqual('Kept', [SELECT Description FROM Case WHERE Id = :caseId].Description);
    }

    @isTest
    static void blankSourceIdThrows() {
        try {
            EnvelopeActionCaseController.saveAccountActionCase(
                faId(), new Map<String, Object>(), envelopeId(), '');
            Assert.fail('A blank sourceId must throw.');
        } catch (AuraHandledException expected) {
        }
    }

    @isTest
    static void unknownSourceIdReturnsEmpty() {
        String result = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Not A Real Action');
        Assert.areEqual('', result, 'Unrouted actions fall through to an empty id.');
    }

    // ---------------------------------------------------------
    // Member action items
    // ---------------------------------------------------------

    private static Id memberId() {
        return [SELECT Id FROM Account WHERE Name = 'Wizard Member' LIMIT 1].Id;
    }

    @isTest
    static void memberActionCaseIsAttributedAndLinked() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveMemberActionCase(
            memberId(), envelopeId(), 'editIndividual');
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(caseId), 'The router must create and return a Case.');
        Case created = [
            SELECT Type, Subject, Description, Origin, Status, AccountId,
                Needs_Principal_Review__c, DoNotCalc__c, RecordType.DeveloperName,
                Wizard_Financial_Account__c
            FROM Case
            WHERE Id = :caseId
        ];
        Assert.areEqual('Edit Individual', created.Type);
        Assert.areEqual('Edit Individual for Wizard Member', created.Subject);
        Assert.areEqual('Wizard', created.Origin);
        Assert.areEqual('New', created.Status);
        Assert.areEqual(memberId(), created.AccountId,
            'A member action points at the member itself, not the household.');
        Assert.isNull(created.Wizard_Financial_Account__c,
            'A member action services no financial account.');
        Assert.isTrue(created.Needs_Principal_Review__c,
            'A change to a submitted member always needs a principal review.');
        Assert.isTrue(created.DoNotCalc__c);
        Assert.areEqual('Account_Servicing_Principal_Review', created.RecordType.DeveloperName);

        List<Envelope_Content__c> links = [
            SELECT Envelope__c FROM Envelope_Content__c WHERE Case__c = :caseId
        ];
        Assert.areEqual(1, links.size(), 'The case joins the envelope through Envelope_Content__c.');
        Assert.areEqual(envelopeId(), links[0].Envelope__c);
    }

    @isTest
    static void memberActionCaseSnapshotsTheMembersCurrentValues() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveMemberActionCase(
            memberId(), envelopeId(), 'editBusiness');
        Test.stopTest();

        Case created = [
            SELECT Type, Original_Physical_City__c, Proposed_Physical_City__c, Original_Name__c
            FROM Case
            WHERE Id = :caseId
        ];
        Assert.areEqual('Edit Business', created.Type);
        Assert.areEqual('Old Town', created.Original_Physical_City__c,
            'The baseline is taken from the member at the moment the request is raised.');
        Assert.areEqual('Wizard Member', created.Original_Name__c,
            'Every mapped field the member carries is snapshotted, not just a chosen few.');
        Assert.isNull(created.Proposed_Physical_City__c,
            'Nothing has been proposed yet, so the proposed half stays empty.');
    }

    // The snapshot is the baseline every later edit is diffed against, so a field the member has left
    // empty must snapshot as an empty original rather than being skipped — a missing baseline would
    // make the first save read the prefilled value as a change.
    @isTest
    static void memberActionCaseSnapshotsFieldsTheMemberLeftEmpty() {
        String caseId = EnvelopeActionCaseController.saveMemberActionCase(
            memberId(), envelopeId(), 'editIndividual');

        Test.startTest();
        WizardEnvelopeStateService.saveProposedCaseFields(
            caseId,
            memberId(),
            new Map<String, Object>{ 'BillingCity' => 'Old Town' }
        );
        Test.stopTest();

        Case updated = [
            SELECT Original_Physical_City__c, Proposed_Physical_City__c
            FROM Case WHERE Id = :caseId
        ];
        Assert.areEqual('Old Town', updated.Original_Physical_City__c);
        Assert.isNull(updated.Proposed_Physical_City__c,
            'Resending the member\'s own value is not a proposed change.');
    }

    @isTest
    static void everyMemberActionTypeIsRoutable() {
        Map<String, String> expectedTypes = new Map<String, String>{
            'editIndividual' => 'Edit Individual',
            'editBusiness' => 'Edit Business',
            'editTrust' => 'Edit Trust',
            'editRetirementPlan' => 'Edit Retirement Plan'
        };

        Test.startTest();
        for (String token : expectedTypes.keySet()) {
            String caseId = EnvelopeActionCaseController.saveMemberActionCase(
                memberId(), envelopeId(), token);
            Assert.areEqual(expectedTypes.get(token),
                [SELECT Type FROM Case WHERE Id = :caseId].Type,
                'Each catalog token maps to its own Case Type.');
        }
        Test.stopTest();
    }

    @isTest
    static void memberActionWithoutAnEnvelopeIsStillCreated() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.saveMemberActionCase(
            memberId(), null, 'editIndividual');
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(caseId), 'The case is created even with no envelope.');
        Assert.areEqual(0, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId],
            'With no envelope there is nothing to link it to.');
    }

    @isTest
    static void blankMemberSourceIdThrows() {
        try {
            EnvelopeActionCaseController.saveMemberActionCase(memberId(), envelopeId(), '');
            Assert.fail('A blank sourceId must throw.');
        } catch (AuraHandledException expected) {
        }
    }

    @isTest
    static void blankMemberIdThrows() {
        try {
            EnvelopeActionCaseController.saveMemberActionCase(null, envelopeId(), 'editIndividual');
            Assert.fail('A missing member must throw.');
        } catch (AuraHandledException expected) {
        }
    }

    // Unlike the account router, an unroutable member token throws: returning an empty id would
    // leave the client holding an action item with no record behind it.
    @isTest
    static void unknownMemberSourceIdThrows() {
        try {
            EnvelopeActionCaseController.saveMemberActionCase(
                memberId(), envelopeId(), 'editSomethingElse');
            Assert.fail('An unrouted member action must throw.');
        } catch (AuraHandledException expected) {
        }
    }
}