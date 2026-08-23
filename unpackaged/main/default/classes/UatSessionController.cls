/**
 * UatSessionController
 *
 * Apex behind the ad-hoc session workflow (uatSessionList +
 * uatSessionWorkspace): list the audience's sessions, start one, log entries in
 * its timeline, finish it, or delete it. Kept out of UatRunController
 * deliberately — that class is the case/claim surface; sessions are a
 * separate workflow that only shares the audience gates (UatAudienceService)
 * and the finding DTO mapping (UatRunController.toFindingDTOs).
 *
 * Ownership model (2026-08 decision): a CYCLED session is PERSONAL but
 * TEAM-VISIBLE — any cycle-audience member can read it; only the owning
 * tester — or a UAT_Console admin — can edit notes, add findings (enforced
 * in UatRunController.saveFinding), or finish. A STANDALONE session (null
 * cycle) has no team audience: it is personal outright — owner-or-admin on
 * every path, reads included (UatAudienceService.assertSessionAudience).
 * Both are Apex-enforced; the objects' OWD is Public Read/Write.
 *
 * Lifecycle: born Active (there is no Not Started — a session exists once the
 * tester starts working), finished to Completed exactly once. The timebox is
 * display-only; nothing here enforces it. Deletion: the owner may delete
 * their own ACTIVE session (queue cleanup); Completed sessions are part of
 * the team record — only a UAT admin deletes those. A cycled session's
 * findings survive its delete (SetNull lookup) and fall back to the cycle
 * log; a standalone session's findings die with it — there is no log for a
 * null-cycle finding to fall back to.
 *
 * The LOG (2026-08-06): a session's notes are Session_Note__c rows, not one
 * Session_Notes__c blob. Each entry is timestamped at insert, optionally
 * tagged, individually attachable, and individually promotable to a Finding —
 * which is what replaced the undiscoverable "select note text before adding a
 * finding" gesture. Evidence hangs off the ENTRY, so it is always clear what a
 * screenshot is evidence FOR. Editing an entry never restamps Logged_At__c, so
 * a correction does not move it in the timeline.
 *
 * Finishing is gated: a High/Critical defect with neither evidence nor a stated
 * reason throws (assertSevereDefectsAreEvidenced). Every other checklist item
 * is orientation only.
 *
 * Tag chips are config, not code — resolved per session as cycle override
 * (Test_Cycle__c.Focus_Prompts__c) → active UAT_Focus_Prompt__mdt records →
 * built-in defaults. See resolvePrompts.
 *
 * Conventions: with sharing, describe asserts, AuraHandledException,
 * JSON-string write payloads (org quirk).
 */
public with sharing class UatSessionController {

    // ---- DTOs ----------------------------------------------------------------

    public class SessionDTO {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String name;            // 'ES-00012'
        @AuraEnabled public String title;
        @AuraEnabled public String charter;
        @AuraEnabled public String areaText;
        @AuraEnabled public Id cycleId;
        @AuraEnabled public String cycleName;
        @AuraEnabled public String status;          // Active | Completed
        @AuraEnabled public Integer timeboxMinutes;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime finishedAt;
        @AuraEnabled public Datetime lastUpdated;   // LastModifiedDate
        @AuraEnabled public Integer findingsCount = 0;
        @AuraEnabled public Integer filesCount = 0; // evidence across the session's findings
        @AuraEnabled public Boolean isMine;
        @AuraEnabled public Id testerId;
        @AuraEnabled public String testerName;
    }

    public class SessionWorkspaceDTO {
        @AuraEnabled public SessionDTO session;
        @AuraEnabled public List<UatRunController.FindingDTO> findings =
            new List<UatRunController.FindingDTO>();
        /** Lets the workspace render admin-only affordances (delete any
         *  session). Deliberately NOT on the list DTO — the list stays
         *  owner-scoped. */
        @AuraEnabled public Boolean viewerIsAdmin = false;
        /** The session's log, oldest first. Replaces the single notes blob. */
        @AuraEnabled public List<NoteDTO> notes = new List<NoteDTO>();
        /** Tag chips offered by the composer, already resolved (cycle override
         *  → CMDT → built-in defaults). Rides this DTO so the workspace needs
         *  no second round trip. */
        @AuraEnabled public List<PromptDTO> prompts = new List<PromptDTO>();
    }

    public class PromptDTO {
        @AuraEnabled public String label;      // the chip's button text
        @AuraEnabled public String insertText; // legacy name; the tag value
    }

    public class NoteDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;          // 'SN-00007'
        @AuraEnabled public String text;
        @AuraEnabled public String tag;           // may be blank — tagging is optional
        @AuraEnabled public Datetime loggedAt;
        @AuraEnabled public Id authorId;
        @AuraEnabled public String authorName;
        @AuraEnabled public Boolean isMine = false;
        /** Set when this entry was logged from inside a scripted run. */
        @AuraEnabled public Id executionId;
        @AuraEnabled public String caseTitle;
        /** Populated once the entry has been promoted — drives the "→ EF-00003"
         *  badge, and tells the client not to offer Promote a second time. */
        @AuraEnabled public Id findingId;
        @AuraEnabled public String findingName;
        @AuraEnabled public List<UatFileService.FileDTO> files =
            new List<UatFileService.FileDTO>();
    }

    public class NoteInput {
        public Id id;             // null = create
        public Id sessionId;      // create only
        public Id executionId;    // create only: logged from a scripted run
        public String text;
        public String tag;
    }

    public class SessionStartInput {
        public String title;
        public String charter;
        public String areaText;
        public Integer timeboxMinutes;
        public Id cycleId;
    }

    public class SessionFinishInput {
        public Id sessionId;
    }

    // ---- Endpoints -------------------------------------------------------------

    /** Every session in my audience cycles (team cycles + team-less ones),
     *  newest first, plus standalone (null-cycle) sessions — mine always,
     *  everyone's for a UAT admin (moderation has to be able to reach them).
     *  The client scopes by cycle like the rest of the queue. Sessions in
     *  closed cycles drop out — consistent with the whole app. */
    @AuraEnabled
    public static List<SessionDTO> getExploratorySessions() {
        UatAudienceService.assertTester();
        Id me = UserInfo.getUserId();
        Set<Id> myTeams = UatAudienceService.myTeamIds(me);
        Boolean viewerIsAdmin = UatAudienceService.isUatAdmin();
        List<Exploratory_Session__c> rows = [
            SELECT Id, Name, Title__c, Charter__c, Area__c, Status__c,
                Timebox_Minutes__c, Started_At__c, Finished_At__c, LastModifiedDate,
                Tester__c, Tester__r.Name,
                Test_Cycle__c, Test_Cycle__r.Name
            FROM Exploratory_Session__c
            WHERE (Test_Cycle__c = null
                OR ((Test_Cycle__r.Assigned_Team__c IN :myTeams
                        OR Test_Cycle__r.Assigned_Team__c = null)
                    AND Test_Cycle__r.Status__c != :UatConstants.CYCLE_CLOSED))
            ORDER BY Started_At__c DESC
            LIMIT 500
        ];
        // Standalone sessions are personal — owner-or-admin. SOQL can't bind
        // the admin flag into the predicate, so the last mile is filtered here.
        List<Exploratory_Session__c> sessions = new List<Exploratory_Session__c>();
        for (Exploratory_Session__c s : rows) {
            if (s.Test_Cycle__c == null && s.Tester__c != me && !viewerIsAdmin) {
                continue;
            }
            sessions.add(s);
        }

        // Findings per session, files per finding — two queries total.
        Map<Id, Integer> findingsBySession = new Map<Id, Integer>();
        Map<Id, Id> sessionByFinding = new Map<Id, Id>();
        for (Exploratory_Finding__c f : [
            SELECT Id, Exploratory_Session__c FROM Exploratory_Finding__c
            WHERE Exploratory_Session__c IN :new Map<Id, Exploratory_Session__c>(sessions).keySet()
        ]) {
            sessionByFinding.put(f.Id, f.Exploratory_Session__c);
            Integer runningTotal = findingsBySession.containsKey(f.Exploratory_Session__c)
                ? findingsBySession.get(f.Exploratory_Session__c) : 0;
            findingsBySession.put(f.Exploratory_Session__c, runningTotal + 1);
        }
        Map<Id, Integer> filesBySession = new Map<Id, Integer>();
        if (!sessionByFinding.isEmpty()) {
            Map<Id, List<UatFileService.FileDTO>> filesByFinding =
                UatFileService.getFilesFor(sessionByFinding.keySet());
            for (Id findingId : filesByFinding.keySet()) {
                Id sessionId = sessionByFinding.get(findingId);
                Integer runningTotal = filesBySession.containsKey(sessionId)
                    ? filesBySession.get(sessionId) : 0;
                filesBySession.put(sessionId, runningTotal + filesByFinding.get(findingId).size());
            }
        }

        List<SessionDTO> result = new List<SessionDTO>();
        for (Exploratory_Session__c s : sessions) {
            SessionDTO dto = toSessionDTO(s, me);
            if (findingsBySession.containsKey(s.Id)) {
                dto.findingsCount = findingsBySession.get(s.Id);
            }
            if (filesBySession.containsKey(s.Id)) {
                dto.filesCount = filesBySession.get(s.Id);
            }
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static Id startSession(String inputJson) {
        UatAudienceService.assertTester();
        SessionStartInput input;
        try {
            input = (SessionStartInput) JSON.deserialize(inputJson, SessionStartInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the session — refresh and try again.');
        }
        if (input == null || String.isBlank(input.title)) {
            throw auraError('Give the session a title.');
        }
        // Charter is no longer asked for or required (2026-08-06). It was
        // exploratory-testing ceremony standing between a business user and
        // writing down what they just saw; Area__c carries the one optional
        // line ("what are you looking at?") instead.
        if (input.timeboxMinutes != null && input.timeboxMinutes <= 0) {
            throw auraError('Timebox must be a positive number of minutes.');
        }
        // Null cycle = standalone personal session — any tester may start one.
        if (input.cycleId != null) {
            UatAudienceService.assertCycleAudience(input.cycleId);
        }
        Exploratory_Session__c session = new Exploratory_Session__c(
            Title__c = input.title,
            Charter__c = input.charter,
            Area__c = String.isBlank(input.areaText) ? null : input.areaText,
            Timebox_Minutes__c = input.timeboxMinutes,
            Test_Cycle__c = input.cycleId,
            Tester__c = UserInfo.getUserId(),
            Status__c = UatConstants.SESSION_ACTIVE,
            Started_At__c = System.now()
        );
        insert session;
        return session.Id;
    }

    /** The full workspace: session + notes + its findings (files attached).
     *  Cycled: team-visible — any audience member may open it; the client
     *  renders it read-only unless isMine and Active (the write endpoints
     *  enforce the same server-side). Standalone: owner-or-admin only. */
    @AuraEnabled
    public static SessionWorkspaceDTO getSessionWorkspace(Id sessionId) {
        UatAudienceService.assertTester();
        Exploratory_Session__c session = loadSession(sessionId);
        UatAudienceService.assertSessionAudience(session.Test_Cycle__c, session.Tester__c);

        SessionWorkspaceDTO dto = new SessionWorkspaceDTO();
        dto.session = toSessionDTO(session, UserInfo.getUserId());
        dto.viewerIsAdmin = UatAudienceService.isUatAdmin();
        dto.prompts = resolvePrompts(session.Test_Cycle__r);
        dto.notes = loadNotes(sessionId);

        List<Exploratory_Finding__c> findings = [
            SELECT Id, Name, Title__c, Type__c, Source__c,
                What_Testing__c, What_Expected__c, What_Happened__c,
                Severity__c, Workflow_Status__c, External_Ref__c,
                No_Evidence_Reason__c,
                Source_Note__c, Source_Note__r.Logged_At__c,
                Test_Execution__c, Test_Execution__r.Test_Case__r.Title__c,
                Tester__c, Tester__r.Name, Date__c,
                Exploratory_Session__c, Exploratory_Session__r.Name,
                Exploratory_Session__r.Title__c
            FROM Exploratory_Finding__c
            WHERE Exploratory_Session__c = :sessionId
            ORDER BY CreatedDate DESC
        ];
        Map<Id, List<UatFileService.FileDTO>> filesByFinding =
            UatFileService.getFilesFor(new Map<Id, Exploratory_Finding__c>(findings).keySet());
        dto.findings = UatRunController.toFindingDTOs(findings, filesByFinding);
        dto.session.findingsCount = dto.findings.size();
        Integer files = 0;
        for (UatRunController.FindingDTO f : dto.findings) {
            files += f.files.size();
        }
        dto.session.filesCount = files;
        return dto;
    }

    /**
     * Stamps Completed + Finished_At.
     *
     * HARD GATE (2026-08-06): a High or Critical defect with neither evidence
     * nor a stated reason blocks the finish. It is the one rule strong enough
     * to be worth stopping someone over — a severe defect nobody can reproduce
     * is a severe defect nobody will fix, and the session is the last moment
     * the tester still remembers what they saw. Everything else in the
     * "before finishing" checklist is orientation and does not block.
     */
    @AuraEnabled
    public static void finishSession(String inputJson) {
        UatAudienceService.assertTester();
        SessionFinishInput input;
        try {
            input = (SessionFinishInput) JSON.deserialize(inputJson, SessionFinishInput.class);
        } catch (Exception e) {
            throw auraError('Could not read the request — refresh and try again.');
        }
        if (input == null || input.sessionId == null) {
            throw auraError('Missing session — refresh and try again.');
        }
        Exploratory_Session__c session = loadSession(input.sessionId);
        UatAudienceService.assertSessionAudience(session.Test_Cycle__c, session.Tester__c);
        UatAudienceService.assertOwnerOrAdmin(session.Tester__c, 'session');
        if (session.Status__c == UatConstants.SESSION_COMPLETED) {
            throw auraError('This session is already finished.');
        }
        assertSevereDefectsAreEvidenced(session.Id);
        update new Exploratory_Session__c(
            Id = session.Id,
            Status__c = UatConstants.SESSION_COMPLETED,
            Finished_At__c = System.now()
        );
        // NO staging sweep here since 2026-08-06. Session file links used to
        // mean only "evidence staged for a finding form that never claimed
        // it", so finish deleted them as dead weight. Testers can now attach
        // screenshots directly to their running notes, which makes those same
        // links the session's own EVIDENCE — deleting them on finish would
        // destroy the record the tester just spent the session building. A
        // file abandoned by a cancelled finding form now surfaces as session
        // evidence instead of invisible dead weight, which is the better
        // outcome and is why no discriminator field was needed.
    }

    /**
     * Owner cleanup or admin moderation. Owner: own ACTIVE sessions only —
     * a finished session is part of the team record. Admin (UAT_Console):
     * any session, any status. A cycled session's findings survive (SetNull)
     * and fall back to the cycle log; a standalone session's findings are
     * deleted with it — null-cycle findings exist nowhere outside their
     * session's workspace. The session's evidence links die with the record
     * (the documents themselves stay in the uploaders' Files).
     */
    @AuraEnabled
    public static void deleteSession(Id sessionId) {
        UatAudienceService.assertTester();
        Exploratory_Session__c session = loadSession(sessionId);
        UatAudienceService.assertSessionAudience(session.Test_Cycle__c, session.Tester__c);
        UatAudienceService.assertOwnerOrAdmin(session.Tester__c, 'session');
        if (session.Status__c == UatConstants.SESSION_COMPLETED
            && !UatAudienceService.isUatAdmin()) {
            throw auraError('Finished sessions are part of the team record — ask a UAT admin to delete this one.');
        }
        if (session.Test_Cycle__c == null) {
            delete [
                SELECT Id FROM Exploratory_Finding__c
                WHERE Exploratory_Session__c = :session.Id
            ];
        }
        delete new Exploratory_Session__c(Id = session.Id);
    }

    /**
     * The one blocking rule on the way out. A High or Critical defect with
     * neither evidence nor a stated reason cannot be reproduced by whoever
     * picks it up, and the session is the last moment the tester still
     * remembers what they saw — so this throws rather than warns.
     *
     * Mirrors UatRunController's save-time rule, but has to be re-checked here:
     * a finding can be saved with a screenshot and have it deleted afterwards,
     * and severity can be raised on an existing finding.
     */
    private static void assertSevereDefectsAreEvidenced(Id sessionId) {
        // No_Evidence_Reason__c is a LongTextArea, and the platform refuses to
        // filter on those in SOQL — so it is selected and tested in Apex.
        List<Exploratory_Finding__c> severe = new List<Exploratory_Finding__c>();
        for (Exploratory_Finding__c f : [
            SELECT Id, Name, Title__c, No_Evidence_Reason__c
            FROM Exploratory_Finding__c
            WHERE Exploratory_Session__c = :sessionId
            AND Type__c = :UatRunController.FINDING_TYPE_DEFECT
            AND Severity__c IN ('High', 'Critical')
        ]) {
            if (String.isBlank(f.No_Evidence_Reason__c)) {
                severe.add(f);
            }
        }
        if (severe.isEmpty()) {
            return;
        }
        Map<Id, List<UatFileService.FileDTO>> filesByFinding =
            UatFileService.getFilesFor(new Map<Id, Exploratory_Finding__c>(severe).keySet());
        List<String> unevidenced = new List<String>();
        for (Exploratory_Finding__c f : severe) {
            List<UatFileService.FileDTO> files = filesByFinding.get(f.Id);
            if (files == null || files.isEmpty()) {
                unevidenced.add(String.isBlank(f.Title__c) ? f.Name : f.Title__c);
            }
        }
        if (unevidenced.isEmpty()) {
            return;
        }
        throw auraError(unevidenced.size() == 1
            ? 'Attach a screenshot to "' + unevidenced[0]
                + '" — or say why there isn\'t one — before finishing.'
            : unevidenced.size() + ' severe defects still need a screenshot or a reason: '
                + String.join(unevidenced, '; '));
    }

    // ---- The session log ---------------------------------------------------------

    /**
     * Oldest first — this reads as a log of what happened, not a feed. Findings
     * are joined in so an already-promoted entry can show its badge instead of
     * offering Promote again; the join is by Source_Note__c, one query for the
     * whole session.
     */
    private static List<NoteDTO> loadNotes(Id sessionId) {
        List<Session_Note__c> rows = [
            SELECT Id, Name, Entry_Text__c, Tag__c, Logged_At__c,
                Author__c, Author__r.Name,
                Test_Execution__c, Test_Execution__r.Test_Case__r.Title__c
            FROM Session_Note__c
            WHERE Exploratory_Session__c = :sessionId
            ORDER BY Logged_At__c ASC, CreatedDate ASC
            LIMIT 1000
        ];
        if (rows.isEmpty()) {
            return new List<NoteDTO>();
        }
        Set<Id> noteIds = new Map<Id, Session_Note__c>(rows).keySet();
        Map<Id, Exploratory_Finding__c> findingByNote =
            new Map<Id, Exploratory_Finding__c>();
        for (Exploratory_Finding__c f : [
            SELECT Id, Name, Source_Note__c FROM Exploratory_Finding__c
            WHERE Source_Note__c IN :noteIds
        ]) {
            findingByNote.put(f.Source_Note__c, f);
        }
        Map<Id, List<UatFileService.FileDTO>> filesByNote =
            UatFileService.getFilesFor(noteIds);

        Id me = UserInfo.getUserId();
        List<NoteDTO> result = new List<NoteDTO>();
        for (Session_Note__c n : rows) {
            NoteDTO dto = new NoteDTO();
            dto.id = n.Id;
            dto.name = n.Name;
            dto.text = n.Entry_Text__c;
            dto.tag = n.Tag__c;
            dto.loggedAt = n.Logged_At__c;
            dto.authorId = n.Author__c;
            dto.authorName = n.Author__r != null ? n.Author__r.Name : null;
            dto.isMine = n.Author__c == me;
            dto.executionId = n.Test_Execution__c;
            dto.caseTitle = n.Test_Execution__r != null
                && n.Test_Execution__r.Test_Case__r != null
                ? n.Test_Execution__r.Test_Case__r.Title__c : null;
            if (findingByNote.containsKey(n.Id)) {
                dto.findingId = findingByNote.get(n.Id).Id;
                dto.findingName = findingByNote.get(n.Id).Name;
            }
            if (filesByNote.containsKey(n.Id)) {
                dto.files = filesByNote.get(n.Id);
            }
            result.add(dto);
        }
        return result;
    }

    /** Logging an entry is the one write a tester does constantly, so it stays
     *  cheap: no cycle round trip, no reload — the client appends what this
     *  returns. Author-or-admin is asserted on the SESSION, because that is
     *  what the entry belongs to. */
    @AuraEnabled
    public static NoteDTO addSessionNote(String inputJson) {
        UatAudienceService.assertTester();
        NoteInput input = parseNote(inputJson);
        if (input.sessionId == null) {
            throw auraError('Missing session — refresh and try again.');
        }
        if (String.isBlank(input.text)) {
            throw auraError('Write something before adding the entry.');
        }
        Exploratory_Session__c session = loadSession(input.sessionId);
        UatAudienceService.assertSessionAudience(session.Test_Cycle__c, session.Tester__c);
        UatAudienceService.assertOwnerOrAdmin(session.Tester__c, 'session');
        assertSessionActive(session);

        Session_Note__c note = new Session_Note__c(
            Exploratory_Session__c = session.Id,
            Entry_Text__c = input.text,
            Tag__c = String.isBlank(input.tag) ? null : input.tag,
            Test_Execution__c = input.executionId,
            Author__c = UserInfo.getUserId(),
            // Server-stamped and never edited afterwards, so editing an entry's
            // text does not move it in the timeline.
            Logged_At__c = System.now()
        );
        insert note;
        return loadOneNote(note.Id);
    }

    /** Author-or-admin, and only while the session is Active. Editing text does
     *  NOT restamp Logged_At__c. */
    @AuraEnabled
    public static NoteDTO updateSessionNote(String inputJson) {
        UatAudienceService.assertTester();
        NoteInput input = parseNote(inputJson);
        if (input.id == null) {
            throw auraError('Missing entry — refresh and try again.');
        }
        if (String.isBlank(input.text)) {
            throw auraError('An entry cannot be empty — delete it instead.');
        }
        Session_Note__c note = loadNote(input.id);
        Exploratory_Session__c session = loadSession(note.Exploratory_Session__c);
        UatAudienceService.assertSessionAudience(session.Test_Cycle__c, session.Tester__c);
        UatAudienceService.assertOwnerOrAdmin(note.Author__c, 'entry');
        assertSessionActive(session);
        update new Session_Note__c(
            Id = note.Id,
            Entry_Text__c = input.text,
            Tag__c = String.isBlank(input.tag) ? null : input.tag
        );
        return loadOneNote(note.Id);
    }

    /** Deleting an entry drops its evidence links but NOT any finding promoted
     *  from it — Source_Note__c is SetNull, so the finding keeps the copied
     *  text and its own evidence and simply loses the back-link. */
    @AuraEnabled
    public static void deleteSessionNote(Id noteId) {
        UatAudienceService.assertTester();
        Session_Note__c note = loadNote(noteId);
        Exploratory_Session__c session = loadSession(note.Exploratory_Session__c);
        UatAudienceService.assertSessionAudience(session.Test_Cycle__c, session.Tester__c);
        UatAudienceService.assertOwnerOrAdmin(note.Author__c, 'entry');
        assertSessionActive(session);
        delete new Session_Note__c(Id = noteId);
    }

    /**
     * "Log something off-script" — the entry point from the Dashboard and from
     * inside a scripted run.
     *
     * Find-or-create, deliberately: one Active ad-hoc session per tester per
     * cycle. A tester who clicks this five times across a sprint gets one
     * running log, not five stub sessions, and there is nothing to tidy up
     * afterwards. Reuse only picks up a session the caller could already write
     * to — their own, still Active, in this cycle.
     *
     * @param cycleId null = a standalone session (no cycle selected).
     */
    @AuraEnabled
    public static Id findOrCreateAdHocSession(Id cycleId) {
        UatAudienceService.assertTester();
        if (cycleId != null) {
            UatAudienceService.assertCycleAudience(cycleId);
        }
        Id me = UserInfo.getUserId();
        List<Exploratory_Session__c> mine = [
            SELECT Id FROM Exploratory_Session__c
            WHERE Tester__c = :me
            AND Status__c = :UatConstants.SESSION_ACTIVE
            AND Test_Cycle__c = :cycleId
            ORDER BY Started_At__c DESC
            LIMIT 1
        ];
        if (!mine.isEmpty()) {
            return mine[0].Id;
        }
        Exploratory_Session__c session = new Exploratory_Session__c(
            Title__c = 'Off-script notes',
            Test_Cycle__c = cycleId,
            Tester__c = me,
            Status__c = UatConstants.SESSION_ACTIVE,
            Started_At__c = System.now()
        );
        insert session;
        return session.Id;
    }

    /**
     * Log an entry from inside a scripted run without leaving it. Finds or
     * creates the tester's ad-hoc session in the SAME cycle as the run, links
     * the entry back to the execution, and returns the session so the client
     * can offer a way in later — the tester's place in the run is the client's
     * to keep, and nothing here disturbs it.
     */
    @AuraEnabled
    public static NoteDTO logOffScript(String inputJson) {
        UatAudienceService.assertTester();
        NoteInput input = parseNote(inputJson);
        if (input.executionId == null) {
            throw auraError('Missing the test run — refresh and try again.');
        }
        if (String.isBlank(input.text)) {
            throw auraError('Write something before adding the entry.');
        }
        Test_Execution__c execution;
        try {
            execution = [
                SELECT Id, Test_Cycle__c, Assigned_Tester__c
                FROM Test_Execution__c WHERE Id = :input.executionId
            ];
        } catch (QueryException e) {
            throw auraError('That test run no longer exists — refresh your queue.');
        }
        Id sessionId = findOrCreateAdHocSession(execution.Test_Cycle__c);
        return addSessionNote(JSON.serialize(new Map<String, Object>{
            'sessionId' => sessionId,
            'executionId' => execution.Id,
            'text' => input.text,
            'tag' => input.tag
        }));
    }

    /**
     * Move files the composer staged on the session onto the entry they were
     * meant for. lightning-file-upload hard-requires a record id, and the entry
     * does not exist until Add is pressed, so the session is the staging parent
     * exactly as it is for the finding form (uatEvidenceUpload's staging mode).
     *
     * The note's parent session is derived server-side from the note, never
     * named by the client, so files can only ever move session → its own entry.
     */
    @AuraEnabled
    public static void claimNoteFiles(Id noteId, List<String> contentDocumentIds) {
        UatAudienceService.assertTester();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return;
        }
        Session_Note__c note = loadNote(noteId);
        Exploratory_Session__c session = loadSession(note.Exploratory_Session__c);
        UatAudienceService.assertSessionAudience(session.Test_Cycle__c, session.Tester__c);
        UatAudienceService.assertOwnerOrAdmin(note.Author__c, 'entry');
        List<Id> docIds = new List<Id>();
        for (String s : contentDocumentIds) {
            docIds.add((Id) s);
        }
        try {
            UatFileService.relinkFiles(session.Id, note.Id, docIds);
        } catch (UatFileService.UatFileException e) {
            throw auraError(e.getMessage());
        }
    }

    private static NoteInput parseNote(String inputJson) {
        try {
            NoteInput input = (NoteInput) JSON.deserialize(inputJson, NoteInput.class);
            if (input == null) {
                throw new JSONException('null');
            }
            return input;
        } catch (Exception e) {
            throw auraError('Could not read the entry — refresh and try again.');
        }
    }

    private static void assertSessionActive(Exploratory_Session__c session) {
        if (session.Status__c == UatConstants.SESSION_COMPLETED) {
            throw auraError('This session is finished — its log is read-only.');
        }
    }

    private static Session_Note__c loadNote(Id noteId) {
        try {
            return [
                SELECT Id, Author__c, Exploratory_Session__c
                FROM Session_Note__c WHERE Id = :noteId
            ];
        } catch (QueryException e) {
            throw auraError('That entry no longer exists — refresh and try again.');
        }
    }

    private static NoteDTO loadOneNote(Id noteId) {
        Session_Note__c row = [
            SELECT Exploratory_Session__c FROM Session_Note__c WHERE Id = :noteId
        ];
        for (NoteDTO dto : loadNotes(row.Exploratory_Session__c)) {
            if (dto.id == noteId) {
                return dto;
            }
        }
        return null;
    }

    // ---- Focus prompts ---------------------------------------------------------

    /** Last-resort chips so a fresh org (no CMDT records deployed yet) is never
     *  promptless. Mirrors the four seed UAT_Focus_Prompt__mdt records. */
    private static final List<List<String>> DEFAULT_PROMPTS = new List<List<String>>{
        new List<String>{ 'Observation', 'Observation: ' },
        new List<String>{ 'Question', 'Question: ' },
        new List<String>{ 'Unexpected', 'Unexpected: ' },
        new List<String>{ 'Follow-up', 'Follow-up: ' }
    };

    private static final Integer MAX_PROMPTS = 8;

    /**
     * Resolution order: the cycle's Focus_Prompts__c override, else the active
     * UAT_Focus_Prompt__mdt records, else DEFAULT_PROMPTS. A standalone
     * (cycle-less) session has no override, so it always gets the org defaults.
     *
     * getAll() rather than SOQL on purpose: custom-metadata SOQL carries real
     * restrictions in this org (a prior build hit OR being rejected outright),
     * and getAll() is neither query-limited nor governor-limited.
     */
    private static List<PromptDTO> resolvePrompts(Test_Cycle__c cycle) {
        if (cycle != null && String.isNotBlank(cycle.Focus_Prompts__c)) {
            List<PromptDTO> parsed = parsePrompts(cycle.Focus_Prompts__c);
            // An override of nothing but blank/garbage lines falls through to
            // the defaults rather than leaving the tester with no chips.
            if (!parsed.isEmpty()) {
                return parsed;
            }
        }
        List<UAT_Focus_Prompt__mdt> active = new List<UAT_Focus_Prompt__mdt>();
        for (UAT_Focus_Prompt__mdt p : UAT_Focus_Prompt__mdt.getAll().values()) {
            if (p.Active__c == true) {
                active.add(p);
            }
        }
        if (active.isEmpty()) {
            List<PromptDTO> fallback = new List<PromptDTO>();
            for (List<String> pair : DEFAULT_PROMPTS) {
                fallback.add(newPrompt(pair[0], pair[1]));
            }
            return fallback;
        }
        // Sortable wrapper: "Sort_Order__c then label", blank order last.
        List<String> keys = new List<String>();
        Map<String, UAT_Focus_Prompt__mdt> byKey = new Map<String, UAT_Focus_Prompt__mdt>();
        for (UAT_Focus_Prompt__mdt p : active) {
            Decimal order = p.Sort_Order__c == null ? 9999 : p.Sort_Order__c;
            // Zero-padded so string sorting matches numeric intent.
            String key = String.valueOf(order.intValue() + 100000) + '|' + p.MasterLabel;
            keys.add(key);
            byKey.put(key, p);
        }
        keys.sort();
        List<PromptDTO> result = new List<PromptDTO>();
        for (String key : keys) {
            UAT_Focus_Prompt__mdt p = byKey.get(key);
            result.add(newPrompt(p.MasterLabel, p.Insert_Text__c));
            if (result.size() == MAX_PROMPTS) {
                break;
            }
        }
        return result;
    }

    /** "Label | Insert text" per line; no pipe = label with ": " appended. */
    private static List<PromptDTO> parsePrompts(String raw) {
        List<PromptDTO> prompts = new List<PromptDTO>();
        for (String line : raw.split('\n')) {
            String trimmed = line.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            List<String> parts = trimmed.split('\\|', 2);
            String label = parts[0].trim();
            if (String.isBlank(label)) {
                continue;
            }
            prompts.add(newPrompt(label, parts.size() > 1 ? parts[1].trim() + ' ' : null));
            if (prompts.size() == MAX_PROMPTS) {
                break;
            }
        }
        return prompts;
    }

    private static PromptDTO newPrompt(String label, String insertText) {
        PromptDTO dto = new PromptDTO();
        dto.label = label;
        dto.insertText = String.isBlank(insertText) ? label + ': ' : insertText;
        return dto;
    }

    // ---- Internals -------------------------------------------------------------

    private static SessionDTO toSessionDTO(Exploratory_Session__c s, Id me) {
        SessionDTO dto = new SessionDTO();
        dto.sessionId = s.Id;
        dto.name = s.Name;
        dto.title = s.Title__c;
        dto.charter = s.Charter__c;
        dto.areaText = s.Area__c;
        dto.cycleId = s.Test_Cycle__c;
        dto.cycleName = s.Test_Cycle__r != null ? s.Test_Cycle__r.Name : null;
        dto.status = s.Status__c;
        dto.timeboxMinutes = s.Timebox_Minutes__c == null
            ? null : s.Timebox_Minutes__c.intValue();
        dto.startedAt = s.Started_At__c;
        dto.finishedAt = s.Finished_At__c;
        dto.lastUpdated = s.LastModifiedDate;
        dto.isMine = s.Tester__c == me;
        dto.testerId = s.Tester__c;
        dto.testerName = s.Tester__r != null ? s.Tester__r.Name : null;
        return dto;
    }

    private static Exploratory_Session__c loadSession(Id sessionId) {
        if (sessionId == null) {
            throw auraError('Missing session — refresh and try again.');
        }
        try {
            return [
                SELECT Id, Name, Title__c, Charter__c, Area__c, Status__c,
                    Timebox_Minutes__c, Started_At__c, Finished_At__c, LastModifiedDate,
                    Tester__c, Tester__r.Name,
                    Test_Cycle__c, Test_Cycle__r.Name,
                    Test_Cycle__r.Focus_Prompts__c
                FROM Exploratory_Session__c WHERE Id = :sessionId
            ];
        } catch (QueryException ex) {
            throw auraError('That session no longer exists — refresh and try again.');
        }
    }

    /** AuraHandledException whose message survives into logs and test output. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}