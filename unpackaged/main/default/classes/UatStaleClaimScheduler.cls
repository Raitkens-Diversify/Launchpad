/**
 * UatStaleClaimScheduler
 *
 * Nightly sweep returning stale claims to the pool (open-pool design §7):
 * a claim still at Not Started after its cycle's Stale_Claim_Days__c is
 * auto-released by UatExecutionService.releaseStaleClaims — same release
 * state machine as a tester's own release, logged as 'Auto Released'.
 *
 * Thin by design: the state machine lives in the service; scheduled Apex was
 * chosen over a scheduled flow so there is exactly one implementation of the
 * release rules (design §7). Volumes are tiny and the service is set-based,
 * so no Batchable is needed.
 *
 * NOT self-scheduling. Schedule once after deploy (any admin):
 *   System.schedule('UAT Stale Claim Release', '0 0 6 * * ?',
 *       new UatStaleClaimScheduler());
 */
public with sharing class UatStaleClaimScheduler implements Schedulable {

    public void execute(SchedulableContext context) {
        UatExecutionService.releaseStaleClaims(UserInfo.getUserId());
    }
}