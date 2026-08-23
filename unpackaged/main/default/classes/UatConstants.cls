/**
 * UatConstants
 *
 * The cross-class string contracts of the UAT feature: values that more than
 * one class writes/reads and that silently break matching if they drift.
 * Client-side mirror: lwc/uatConstants (change both together, and only when
 * the underlying picklist changes).
 *
 * Deliberately narrow — single-class literals stay where they're used; this
 * is a contract registry, not a string dumping ground.
 */
public with sharing class UatConstants {

    // ---- Test_Cycle__c.Status__c ------------------------------------------------
    public static final String CYCLE_ACTIVE = 'Active';
    public static final String CYCLE_CLAIMS_PAUSED = 'Claims Paused';
    public static final String CYCLE_CLOSED = 'Closed';

    // ---- Test_Case__c.Creation_Status__c ---------------------------------------
    /** Only Complete cases may enter books/cycles (books + cycles both gate on it). */
    public static final String CREATION_COMPLETE = 'Complete';
    /** Hidden from every add-picker (they gate on Complete); wherever the
     *  case already lives — books, cycles, run history — stays untouched. */
    public static final String CREATION_RETIRED = 'Retired';

    // ---- Exploratory_Session__c.Status__c ----------------------------------------
    // Written by UatSessionController's lifecycle; read by its gates and the
    // session LWCs (client mirror: lwc/uatConstants SESSION_STATUSES).
    public static final String SESSION_ACTIVE = 'Active';
    public static final String SESSION_COMPLETED = 'Completed';

    // ---- Test_Assignment_Event__c.Action__c ------------------------------------
    // Written by UatExecutionService's state machine; read back by the
    // dashboard activity feed and Pool Health audit trail.
    public static final String EVENT_CLAIMED = 'Claimed';
    public static final String EVENT_RELEASED = 'Released';
    public static final String EVENT_REASSIGNED = 'Reassigned';
    public static final String EVENT_FORCE_UNASSIGNED = 'Force Unassigned';
    public static final String EVENT_AUTO_RELEASED = 'Auto Released';

    /** The event types the tester dashboard's Cycle Activity feed displays. */
    public static final List<String> ACTIVITY_FEED_EVENTS = new List<String>{
        EVENT_CLAIMED, EVENT_RELEASED, EVENT_AUTO_RELEASED, EVENT_REASSIGNED
    };
}