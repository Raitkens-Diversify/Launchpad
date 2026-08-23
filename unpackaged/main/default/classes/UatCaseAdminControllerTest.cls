/**
 * Tests for UatCaseAdminController — case list, New Case sequence preview,
 * step batch authoring (order, condition groups, explore steps), condition
 * rename propagation (03 §8), reference material (links + file rows), and
 * module re-filing (single + bulk, with the re-sequencing that keeps two
 * cases from rendering one Case ID).
 */
@IsTest
private class UatCaseAdminControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createAdminUser('uatadm');
        UatTestDataFactory.createTesterUser('uattst');
    }

    private static User adminUser() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uatadm' LIMIT 1];
    }

    private static User testerUser() {
        return [SELECT Id FROM User WHERE LastName = 'UAT uattst' LIMIT 1];
    }

    private static String caseInput(Id id, Id moduleId, String version, Decimal sequence) {
        UatCaseAdminController.CaseInput input = new UatCaseAdminController.CaseInput();
        input.id = id;
        input.moduleId = moduleId;
        input.version = version;
        input.sequence = sequence;
        input.testingSurface = 'Lightning App (Internal)';
        input.creationStatus = 'Draft';
        return JSON.serialize(input);
    }

    private static UatCaseAdminController.StepInput step(Id id, String condition, String description) {
        UatCaseAdminController.StepInput s = new UatCaseAdminController.StepInput();
        s.id = id;
        s.condition = condition;
        s.description = description;
        s.expected = description + ' happens';
        s.isExplore = false;
        return s;
    }

    @IsTest
    static void createCaseAndSequencePreview() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');

            Assert.areEqual(1001, UatCaseAdminController.getNextSequence(tax.mod.Id),
                'Empty module previews the 1001 seed.');

            Test.startTest();
            Id caseId = UatCaseAdminController.saveCase(caseInput(null, tax.mod.Id, 'v1.0', 1001));
            Test.stopTest();

            Test_Case__c saved = [
                SELECT Case_ID__c, Author__c, Sequence__c FROM Test_Case__c WHERE Id = :caseId
            ];
            Assert.areEqual(UserInfo.getUserId(), saved.Author__c, 'Author defaults to creator.');
            Assert.isTrue(saved.Case_ID__c.endsWith('-v1.0-1001'), 'Case ID: ' + saved.Case_ID__c);

            Assert.areEqual(1002, UatCaseAdminController.getNextSequence(tax.mod.Id),
                'Preview advances past the existing max.');

            List<UatCaseAdminController.CaseRowDTO> rows = UatCaseAdminController.getCaseList();
            Assert.areEqual(1, rows.size());
            Assert.areEqual(tax.sys.Id, rows[0].systemId, 'System id carried for filtering.');
            Assert.isNull(rows[0].title, 'No title set on create — falls back to the code in the UI.');
        }
    }

    @IsTest
    static void titleRoundTripsThroughSaveAndDetail() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            UatCaseAdminController.CaseInput input = new UatCaseAdminController.CaseInput();
            input.moduleId = tax.mod.Id;
            input.version = 'v1.0';
            input.sequence = 1001;
            input.title = '  Verify household record merge retains linked accounts  ';
            input.description = '  Merge two duplicate households and confirm the survivor keeps every linked account.  ';

            Test.startTest();
            Id caseId = UatCaseAdminController.saveCase(JSON.serialize(input));
            Test.stopTest();

            Assert.areEqual('Verify household record merge retains linked accounts',
                UatCaseAdminController.getCaseDetail(caseId).title, 'Title is trimmed and persisted.');
            Assert.areEqual('Verify household record merge retains linked accounts',
                UatCaseAdminController.getCaseList()[0].title, 'Title also carries onto the list row.');
            Assert.areEqual('Merge two duplicate households and confirm the survivor keeps every linked account.',
                UatCaseAdminController.getCaseDetail(caseId).description,
                'Description is trimmed and persisted.');
        }
    }

    @IsTest
    static void preConditionsAndStepTitlesRoundTrip() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            UatCaseAdminController.CaseInput input = new UatCaseAdminController.CaseInput();
            input.moduleId = tax.mod.Id;
            input.version = 'v1.0';
            input.sequence = 1001;
            input.preConditions = '  Log in as an advisor with one household.  ';
            Id caseId = UatCaseAdminController.saveCase(JSON.serialize(input));

            Assert.areEqual('Log in as an advisor with one household.',
                UatCaseAdminController.getCaseDetail(caseId).preConditions,
                'Pre-conditions trim and persist.');

            UatCaseAdminController.StepsInput stepsInput = new UatCaseAdminController.StepsInput();
            stepsInput.caseId = caseId;
            UatCaseAdminController.StepInput s1 = step(null, 'Setup', 'Open the household');
            s1.title = '  Open household  ';
            stepsInput.steps.add(s1);
            stepsInput.steps.add(step(null, 'Setup', 'Verify members'));

            Test.startTest();
            List<UatCaseAdminController.StepDTO> saved =
                UatCaseAdminController.saveSteps(JSON.serialize(stepsInput));
            Test.stopTest();

            Assert.areEqual('Open household', saved[0].title, 'Step title trims and round-trips.');
            Assert.isNull(saved[1].title, 'A blank title stays null.');
        }
    }

    /** Target_Book__c holds the intent while the case is Draft; the flip to
     *  Complete appends the case to the book and clears the pointer. */
    @IsTest
    static void targetBookDefersUntilComplete() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Book__c book = UatTestDataFactory.makeBook('Smoke Book', new List<Id>());

            UatCaseAdminController.CaseInput input = new UatCaseAdminController.CaseInput();
            input.moduleId = tax.mod.Id;
            input.version = 'v1.0';
            input.sequence = 1001;
            input.creationStatus = 'Draft';
            input.targetBookId = book.Id;
            Id caseId = UatCaseAdminController.saveCase(JSON.serialize(input));

            Assert.areEqual(0, [SELECT COUNT() FROM Test_Book_Item__c WHERE Test_Book__c = :book.Id],
                'A Draft case only stores the intent.');
            Assert.areEqual(book.Id, UatCaseAdminController.getCaseDetail(caseId).targetBookId,
                'Pending target round-trips onto the detail.');

            input.id = caseId;
            input.creationStatus = 'Complete';
            Test.startTest();
            UatCaseAdminController.saveCase(JSON.serialize(input));
            Test.stopTest();

            List<Test_Book_Item__c> items = [
                SELECT Test_Case__c FROM Test_Book_Item__c WHERE Test_Book__c = :book.Id
            ];
            Assert.areEqual(1, items.size(), 'The Complete flip appends the case to its target book.');
            Assert.areEqual(caseId, items[0].Test_Case__c);
            Assert.isNull([SELECT Target_Book__c FROM Test_Case__c WHERE Id = :caseId].Target_Book__c,
                'Pointer clears after the deferred add.');
        }
    }

    /** The status endpoint (Restore, list actions) fires the same deferred
     *  add; an already-present case clears the pointer without duplicating. */
    @IsTest
    static void targetBookViaStatusEndpointIsIdempotent() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c seeded = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Test_Book__c book = UatTestDataFactory.makeBook('Smoke Book', new List<Id>{ seeded.Id });

            Test_Case__c pending = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            update new Test_Case__c(
                Id = pending.Id, Creation_Status__c = 'Draft', Target_Book__c = book.Id);

            Test.startTest();
            UatCaseAdminController.setCaseCreationStatus(pending.Id, 'Complete');
            Test.stopTest();

            List<Test_Book_Item__c> items = [
                SELECT Test_Case__c, Sort_Order__c FROM Test_Book_Item__c
                WHERE Test_Book__c = :book.Id ORDER BY Sort_Order__c
            ];
            Assert.areEqual(2, items.size(), 'Status endpoint also fires the deferred add.');
            Assert.areEqual(pending.Id, items[1].Test_Case__c, 'Appended at the end of the run order.');
            Assert.isNull([SELECT Target_Book__c FROM Test_Case__c WHERE Id = :pending.Id].Target_Book__c);

            update new Test_Case__c(Id = pending.Id, Target_Book__c = book.Id);
            UatCaseAdminController.setCaseCreationStatus(pending.Id, 'Complete');
            Assert.areEqual(2, [SELECT COUNT() FROM Test_Book_Item__c WHERE Test_Book__c = :book.Id],
                'No duplicate item for a case already in the book.');
            Assert.isNull([SELECT Target_Book__c FROM Test_Case__c WHERE Id = :pending.Id].Target_Book__c,
                'A stale pointer still clears.');
        }
    }

    /** Max_Testers_Override__c is (3,0): 100 saves, 1000 gets the friendly
     *  bound message instead of a raw DML range error. */
    @IsTest
    static void maxTestersOverrideBounds() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');

            UatCaseAdminController.CaseInput input = new UatCaseAdminController.CaseInput();
            input.moduleId = tax.mod.Id;
            input.version = 'v1.0';
            input.sequence = 1001;
            input.testingSurface = 'Lightning App (Internal)';
            input.creationStatus = 'Draft';
            input.maxTestersOverride = 100;
            Id caseId = UatCaseAdminController.saveCase(JSON.serialize(input));
            Assert.areEqual(100, [
                SELECT Max_Testers_Override__c FROM Test_Case__c WHERE Id = :caseId
            ].Max_Testers_Override__c, 'Three-digit override fits the widened field.');

            input.id = caseId;
            input.maxTestersOverride = 1000;
            try {
                UatCaseAdminController.saveCase(JSON.serialize(input));
                Assert.fail('Override above 999 should be rejected.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('between 1 and 999'), e.getMessage());
            }
        }
    }

    @IsTest
    static void stepBatchSaveOrdersAndRenumbers() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Id caseId = UatCaseAdminController.saveCase(caseInput(null, tax.mod.Id, 'v1.0', 1001));

            UatCaseAdminController.StepsInput input = new UatCaseAdminController.StepsInput();
            input.caseId = caseId;
            input.steps.add(step(null, 'Login', 'Open the app'));
            input.steps.add(step(null, 'Login', 'Enter credentials'));
            UatCaseAdminController.StepInput explore = new UatCaseAdminController.StepInput();
            explore.condition = 'Login';
            explore.isExplore = true;
            explore.explorePrompt = 'Try wrong passwords';
            explore.description = 'should be blanked';
            input.steps.add(explore);

            Test.startTest();
            List<UatCaseAdminController.StepDTO> saved =
                UatCaseAdminController.saveSteps(JSON.serialize(input));
            Test.stopTest();

            Assert.areEqual(3, saved.size());
            Assert.areEqual(1, saved[0].stepNumber, 'Renumbered from array order.');
            Assert.areEqual(3, saved[2].stepNumber);
            Assert.isTrue(saved[2].isExplore);
            Assert.isNull(saved[2].description, 'Explore steps carry no scripted description.');
            Assert.areEqual('Try wrong passwords', saved[2].explorePrompt);

            // Reorder: reverse the two scripted steps (explore stays last).
            // saveSteps upserts the submitted array — it never deletes; removal
            // is explicit via deleteStep. Numbers follow array order.
            UatCaseAdminController.StepsInput second = new UatCaseAdminController.StepsInput();
            second.caseId = caseId;
            second.steps.add(step(saved[1].id, 'Login', 'Enter credentials'));
            second.steps.add(step(saved[0].id, 'Login', 'Open the app'));
            UatCaseAdminController.StepInput explore2 = new UatCaseAdminController.StepInput();
            explore2.id = saved[2].id;
            explore2.condition = 'Login';
            explore2.isExplore = true;
            explore2.explorePrompt = 'Try wrong passwords';
            second.steps.add(explore2);
            List<UatCaseAdminController.StepDTO> reordered =
                UatCaseAdminController.saveSteps(JSON.serialize(second));
            Assert.areEqual(3, reordered.size());
            Assert.areEqual('Enter credentials', reordered[0].description, 'Order follows the array.');
            Assert.areEqual(1, reordered[0].stepNumber);
            Assert.areEqual('Open the app', reordered[1].description);
            Assert.areEqual(2, reordered[1].stepNumber);
        }
    }

    @IsTest
    static void conditionRenamePropagatesThroughSaveSteps() {
        // The UI renames a condition group by rewriting the steps through
        // saveSteps (the dedicated renameCondition endpoint was dead and
        // removed 2026-08-04) — assert the group label round-trips that way.
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 3); // 'Default Condition' x3
            List<Test_Step__c> steps = [
                SELECT Id, Step_Description__c, Expected_Result__c
                FROM Test_Step__c WHERE Test_Case__c = :tc.Id ORDER BY Step_Number__c
            ];
            UatCaseAdminController.StepsInput input = new UatCaseAdminController.StepsInput();
            input.caseId = tc.Id;
            for (Test_Step__c s : steps) {
                UatCaseAdminController.StepInput row = new UatCaseAdminController.StepInput();
                row.id = s.Id;
                row.condition = 'Smoke Checks';
                row.description = s.Step_Description__c;
                row.expected = s.Expected_Result__c;
                input.steps.add(row);
            }

            Test.startTest();
            UatCaseAdminController.saveSteps(JSON.serialize(input));
            Test.stopTest();

            Assert.areEqual(3, [
                SELECT COUNT() FROM Test_Step__c
                WHERE Test_Case__c = :tc.Id AND Test_Condition__c = 'Smoke Checks'
            ], 'Every step in the group renamed through saveSteps.');
        }
    }

    @IsTest
    static void deleteStepRemovesDefinition() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2);
            Id stepId = [SELECT Id FROM Test_Step__c WHERE Test_Case__c = :tc.Id LIMIT 1].Id;

            Test.startTest();
            UatCaseAdminController.deleteStep(stepId);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM Test_Step__c WHERE Test_Case__c = :tc.Id]);
        }
    }

    @IsTest
    static void referenceLinksAndFiles() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1);

            Test.startTest();
            UatCaseAdminController.saveReferenceLink(JSON.serialize(
                new Map<String, Object>{
                    'caseId' => tc.Id, 'label' => 'Standards doc', 'url' => 'https://example.com/standards'
                }));
            Id refId = UatCaseAdminController.createReferenceFile(tc.Id);
            Id docId = UatTestDataFactory.attachFile(refId, 'evidence-shot');
            UatCaseAdminController.registerReferenceUpload(refId, new List<String>{ docId });
            Test.stopTest();

            UatCaseAdminController.CaseDetailDTO detail = UatCaseAdminController.getCaseDetail(tc.Id);
            Assert.areEqual(2, detail.refMaterials.size(), 'Link + file rows.');
            UatCaseAdminController.RefMaterialDTO fileRow;
            for (UatCaseAdminController.RefMaterialDTO r : detail.refMaterials) {
                if (r.type == 'File') {
                    fileRow = r;
                }
            }
            Assert.isNotNull(fileRow.file, 'File metadata attached.');
            Assert.areEqual('evidence-shot', fileRow.label, 'Label set from the file title.');

            // Removing the file row deletes its ContentDocument too.
            UatCaseAdminController.deleteReferenceMaterial(fileRow.id);
            Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument WHERE Id = :docId]);
            Assert.areEqual(1, UatCaseAdminController.getCaseDetail(tc.Id).refMaterials.size());
        }
    }

    @IsTest
    static void executionViewAndReIdentification() {
        User tester = testerUser();
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
            Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester.Id });
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null, new List<Id>{ tc.Id });

            List<UatCaseAdminController.ExecutionOptionDTO> options =
                UatCaseAdminController.getExecutionsForCase(tc.Id);
            Assert.areEqual(1, options.size(), 'The eager unclaimed slot lists.');
            Assert.areEqual('Sprint 1 — Unclaimed', options[0].label);

            // Answer a step + attach evidence, then read the execution view.
            List<Test_Step_Result__c> results = UatExecutionService.ensureStepResults(options[0].id);
            results[0].Result__c = 'Pass';
            results[0].Actual_Result__c = 'Looked right';
            update results[0];
            UatTestDataFactory.attachFile(options[0].id, 'run-shot');

            Test.startTest();
            UatCaseAdminController.ExecutionViewDTO view =
                UatCaseAdminController.getExecutionView(options[0].id);
            Assert.areEqual(2, view.stepResults.size());
            Assert.areEqual(1, view.caseEvidence.size(), 'Case-level evidence listed.');
            Assert.areEqual('In Progress', view.status);

            // 03 §2: picking a tester resolves to a DIFFERENT (new) execution.
            UatCaseAdminController.ExecutionOptionDTO resolved =
                UatCaseAdminController.resolveExecutionForIdentity(tc.Id, cycle.Id, tester.Id);
            Test.stopTest();

            Assert.areNotEqual(options[0].id, resolved.id, 'Re-identify, never relabel.');
            Assert.areEqual(2, UatCaseAdminController.getExecutionsForCase(tc.Id).size());
            Assert.areEqual(1, UatCaseAdminController.getTeamMembers(team.Id).size());

            // Admins can prune case-level evidence for a run.
            UatCaseAdminController.deleteEvidence(
                view.caseEvidence[0].contentDocumentId, options[0].id);
            Assert.areEqual(0,
                UatCaseAdminController.getExecutionView(options[0].id).caseEvidence.size());
        }
    }

    @IsTest
    static void findExecutionForIdentityIsLookupOnly() {
        User tester = testerUser();
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ tester.Id });
            Test_Cycle__c cycle = UatTestDataFactory.makeCycle('Sprint 1', team.Id, null,
                new List<Id>{ tc.Id });

            Test.startTest();
            // The eager unclaimed slot is findable; the tester's run is not —
            // and looking must not create it (the browse-safe dropdown path).
            Assert.isNotNull(
                UatCaseAdminController.findExecutionForIdentity(tc.Id, cycle.Id, null));
            Assert.isNull(
                UatCaseAdminController.findExecutionForIdentity(tc.Id, cycle.Id, tester.Id));
            Assert.areEqual(1, [SELECT COUNT() FROM Test_Execution__c WHERE Test_Case__c = :tc.Id],
                'Lookup created nothing.');

            // After the confirmed create, find returns the same run.
            UatCaseAdminController.ExecutionOptionDTO created =
                UatCaseAdminController.resolveExecutionForIdentity(tc.Id, cycle.Id, tester.Id);
            UatCaseAdminController.ExecutionOptionDTO found =
                UatCaseAdminController.findExecutionForIdentity(tc.Id, cycle.Id, tester.Id);
            Test.stopTest();

            Assert.areEqual(created.id, found.id);
        }
    }

    @IsTest
    static void testerCannotWrite() {
        Id moduleId;
        System.runAs(adminUser()) {
            moduleId = UatTestDataFactory.makeTaxonomy('Helios').mod.Id;
        }
        System.runAs(testerUser()) {
            try {
                UatCaseAdminController.saveCase(caseInput(null, moduleId, 'v1.0', null));
                Assert.fail('Tester write should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), 'Access message: ' + e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Test_Case__c], 'Nothing written.');
    }

    @IsTest
    static void blankVersionRejected() {
        System.runAs(adminUser()) {
            Id moduleId = UatTestDataFactory.makeTaxonomy('Helios').mod.Id;
            try {
                UatCaseAdminController.saveCase(caseInput(null, moduleId, '  ', null));
                Assert.fail('Blank version should throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Version'), 'Version message: ' + e.getMessage());
            }
        }
    }

    /** Regression pin for the two-status confusion: the Creation status an
     *  admin edits is the DEFINITION's authoring progress, and saving it must
     *  never touch any run's Testing_Status__c — the field testers (and the
     *  admin list's run-status column) actually read. Both values ride the
     *  list row independently so the admin's edit is visible somewhere. */
    @IsTest
    static void saveCaseNeverTouchesRunStatus() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Helios');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Team__c team = UatTestDataFactory.makeTeam('Alpha', new List<Id>{ testerUser().Id });
        UatTestDataFactory.makeCycle('Sprint 1', team.Id, null, new List<Id>{ tc.Id });

        // A finished run, stamped directly (the runner flow is covered in
        // UatRunControllerTest).
        Test_Execution__c run = [
            SELECT Id FROM Test_Execution__c WHERE Test_Case__c = :tc.Id
        ];
        run.Assigned_Tester__c = testerUser().Id;
        run.Claimed_Date__c = Datetime.now();
        run.Testing_Status__c = 'Complete';
        run.Testing_Result__c = 'Passed';
        update run;

        System.runAs(adminUser()) {
            UatCaseAdminController.CaseInput input = new UatCaseAdminController.CaseInput();
            input.id = tc.Id;
            input.moduleId = tax.mod.Id;
            input.version = 'v1.0';
            input.sequence = 1001;
            input.testingSurface = 'Lightning App (Internal)';
            input.creationStatus = 'In Progress'; // Complete -> back to authoring

            Test.startTest();
            UatCaseAdminController.saveCase(JSON.serialize(input));
            Test.stopTest();

            Assert.areEqual('In Progress', [
                SELECT Creation_Status__c FROM Test_Case__c WHERE Id = :tc.Id
            ].Creation_Status__c, 'The admin\'s edit landed on the definition.');

            Test_Execution__c after = [
                SELECT Testing_Status__c, Testing_Result__c
                FROM Test_Execution__c WHERE Id = :run.Id
            ];
            Assert.areEqual('Complete', after.Testing_Status__c,
                'Editing Creation status must not rewrite any run\'s testing status.');
            Assert.areEqual('Passed', after.Testing_Result__c,
                'The run\'s verdict is untouched too.');

            // The list row shows BOTH statuses, so the edit is visible.
            UatCaseAdminController.CaseRowDTO row = UatCaseAdminController.getCaseList()[0];
            Assert.areEqual('In Progress', row.creationStatus,
                'Creation status rides the list row for its own column.');
            Assert.areEqual('Complete', row.testingStatus,
                'The run-status column still shows the latest run.');
        }

        // The tester surface reads the run, not the definition — unchanged.
        System.runAs(testerUser()) {
            UatRunController.QueueDTO queue = UatRunController.getQueue();
            Assert.areEqual('Complete', queue.cycleGroups[0].cards[0].status,
                'Tester queue still shows the run\'s own status after the admin edit.');
        }
    }

    // ---- Retire / delete (2026-08-05) ---------------------------------------------

    @IsTest
    static void deleteCaseBlockedListsBooksCyclesAndRuns() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Del');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
            UatTestDataFactory.makeBook('Blocking Book', new List<Id>{ tc.Id });
            UatTestDataFactory.makeCycle('Blocking Cycle', null, null, new List<Id>{ tc.Id });

            Test.startTest();
            UatCaseAdminController.CaseDeleteImpactDTO impact =
                UatCaseAdminController.getCaseDeleteImpact(tc.Id);
            Test.stopTest();

            Assert.isTrue(impact.blocked);
            Assert.areEqual(new List<String>{ 'Blocking Book' }, impact.bookNames);
            Assert.areEqual(new List<String>{ 'Blocking Cycle' }, impact.cycleNames);
            Assert.areEqual(1, impact.executionCount, 'The eager slot counts as a run.');

            try {
                UatCaseAdminController.deleteCase(tc.Id);
                Assert.fail('Referenced cases must not delete.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('retire it'), e.getMessage());
                Assert.isTrue(e.getMessage().contains('1 book'), e.getMessage());
            }
            Assert.areEqual(1, [SELECT COUNT() FROM Test_Case__c WHERE Id = :tc.Id]);
        }
    }

    @IsTest
    static void deleteCaseCleanCascadesStepsAndRefs() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Del');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 2, 1001);
            Id refId = UatCaseAdminController.saveReferenceLink(JSON.serialize(new Map<String, Object>{
                'caseId' => tc.Id, 'label' => 'Spec', 'url' => 'https://example.invalid/spec'
            }));

            UatCaseAdminController.CaseDeleteImpactDTO impact =
                UatCaseAdminController.getCaseDeleteImpact(tc.Id);
            Assert.isFalse(impact.blocked);
            Assert.areEqual(2, impact.stepCount);
            Assert.areEqual(1, impact.refCount);

            Test.startTest();
            UatCaseAdminController.deleteCase(tc.Id);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Test_Case__c WHERE Id = :tc.Id]);
            Assert.areEqual(0, [SELECT COUNT() FROM Test_Step__c WHERE Test_Case__c = :tc.Id]);
            Assert.areEqual(0, [SELECT COUNT() FROM Reference_Material__c WHERE Id = :refId]);
        }
    }

    @IsTest
    static void setCaseCreationStatusRetiresAndRestores() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Ret');
            Test_Case__c retired = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1002);
            // Already in a book and a cycle BEFORE retiring — both must survive.
            UatTestDataFactory.makeBook('Existing Book', new List<Id>{ retired.Id });
            UatTestDataFactory.makeCycle('Existing Cycle', null, null, new List<Id>{ retired.Id });
            // The picker assertions need a surface the case is NOT already in —
            // add-pickers exclude present cases regardless of status.
            Test_Cycle__c freshCycle = UatTestDataFactory.makeCycle('Fresh Cycle', null, null, null);

            Test.startTest();
            UatCaseAdminController.setCaseCreationStatus(retired.Id, 'Retired');
            Test.stopTest();

            Assert.areEqual('Retired', [
                SELECT Creation_Status__c FROM Test_Case__c WHERE Id = :retired.Id
            ].Creation_Status__c);
            Assert.areEqual(1, [
                SELECT COUNT() FROM Test_Book_Item__c WHERE Test_Case__c = :retired.Id
            ], 'Existing book membership untouched.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM Test_Execution__c WHERE Test_Case__c = :retired.Id
            ], 'Materialized run untouched.');

            // Gone from the add-picker (it gates on Complete)...
            for (UatCycleAdminController.JunctionDTO cand :
                UatCycleAdminController.getCycleDetail(freshCycle.Id).availableCases) {
                Assert.areNotEqual(retired.Id, cand.targetId, 'Retired case left the cycle picker.');
            }
            // ...and the add endpoints refuse it outright.
            try {
                UatCycleAdminController.addDirectCase(freshCycle.Id, retired.Id);
                Assert.fail('Retired cases must not enter cycles.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Complete'), e.getMessage());
            }

            // Restore puts it back in play.
            UatCaseAdminController.setCaseCreationStatus(retired.Id, 'Complete');
            Boolean visibleAgain = false;
            for (UatCycleAdminController.JunctionDTO cand :
                UatCycleAdminController.getCycleDetail(freshCycle.Id).availableCases) {
                visibleAgain = visibleAgain || cand.targetId == retired.Id;
            }
            Assert.isTrue(visibleAgain, 'Restored case is a candidate again.');
        }
    }

    @IsTest
    static void setCaseCreationStatusRejectsUnknownValue() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Ret');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);
            try {
                UatCaseAdminController.setCaseCreationStatus(tc.Id, 'Archived');
                Assert.fail('Only the four picklist values pass the whitelist.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Unknown creation status'), e.getMessage());
            }
        }
    }

    @IsTest
    static void deleteCaseGateNegative() {
        Test_Case__c tc;
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Del');
            tc = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);
        }
        System.runAs(testerUser()) {
            try {
                UatCaseAdminController.deleteCase(tc.Id);
                Assert.fail('Testers must not delete case definitions.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
            try {
                UatCaseAdminController.setCaseCreationStatus(tc.Id, 'Retired');
                Assert.fail('Testers must not retire case definitions.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Test_Case__c WHERE Id = :tc.Id]);
    }

    // ---- Module re-filing (2026-08-12) ---------------------------------------------

    /** saveCase moves the case AND re-sequences it: Case_ID__c is a formula
     *  over the taxonomy, and the destination's numbering is what keeps two
     *  cases from rendering the same code. */
    @IsTest
    static void saveCaseMovesModuleAndReSequences() {
        System.runAs(adminUser()) {
            // Not named `from` — that is a reserved word in Apex and the class
            // will not compile.
            UatTestDataFactory.Taxonomy origin = UatTestDataFactory.makeTaxonomy('Origin');
            UatTestDataFactory.Taxonomy dest = UatTestDataFactory.makeTaxonomy('Target');
            // A case already sitting on 1001 in the destination: carrying the
            // number across would produce a duplicate Case ID.
            UatTestDataFactory.makeCase(dest.mod.Id, 0, 1001);
            Id caseId = UatCaseAdminController.saveCase(caseInput(null, origin.mod.Id, 'v1.0', 1001));

            Test.startTest();
            UatCaseAdminController.saveCase(caseInput(caseId, dest.mod.Id, 'v1.0', 1001));
            Test.stopTest();

            Test_Case__c moved = [
                SELECT Module__c, Sequence__c, Case_ID__c FROM Test_Case__c WHERE Id = :caseId
            ];
            Assert.areEqual(dest.mod.Id, moved.Module__c, 'Module is editable after create.');
            Assert.areEqual(1002, (Integer) moved.Sequence__c, 'Re-sequenced past the destination max.');
            Assert.isTrue(moved.Case_ID__c.contains('target'),
                'Case ID follows the taxonomy: ' + moved.Case_ID__c);
            Assert.areEqual(1, [
                SELECT COUNT() FROM Test_Case__c
                WHERE Module__c = :dest.mod.Id AND Sequence__c = 1001
            ], 'The move must not collide with the case already on 1001.');

            UatCaseAdminController.CaseDetailDTO dto = UatCaseAdminController.getCaseDetail(caseId);
            Assert.areEqual(dest.mod.Id, dto.moduleId, 'Detail reports the new module.');
            Assert.areEqual(dest.grp.Id, dto.groupId, 'Ancestry carried for the picker.');
            Assert.areEqual(dest.sys.Id, dto.systemId);
            Assert.isNotNull(dto.systemCode, 'System code drives the Case ID preview.');
        }
    }

    /** The detail editor round-trips moduleId on every save; an unchanged one
     *  must not renumber the case (its Case ID would churn on every keystroke
     *  save). */
    @IsTest
    static void saveCaseWithUnchangedModuleLeavesSequenceAlone() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Stay');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1007);

            Test.startTest();
            UatCaseAdminController.saveCase(caseInput(tc.Id, tax.mod.Id, 'v1.0', 1007));
            Test.stopTest();

            Assert.areEqual(1007,
                (Integer) [SELECT Sequence__c FROM Test_Case__c WHERE Id = :tc.Id].Sequence__c,
                'Same module = no re-sequence.');
        }
    }

    /** getNextSequence reads committed rows, so a batch has to hand out its own
     *  consecutive numbers — otherwise every case in one move lands on the same
     *  sequence and they all share a Case ID. */
    @IsTest
    static void bulkMoveGivesEveryCaseItsOwnSequence() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy origin = UatTestDataFactory.makeTaxonomy('Bulkfrom');
            UatTestDataFactory.Taxonomy dest = UatTestDataFactory.makeTaxonomy('Bulkdest');
            List<Id> caseIds = new List<Id>();
            for (Integer i = 0; i < 3; i++) {
                caseIds.add(UatTestDataFactory.makeCase(origin.mod.Id, 0, 1001 + i).Id);
            }

            Test.startTest();
            Integer moved = UatCaseAdminController.moveCasesToModule(caseIds, dest.mod.Id);
            Test.stopTest();

            Assert.areEqual(3, moved, 'All three re-filed.');
            Set<Decimal> sequences = new Set<Decimal>();
            Set<String> codes = new Set<String>();
            for (Test_Case__c c : [
                SELECT Module__c, Sequence__c, Case_ID__c FROM Test_Case__c WHERE Id IN :caseIds
            ]) {
                Assert.areEqual(dest.mod.Id, c.Module__c);
                sequences.add(c.Sequence__c);
                codes.add(c.Case_ID__c);
            }
            Assert.areEqual(3, sequences.size(), 'Sequences must be distinct: ' + sequences);
            Assert.areEqual(3, codes.size(), 'And so must the Case IDs they build.');
        }
    }

    @IsTest
    static void bulkMoveSkipsCasesAlreadyInTheDestination() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Noop');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);

            Test.startTest();
            Integer moved = UatCaseAdminController.moveCasesToModule(
                new List<Id>{ tc.Id }, tax.mod.Id
            );
            Test.stopTest();

            Assert.areEqual(0, moved, 'Nothing to do — and no gratuitous renumber.');
            Assert.areEqual(1001,
                (Integer) [SELECT Sequence__c FROM Test_Case__c WHERE Id = :tc.Id].Sequence__c);
        }
    }

    @IsTest
    static void bulkMoveValidatesItsInputs() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Guard');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);
            try {
                UatCaseAdminController.moveCasesToModule(new List<Id>{ tc.Id }, null);
                Assert.fail('A null module must be refused.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('destination module'), e.getMessage());
            }
            try {
                UatCaseAdminController.moveCasesToModule(new List<Id>(), tax.mod.Id);
                Assert.fail('An empty selection must be refused.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('at least one'), e.getMessage());
            }
        }
    }

    @IsTest
    static void bulkMoveIsAdminOnly() {
        Test_Case__c tc;
        Id moduleId;
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Perm');
            tc = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);
            moduleId = tax.mod.Id;
        }
        System.runAs(testerUser()) {
            try {
                UatCaseAdminController.moveCasesToModule(new List<Id>{ tc.Id }, moduleId);
                Assert.fail('Testers must not re-file case definitions.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
            }
        }
    }

    /** The detail page's book chips. Target_Book__c can't answer "where is
     *  this case?" — the server clears it the instant it fires. */
    @IsTest
    static void caseDetailReportsCurrentBookMembership() {
        System.runAs(adminUser()) {
            UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Books');
            Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 0, 1001);
            Test_Book__c book = UatTestDataFactory.makeBook('Smoke Book', new List<Id>{ tc.Id });

            Test.startTest();
            UatCaseAdminController.CaseDetailDTO dto = UatCaseAdminController.getCaseDetail(tc.Id);
            Test.stopTest();

            Assert.areEqual(1, dto.books.size(), 'Membership is reported.');
            Assert.areEqual(book.Id, dto.books[0].bookId);
            Assert.areEqual('Smoke Book', dto.books[0].bookName);
            Assert.isNotNull(dto.books[0].bookItemId, 'The chip needs the junction Id to remove.');
            Assert.isNull(dto.targetBookId, 'The pending pointer stays empty and separate.');
        }
    }
}