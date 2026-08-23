/**
 * uatConstants — the single client-side source for the UAT picklist
 * vocabularies and their badge-variant/sort mappings (the envelopeFormSchema
 * pattern: shared pure module instead of per-component copies).
 *
 * Values mirror the picklists on the UAT objects; the server-side mirror is
 * UatConstants.cls — change both together, and only when the field changes.
 *
 * Note the two deliberately different result vocabularies:
 *  - Test_Step_Result__c.Result__c:        Pass / Fail / Blocked / N/A
 *  - Test_Execution__c.Testing_Result__c:  Passed / Failed / Blocked / Postponed
 * A step gets a verb, an execution gets an outcome. Don't "fix" one to match
 * the other — the fields differ on purpose.
 */
import { joinMeta, formatTime } from 'c/uatCardUtil';

// Test_Case__c
export const CASE_PRIORITIES = ['Critical', 'High', 'Medium', 'Low'];
export const CASE_EFFORTS = ['Small', 'Medium', 'Large'];
// Retired hides a case from the book/cycle add-pickers (they gate on
// Complete) while keeping it everywhere it already is — history untouched.
export const CASE_CREATION_STATUSES = ['Draft', 'In Progress', 'Complete', 'Retired'];
export const TESTING_SURFACES = [
    'Lightning App (Internal)',
    'Client Portal / Experience Cloud',
    'Integration / API Layer',
    'Mobile',
    'Multiple'
];

// Test_Step_Result__c.Result__c
export const STEP_RESULTS = ['Pass', 'Fail', 'Blocked', 'N/A'];

// Test_Execution__c
export const EXECUTION_RESULTS = ['Passed', 'Failed', 'Blocked', 'Postponed'];
export const EXECUTION_STATUSES = ['Not Started', 'In Progress', 'Complete'];

// Test_Cycle__c.Status__c
export const CYCLE_STATUSES = ['Active', 'Claims Paused', 'Closed'];

// Exploratory_Session__c.Status__c (server mirror: UatConstants.SESSION_*)
export const SESSION_STATUSES = ['Active', 'Completed'];

// Severity vocabulary — Test_Step_Result__c.Defect_Severity__c (the runner's
// defect capture); Exploratory_Finding__c.Severity__c mirrors it exactly.
export const DEFECT_SEVERITIES = ['Low', 'Medium', 'High', 'Critical'];

/**
 * Exploratory_Finding__c.Type__c. REPLACED the old Pass/Fail Result__c, which
 * was a test verdict masquerading as a defect description — a "Pass" finding
 * carrying a Critical severity said nothing at all. Severity applies ONLY to
 * Defect; the server force-clears it for the other three.
 */
export const FINDING_TYPES = ['Defect', 'Works as expected', 'Suggestion', 'Question'];
export const FINDING_TYPE_DEFECT = 'Defect';

/** Severities serious enough that "no evidence" has to be a stated choice —
 *  mirrors UatRunController.EVIDENCE_REQUIRED and the finish gate. */
export const EVIDENCE_REQUIRED_SEVERITIES = ['High', 'Critical'];

/** Finding type → ds-badge variant. */
export const FINDING_TYPE_VARIANT = {
    Defect: 'error',
    'Works as expected': 'success',
    Suggestion: 'info',
    Question: 'default'
};

/** Where a finding came from → ds-badge variant (the triage filter). */
export const FINDING_SOURCE_VARIANT = { Session: 'default', 'Test case': 'info' };

/**
 * Exploratory_Finding__c.Workflow_Status__c — the admin triage disposition
 * (which tracker a defect went to). Written only through
 * UatReportController.setFindingWorkflowStatus; every tester surface shows it
 * read-only. Server mirror: UatReportController.WORKFLOW_STATUS_VALUES and the
 * field XML — change all three together. Null on a DTO means 'New' (the
 * picklist default): pre-backfill rows and orgs mid-deploy both look like that.
 */
export const WORKFLOW_STATUSES = ['New', 'Added to Jira', 'Added to ClickUp', 'Not verified', 'Resolved'];
export const WORKFLOW_STATUS_NEW = 'New';
/** The two Added-to-* values — the "In tracker" filter bucket, and the ones
 *  whose selection prompts for a ticket ref. */
export const WORKFLOW_STATUSES_IN_TRACKER = ['Added to Jira', 'Added to ClickUp'];

/** Workflow status → ds-badge variant. New stays 'default' deliberately —
 *  it is the resting state of every finding, not an alert. */
export const WORKFLOW_STATUS_VARIANT = {
    New: 'default',
    'Added to Jira': 'info',
    'Added to ClickUp': 'info',
    'Not verified': 'warning',
    Resolved: 'success'
};

// ---- Badge variants (ds-badge) and sort weights ----------------------------

export const PRIORITY_VARIANT = { Critical: 'error', High: 'warning', Medium: 'info', Low: 'default' };
export const PRIORITY_ORDER = { Critical: 0, High: 1, Medium: 2, Low: 3 };
export const EFFORT_ORDER = { Small: 0, Medium: 1, Large: 2 };

/** Execution results (Passed/Failed/Blocked) → ds-badge variant. */
export const RESULT_VARIANT = { Passed: 'success', Failed: 'error', Blocked: 'warning' };

/** Cycle status → ds-badge variant. */
export const CYCLE_STATUS_VARIANT = { Active: 'success', 'Claims Paused': 'warning', Closed: 'default' };

/** Session status → ds-badge variant. */
export const SESSION_STATUS_VARIANT = { Active: 'info', Completed: 'success' };

/** Finding/defect severity → ds-badge variant. */
export const SEVERITY_VARIANT = { Critical: 'error', High: 'warning', Medium: 'info', Low: 'default' };

/**
 * Lifecycle pill per bucketOf() bucket (My Queue rows). The pill carries the
 * LIFECYCLE only — verdicts (Passed/Failed, "1 failed step") render as
 * secondary indicators via RESULT_VARIANT, never as the pill itself: a
 * mid-run execution with one failed step is In Progress, not "Failed".
 */
export const BUCKET_BADGE = {
    notStarted: { label: 'Not Started', variant: 'default' },
    inProgress: { label: 'In Progress', variant: 'info' },
    blocked: { label: 'Blocked', variant: 'warning' },
    completed: { label: 'Completed', variant: 'success' }
};

/** Assigned-list lifecycle group order (My Queue's default sort): active
 *  work first, stuck work right behind it, fresh work next, done work last.
 *  Client-only — no Apex mirror; the buckets themselves stay mirrored via
 *  bucketOf. */
export const BUCKET_ORDER = { inProgress: 0, blocked: 1, notStarted: 2, completed: 3 };

// ---- Helpers ----------------------------------------------------------------

/**
 * One status bucket per queue card — the client mirror of
 * UatRunController.bucketOf (keep the two in step). The verdict outranks the
 * status: a Complete run whose result is Blocked is stuck, not done. Used by
 * the queue's filter chips so their counts agree with the server summary.
 * Returns: 'notStarted' | 'inProgress' | 'blocked' | 'completed'.
 * (The Apex side splits completed into passed/failed for the hero; the chip
 * vocabulary only needs the merged bucket.)
 */
export function bucketOf(card) {
    if (card.status === 'Complete') {
        return card.result === 'Blocked' ? 'blocked' : 'completed';
    }
    if (card.result === 'Blocked') {
        return 'blocked';
    }
    if (card.status === 'Not Started') {
        return 'notStarted';
    }
    return 'inProgress';
}

/**
 * RunnerDTO.referenceMaterials → renderable rows. A reference is either a link
 * (open the URL) or an uploaded file (open its download URL); the label falls
 * back to the URL so a row never renders blank. Shared by the runner's sidebar
 * and the pool's case preview, which read the same DTO.
 */
export function referenceRowsOf(referenceMaterials) {
    return (referenceMaterials || []).map((r, i) => ({
        ...r,
        key: 'ref' + i,
        openUrl: r.type === 'Link' ? r.url : (r.file ? r.file.downloadUrl : null),
        displayLabel: r.label || r.url
    }));
}

/** ['A','B'] → [{label:'A', value:'A'}, …] for lightning-combobox. */
export function toOptions(values) {
    return values.map((v) => ({ label: v, value: v }));
}

/** toOptions() with a leading catch-all entry (filter dropdowns). */
export function toFilterOptions(allLabel, values, allValue = 'all') {
    return [{ label: allLabel, value: allValue }].concat(toOptions(values));
}

/** "From session note · 14:32", or null when the finding was not promoted from
 *  one. The two DTOs name that timestamp differently. */
function originLineOf(f) {
    const loggedAt = f.sourceLoggedAt || f.sourceNoteLoggedAt;
    if (!f.sourceNoteId || !loggedAt) {
        return null;
    }
    return `From session note · ${formatTime(loggedAt)}`;
}

/**
 * One finding, shaped for c/uatFindingDetail.
 *
 * Two DTOs describe the same record under different names —
 * UatRunController.FindingDTO uses id/type (the tester surfaces) and
 * UatReportController.FindingRowDTO uses findingId/findingType (the Cycle
 * Report) — so the normalizer lives here and every consumer maps through it.
 * Without it, "the admin sees exactly what the tester sees" would be a promise
 * kept by hand across two templates, which is precisely how they drift.
 *
 * The unknown-side fields are spread through untouched: a caller that needs
 * caseCode or stepResultName still has them.
 */
export function findingViewModel(dto) {
    const f = dto || {};
    const type = f.type || f.findingType;
    const files = f.files || [];
    const count = files.length;
    const workflowStatus = f.workflowStatus || WORKFLOW_STATUS_NEW;
    const externalRef = f.externalRef || null;
    return {
        ...f,
        id: f.id || f.findingId,
        type,
        files,
        headline: f.title || f.whatHappened,
        typeVariant: FINDING_TYPE_VARIANT[type] || 'default',
        isDefect: type === FINDING_TYPE_DEFECT,
        hasSeverity: Boolean(f.severity),
        severityVariant: SEVERITY_VARIANT[f.severity] || 'default',
        workflowStatus,
        workflowStatusVariant: WORKFLOW_STATUS_VARIANT[workflowStatus] || 'default',
        externalRef,
        /** Only a real URL becomes an anchor; a bare ticket key stays text. */
        externalRefIsLink: /^https?:\/\//i.test(externalRef || ''),
        fromNote: Boolean(f.sourceNoteId),
        originLine: originLineOf(f),
        metaLine: joinMeta([
            f.testerName,
            f.dateLogged,
            count ? `${count} file${count === 1 ? '' : 's'}` : null
        ]),
        hasFiles: count > 0
    };
}

/**
 * The getTaxonomy() tree flattened to one row per module, labelled with its
 * full path ("ARC › Salesforce UI › Opportunities"). A case's module is a
 * single lookup, so anywhere it's PICKED rather than AUTHORED one qualified
 * dropdown beats three cascading ones — it pre-selects from a bare module Id
 * and can't strand the user on a half-made choice. (The New Case modal keeps
 * its cascade: authoring a new case walks the taxonomy on purpose.)
 *
 * Rows carry the ancestry the Case ID preview needs, so callers never re-walk
 * the tree; map to {label, value} when handing them to lightning-combobox.
 */
export function flattenModules(taxonomy) {
    const rows = [];
    (taxonomy || []).forEach((system) => {
        (system.groups || []).forEach((group) => {
            (group.modules || []).forEach((module) => {
                rows.push({
                    value: module.id,
                    label: `${system.name} › ${group.name} › ${module.name}`,
                    systemId: system.id,
                    systemCode: system.code,
                    groupId: group.id,
                    groupName: group.name,
                    moduleName: module.name
                });
            });
        });
    });
    return rows;
}