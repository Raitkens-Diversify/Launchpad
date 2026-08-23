/**
 * Tests for UatSessionController — the exploratory-session workflow: start
 * validations and audience gating, the list's counts and scoping, workspace
 * reads (team-visible), the owner-or-admin write gates on notes/finish,
 * saveFinding's session path (link, severity, cycle derivation), delete
 * (owner-Active / admin-any policy, findings survive), standalone (cycle-less)
 * sessions — owner-or-admin on every path, findings carry a null cycle and die
 * with their session — and, since 2026-08-06, that finish PRESERVES the
 * session's evidence links (the old finish-time sweep is gone) plus the
 * focus-prompt resolution order.
 */
@IsTest
private class UatSessionControllerTest {

    @TestSetup
    static void setup() {
        UatTestDataFactory.createTesterUser('sestst1');
        UatTestDataFactory.createTesterUser('sestst2');
        UatTestDataFactory.createTesterUser('sesout'); // UAT_Tester, not on any team
        UatTestDataFactory.createAdminUser('sesadm');  // carries UAT_Console
    }

    private static User byLastName(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    /** Team of tester1+tester2 (admin NOT on it), one cycle. */
    private static Test_Cycle__c teamedCycle() {
        UatTestDataFactory.Taxonomy tax = UatTestDataFactory.makeTaxonomy('Sess');
        Test_Case__c tc = UatTestDataFactory.makeCase(tax.mod.Id, 1, 1001);
        Team__c team = UatTestDataFactory.makeTeam('Session Team', new List<Id>{
            byLastName('UAT sestst1').Id, byLastName('UAT sestst2').Id
        });
        return UatTestDataFactory.makeCycle('Session Sprint', team.Id, null, new List<Id>{ tc.Id });
    }

    private static Id startStandardSession(Id cycleId) {
        return UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
            'title' => 'Client Records Exploration',
            'charter' => 'Explore duplicate handling and identify unexpected behavior.',
            'areaText' => 'Client Records',
            'timeboxMinutes' => 60,
            'cycleId' => cycleId
        }));
    }

    private static Id addFinding(Id sessionId, String severity) {
        return UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
            'sessionId' => sessionId,
            'title' => 'Survivor history vanished after merge',
            'type' => 'Defect',
            'whatTesting' => 'Merged two records',
            'whatHappened' => 'History vanished from the survivor',
            'severity' => severity == null ? 'Low' : severity,
            // High/Critical need evidence or a stated reason; the helper says
            // why rather than uploading a file in every test that logs one.
            'noEvidenceReason' => 'Captured in the session log instead.'
        }));
    }

    @IsTest
    static void startSessionCreatesActiveOwnedSession() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Test.startTest();
            Id sessionId = startStandardSession(cycle.Id);
            Test.stopTest();

            Exploratory_Session__c s = [
                SELECT Title__c, Charter__c, Area__c, Timebox_Minutes__c,
                    Status__c, Started_At__c, Finished_At__c, Tester__c, Test_Cycle__c
                FROM Exploratory_Session__c WHERE Id = :sessionId
            ];
            Assert.areEqual('Client Records Exploration', s.Title__c);
            Assert.areEqual(UatConstants.SESSION_ACTIVE, s.Status__c, 'Born Active.');
            Assert.isNotNull(s.Started_At__c, 'Start stamped server-side.');
            Assert.isNull(s.Finished_At__c);
            Assert.areEqual(UserInfo.getUserId(), s.Tester__c, 'Owner = the starter.');
            Assert.areEqual(cycle.Id, s.Test_Cycle__c);
            Assert.areEqual(60, s.Timebox_Minutes__c);

            List<UatSessionController.SessionDTO> sessions =
                UatSessionController.getExploratorySessions();
            Assert.areEqual(1, sessions.size());
            Assert.isTrue(sessions[0].isMine);
            Assert.areEqual('Session Sprint', sessions[0].cycleName);
        }
    }

    @IsTest
    static void startSessionRequiresOnlyATitle() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            try {
                UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
                    'charter' => 'c', 'cycleId' => cycle.Id
                }));
                Assert.fail('Missing title must throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('title'), e.getMessage());
            }
            // A charter is no longer asked for: it was exploratory-testing
            // ceremony standing between a business user and writing down what
            // they just saw. Title alone is enough to start.
            Assert.isNotNull(UatSessionController.startSession(
                JSON.serialize(new Map<String, Object>{
                    'title' => 'Poking at the merge fix', 'cycleId' => cycle.Id
                })), 'A title on its own starts a session.');
            try {
                UatSessionController.startSession(JSON.serialize(new Map<String, Object>{
                    'title' => 't', 'timeboxMinutes' => 0, 'cycleId' => cycle.Id
                }));
                Assert.fail('Zero timebox must throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Timebox'), e.getMessage());
            }
        }
    }

    @IsTest
    static void startSessionBlocksOutsideAudience() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sesout')) {
            try {
                startStandardSession(cycle.Id);
                Assert.fail('Outsider must not start a session in a teamed cycle.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('another team'), e.getMessage());
            }
        }
    }

    @IsTest
    static void listCountsFindingsAndFilesAndScopesAudience() {
        Test_Cycle__c cycle = teamedCycle();
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(cycle.Id);
            Id findingA = addFinding(sessionId, 'High');
            addFinding(sessionId, null);
            UatTestDataFactory.attachFile(findingA, 'evidence-shot');
        }

        System.runAs(byLastName('UAT sestst2')) {
            Test.startTest();
            List<UatSessionController.SessionDTO> sessions =
                UatSessionController.getExploratorySessions();
            Test.stopTest();
            Assert.areEqual(1, sessions.size(), 'Teammate sees the session (team-visible).');
            Assert.areEqual(2, sessions[0].findingsCount);
            Assert.areEqual(1, sessions[0].filesCount);
            Assert.isFalse(sessions[0].isMine);
            Assert.areEqual('UAT sestst1', sessions[0].testerName);
        }

        System.runAs(byLastName('UAT sesout')) {
            Assert.areEqual(0, UatSessionController.getExploratorySessions().size(),
                'Foreign-team cycles are out of scope.');
        }
    }

    @IsTest
    static void listExcludesClosedCycles() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            startStandardSession(cycle.Id);
        }
        cycle.Status__c = UatConstants.CYCLE_CLOSED;
        update cycle;
        System.runAs(byLastName('UAT sestst1')) {
            Assert.areEqual(0, UatSessionController.getExploratorySessions().size(),
                'Closed cycles leave the tester app entirely — sessions included.');
        }
    }

    @IsTest
    static void workspaceReadsForAudienceOnlyAndFiltersToSessionFindings() {
        Test_Cycle__c cycle = teamedCycle();
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(cycle.Id);
            addFinding(sessionId, 'Critical');
            // A cycle-log finding WITHOUT a session must stay out of the workspace.
            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'cycleId' => cycle.Id,
                'title' => 'Loose cycle-log observation',
                'type' => 'Question',
                'whatHappened' => 'Logged straight into the cycle log'
            }));
        }

        System.runAs(byLastName('UAT sestst2')) {
            UatSessionController.SessionWorkspaceDTO ws =
                UatSessionController.getSessionWorkspace(sessionId);
            Assert.areEqual(1, ws.findings.size(), 'Only the session\'s findings.');
            Assert.areEqual('Critical', ws.findings[0].severity);
            Assert.areEqual(sessionId, ws.findings[0].sessionId);
            Assert.isFalse(ws.session.isMine, 'Teammate reads it as not-mine (read-only UI).');
        }

        System.runAs(byLastName('UAT sesout')) {
            try {
                UatSessionController.getSessionWorkspace(sessionId);
                Assert.fail('Outsider must not read the workspace.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('another team'), e.getMessage());
            }
        }
    }

    /* The notes blob became a Session_Note__c timeline (2026-08-06). Same gate
     * as before: author-or-admin, and nothing at all once the session is
     * finished. */
    @IsTest
    static void logEntriesGateOwnerPeerAdminAndCompleted() {
        Test_Cycle__c cycle = teamedCycle();
        Id sessionId;
        Id noteId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(cycle.Id);
            UatSessionController.NoteDTO dto = UatSessionController.addSessionNote(
                JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId, 'text' => 'Owner entry', 'tag' => 'Observation'
                }));
            noteId = dto.id;
            Assert.areEqual('Owner entry', dto.text);
            Assert.areEqual('Observation', dto.tag);
            Assert.isNotNull(dto.loggedAt, 'Stamped server-side.');
            Assert.isTrue(dto.isMine);
        }

        System.runAs(byLastName('UAT sestst2')) {
            try {
                UatSessionController.addSessionNote(JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId, 'text' => 'Peer entry'
                }));
                Assert.fail('A peer must not write in someone else\'s log.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only the tester'), e.getMessage());
            }
            try {
                UatSessionController.deleteSessionNote(noteId);
                Assert.fail('A peer must not delete someone else\'s entry.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only the tester'), e.getMessage());
            }
        }

        // Admin override: not on the team, but UAT_Console passes both gates.
        System.runAs(byLastName('UAT sesadm')) {
            UatSessionController.addSessionNote(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId, 'text' => 'Admin moderation entry'
            }));
        }
        Assert.areEqual(2, [
            SELECT COUNT() FROM Session_Note__c WHERE Exploratory_Session__c = :sessionId
        ]);

        System.runAs(byLastName('UAT sestst1')) {
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            try {
                UatSessionController.addSessionNote(JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId, 'text' => 'Too late'
                }));
                Assert.fail('A finished session\'s log is read-only.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('finished'), e.getMessage());
            }
        }
    }

    /* Editing text must NOT restamp Logged_At__c — a correction should not
     * jump the entry to the bottom of the timeline. */
    @IsTest
    static void editingAnEntryKeepsItsPlaceInTheTimeline() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatSessionController.NoteDTO first = UatSessionController.addSessionNote(
                JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId, 'text' => 'Original wording'
                }));

            Test.startTest();
            UatSessionController.NoteDTO edited = UatSessionController.updateSessionNote(
                JSON.serialize(new Map<String, Object>{
                    'id' => first.id, 'text' => 'Corrected wording', 'tag' => 'Question'
                }));
            Test.stopTest();

            Assert.areEqual('Corrected wording', edited.text);
            Assert.areEqual('Question', edited.tag);
            Assert.areEqual(first.loggedAt, edited.loggedAt,
                'An edit must not move the entry in the log.');

            try {
                UatSessionController.updateSessionNote(JSON.serialize(new Map<String, Object>{
                    'id' => first.id, 'text' => '   '
                }));
                Assert.fail('An empty entry must be a delete, not a save.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('cannot be empty'), e.getMessage());
            }
        }
    }

    /* Entries die with their session (master-detail), and a finding promoted
     * from one survives with its Source_Note__c nulled. */
    @IsTest
    static void deletingAnEntryKeepsTheFindingPromotedFromIt() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatSessionController.NoteDTO entry = UatSessionController.addSessionNote(
                JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId, 'text' => 'Warning never appeared'
                }));
            Id findingId = UatRunController.saveFinding(
                JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId,
                    'sourceNoteId' => entry.id,
                    'title' => 'Duplicate warning never appeared',
                    'type' => 'Defect',
                    'severity' => 'Low',
                    'whatHappened' => 'Warning never appeared'
                }));
            Assert.areEqual(entry.id, [
                SELECT Source_Note__c FROM Exploratory_Finding__c WHERE Id = :findingId
            ].Source_Note__c);

            Test.startTest();
            UatSessionController.deleteSessionNote(entry.id);
            Test.stopTest();

            Assert.areEqual(1, [
                SELECT COUNT() FROM Exploratory_Finding__c WHERE Id = :findingId
            ], 'The finding outlives the entry it came from.');
            Assert.isNull([
                SELECT Source_Note__c FROM Exploratory_Finding__c WHERE Id = :findingId
            ].Source_Note__c, 'Its back-link is nulled, not cascaded.');
        }
    }

    @IsTest
    static void finishStampsFlushesAndBlocksDoubleFinishAndPeers() {
        Test_Cycle__c cycle = teamedCycle();
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(cycle.Id);
        }

        System.runAs(byLastName('UAT sestst2')) {
            try {
                UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId
                }));
                Assert.fail('A peer must not finish someone else\'s session.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only the tester'), e.getMessage());
            }
        }

        System.runAs(byLastName('UAT sestst1')) {
            Test.startTest();
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            Test.stopTest();

            Exploratory_Session__c s = [
                SELECT Status__c, Finished_At__c
                FROM Exploratory_Session__c WHERE Id = :sessionId
            ];
            Assert.areEqual(UatConstants.SESSION_COMPLETED, s.Status__c);
            Assert.isNotNull(s.Finished_At__c);

            try {
                UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId
                }));
                Assert.fail('Double finish must throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('already finished'), e.getMessage());
            }
        }
    }

    @IsTest
    static void saveFindingLinksSessionSetsSeverityAndDerivesCycle() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            // No cycleId in the payload — it must derive from the session.
            Id findingId = addFinding(sessionId, 'Medium');
            Exploratory_Finding__c f = [
                SELECT Test_Cycle__c, Exploratory_Session__c, Severity__c, Tester__c
                FROM Exploratory_Finding__c WHERE Id = :findingId
            ];
            Assert.areEqual(cycle.Id, f.Test_Cycle__c, 'Cycle derived from the session.');
            Assert.areEqual(sessionId, f.Exploratory_Session__c);
            Assert.areEqual('Medium', f.Severity__c);
            Assert.areEqual(UserInfo.getUserId(), f.Tester__c);
        }
    }

    @IsTest
    static void saveFindingBlocksPeersSessionsAndCompletedSessions() {
        Test_Cycle__c cycle = teamedCycle();
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(cycle.Id);
        }

        System.runAs(byLastName('UAT sestst2')) {
            try {
                addFinding(sessionId, null);
                Assert.fail('Findings only land in MY session.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('your own session'), e.getMessage());
            }
        }

        System.runAs(byLastName('UAT sestst1')) {
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            try {
                addFinding(sessionId, null);
                Assert.fail('Completed sessions take no new findings.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('finished'), e.getMessage());
            }
        }
    }

    @IsTest
    static void deleteSessionOwnerCleansOwnActiveSession() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            Id findingId = addFinding(sessionId, 'High');
            Id docId = UatTestDataFactory.attachFile(findingId, 'evidence-shot');

            Test.startTest();
            UatSessionController.deleteSession(sessionId);
            Test.stopTest();

            Assert.areEqual(0, [
                SELECT COUNT() FROM Exploratory_Session__c WHERE Id = :sessionId
            ], 'The session row is gone.');
            Assert.isNull([
                SELECT Exploratory_Session__c FROM Exploratory_Finding__c WHERE Id = :findingId
            ].Exploratory_Session__c, 'Findings survive with the link nulled — durable output.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM ContentDocument WHERE Id = :docId
            ], 'Finding evidence is untouched.');
        }
    }

    @IsTest
    static void deleteSessionOwnerBlockedOnCompleted() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            try {
                UatSessionController.deleteSession(sessionId);
                Assert.fail('Owners clean up ACTIVE sessions only — finished ones are team record.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('UAT admin'), e.getMessage());
            }
            Assert.areEqual(1, [
                SELECT COUNT() FROM Exploratory_Session__c WHERE Id = :sessionId
            ], 'Blocked delete left the session intact.');
        }
    }

    @IsTest
    static void deleteSessionAdminDeletesAnyStatusAndPeersBlocked() {
        Test_Cycle__c cycle = teamedCycle();
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(cycle.Id);
        }

        System.runAs(byLastName('UAT sestst2')) {
            try {
                UatSessionController.deleteSession(sessionId);
                Assert.fail('A peer must not delete someone else\'s session.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Only the tester'), e.getMessage());
            }
        }

        System.runAs(byLastName('UAT sestst1')) {
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
        }
        // Admin (UAT_Console, off-team) may delete even a Completed session.
        System.runAs(byLastName('UAT sesadm')) {
            Test.startTest();
            UatSessionController.deleteSession(sessionId);
            Test.stopTest();
        }
        Assert.areEqual(0, [
            SELECT COUNT() FROM Exploratory_Session__c WHERE Id = :sessionId
        ], 'Admin moderation removed the finished session.');
    }

    @IsTest
    static void workspaceViewerIsAdminFollowsUatConsole() {
        Test_Cycle__c cycle = teamedCycle();
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(cycle.Id);
        }
        System.runAs(byLastName('UAT sestst2')) {
            Assert.isFalse(UatSessionController.getSessionWorkspace(sessionId).viewerIsAdmin,
                'Plain testers get no admin affordances.');
        }
        System.runAs(byLastName('UAT sesadm')) {
            Assert.isTrue(UatSessionController.getSessionWorkspace(sessionId).viewerIsAdmin,
                'UAT_Console flags the workspace for admin-only actions.');
        }
    }

    // ---- Standalone (cycle-less) sessions --------------------------------------

    @IsTest
    static void startStandaloneSessionVisibleToOwnerAndAdminOnly() {
        teamedCycle(); // a teamed cycle exists but the session ignores it
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            Test.startTest();
            sessionId = startStandardSession(null);
            Test.stopTest();

            Exploratory_Session__c s = [
                SELECT Test_Cycle__c, Status__c, Tester__c
                FROM Exploratory_Session__c WHERE Id = :sessionId
            ];
            Assert.isNull(s.Test_Cycle__c, 'Standalone = no cycle.');
            Assert.areEqual(UatConstants.SESSION_ACTIVE, s.Status__c);

            List<UatSessionController.SessionDTO> mine =
                UatSessionController.getExploratorySessions();
            Assert.areEqual(1, mine.size(), 'Owner sees their standalone session.');
            Assert.isNull(mine[0].cycleId);
            Assert.isNull(mine[0].cycleName);
        }

        System.runAs(byLastName('UAT sestst2')) {
            Assert.areEqual(0, UatSessionController.getExploratorySessions().size(),
                'Standalone sessions are personal — teammates do not see them.');
        }

        System.runAs(byLastName('UAT sesadm')) {
            Assert.areEqual(1, UatSessionController.getExploratorySessions().size(),
                'Admins see all standalone sessions — moderation must reach them.');
        }

        // Any tester may go standalone — even one on no team at all.
        System.runAs(byLastName('UAT sesout')) {
            Id outsiderSession = startStandardSession(null);
            Assert.isNotNull(outsiderSession);
        }
    }

    @IsTest
    static void standaloneWorkspaceAndWritesAreOwnerOrAdminOnly() {
        Id sessionId;
        System.runAs(byLastName('UAT sestst1')) {
            sessionId = startStandardSession(null);
        }

        System.runAs(byLastName('UAT sestst2')) {
            try {
                UatSessionController.getSessionWorkspace(sessionId);
                Assert.fail('A peer must not read a standalone session.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('personal'), e.getMessage());
            }
        }

        System.runAs(byLastName('UAT sesadm')) {
            UatSessionController.SessionWorkspaceDTO ws =
                UatSessionController.getSessionWorkspace(sessionId);
            Assert.isTrue(ws.viewerIsAdmin, 'Admin opens any standalone session.');
        }

        System.runAs(byLastName('UAT sestst1')) {
            UatSessionController.addSessionNote(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId, 'text' => 'Standalone entry'
            }));
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            Assert.areEqual(UatConstants.SESSION_COMPLETED, [
                SELECT Status__c FROM Exploratory_Session__c WHERE Id = :sessionId
            ].Status__c, 'Owner works their standalone session end to end.');
        }
    }

    @IsTest
    static void standaloneFindingCarriesNullCycleAndOwnerGates() {
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(null);
            Id findingId = addFinding(sessionId, 'High');
            Exploratory_Finding__c f = [
                SELECT Test_Cycle__c, Exploratory_Session__c
                FROM Exploratory_Finding__c WHERE Id = :findingId
            ];
            Assert.isNull(f.Test_Cycle__c, 'Cycle derives from the session: null.');
            Assert.areEqual(sessionId, f.Exploratory_Session__c);

            // Author edits and deletes their null-cycle finding.
            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'id' => findingId,
                'title' => 'Survivor history vanished after merge',
                'type' => 'Defect',
                'severity' => 'Low',
                'whatTesting' => 'Merged two records — updated',
                'whatHappened' => 'History vanished from the survivor'
            }));
            UatRunController.deleteFinding(findingId);
            Assert.areEqual(0, [
                SELECT COUNT() FROM Exploratory_Finding__c WHERE Id = :findingId
            ]);
        }
    }

    @IsTest
    static void deleteStandaloneSessionRemovesItsFindings() {
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(null);
            Id findingId = addFinding(sessionId, 'High');
            Id docId = UatTestDataFactory.attachFile(findingId, 'evidence-shot');

            Test.startTest();
            UatSessionController.deleteSession(sessionId);
            Test.stopTest();

            Assert.areEqual(0, [
                SELECT COUNT() FROM Exploratory_Session__c WHERE Id = :sessionId
            ], 'The session row is gone.');
            Assert.areEqual(0, [
                SELECT COUNT() FROM Exploratory_Finding__c WHERE Id = :findingId
            ], 'Standalone findings die with the session — no cycle log to fall back to.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM ContentDocument WHERE Id = :docId
            ], 'The document itself stays in its uploader\'s Files.');
        }
    }

    @IsTest
    static void directLogFindingStillRequiresCycle() {
        System.runAs(byLastName('UAT sestst1')) {
            try {
                UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                    'title' => 'Loose note with no home',
                    'type' => 'Question',
                    'whatHappened' => 'No session, no cycle'
                }));
                Assert.fail('The direct cycle-log path stays cycle-required.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Missing cycle'), e.getMessage());
            }
        }
    }

    /**
     * INVERTED 2026-08-06 (was finishSweepsStagedSessionLinks). Session file
     * links used to mean only "evidence staged for a finding form that never
     * claimed it", so finish deleted them as dead weight. Testers can now
     * attach screenshots straight to their running notes, which makes those
     * same links the session's own evidence — deleting them on finish would
     * destroy the record the tester just spent the session building.
     */
    @IsTest
    static void finishKeepsSessionEvidence() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            Id docId = UatTestDataFactory.attachFile(sessionId, 'notes-screenshot');

            Test.startTest();
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            Test.stopTest();

            Assert.areEqual(1, [
                SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :sessionId
            ], 'Finish must NOT purge the session\'s own evidence.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM ContentDocument WHERE Id = :docId
            ], 'And the document itself survives.');
        }
    }

    /** Promote copies the entry's evidence onto the finding and leaves the
     *  entry holding it too — the timeline is the tester's record of what they
     *  saw, and stripping it would rewrite history. */
    @IsTest
    static void promotingAnEntryCopiesItsEvidenceWithoutStrippingIt() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatSessionController.NoteDTO entry = UatSessionController.addSessionNote(
                JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId, 'text' => 'Duplicate warning never appeared'
                }));
            UatTestDataFactory.attachFile(entry.id, 'entry-shot');

            Test.startTest();
            Id findingId = UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId,
                'sourceNoteId' => entry.id,
                'title' => 'Duplicate warning never appeared',
                'type' => 'Defect',
                // Critical, with no reason given: the entry's screenshot is
                // what satisfies the evidence gate.
                'severity' => 'Critical',
                'whatHappened' => 'Merged two records and nothing warned me'
            }));
            Test.stopTest();

            Assert.areEqual(1, [
                SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :findingId
            ], 'The finding gets its own link to the same document.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :entry.id
            ], 'And the entry keeps it — copy, not move.');
        }
    }


    // ---- Entry points (dashboard + in-run) -------------------------------------------

    /**
     * Find-or-create is the whole point: a tester who reaches for the escape
     * hatch repeatedly across a sprint should land back in ONE running log, not
     * leave a trail of empty sessions for someone to tidy up.
     */
    @IsTest
    static void adHocSessionIsFoundNotDuplicated() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Test.startTest();
            Id first = UatSessionController.findOrCreateAdHocSession(cycle.Id);
            Id second = UatSessionController.findOrCreateAdHocSession(cycle.Id);
            Test.stopTest();

            Assert.areEqual(first, second, 'The second click reuses the first session.');
            Assert.areEqual(1, [
                SELECT COUNT() FROM Exploratory_Session__c WHERE Test_Cycle__c = :cycle.Id
            ]);

            // A different cycle is a different log — including "no cycle".
            Id standalone = UatSessionController.findOrCreateAdHocSession(null);
            Assert.areNotEqual(first, standalone);
            Assert.isNull([
                SELECT Test_Cycle__c FROM Exploratory_Session__c WHERE Id = :standalone
            ].Test_Cycle__c);
        }
    }

    /** A finished session is not reusable — reaching for the hatch again after
     *  finishing starts a fresh log rather than reopening a closed one. */
    @IsTest
    static void adHocSessionSkipsAFinishedOne() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id first = UatSessionController.findOrCreateAdHocSession(cycle.Id);
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => first
            }));

            Test.startTest();
            Id second = UatSessionController.findOrCreateAdHocSession(cycle.Id);
            Test.stopTest();

            Assert.areNotEqual(first, second);
        }
    }

    /** Someone else's cycle is still someone else's cycle. */
    @IsTest
    static void adHocSessionRespectsTheCycleAudience() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sesout')) {
            try {
                UatSessionController.findOrCreateAdHocSession(cycle.Id);
                Assert.fail('An outsider must not open a log in a teamed cycle.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('another team'), e.getMessage());
            }
        }
    }

    /**
     * The in-run entry point. The tester is mid-case, so the server does all
     * the finding and linking — the client names only the run it is on.
     */
    @IsTest
    static void offScriptNoteLandsInTheRunsCycleAndLinksBack() {
        Test_Cycle__c cycle = teamedCycle();
        Test_Execution__c slot = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
        ];
        System.runAs(byLastName('UAT sestst1')) {
            Test.startTest();
            UatSessionController.NoteDTO entry = UatSessionController.logOffScript(
                JSON.serialize(new Map<String, Object>{
                    'executionId' => slot.Id,
                    'text' => 'Breadcrumb is wrong on this screen'
                }));
            Test.stopTest();

            Assert.areEqual('Breadcrumb is wrong on this screen', entry.text);
            Assert.areEqual(slot.Id, entry.executionId, 'Pre-linked to the run.');

            Session_Note__c row = [
                SELECT Exploratory_Session__r.Test_Cycle__c,
                    Exploratory_Session__r.Tester__c
                FROM Session_Note__c WHERE Id = :entry.id
            ];
            Assert.areEqual(cycle.Id, row.Exploratory_Session__r.Test_Cycle__c,
                'The log belongs to the run\'s cycle, not to a guess.');
            Assert.areEqual(UserInfo.getUserId(), row.Exploratory_Session__r.Tester__c);

            // A second note joins the same log rather than starting another.
            UatSessionController.logOffScript(JSON.serialize(new Map<String, Object>{
                'executionId' => slot.Id, 'text' => 'And the back link goes nowhere'
            }));
            Assert.areEqual(1, [
                SELECT COUNT() FROM Exploratory_Session__c WHERE Test_Cycle__c = :cycle.Id
            ]);
            Assert.areEqual(2, [SELECT COUNT() FROM Session_Note__c]);
        }
    }

    @IsTest
    static void offScriptNoteNeedsARunAndSomeText() {
        Test_Cycle__c cycle = teamedCycle();
        Test_Execution__c slot = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycle.Id LIMIT 1
        ];
        System.runAs(byLastName('UAT sestst1')) {
            try {
                UatSessionController.logOffScript(JSON.serialize(new Map<String, Object>{
                    'text' => 'No run named'
                }));
                Assert.fail('Missing execution must throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('test run'), e.getMessage());
            }
            try {
                UatSessionController.logOffScript(JSON.serialize(new Map<String, Object>{
                    'executionId' => slot.Id, 'text' => '   '
                }));
                Assert.fail('An empty note must throw.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Write something'), e.getMessage());
            }
        }
    }

    // ---- The finish gate ------------------------------------------------------------

    /**
     * The one rule strong enough to stop someone: a severe defect nobody can
     * reproduce is a severe defect nobody will fix, and the session is the last
     * moment the tester still remembers what they saw.
     */
    @IsTest
    static void finishBlocksOnASevereDefectWithNoEvidenceOrReason() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            Id findingId = UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId,
                'title' => 'Save button missing on the household form',
                'type' => 'Defect',
                'severity' => 'Critical',
                'whatHappened' => 'No save button at all',
                'noEvidenceReason' => 'Placeholder so the save itself is allowed.'
            }));
            // Strip the reason to reach the state the gate exists for: a severe
            // defect that ended up with neither evidence nor an explanation.
            update new Exploratory_Finding__c(Id = findingId, No_Evidence_Reason__c = null);

            Test.startTest();
            try {
                UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                    'sessionId' => sessionId
                }));
                Assert.fail('An unevidenced severe defect must block the finish.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Save button missing'), e.getMessage());
            }
            Test.stopTest();

            Assert.areEqual(UatConstants.SESSION_ACTIVE, [
                SELECT Status__c FROM Exploratory_Session__c WHERE Id = :sessionId
            ].Status__c, 'The session stays open.');

            // Evidence satisfies it just as a written reason would.
            UatTestDataFactory.attachFile(findingId, 'repro-shot');
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            Assert.areEqual(UatConstants.SESSION_COMPLETED, [
                SELECT Status__c FROM Exploratory_Session__c WHERE Id = :sessionId
            ].Status__c);
        }
    }

    /** Low and Medium defects never block — the gate is about severity, not
     *  about tidiness. */
    @IsTest
    static void finishIgnoresMildDefectsWithoutEvidence() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatRunController.saveFinding(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId,
                'title' => 'Wording on the merge screen is confusing',
                'type' => 'Defect',
                'severity' => 'Medium',
                'whatHappened' => 'Two buttons say almost the same thing'
            }));

            Test.startTest();
            UatSessionController.finishSession(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId
            }));
            Test.stopTest();

            Assert.areEqual(UatConstants.SESSION_COMPLETED, [
                SELECT Status__c FROM Exploratory_Session__c WHERE Id = :sessionId
            ].Status__c);
        }
    }

    // ---- Focus prompts: config, not code -----------------------------------------

    /** No cycle override → the org defaults. Whether those come from deployed
     *  UAT_Focus_Prompt__mdt records or the built-in fallback, the contract the
     *  client depends on is the same: a non-empty list, every entry labelled and
     *  carrying insert text. */
    @IsTest
    static void promptsFallBackToOrgDefaults() {
        Test_Cycle__c cycle = teamedCycle();
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatSessionController.SessionWorkspaceDTO ws =
                UatSessionController.getSessionWorkspace(sessionId);
            Assert.isFalse(ws.prompts.isEmpty(), 'A session always offers prompts.');
            Assert.isTrue(ws.prompts.size() <= 8, 'The chip row is capped at 8.');
            for (UatSessionController.PromptDTO p : ws.prompts) {
                Assert.isNotNull(p.label, 'Every chip needs a button label.');
                Assert.isTrue(String.isNotBlank(p.insertText),
                    'Every chip must insert something.');
            }
        }
    }

    @IsTest
    static void cycleOverrideReplacesDefaultPrompts() {
        Test_Cycle__c cycle = teamedCycle();
        // Line 2 has no pipe: the label doubles as the insert with ": " added.
        // Lines 4-5 are blank/pipe-only junk and must simply drop out.
        cycle.Focus_Prompts__c = 'Steps | Steps to reproduce:\n'
            + 'Regression\n'
            + '  Spacing | Trimmed both sides  \n'
            + '\n'
            + '   |   ';
        update cycle;
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatSessionController.SessionWorkspaceDTO ws =
                UatSessionController.getSessionWorkspace(sessionId);

            Assert.areEqual(3, ws.prompts.size(),
                'Blank and label-less lines drop out.');
            Assert.areEqual('Steps', ws.prompts[0].label);
            Assert.areEqual('Steps to reproduce: ', ws.prompts[0].insertText);
            Assert.areEqual('Regression', ws.prompts[1].label);
            Assert.areEqual('Regression: ', ws.prompts[1].insertText,
                'No pipe = label plus ": ".');
            Assert.areEqual('Spacing', ws.prompts[2].label);
            Assert.areEqual('Trimmed both sides ', ws.prompts[2].insertText);
        }
    }

    /** An override of nothing but junk must not leave the tester chipless. */
    @IsTest
    static void unparseableOverrideFallsBackToDefaults() {
        Test_Cycle__c cycle = teamedCycle();
        cycle.Focus_Prompts__c = '\n   \n  |  \n';
        update cycle;
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = startStandardSession(cycle.Id);
            UatSessionController.SessionWorkspaceDTO ws =
                UatSessionController.getSessionWorkspace(sessionId);
            Assert.isFalse(ws.prompts.isEmpty(),
                'Junk in the override falls through to the org defaults.');
        }
    }

    /** A standalone session has no cycle to override anything. */
    @IsTest
    static void standaloneSessionGetsOrgDefaultPrompts() {
        System.runAs(byLastName('UAT sestst1')) {
            Id sessionId = UatSessionController.startSession(JSON.serialize(
                new Map<String, Object>{
                    'title' => 'Standalone prompts',
                    'charter' => 'Poke at things with no cycle.'
                }));
            UatSessionController.SessionWorkspaceDTO ws =
                UatSessionController.getSessionWorkspace(sessionId);
            Assert.isFalse(ws.prompts.isEmpty(),
                'Cycle-less sessions still get the org defaults.');
        }
    }
}