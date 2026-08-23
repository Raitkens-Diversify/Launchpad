/**
 * UatExecutionService — the Helios UAT execution-lifecycle engine.
 *
 * Every Test_Execution__c / Test_Step_Result__c mutation flows through here:
 * one home, one test surface, one set of recursion guards. The seven thin
 * trigger handlers and the controllers delegate; nothing else writes these
 * objects.
 *
 * The load-bearing invariant: an execution's identity is the triple
 * (case, cycle-or-null, tester-or-null). Two testers in the same cycle each
 * get their OWN execution; claiming an unclaimed slot mutates it in place;
 * adding a tester creates a new record. Identity_Key__c (unique, stamped in
 * the execution trigger) turns every race into a caught DUPLICATE_VALUE
 * instead of silently merged results.
 *
 * `without sharing`, deliberately: slots are created/retargeted in whatever
 * user's transaction fired the trigger, and claims/rollups mutate records the
 * running tester doesn't own. Controllers gate access before delegating.
 */
public without sharing class UatExecutionService {

    /** Set during the step-delete cascade so the result trigger doesn't
     *  recompute against a denominator that still contains the dying step. */
    @TestVisible
    public static Boolean suppressRollup = false;

    /** Execution ids captured in before-delete, recomputed in after-delete. */
    private static Set<Id> pendingRecompute = new Set<Id>();

    public virtual class UatExecutionException extends Exception {}
    /** Every seat for this (cycle, case) is taken. Controllers map this to the
     *  "someone beat you to it" toast, distinct from generic failures. */
    public class PoolFullException extends UatExecutionException {}
    /** The tester is at the cycle's Claim_Limit_Per_Tester__c. */
    public class ClaimCapException extends UatExecutionException {}

    /** Clock seam: stale-claim aging and Claimed_Date stamping are untestable
     *  against the real clock. Production always sees System.now(). */
    @TestVisible
    private static DateTime nowOverride;

    private static DateTime nowTs() {
        return nowOverride != null ? nowOverride : System.now();
    }

    /** Race seam: true parallelism is impossible in Apex tests, so tests set
     *  this to N to make claimSeat treat its first N locked slots as consumed
     *  by a concurrent winner, exercising the retry/pool-full paths. */
    @TestVisible
    private static Integer simulateConsumedSlots = 0;

    private static Boolean consumeRaceSimulation() {
        if (simulateConsumedSlots > 0) {
            simulateConsumedSlots--;
            return true;
        }
        return false;
    }

    // ---- Identity ---------------------------------------------------------------

    public static String identityKey(Id caseId, Id cycleId, Id testerId) {
        return String.valueOf(caseId)
            + ':' + (cycleId == null ? 'STANDALONE' : String.valueOf(cycleId))
            + ':' + (testerId == null ? 'UNCLAIMED' : String.valueOf(testerId));
    }

    /** Before insert/update on Test_Execution__c. Idempotent. */
    public static void stampIdentityKeys(List<Test_Execution__c> executions) {
        for (Test_Execution__c e : executions) {
            e.Identity_Key__c = identityKey(e.Test_Case__c, e.Test_Cycle__c, e.Assigned_Tester__c);
        }
    }

    // ---- Eager slot materialization (03 §3) ---------------------------------------

    /**
     * Creates an unclaimed slot for every (cycle, case) pair in scope that has
     * NO executions of any kind yet. 3 scope SOQL + 1 SOQL + 1 DML at any
     * batch size. Duplicate-key insert failures are swallowed: they mean a
     * concurrent transaction materialized the same slot first, which is fine.
     */
    public static void materializeSlots(Set<Id> cycleIds) {
        if (cycleIds == null || cycleIds.isEmpty()) {
            return;
        }
        Map<Id, Map<Id, UatScopeService.ScopeEntry>> scope = UatScopeService.effectiveScope(cycleIds);

        Set<String> existingPairs = new Set<String>();
        for (Test_Execution__c e : [
            SELECT Test_Cycle__c, Test_Case__c
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds
        ]) {
            existingPairs.add(String.valueOf(e.Test_Cycle__c) + ':' + String.valueOf(e.Test_Case__c));
        }

        Map<Id, Test_Cycle__c> cycles = new Map<Id, Test_Cycle__c>([
            SELECT Id, Assigned_Team__c FROM Test_Cycle__c WHERE Id IN :cycleIds
        ]);

        List<Test_Execution__c> slots = new List<Test_Execution__c>();
        for (Id cycleId : scope.keySet()) {
            for (Id caseId : scope.get(cycleId).keySet()) {
                if (!existingPairs.contains(String.valueOf(cycleId) + ':' + String.valueOf(caseId))) {
                    slots.add(new Test_Execution__c(
                        Test_Case__c = caseId,
                        Test_Cycle__c = cycleId,
                        Assigned_Team__c = cycles.get(cycleId).Assigned_Team__c,
                        Testing_Status__c = 'Not Started'
                    ));
                }
            }
        }
        if (!slots.isEmpty()) {
            for (Database.SaveResult sr : Database.insert(slots, false)) {
                if (!sr.isSuccess() && !isDuplicateKeyFailure(sr)) {
                    throw new UatExecutionException(sr.getErrors()[0].getMessage());
                }
            }
        }
    }

    /**
     * Scope-shrink cleanup (decision 2026-07-23): after a junction delete,
     * remove executions whose case left scope AND that are pristine —
     * unclaimed, Not Started, no recorded content. Claimed or touched
     * executions are history and are never deleted.
     */
    public static void cleanupPristineSlots(Set<Id> cycleIds) {
        if (cycleIds == null || cycleIds.isEmpty()) {
            return;
        }
        Map<Id, Map<Id, UatScopeService.ScopeEntry>> scope = UatScopeService.effectiveScope(cycleIds);

        List<Test_Execution__c> candidates = [
            SELECT Id, Test_Cycle__c, Test_Case__c,
                (SELECT Id, Result__c, Actual_Result__c, Explore_Notes__c
                 FROM Test_Step_Results__r)
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds
            AND Assigned_Tester__c = null
            AND Testing_Status__c = 'Not Started'
        ];
        List<Test_Execution__c> toDelete = new List<Test_Execution__c>();
        for (Test_Execution__c e : candidates) {
            Boolean inScope = scope.containsKey(e.Test_Cycle__c)
                && scope.get(e.Test_Cycle__c).containsKey(e.Test_Case__c);
            if (inScope) {
                continue;
            }
            Boolean pristine = true;
            for (Test_Step_Result__c r : e.Test_Step_Results__r) {
                if (r.Result__c != null
                    || String.isNotBlank(r.Actual_Result__c)
                    || String.isNotBlank(r.Explore_Notes__c)) {
                    pristine = false;
                    break;
                }
            }
            if (pristine) {
                toDelete.add(e);
            }
        }
        if (!toDelete.isEmpty()) {
            suppressRollup = true;
            try {
                delete toDelete; // blank child results cascade with the master-detail
            } finally {
                suppressRollup = false;
            }
        }
    }

    /**
     * Cycle-delete purge (admin console, 2026-08-05): removes EVERY execution
     * of the cycle — claimed or not, touched or not. This is the one
     * sanctioned bulk-history delete; everything else in this service only
     * ever deletes pristine slots. Results cascade with the master-detail and
     * suppressRollup stops their trigger recomputing against dying
     * executions. Assignment-audit rows keep their history (every
     * Test_Assignment_Event__c lookup is SetNull). Returns the purged count.
     */
    public static Integer purgeCycleExecutions(Id cycleId) {
        List<Test_Execution__c> executions = [
            SELECT Id FROM Test_Execution__c WHERE Test_Cycle__c = :cycleId
        ];
        if (executions.isEmpty()) {
            return 0;
        }
        suppressRollup = true;
        try {
            delete executions;
        } finally {
            suppressRollup = false;
        }
        return executions.size();
    }

    // ---- Identity resolution / claiming / adding testers ----------------------------

    /** 03 §2: find-or-create the execution matching the triple. The UI then
     *  displays the RETURNED record — it never relabels the one it was on. */
    public static Test_Execution__c resolveForIdentity(Id caseId, Id cycleId, Id testerId) {
        String key = identityKey(caseId, cycleId, testerId);
        List<Test_Execution__c> found = [
            SELECT Id FROM Test_Execution__c WHERE Identity_Key__c = :key LIMIT 1
        ];
        if (!found.isEmpty()) {
            return found[0];
        }
        Id teamId = null;
        if (cycleId != null) {
            teamId = [SELECT Assigned_Team__c FROM Test_Cycle__c WHERE Id = :cycleId].Assigned_Team__c;
        }
        Test_Execution__c fresh = new Test_Execution__c(
            Test_Case__c = caseId,
            Test_Cycle__c = cycleId,
            Assigned_Tester__c = testerId,
            Assigned_Team__c = teamId,
            Testing_Status__c = 'Not Started'
        );
        Database.SaveResult sr = Database.insert(fresh, false);
        if (sr.isSuccess()) {
            return fresh;
        }
        if (isDuplicateKeyFailure(sr)) {
            // Lost the race — the record now exists; return it.
            return [SELECT Id FROM Test_Execution__c WHERE Identity_Key__c = :key LIMIT 1];
        }
        throw new UatExecutionException(sr.getErrors()[0].getMessage());
    }

    /** 03 §4: claiming mutates the SAME record — "this unclaimed slot becomes
     *  mine", never an additional run. FOR UPDATE closes the double-click race.
     *  Legacy single-slot path, kept for standalone assignments; pool claims
     *  (cycle-scoped, capacity-aware) go through claimSeat instead. */
    public static Test_Execution__c claim(Id executionId, Id userId) {
        List<Test_Execution__c> locked = [
            SELECT Id, Test_Case__c, Test_Cycle__c, Assigned_Tester__c FROM Test_Execution__c
            WHERE Id = :executionId
            FOR UPDATE
        ];
        if (locked.isEmpty()) {
            throw new UatExecutionException('That test no longer exists — refresh your queue.');
        }
        Test_Execution__c e = locked[0];
        if (e.Assigned_Tester__c != null && e.Assigned_Tester__c != userId) {
            throw new UatExecutionException('Someone else just claimed this test — refresh your queue.');
        }
        if (e.Assigned_Tester__c == null) {
            e.Assigned_Tester__c = userId;
            e.Claimed_Date__c = nowTs();
            update e;
            logEvent(UatConstants.EVENT_CLAIMED, e.Test_Case__c, e.Test_Cycle__c, e.Id, userId, userId, null);
        }
        return e;
    }

    /** 03 §5: an admin adding a second tester creates a NEW, permanently
     *  independent execution — the existing one is never touched. Also
     *  re-activates a previously released run (same identity key) and settles
     *  the pool slot: a deliberate admin add can fill — or overfill — the
     *  seats, which closes the pool for that case. */
    public static Test_Execution__c createIndependentExecution(Id cycleId, Id caseId, Id testerId) {
        if (testerId == null) {
            throw new UatExecutionException('Pick a tester to add.');
        }
        Test_Execution__c resolved = resolveForIdentity(caseId, cycleId, testerId);
        Test_Execution__c row = [
            SELECT Id, Released__c, Claimed_Date__c FROM Test_Execution__c WHERE Id = :resolved.Id
        ];
        if (row.Released__c || row.Claimed_Date__c == null) {
            row.Released__c = false;
            if (row.Claimed_Date__c == null) {
                row.Claimed_Date__c = nowTs();
            }
            update row;
            logEvent(UatConstants.EVENT_CLAIMED, caseId, cycleId, row.Id, testerId, UserInfo.getUserId(), null);
        }
        reconcileSeatPair(caseId, cycleId);
        return row;
    }

    // ---- Pool seats: capacity-aware claim / release / reconcile (open-pool design doc §2-4) ----

    /**
     * Self-service claim of one seat on (cycle, case). The single unclaimed
     * slot is the claim token: FOR UPDATE on it serializes all claimants for
     * the pair, the seat count is taken while holding that lock, and a fresh
     * slot is re-materialized in the same transaction while seats remain. The
     * unique Identity_Key__c stays as the backstop. A race loser either claims
     * the winner's re-materialized slot transparently (one retry) or gets a
     * clean PoolFullException.
     */
    public static Test_Execution__c claimSeat(Id cycleId, Id caseId, Id userId) {
        if (cycleId == null || caseId == null) {
            throw new UatExecutionException('That test no longer exists — refresh the pool.');
        }
        Test_Cycle__c cycle = [
            SELECT Status__c, Max_Testers__c, Claim_Limit_Per_Tester__c, Assigned_Team__c
            FROM Test_Cycle__c WHERE Id = :cycleId
        ];
        if (cycle.Status__c == UatConstants.CYCLE_CLAIMS_PAUSED) {
            throw new UatExecutionException('This cycle isn\'t taking new claims right now.');
        }
        if (cycle.Status__c == UatConstants.CYCLE_CLOSED) {
            throw new UatExecutionException('This cycle is closed — refresh the pool.');
        }
        // Per-tester cap (§6.1): counted before the lock. Two simultaneous
        // claims by the SAME tester on different cases can each pass and land
        // one over the cap — accepted; the cap throttles hoarding, not physics.
        if (cycle.Claim_Limit_Per_Tester__c != null) {
            Integer myOpen = [
                SELECT COUNT() FROM Test_Execution__c
                WHERE Test_Cycle__c = :cycleId AND Assigned_Tester__c = :userId
                AND Released__c = false AND Testing_Status__c != 'Complete'
            ];
            if (myOpen >= cycle.Claim_Limit_Per_Tester__c) {
                throw new ClaimCapException('You\'re at this cycle\'s limit of '
                    + Integer.valueOf(cycle.Claim_Limit_Per_Tester__c)
                    + ' open claims — finish or release one first.');
            }
        }
        Integer maxSeats = effectiveMaxTesters(cycle, caseId);
        String unclaimedKey = identityKey(caseId, cycleId, null);
        String myKey = identityKey(caseId, cycleId, userId);

        // Idempotent double-click / already added by an admin: the seat is
        // theirs even when no slot remains — checked before the lock so a
        // full pool never rejects its own claimant.
        Test_Execution__c alreadyMine = findByKey(myKey);
        if (alreadyMine != null && !alreadyMine.Released__c) {
            return alreadyMine;
        }

        for (Integer attempt = 0; attempt < 2; attempt++) {
            List<Test_Execution__c> lockedSlot = [
                SELECT Id FROM Test_Execution__c
                WHERE Identity_Key__c = :unclaimedKey
                FOR UPDATE
            ];
            Test_Execution__c slot = lockedSlot.isEmpty() ? null : lockedSlot[0];
            if (slot != null) {
                // Re-read under the lock: if we blocked while a winner
                // committed a restamp, the row we selected is no longer the
                // slot — retry the key once (the winner may have
                // re-materialized a fresh one).
                Test_Execution__c current = [
                    SELECT Assigned_Tester__c FROM Test_Execution__c WHERE Id = :slot.Id
                ];
                if (current.Assigned_Tester__c != null || consumeRaceSimulation()) {
                    slot = null;
                }
            }
            if (slot == null) {
                continue;
            }

            List<Test_Execution__c> siblings = [
                SELECT Id, Assigned_Tester__c, Released__c FROM Test_Execution__c
                WHERE Test_Case__c = :caseId AND Test_Cycle__c = :cycleId
                AND Assigned_Tester__c != null
            ];
            Integer active = 0;
            Test_Execution__c mine = null;
            for (Test_Execution__c s : siblings) {
                if (!s.Released__c) {
                    active++;
                }
                if (s.Assigned_Tester__c == userId) {
                    mine = s;
                }
            }
            if (mine != null && !mine.Released__c) {
                return mine; // idempotent double-click: the seat is already theirs
            }
            if (active >= maxSeats) {
                // Shouldn't exist — capacity was lowered or an admin overfilled.
                // Retire the surplus slot and report full.
                suppressRollup = true;
                try {
                    delete slot;
                } finally {
                    suppressRollup = false;
                }
                break;
            }
            if (mine != null && mine.Released__c) {
                // Re-claim after release resumes their OWN partial run (unique
                // key points at it) — never a fresh record that could merge.
                mine.Released__c = false;
                mine.Claimed_Date__c = nowTs();
                update mine;
                if (active + 1 >= maxSeats) {
                    suppressRollup = true;
                    try {
                        delete slot; // that re-claim took the last seat
                    } finally {
                        suppressRollup = false;
                    }
                }
                logEvent(UatConstants.EVENT_CLAIMED, caseId, cycleId, mine.Id, userId, userId, null);
                return mine;
            }

            slot.Assigned_Tester__c = userId;
            slot.Claimed_Date__c = nowTs();
            slot.Released__c = false;
            update slot;
            if (active + 1 < maxSeats) {
                insertSlot(caseId, cycleId, cycle.Assigned_Team__c);
            }
            logEvent(UatConstants.EVENT_CLAIMED, caseId, cycleId, slot.Id, userId, userId, null);
            return slot;
        }
        // A same-user race (double-click) can land here after the first
        // request already won — hand back their run instead of an error.
        alreadyMine = findByKey(myKey);
        if (alreadyMine != null && !alreadyMine.Released__c) {
            return alreadyMine;
        }
        throw new PoolFullException('Someone beat you to the last spot on this one.');
    }

    private static Test_Execution__c findByKey(String key) {
        List<Test_Execution__c> found = [
            SELECT Id, Released__c FROM Test_Execution__c WHERE Identity_Key__c = :key LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /**
     * Returns a claimed seat to the pool (§3.2). The rule that shapes the
     * three branches: a later claimant must never inherit another tester's
     * partial work.
     *   pristine, no slot open  -> revert this record to the unclaimed slot
     *   pristine, slot exists   -> delete this record (keeping it would
     *                              collide on the UNCLAIMED key)
     *   work recorded           -> keep it, flagged Released; reopen a seat
     * action: 'Released' (self), 'Force Unassigned' (admin), 'Auto Released'
     * (stale job) — same mechanics, different audit rows.
     */
    public static void releaseSeat(Id executionId, Id actorId, String reason, String action) {
        List<Test_Execution__c> locked = [
            SELECT Id, Test_Case__c, Test_Cycle__c, Assigned_Tester__c, Testing_Status__c,
                Released__c,
                (SELECT Result__c, Actual_Result__c, Explore_Notes__c FROM Test_Step_Results__r)
            FROM Test_Execution__c
            WHERE Id = :executionId
            FOR UPDATE
        ];
        if (locked.isEmpty()) {
            throw new UatExecutionException('That run no longer exists — refresh and try again.');
        }
        Test_Execution__c e = locked[0];
        if (e.Assigned_Tester__c == null) {
            throw new UatExecutionException('That run isn\'t claimed by anyone.');
        }
        if (e.Released__c) {
            return; // already released — idempotent
        }
        releaseInternal(e, actorId, reason, action, true);
    }

    /** Admin reassignment (§3.2): free the old tester's seat WITHOUT
     *  re-materializing, hand the new tester their own independent execution,
     *  then settle the slot — the net seat count is unchanged. */
    public static Test_Execution__c reassignSeat(Id executionId, Id newTesterId, Id actorId, String reason) {
        if (newTesterId == null) {
            throw new UatExecutionException('Pick a tester to reassign to.');
        }
        List<Test_Execution__c> locked = [
            SELECT Id, Test_Case__c, Test_Cycle__c, Assigned_Tester__c, Testing_Status__c,
                Released__c,
                (SELECT Result__c, Actual_Result__c, Explore_Notes__c FROM Test_Step_Results__r)
            FROM Test_Execution__c
            WHERE Id = :executionId
            FOR UPDATE
        ];
        if (locked.isEmpty()) {
            throw new UatExecutionException('That run no longer exists — refresh and try again.');
        }
        Test_Execution__c e = locked[0];
        if (e.Assigned_Tester__c == null) {
            throw new UatExecutionException('That run isn\'t claimed — add the tester instead.');
        }
        if (e.Assigned_Tester__c == newTesterId) {
            return e;
        }
        Id caseId = e.Test_Case__c;
        Id cycleId = e.Test_Cycle__c;
        if (!e.Released__c) {
            releaseInternal(e, actorId, reason, UatConstants.EVENT_FORCE_UNASSIGNED, false);
        }
        Test_Execution__c fresh = resolveForIdentity(caseId, cycleId, newTesterId);
        Test_Execution__c row = [
            SELECT Id, Released__c, Claimed_Date__c FROM Test_Execution__c WHERE Id = :fresh.Id
        ];
        row.Released__c = false;
        row.Claimed_Date__c = nowTs();
        update row;
        logEvent('Reassigned', caseId, cycleId, row.Id, newTesterId, actorId, reason);
        reconcileSeatPair(caseId, cycleId);
        return row;
    }

    /**
     * Settles the slot for every in-scope pair of the given cycles after a
     * capacity edit: opens the missing slot when seats are free, retires the
     * surplus one when they aren't. Called from the admin save paths (not
     * triggers) — Data Loader edits settle on the next claim/release instead.
     */
    public static void reconcileSeats(Set<Id> cycleIds) {
        if (cycleIds == null || cycleIds.isEmpty()) {
            return;
        }
        Map<Id, Map<Id, UatScopeService.ScopeEntry>> scope = UatScopeService.effectiveScope(cycleIds);
        Map<Id, Test_Cycle__c> cycles = new Map<Id, Test_Cycle__c>([
            SELECT Id, Status__c, Max_Testers__c, Assigned_Team__c
            FROM Test_Cycle__c WHERE Id IN :cycleIds
        ]);
        Set<Id> caseIds = new Set<Id>();
        for (Id cycleId : scope.keySet()) {
            caseIds.addAll(scope.get(cycleId).keySet());
        }
        Map<Id, Test_Case__c> cases = new Map<Id, Test_Case__c>([
            SELECT Id, Max_Testers_Override__c FROM Test_Case__c WHERE Id IN :caseIds
        ]);

        Map<String, Integer> activeByPair = new Map<String, Integer>();
        Map<String, Test_Execution__c> slotByPair = new Map<String, Test_Execution__c>();
        for (Test_Execution__c e : [
            SELECT Id, Test_Case__c, Test_Cycle__c, Assigned_Tester__c, Released__c,
                Testing_Status__c
            FROM Test_Execution__c
            WHERE Test_Cycle__c IN :cycleIds
        ]) {
            String pair = String.valueOf(e.Test_Cycle__c) + ':' + String.valueOf(e.Test_Case__c);
            if (e.Assigned_Tester__c == null) {
                slotByPair.put(pair, e);
            } else if (!e.Released__c) {
                Integer current = activeByPair.containsKey(pair) ? activeByPair.get(pair) : 0;
                activeByPair.put(pair, current + 1);
            }
        }

        List<Test_Execution__c> toInsert = new List<Test_Execution__c>();
        List<Test_Execution__c> toDelete = new List<Test_Execution__c>();
        for (Id cycleId : scope.keySet()) {
            Test_Cycle__c cycle = cycles.get(cycleId);
            if (cycle == null || cycle.Status__c == UatConstants.CYCLE_CLOSED) {
                continue;
            }
            for (Id caseId : scope.get(cycleId).keySet()) {
                String pair = String.valueOf(cycleId) + ':' + String.valueOf(caseId);
                Integer maxSeats = resolveMax(cycle.Max_Testers__c,
                    cases.containsKey(caseId) ? cases.get(caseId).Max_Testers_Override__c : null);
                Integer active = activeByPair.containsKey(pair) ? activeByPair.get(pair) : 0;
                Test_Execution__c slot = slotByPair.get(pair);
                if (slot == null && active < maxSeats) {
                    toInsert.add(new Test_Execution__c(
                        Test_Case__c = caseId,
                        Test_Cycle__c = cycleId,
                        Assigned_Team__c = cycle.Assigned_Team__c,
                        Testing_Status__c = 'Not Started'
                    ));
                } else if (slot != null && active >= maxSeats
                    && slot.Testing_Status__c == 'Not Started') {
                    toDelete.add(slot);
                }
            }
        }
        if (!toInsert.isEmpty()) {
            for (Database.SaveResult sr : Database.insert(toInsert, false)) {
                if (!sr.isSuccess() && !isDuplicateKeyFailure(sr)) {
                    throw new UatExecutionException(sr.getErrors()[0].getMessage());
                }
            }
        }
        if (!toDelete.isEmpty()) {
            suppressRollup = true;
            try {
                delete toDelete;
            } finally {
                suppressRollup = false;
            }
        }
    }

    /** Case-override edits reconcile every open cycle the case runs in. The
     *  materialized executions ARE the scope, so they name those cycles. */
    public static void reconcileSeatsForCase(Id caseId) {
        Set<Id> cycleIds = new Set<Id>();
        for (Test_Execution__c e : [
            SELECT Test_Cycle__c FROM Test_Execution__c
            WHERE Test_Case__c = :caseId AND Test_Cycle__c != null
            AND Test_Cycle__r.Status__c != 'Closed'
        ]) {
            cycleIds.add(e.Test_Cycle__c);
        }
        reconcileSeats(cycleIds);
    }

    /**
     * The nightly stale sweep (§7): claims still at Not Started after the
     * cycle's Stale_Claim_Days__c go back to the pool. Set-based throughout —
     * per-record releases would blow SOQL limits on a bad backlog. Returns the
     * number of seats released.
     */
    public static Integer releaseStaleClaims(Id actorId) {
        DateTime current = nowTs();
        List<Test_Execution__c> stale = new List<Test_Execution__c>();
        for (Test_Execution__c e : [
            SELECT Id, Test_Case__c, Test_Cycle__c, Assigned_Tester__c, Testing_Status__c,
                Released__c, Claimed_Date__c,
                Test_Cycle__r.Stale_Claim_Days__c, Test_Cycle__r.Assigned_Team__c,
                Test_Cycle__r.Max_Testers__c, Test_Case__r.Max_Testers_Override__c,
                (SELECT Result__c, Actual_Result__c, Explore_Notes__c FROM Test_Step_Results__r)
            FROM Test_Execution__c
            WHERE Assigned_Tester__c != null AND Released__c = false
            AND Testing_Status__c = 'Not Started'
            AND Claimed_Date__c != null
            AND Test_Cycle__c != null
            AND Test_Cycle__r.Stale_Claim_Days__c != null
            AND (Test_Cycle__r.Status__c = 'Active' OR Test_Cycle__r.Status__c = null)
        ]) {
            Integer days = Integer.valueOf(e.Test_Cycle__r.Stale_Claim_Days__c);
            if (e.Claimed_Date__c < current.addDays(-days)) {
                stale.add(e);
            }
        }
        if (stale.isEmpty()) {
            return 0;
        }

        // One slot-existence check for every touched pair.
        Set<String> pairKeys = new Set<String>();
        Set<Id> staleCaseIds = new Set<Id>();
        Set<Id> staleCycleIds = new Set<Id>();
        for (Test_Execution__c e : stale) {
            pairKeys.add(identityKey(e.Test_Case__c, e.Test_Cycle__c, null));
            staleCaseIds.add(e.Test_Case__c);
            staleCycleIds.add(e.Test_Cycle__c);
        }
        Set<String> pairsWithSlot = new Set<String>();
        Map<String, Integer> activeByPair = new Map<String, Integer>();
        for (Test_Execution__c e : [
            SELECT Test_Case__c, Test_Cycle__c, Assigned_Tester__c, Released__c, Identity_Key__c
            FROM Test_Execution__c
            WHERE Test_Case__c IN :staleCaseIds AND Test_Cycle__c IN :staleCycleIds
        ]) {
            String pair = String.valueOf(e.Test_Cycle__c) + ':' + String.valueOf(e.Test_Case__c);
            if (e.Assigned_Tester__c == null) {
                pairsWithSlot.add(pair);
            } else if (!e.Released__c) {
                Integer count = activeByPair.containsKey(pair) ? activeByPair.get(pair) : 0;
                activeByPair.put(pair, count + 1);
            }
        }

        List<Test_Execution__c> reverts = new List<Test_Execution__c>();
        List<Test_Execution__c> marks = new List<Test_Execution__c>();
        List<Test_Execution__c> deletions = new List<Test_Execution__c>();
        List<Test_Execution__c> newSlots = new List<Test_Execution__c>();
        List<Test_Assignment_Event__c> events = new List<Test_Assignment_Event__c>();

        for (Test_Execution__c e : stale) {
            String pair = String.valueOf(e.Test_Cycle__c) + ':' + String.valueOf(e.Test_Case__c);
            String reason = 'Auto-released after '
                + Integer.valueOf(e.Test_Cycle__r.Stale_Claim_Days__c)
                + ' days without starting.';
            Boolean pristine = resultsPristine(e.Test_Step_Results__r);
            Id executionRef = e.Id;
            if (pristine) {
                if (pairsWithSlot.contains(pair)) {
                    deletions.add(e);
                    executionRef = null;
                } else {
                    reverts.add(new Test_Execution__c(
                        Id = e.Id,
                        Assigned_Tester__c = null,
                        Claimed_Date__c = null,
                        Released__c = false,
                        Assigned_Team__c = e.Test_Cycle__r.Assigned_Team__c
                    ));
                    pairsWithSlot.add(pair); // this record IS the slot again
                }
            } else {
                marks.add(new Test_Execution__c(Id = e.Id, Released__c = true));
            }
            Integer count = activeByPair.containsKey(pair) ? activeByPair.get(pair) : 0;
            activeByPair.put(pair, count - 1); // this seat is no longer active
            events.add(buildEvent(UatConstants.EVENT_AUTO_RELEASED, e.Test_Case__c, e.Test_Cycle__c,
                executionRef, e.Assigned_Tester__c, actorId, reason));
        }
        // Reopen a seat where a non-pristine release left no slot behind.
        Set<String> slotPlanned = new Set<String>();
        for (Test_Execution__c e : stale) {
            String pair = String.valueOf(e.Test_Cycle__c) + ':' + String.valueOf(e.Test_Case__c);
            if (pairsWithSlot.contains(pair) || slotPlanned.contains(pair)) {
                continue;
            }
            Integer maxSeats = resolveMax(e.Test_Cycle__r.Max_Testers__c,
                e.Test_Case__r.Max_Testers_Override__c);
            Integer active = activeByPair.containsKey(pair) ? activeByPair.get(pair) : 0;
            if (active < maxSeats) {
                newSlots.add(new Test_Execution__c(
                    Test_Case__c = e.Test_Case__c,
                    Test_Cycle__c = e.Test_Cycle__c,
                    Assigned_Team__c = e.Test_Cycle__r.Assigned_Team__c,
                    Testing_Status__c = 'Not Started'
                ));
                slotPlanned.add(pair);
            }
        }

        List<Test_Execution__c> updates = new List<Test_Execution__c>();
        updates.addAll(reverts);
        updates.addAll(marks);
        if (!updates.isEmpty()) {
            update updates;
        }
        if (!deletions.isEmpty()) {
            suppressRollup = true;
            try {
                delete deletions;
            } finally {
                suppressRollup = false;
            }
        }
        if (!newSlots.isEmpty()) {
            for (Database.SaveResult sr : Database.insert(newSlots, false)) {
                if (!sr.isSuccess() && !isDuplicateKeyFailure(sr)) {
                    throw new UatExecutionException(sr.getErrors()[0].getMessage());
                }
            }
        }
        if (!events.isEmpty()) {
            insert events;
        }
        return stale.size();
    }

    // ---- Pool internals ---------------------------------------------------------

    private static void releaseInternal(Test_Execution__c e, Id actorId, String reason,
        String action, Boolean rematerialize) {
        Id tester = e.Assigned_Tester__c;
        Id caseId = e.Test_Case__c;
        Id cycleId = e.Test_Cycle__c;
        Boolean pristine = e.Testing_Status__c == 'Not Started'
            && resultsPristine(e.Test_Step_Results__r);
        Id slotId = findSlotId(caseId, cycleId);
        Id executionRef = e.Id;

        if (pristine) {
            if (slotId != null || cycleId == null) {
                // Surplus copy (a slot is already open), or a standalone run
                // that has no pool to return to: remove the empty record.
                suppressRollup = true;
                try {
                    delete new Test_Execution__c(Id = e.Id);
                } finally {
                    suppressRollup = false;
                }
                executionRef = null;
            } else {
                update new Test_Execution__c(
                    Id = e.Id,
                    Assigned_Tester__c = null,
                    Claimed_Date__c = null,
                    Released__c = false,
                    Assigned_Team__c = currentTeamOf(cycleId)
                );
            }
        } else {
            update new Test_Execution__c(Id = e.Id, Released__c = true);
            if (rematerialize && cycleId != null && slotId == null
                && activeClaims(caseId, cycleId) < effectiveMaxTesters(cycleId, caseId)) {
                insertSlot(caseId, cycleId, currentTeamOf(cycleId));
            }
        }
        logEvent(action, caseId, cycleId, executionRef, tester, actorId, reason);
    }

    /** Settle one pair's slot after an out-of-band seat change (admin add,
     *  reassign): open the missing slot or retire the surplus one. */
    private static void reconcileSeatPair(Id caseId, Id cycleId) {
        if (cycleId == null) {
            return;
        }
        Test_Cycle__c cycle = [
            SELECT Status__c, Max_Testers__c, Assigned_Team__c
            FROM Test_Cycle__c WHERE Id = :cycleId
        ];
        if (cycle.Status__c == UatConstants.CYCLE_CLOSED) {
            return;
        }
        Integer maxSeats = effectiveMaxTesters(cycle, caseId);
        Integer active = activeClaims(caseId, cycleId);
        Id slotId = findSlotId(caseId, cycleId);
        if (slotId == null && active < maxSeats) {
            insertSlot(caseId, cycleId, cycle.Assigned_Team__c);
        } else if (slotId != null && active >= maxSeats) {
            List<Test_Execution__c> slot = [
                SELECT Id FROM Test_Execution__c
                WHERE Id = :slotId AND Testing_Status__c = 'Not Started'
            ];
            if (!slot.isEmpty()) {
                suppressRollup = true;
                try {
                    delete slot;
                } finally {
                    suppressRollup = false;
                }
            }
        }
    }

    private static Integer effectiveMaxTesters(Id cycleId, Id caseId) {
        return effectiveMaxTesters([
            SELECT Status__c, Max_Testers__c, Assigned_Team__c
            FROM Test_Cycle__c WHERE Id = :cycleId
        ], caseId);
    }

    private static Integer effectiveMaxTesters(Test_Cycle__c cycle, Id caseId) {
        Decimal caseOverride = [
            SELECT Max_Testers_Override__c FROM Test_Case__c WHERE Id = :caseId
        ].Max_Testers_Override__c;
        return resolveMax(cycle.Max_Testers__c, caseOverride);
    }

    /** Override wins, then the cycle default, then 1 — never below 1. */
    private static Integer resolveMax(Decimal cycleDefault, Decimal caseOverride) {
        Decimal resolved = caseOverride != null ? caseOverride
            : (cycleDefault != null ? cycleDefault : 1);
        return resolved < 1 ? 1 : Integer.valueOf(resolved);
    }

    private static Integer activeClaims(Id caseId, Id cycleId) {
        return [
            SELECT COUNT() FROM Test_Execution__c
            WHERE Test_Case__c = :caseId AND Test_Cycle__c = :cycleId
            AND Assigned_Tester__c != null AND Released__c = false
        ];
    }

    private static Id findSlotId(Id caseId, Id cycleId) {
        if (cycleId == null) {
            return null;
        }
        String key = identityKey(caseId, cycleId, null);
        List<Test_Execution__c> slot = [
            SELECT Id FROM Test_Execution__c WHERE Identity_Key__c = :key LIMIT 1
        ];
        return slot.isEmpty() ? null : slot[0].Id;
    }

    private static void insertSlot(Id caseId, Id cycleId, Id teamId) {
        Database.SaveResult sr = Database.insert(new Test_Execution__c(
            Test_Case__c = caseId,
            Test_Cycle__c = cycleId,
            Assigned_Team__c = teamId,
            Testing_Status__c = 'Not Started'
        ), false);
        if (!sr.isSuccess() && !isDuplicateKeyFailure(sr)) {
            throw new UatExecutionException(sr.getErrors()[0].getMessage());
        }
    }

    private static Id currentTeamOf(Id cycleId) {
        return [
            SELECT Assigned_Team__c FROM Test_Cycle__c WHERE Id = :cycleId
        ].Assigned_Team__c;
    }

    /** Pristine = nothing a later claimant could inherit (same test
     *  cleanupPristineSlots applies). */
    private static Boolean resultsPristine(List<Test_Step_Result__c> results) {
        for (Test_Step_Result__c r : results) {
            if (r.Result__c != null
                || String.isNotBlank(r.Actual_Result__c)
                || String.isNotBlank(r.Explore_Notes__c)) {
                return false;
            }
        }
        return true;
    }

    /** Audit rows are system-written here and nowhere else — no permission
     *  set grants create on Test_Assignment_Event__c, so the trail cannot be
     *  forged or edited through the API. */
    private static void logEvent(String action, Id caseId, Id cycleId, Id executionId,
        Id testerId, Id actorId, String reason) {
        insert buildEvent(action, caseId, cycleId, executionId, testerId, actorId, reason);
    }

    private static Test_Assignment_Event__c buildEvent(String action, Id caseId, Id cycleId,
        Id executionId, Id testerId, Id actorId, String reason) {
        return new Test_Assignment_Event__c(
            Action__c = action,
            Test_Case__c = caseId,
            Test_Cycle__c = cycleId,
            Test_Execution__c = executionId,
            Tester__c = testerId,
            Actor__c = actorId,
            Reason__c = reason
        );
    }

    /** 03 §6: team reassignment retargets UNCLAIMED slots only — a claimed
     *  execution is never silently affected by a later team change. */
    public static void retargetUnclaimed(Map<Id, Id> newTeamByCycle) {
        if (newTeamByCycle == null || newTeamByCycle.isEmpty()) {
            return;
        }
        List<Test_Execution__c> updates = new List<Test_Execution__c>();
        for (Test_Execution__c e : [
            SELECT Id, Test_Cycle__c FROM Test_Execution__c
            WHERE Test_Cycle__c IN :newTeamByCycle.keySet()
            AND Assigned_Tester__c = null
        ]) {
            updates.add(new Test_Execution__c(
                Id = e.Id,
                Assigned_Team__c = newTeamByCycle.get(e.Test_Cycle__c)
            ));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    // ---- Runner support ---------------------------------------------------------------

    /** Find-or-create one blank Test_Step_Result__c per current step, so the
     *  runner has rows to write to and per-step evidence has a LinkedEntityId.
     *  Also heals executions opened after the admin added steps (03 P2 §5:
     *  definition edits appear on next load). */
    public static List<Test_Step_Result__c> ensureStepResults(Id executionId) {
        Test_Execution__c e = [
            SELECT Id, Test_Case__c FROM Test_Execution__c WHERE Id = :executionId
        ];
        Map<Id, Test_Step_Result__c> byStep = new Map<Id, Test_Step_Result__c>();
        for (Test_Step_Result__c r : [
            SELECT Id, Test_Step__c FROM Test_Step_Result__c
            WHERE Test_Execution__c = :executionId AND Test_Step__c != null
        ]) {
            byStep.put(r.Test_Step__c, r);
        }
        List<Test_Step_Result__c> missing = new List<Test_Step_Result__c>();
        for (Test_Step__c s : [
            SELECT Id FROM Test_Step__c WHERE Test_Case__c = :e.Test_Case__c
        ]) {
            if (!byStep.containsKey(s.Id)) {
                missing.add(new Test_Step_Result__c(
                    Test_Execution__c = executionId,
                    Test_Step__c = s.Id
                ));
            }
        }
        if (!missing.isEmpty()) {
            suppressRollup = true;
            try {
                insert missing;
            } finally {
                suppressRollup = false;
            }
        }
        return [
            SELECT Id, Test_Step__c, Actual_Result__c, Result__c, Explore_Notes__c,
                Defect_Severity__c, Defect_Summary__c
            FROM Test_Step_Result__c
            WHERE Test_Execution__c = :executionId
        ];
    }

    // ---- Status/result rollup (03 §10) ---------------------------------------------------

    /**
     * Recomputed on EVERY result change so queue badges stay live.
     * Status: Complete when every current non-exploratory step has an answer;
     * In Progress when some do (or the tester saved-and-exited — never
     * downgraded back to Not Started); Not Started when none do.
     * Result: Failed if any Fail, else Blocked if any Blocked, else Passed
     * (only when Complete), else null.
     */
    public static void recomputeRollups(Set<Id> executionIds) {
        if (suppressRollup || executionIds == null || executionIds.isEmpty()) {
            return;
        }
        List<Test_Execution__c> executions = [
            SELECT Id, Test_Case__c, Testing_Status__c, Testing_Result__c, Last_Tested_Date__c
            FROM Test_Execution__c
            WHERE Id IN :executionIds
        ];
        Set<Id> caseIds = new Set<Id>();
        for (Test_Execution__c e : executions) {
            caseIds.add(e.Test_Case__c);
        }
        Map<Id, Integer> denominatorByCase = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Test_Case__c caseId, COUNT(Id) total
            FROM Test_Step__c
            WHERE Test_Case__c IN :caseIds AND Is_Explore__c = false
            GROUP BY Test_Case__c
        ]) {
            denominatorByCase.put((Id) ar.get('caseId'), (Integer) ar.get('total'));
        }

        Map<Id, Integer> answeredByExec = new Map<Id, Integer>();
        Map<Id, Boolean> anyFailByExec = new Map<Id, Boolean>();
        Map<Id, Boolean> anyBlockedByExec = new Map<Id, Boolean>();
        for (Test_Step_Result__c r : [
            SELECT Test_Execution__c, Result__c, Test_Step__r.Is_Explore__c, Test_Step__c
            FROM Test_Step_Result__c
            WHERE Test_Execution__c IN :executionIds
        ]) {
            if (r.Test_Step__c == null || r.Test_Step__r.Is_Explore__c == true) {
                continue; // exploratory rows and orphans don't count
            }
            if (r.Result__c != null) {
                Integer current = answeredByExec.containsKey(r.Test_Execution__c)
                    ? answeredByExec.get(r.Test_Execution__c) : 0;
                answeredByExec.put(r.Test_Execution__c, current + 1);
            }
            if (r.Result__c == 'Fail') {
                anyFailByExec.put(r.Test_Execution__c, true);
            }
            if (r.Result__c == 'Blocked') {
                anyBlockedByExec.put(r.Test_Execution__c, true);
            }
        }

        List<Test_Execution__c> updates = new List<Test_Execution__c>();
        for (Test_Execution__c e : executions) {
            Integer denominator = denominatorByCase.containsKey(e.Test_Case__c)
                ? denominatorByCase.get(e.Test_Case__c) : 0;
            Integer answered = answeredByExec.containsKey(e.Id) ? answeredByExec.get(e.Id) : 0;

            String status;
            if (denominator > 0 && answered >= denominator) {
                status = 'Complete';
            } else if (answered > 0) {
                status = 'In Progress';
            } else {
                // Never downgrade an explicit save-and-exit floor.
                status = e.Testing_Status__c == 'In Progress' ? 'In Progress' : 'Not Started';
            }

            String verdict;
            if (anyFailByExec.containsKey(e.Id)) {
                verdict = 'Failed';
            } else if (anyBlockedByExec.containsKey(e.Id)) {
                verdict = 'Blocked';
            } else if (status == 'Complete') {
                verdict = 'Passed';
            } else {
                verdict = null;
            }

            Date lastTested = answered > 0 ? Date.today() : e.Last_Tested_Date__c;

            if (e.Testing_Status__c != status
                || e.Testing_Result__c != verdict
                || e.Last_Tested_Date__c != lastTested) {
                updates.add(new Test_Execution__c(
                    Id = e.Id,
                    Testing_Status__c = status,
                    Testing_Result__c = verdict,
                    Last_Tested_Date__c = lastTested
                ));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    /** Recompute every execution of the given cases — step authoring changes
     *  the denominator (accepted behavior: adding a step regresses Complete
     *  runs to In Progress; deleting one can promote). */
    public static void recomputeForCases(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return;
        }
        Set<Id> executionIds = new Map<Id, Test_Execution__c>([
            SELECT Id FROM Test_Execution__c WHERE Test_Case__c IN :caseIds
        ]).keySet();
        recomputeRollups(executionIds);
    }

    // ---- Step-delete cascade (03 §9) --------------------------------------------------------

    /**
     * BEFORE delete: the result->step lookup clears once the step dies, so the
     * results must be found and deleted now, with rollups suppressed (the
     * denominator still includes the dying step).
     */
    public static void cascadeStepDelete(List<Test_Step__c> oldSteps) {
        Set<Id> stepIds = new Map<Id, Test_Step__c>(oldSteps).keySet();
        List<Test_Step_Result__c> results = [
            SELECT Id, Test_Execution__c FROM Test_Step_Result__c
            WHERE Test_Step__c IN :stepIds
        ];
        for (Test_Step_Result__c r : results) {
            pendingRecompute.add(r.Test_Execution__c);
        }
        // Executions of these cases recompute even if they had no result rows
        // yet (their denominator shrinks too).
        Set<Id> caseIds = new Set<Id>();
        for (Test_Step__c s : oldSteps) {
            caseIds.add(s.Test_Case__c);
        }
        for (Test_Execution__c e : [
            SELECT Id FROM Test_Execution__c WHERE Test_Case__c IN :caseIds
        ]) {
            pendingRecompute.add(e.Id);
        }
        if (!results.isEmpty()) {
            suppressRollup = true;
            try {
                delete results;
            } finally {
                suppressRollup = false;
            }
        }
    }

    /** AFTER delete: the step row is gone, so the denominator is correct now
     *  (an execution can legitimately flip In Progress -> Complete here). */
    public static void afterStepDelete() {
        Set<Id> toRecompute = pendingRecompute;
        pendingRecompute = new Set<Id>();
        recomputeRollups(toRecompute);
    }

    // ---- Internals -----------------------------------------------------------------------------

    private static Boolean isDuplicateKeyFailure(Database.SaveResult sr) {
        for (Database.Error err : sr.getErrors()) {
            if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }
}