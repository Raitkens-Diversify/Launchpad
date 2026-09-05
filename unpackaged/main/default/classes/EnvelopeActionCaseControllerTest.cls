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

    @isTest
    static void memberActionCaseThrowsWhenMemberRecordIsGone() {
        Account toDelete = new Account(Name = 'Ghost Member', Type = 'Prospect');
        insert toDelete;
        Id ghostId = toDelete.Id;
        delete toDelete;

        Test.startTest();
        try {
            EnvelopeActionCaseController.saveMemberActionCase(ghostId, envelopeId(), 'editIndividual');
            Assert.fail('A member record that no longer exists must throw.');
        } catch (AuraHandledException expected) {
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------
    // updateActionCaseFields: coercion and DML failure paths
    // ---------------------------------------------------------

    @isTest
    static void updateActionCaseFieldsCoercionFailureReportsFieldName() {
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Account Closure');

        Test.startTest();
        try {
            EnvelopeActionCaseController.saveAccountActionCase(
                faId(),
                new Map<String, Object>{ 'Id' => caseId, 'Account_Closure_End_Date__c' => 'not-a-date' },
                envelopeId(),
                'Account Closure'
            );
            Assert.fail('A field value that cannot be coerced must be reported, not silently dropped.');
        } catch (AuraHandledException expected) {
            // AuraHandledException.getMessage() always returns 'Script-thrown exception' unless
            // setMessage() is called explicitly — a platform limitation, not a bug here — so only
            // the throw itself (not its text) can be asserted from Apex.
        }
        Test.stopTest();
    }

    @isTest
    static void updateActionCaseFieldsDmlFailureIsWrapped() {
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Account Closure');

        Test.startTest();
        try {
            EnvelopeActionCaseController.saveAccountActionCase(
                faId(),
                new Map<String, Object>{ 'Id' => caseId, 'Account_Closure_Reason__c' => 'NotARealReason' },
                envelopeId(),
                'Account Closure'
            );
            Assert.fail('An invalid restricted-picklist value must fail the update.');
        } catch (AuraHandledException expected) {
            // getMessage() is masked to 'Script-thrown exception' by the platform; the DML failure
            // path itself is what this test covers.
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------
    // createManagedPlatformCase
    // ---------------------------------------------------------

    @isTest
    static void managedPlatformCaseNonDmsCreatesCaseAndUpdatesPlatform() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.createManagedPlatformCase(
            faId(),
            new Map<String, Object>{ 'managedAccountPlatform' => 'AMS (Wrap)' },
            envelopeId()
        );
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(caseId), 'The router must create and return a Case.');
        Case created = [
            SELECT Type, Subject, Management_Style__c, Previous_Management_Style__c, Order_Tickets__c
            FROM Case WHERE Id = :caseId
        ];
        Assert.areEqual('Change Management Style', created.Type);
        Assert.areEqual('AMS (Wrap)', created.Management_Style__c);
        Assert.areEqual('AMS', created.Previous_Management_Style__c,
            'The previous style is the account platform before this call.');
        Assert.isFalse(created.Order_Tickets__c,
            'A non-DMS platform does not open the DMS order-ticket workload.');
        Assert.areEqual('AMS (Wrap)',
            [SELECT Managed_Account_Platform__c FROM Financial_Account__c WHERE Id = :faId()]
                .Managed_Account_Platform__c,
            'The account moves onto the new platform.');
        Assert.areEqual(1, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId]);
    }

    // A DMS platform change also flips Household__c.Has_FAs_that_are_DMS__c
    // (Financial_Account_TriggerHandler.setDMSOnHousehold), which requires the Financial Account to
    // carry a real Household__c — the shared @testSetup account has none, so the DMS-path tests use
    // their own Financial Account with a household attached.
    private static Id dmsCapableFaId() {
        Account household = new Account(Name = 'DMS Household', Type = 'Prospect');
        insert household;
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'DMS FA', Managed_Account_Platform__c = 'AMS', Household__c = household.Id
        );
        insert fa;
        return fa.Id;
    }

    @isTest
    static void managedPlatformCaseDmsWithBondLadderCapturesAddendumFields() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.createManagedPlatformCase(
            dmsCapableFaId(),
            new Map<String, Object>{
                'managedAccountPlatform' => 'DMS',
                'bondLadder' => true,
                'blCashWithdrawalSelection' => 'Coupon Only',
                'blAmount' => 5000.0,
                'blFrequency' => 'Monthly',
                'blOtherFrequency' => '',
                'blStartDate' => '2026-01-01',
                'blLiquidatePermission' => true,
                'blReinvestPermission' => false,
                'blCustomization' => 'Ladder notes'
            },
            envelopeId()
        );
        Test.stopTest();

        Case created = [
            SELECT Order_Tickets__c, Incomplete_Record__c, Bond_Ladder__c, Cash_Withdrawal_Selection__c,
                Cash_Withdrawal_Amount__c, DMS_Addendum_Frequency__c, DMS_Frequency_Start_Date__c,
                Permission_to_Liquidate__c, Permission_to_Reinvest__c, Special_Instructions__c
            FROM Case WHERE Id = :caseId
        ];
        Assert.isTrue(created.Order_Tickets__c, 'DMS opens the order-ticket workload.');
        Assert.isFalse(created.Incomplete_Record__c);
        Assert.isTrue(created.Bond_Ladder__c);
        Assert.areEqual('Coupon Only', created.Cash_Withdrawal_Selection__c);
        Assert.areEqual(5000.0, created.Cash_Withdrawal_Amount__c);
        Assert.areEqual('Monthly', created.DMS_Addendum_Frequency__c);
        Assert.areEqual(Date.valueOf('2026-01-01'), created.DMS_Frequency_Start_Date__c);
        Assert.isTrue(created.Permission_to_Liquidate__c);
        Assert.isFalse(created.Permission_to_Reinvest__c);
        Assert.areEqual('Ladder notes', created.Special_Instructions__c);
    }

    @isTest
    static void managedPlatformCaseDmsWithStcmCapturesAddendumFields() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.createManagedPlatformCase(
            dmsCapableFaId(),
            new Map<String, Object>{
                'managedAccountPlatform' => 'DMS (Wrap)',
                'stcm' => true,
                'stcmCashWithdrawalSelection' => 'Other',
                'stcmFrequency' => 'Quarterly',
                'stcmOtherFrequency' => '',
                'stcmStartDate' => '2026-02-01',
                'stcmLiquidatePermission' => false,
                'stcmReinvestPermission' => true,
                'stcmCustomization' => 'STCM notes',
                'stcmStrategyTerm' => 'Perpetual'
            },
            envelopeId()
        );
        Test.stopTest();

        Case created = [
            SELECT STCM__c, Cash_Withdrawal_Selection__c, DMS_Addendum_Frequency__c,
                DMS_Frequency_Start_Date__c, Permission_to_Liquidate__c, Permission_to_Reinvest__c,
                Special_Instructions__c, STCM_Strategy_Term__c
            FROM Case WHERE Id = :caseId
        ];
        Assert.isTrue(created.STCM__c);
        Assert.areEqual('Other', created.Cash_Withdrawal_Selection__c);
        Assert.areEqual('Quarterly', created.DMS_Addendum_Frequency__c);
        Assert.areEqual(Date.valueOf('2026-02-01'), created.DMS_Frequency_Start_Date__c);
        Assert.isFalse(created.Permission_to_Liquidate__c);
        Assert.isTrue(created.Permission_to_Reinvest__c);
        Assert.areEqual('STCM notes', created.Special_Instructions__c);
        Assert.areEqual('Perpetual', created.STCM_Strategy_Term__c);
    }

    @isTest
    static void managedPlatformCaseUpdateRoundTripsIdWithoutDuplicateLink() {
        String caseId = EnvelopeActionCaseController.createManagedPlatformCase(
            faId(), new Map<String, Object>{ 'managedAccountPlatform' => 'AMS' }, envelopeId());

        Test.startTest();
        String updated = EnvelopeActionCaseController.createManagedPlatformCase(
            faId(),
            new Map<String, Object>{ 'Id' => caseId, 'managedAccountPlatform' => 'OMS' },
            envelopeId()
        );
        Test.stopTest();

        Assert.areEqual(caseId, updated, 'An update call round-trips the existing id.');
        Assert.areEqual(1, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId],
            'No duplicate envelope link is created on update.');
    }

    @isTest
    static void managedPlatformCaseWrapsUnexpectedFailure() {
        Test.startTest();
        try {
            EnvelopeActionCaseController.createManagedPlatformCase(
                null, new Map<String, Object>{ 'managedAccountPlatform' => 'AMS' }, envelopeId());
            Assert.fail('A missing Financial Account must not silently succeed.');
        } catch (AuraHandledException expected) {
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------
    // createAccountClosureCase
    // ---------------------------------------------------------

    @isTest
    static void accountClosureClientTerminatedServicesCapturesEndDate() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.createAccountClosureCase(
            faId(),
            new Map<String, Object>{
                'accountClosureReason' => 'Client Terminated Services',
                'endDate' => '2026-03-01'
            },
            envelopeId()
        );
        Test.stopTest();

        Case created = [
            SELECT Type, Subject, Account_Closure_Reason__c, Account_Closure_End_Date__c
            FROM Case WHERE Id = :caseId
        ];
        Assert.areEqual('Account Closure', created.Type);
        Assert.areEqual('Account Closure - Client Terminated Services', created.Subject);
        Assert.areEqual('Client Terminated Services', created.Account_Closure_Reason__c);
        Assert.areEqual(Date.valueOf('2026-03-01'), created.Account_Closure_End_Date__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :caseId]);
    }

    @isTest
    static void accountClosureMissingEndDateThrows() {
        Test.startTest();
        try {
            EnvelopeActionCaseController.createAccountClosureCase(
                faId(),
                new Map<String, Object>{ 'accountClosureReason' => 'Client Terminated Services' },
                envelopeId()
            );
            Assert.fail('A missing required End Date must throw.');
        } catch (AuraHandledException expected) {
            // getMessage() is masked to 'Script-thrown exception' by the platform (see the coercion
            // test above); the throw itself is what this test covers.
        }
        Test.stopTest();
    }

    @isTest
    static void accountClosureInvalidEndDateThrows() {
        Test.startTest();
        try {
            EnvelopeActionCaseController.createAccountClosureCase(
                faId(),
                new Map<String, Object>{
                    'accountClosureReason' => 'Client Terminated Services',
                    'endDate' => 'not-a-date'
                },
                envelopeId()
            );
            Assert.fail('A malformed End Date must throw.');
        } catch (AuraHandledException expected) {
        }
        Test.stopTest();
    }

    // 'Terminated Services' (without 'Client') is not an active Account_Closure_Reason__c value in
    // this org - only 'Client Terminated Services' is (confirmed against the org's field describe).
    // Setting the reason to this legacy value fails the Case insert with a restricted-picklist
    // error, wrapped as an AuraHandledException. Documents current behavior; the branch that reads
    // 'additionalInformation' is otherwise unreachable through a valid save.
    @isTest
    static void accountClosureLegacyTerminatedServicesReasonFails() {
        Test.startTest();
        try {
            EnvelopeActionCaseController.createAccountClosureCase(
                faId(),
                new Map<String, Object>{
                    'accountClosureReason' => 'Terminated Services',
                    'additionalInformation' => 'Some notes'
                },
                envelopeId()
            );
            Assert.fail('An inactive closure reason value must not silently insert.');
        } catch (AuraHandledException expected) {
        }
        Test.stopTest();
    }

    @isTest
    static void accountClosureOtherReasonCapturesExplanation() {
        Test.startTest();
        String caseId = EnvelopeActionCaseController.createAccountClosureCase(
            faId(),
            new Map<String, Object>{
                'accountClosureReason' => 'Other',
                'explanation' => 'Client moving to another firm'
            },
            envelopeId()
        );
        Test.stopTest();

        Assert.areEqual('Client moving to another firm',
            [SELECT Account_Closure_Explanation__c FROM Case WHERE Id = :caseId]
                .Account_Closure_Explanation__c);
    }

    @isTest
    static void accountClosureDeathInTheFutureThrows() {
        Test.startTest();
        try {
            EnvelopeActionCaseController.createAccountClosureCase(
                faId(),
                new Map<String, Object>{
                    'accountClosureReason' => 'Death',
                    'dateOfDeath' => String.valueOf(Date.today().addDays(30))
                },
                envelopeId()
            );
            Assert.fail('A future Date of Death must throw.');
        } catch (AuraHandledException expected) {
        }
        Test.stopTest();
    }

    @isTest
    static void accountClosureDeathMarksThePrimaryOwnerDeceased() {
        Id personRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Account owner = new Account(
            FirstName = 'Pat', LastName = 'Owner', RecordTypeId = personRtId, Type = 'Prospect'
        );
        insert owner;
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Owned FA', Managed_Account_Platform__c = 'AMS', Primary_Owner__c = owner.Id
        );
        insert fa;

        Test.startTest();
        String caseId = EnvelopeActionCaseController.createAccountClosureCase(
            fa.Id,
            new Map<String, Object>{
                'accountClosureReason' => 'Death',
                'dateOfDeath' => '2026-01-15'
            },
            envelopeId()
        );
        Test.stopTest();

        Assert.areEqual(Date.valueOf('2026-01-15'),
            [SELECT Date_of_Death__c FROM Case WHERE Id = :caseId].Date_of_Death__c);
        Account updatedOwner = [SELECT LastName, Date_of_Death__c FROM Account WHERE Id = :owner.Id];
        Assert.areEqual(Date.valueOf('2026-01-15'), updatedOwner.Date_of_Death__c);
        Assert.areEqual('Owner (DECEASED)', updatedOwner.LastName,
            'The primary owner is flagged deceased on the account itself.');
    }

    @isTest
    static void accountClosureAttachesUploadedFiles() {
        ContentVersion cv = new ContentVersion(
            Title = 'Closure Doc',
            PathOnClient = 'closure.pdf',
            VersionData = Blob.valueOf('closure document body')
        );
        insert cv;
        Id contentDocumentId = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id
        ].ContentDocumentId;

        Test.startTest();
        String caseId = EnvelopeActionCaseController.createAccountClosureCase(
            faId(),
            new Map<String, Object>{
                'accountClosureReason' => 'Other',
                'explanation' => 'With supporting doc',
                'uploadedFiles' => new List<Object>{
                    new Map<Object, Object>{ 'documentId' => (Object) String.valueOf(contentDocumentId) }
                }
            },
            envelopeId()
        );
        Test.stopTest();

        Assert.areEqual(1,
            [SELECT COUNT() FROM ContentDocumentLink
                WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId = :caseId],
            'The uploaded file is linked to the new closure Case.');
    }

    // ---------------------------------------------------------
    // deleteAccountActionCase
    // ---------------------------------------------------------

    @isTest
    static void deleteAccountActionCaseRemovesTheCase() {
        String caseId = EnvelopeActionCaseController.saveAccountActionCase(
            faId(), new Map<String, Object>(), envelopeId(), 'Additional Funding');

        Test.startTest();
        EnvelopeActionCaseController.deleteAccountActionCase(caseId);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Id = :caseId],
            'The case is deleted.');
    }
}