import { LightningElement, api } from 'lwc';
import getCaseDetail from '@salesforce/apex/UatCaseAdminController.getCaseDetail';
import saveCase from '@salesforce/apex/UatCaseAdminController.saveCase';
import saveSteps from '@salesforce/apex/UatCaseAdminController.saveSteps';
import deleteStep from '@salesforce/apex/UatCaseAdminController.deleteStep';
import saveReferenceLink from '@salesforce/apex/UatCaseAdminController.saveReferenceLink';
import createReferenceFile from '@salesforce/apex/UatCaseAdminController.createReferenceFile';
import registerReferenceUpload from '@salesforce/apex/UatCaseAdminController.registerReferenceUpload';
import deleteReferenceMaterial from '@salesforce/apex/UatCaseAdminController.deleteReferenceMaterial';
import getExecutionsForCase from '@salesforce/apex/UatCaseAdminController.getExecutionsForCase';
import getExecutionView from '@salesforce/apex/UatCaseAdminController.getExecutionView';
import resolveExecutionForIdentity from '@salesforce/apex/UatCaseAdminController.resolveExecutionForIdentity';
import findExecutionForIdentity from '@salesforce/apex/UatCaseAdminController.findExecutionForIdentity';
import getTeamMembers from '@salesforce/apex/UatCaseAdminController.getTeamMembers';
import deleteEvidence from '@salesforce/apex/UatCaseAdminController.deleteEvidence';
import getCaseDeleteImpact from '@salesforce/apex/UatCaseAdminController.getCaseDeleteImpact';
import deleteCase from '@salesforce/apex/UatCaseAdminController.deleteCase';
import setCaseCreationStatus from '@salesforce/apex/UatCaseAdminController.setCaseCreationStatus';
import getBooks from '@salesforce/apex/UatBookAdminController.getBooks';
import addCaseToBook from '@salesforce/apex/UatBookAdminController.addCaseToBook';
import removeCaseFromBook from '@salesforce/apex/UatBookAdminController.removeCaseFromBook';
import getTaxonomy from '@salesforce/apex/UatTaxonomyAdminController.getTaxonomy';
import { messageFrom, toast } from 'c/messageUtil';
import { humanizeCaseCode, buildCaseCode } from 'c/uatTitleUtil';
import {
    CASE_CREATION_STATUSES, CASE_PRIORITIES, CASE_EFFORTS, toOptions, flattenModules
} from 'c/uatConstants';

/**
 * adminUatCaseDetail — the Test Case detail drill-in (adminArticleEditor
 * pattern: back-arrow bar + title + Save, full-screen inline page).
 *
 * Breadcrumb reflects how you got here: "All Test Cases / [Module]" normally,
 * or "All Test Cycles / [Cycle] / [Module]" when opened from a cycle's
 * execution chip — both ancestor levels clickable.
 *
 * Module is editable here (2026-08-12). It used to be create-only, which left
 * a mis-filed case stuck in its module forever; moving one re-sequences it in
 * the destination, so the Case ID changes and the preview says so up front.
 *
 * Test books shows CURRENT membership, add and remove. The old single
 * "Add to book when complete" picker was a pending pointer that the server
 * clears the instant it fires, so a case already in a book always rendered
 * "— none —" and every save looked like it had done nothing. That deferred
 * pointer survives for cases that aren't Complete yet — books refuse
 * non-Complete cases — but it's now labelled as the queue it is.
 *
 * The run selector lists every execution of this case ("[Cycle|Standalone] —
 * [Tester|Unclaimed]"); the read-only actuals in the Steps tab and the whole
 * Evidence & Feedback tab reflect the selected run. It is a VIEWER: a case's
 * runs come from the cycles its books are in, so picking here never moves the
 * case. Switching the Tester dropdown to a DIFFERENT tester re-identifies
 * which execution is displayed (find-or-create, 03 §2) — it never relabels
 * the current one, so two testers' results can never silently merge.
 *
 * Steps tab: the authoring surface (admins author, they don't grade). Steps
 * are edited locally and persisted as one batch on Save; the Test Condition
 * heading renames its whole group (03 §8); removal warns about the
 * cross-execution result loss (03 §9).
 */
let clientKey = 0;
const nextKey = () => 'k' + ++clientKey;

const STATUS_OPTIONS = toOptions(CASE_CREATION_STATUSES);
const PRIORITY_OPTIONS = toOptions(CASE_PRIORITIES);
const EFFORT_OPTIONS = [{ label: '—', value: '' }].concat(toOptions(CASE_EFFORTS));
const UNCLAIMED = 'UNCLAIMED';

export default class AdminUatCaseDetail extends LightningElement {
    @api caseId;
    @api openExecutionId;
    @api originCycleId;
    @api originCycleName;

    detail;
    loading = true;
    saving = false;
    errorMessage;

    activeTab = 'steps'; // steps | reference | evidence
    steps = [];
    stepsDirty = false;
    title = '';
    description = '';
    preConditions = '';
    creationStatus;
    priority;
    estimatedEffort = '';
    maxTestersOverride = ''; // '' = inherit the cycle default
    targetBookId = '';       // pending "add to book when Complete"
    allBooks = null;         // lazy-loaded once
    booksError;              // non-fatal: books unreadable, rest of page fine
    moduleRows = null;       // lazy-loaded once: flattened taxonomy
    moduleId = '';           // edited value; detail.moduleId is the saved one
    books = [];              // books this case is in right now

    executions = [];
    viewingId = '';
    execView = null;
    teamMembers = [];

    confirm = null;
    addLink = null;
    pendingFileRefId = null;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const [detail, executions] = await Promise.all([
                getCaseDetail({ caseId: this.caseId }),
                getExecutionsForCase({ caseId: this.caseId })
            ]);
            this.detail = detail;
            this.title = detail.title || '';
            this.description = detail.description || '';
            this.preConditions = detail.preConditions || '';
            this.creationStatus = detail.creationStatus;
            this.priority = detail.priority || 'Medium';
            this.estimatedEffort = detail.estimatedEffort || '';
            this.maxTestersOverride = detail.maxTestersOverride == null
                ? '' : String(detail.maxTestersOverride);
            this.targetBookId = detail.targetBookId || '';
            this.moduleId = detail.moduleId || '';
            this.books = detail.books || [];
            // Both lazy-load once and are reused across reloads. Taxonomy is
            // load-bearing (the console's list treats it the same way), so a
            // failure there fails the page. A books failure is survivable —
            // you can still author steps — but it is NAMED rather than
            // swallowed: an empty list that really meant "you can't read
            // books" used to render as a legitimate-looking "— none —", which
            // is how a broken picker passes for a working one.
            if (!this.moduleRows) {
                this.moduleRows = flattenModules(await getTaxonomy());
            }
            if (!this.allBooks) {
                try {
                    this.allBooks = await getBooks();
                    this.booksError = undefined;
                } catch (e) {
                    this.allBooks = [];
                    this.booksError = 'Test books could not be loaded: ' + messageFrom(e);
                }
            }
            this.steps = detail.steps.map((s) => ({ ...s, key: nextKey() }));
            this.stepsDirty = false;
            this.executions = executions;
            // Deep-linked run first, then the most recently touched CLAIMED
            // one, then simply the most recent (list is LastModifiedDate DESC,
            // matching the list view's "Latest Run" column). Claimed still
            // outranks unclaimed so a real tester's run isn't buried under a
            // freshly materialized empty seat — but landing on nothing at all
            // was worse: a case whose seats are all unclaimed opened on the
            // "Select a run…" placeholder and read as having no runs.
            const claimed = executions.find((e) => e.testerId);
            const fallback = claimed || executions[0];
            const preferred = this.openExecutionId
                && executions.some((e) => e.id === this.openExecutionId)
                ? this.openExecutionId
                : (fallback ? fallback.id : '');
            await this.selectExecution(preferred);
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    async selectExecution(executionId) {
        this.viewingId = executionId || '';
        if (!this.viewingId) {
            this.execView = null;
            this.teamMembers = [];
            return;
        }
        this.execView = await getExecutionView({ executionId: this.viewingId });
        this.teamMembers = this.execView.teamId
            ? await getTeamMembers({ teamId: this.execView.teamId })
            : [];
    }

    // ---- Header + breadcrumb ---------------------------------------------------

    /** Title headline; the Case ID slug moves down into the meta line. */
    get headerTitle() {
        return this.title || humanizeCaseCode(this.detail && this.detail.caseCode);
    }

    get metaLine() {
        const d = this.detail;
        if (!d) {
            return '';
        }
        return `${d.caseCode} · ${d.systemName} › ${d.groupName} · ${d.moduleName} · ${d.version}`
            + (d.authorName ? ` · Authored by ${d.authorName}` : '');
    }

    get statusOptions() {
        return STATUS_OPTIONS;
    }

    get busy() {
        return this.loading || this.saving;
    }

    get saveDisabled() {
        return this.busy;
    }

    get cameFromCycle() {
        return Boolean(this.originCycleId && this.originCycleName);
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleCrumbCycle() {
        this.dispatchEvent(new CustomEvent('navigatecycle', {
            detail: { cycleId: this.originCycleId }
        }));
    }

    handleStatusChange(event) {
        this.creationStatus = event.detail.value;
        this.stepsDirty = true;
    }

    get priorityOptions() {
        return PRIORITY_OPTIONS;
    }

    get effortOptions() {
        return EFFORT_OPTIONS;
    }

    handlePriorityChange(event) {
        this.priority = event.detail.value;
        this.stepsDirty = true;
    }

    handleTitleChange(event) {
        this.title = event.target.value;
        this.stepsDirty = true;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
        this.stepsDirty = true;
    }

    handlePreConditionsChange(event) {
        this.preConditions = event.target.value;
        this.stepsDirty = true;
    }

    handleEffortChange(event) {
        this.estimatedEffort = event.detail.value;
        this.stepsDirty = true;
    }

    handleMaxTestersOverrideChange(event) {
        this.maxTestersOverride = event.target.value;
        this.stepsDirty = true;
    }

    // ---- Module (re-filing) ------------------------------------------------------

    /** One qualified dropdown rather than the New Case modal's System > Group >
     *  Module cascade: here the module already exists and is only being picked,
     *  so a flat list pre-selects from detail.moduleId and can't strand you
     *  half-way down the tree. */
    get moduleOptions() {
        return (this.moduleRows || []).map((r) => ({ label: r.label, value: r.value }));
    }

    get moduleChanged() {
        return Boolean(this.detail) && this.moduleId !== (this.detail.moduleId || '');
    }

    /** The Case ID this move will produce — Case_ID__c is a formula over the
     *  taxonomy, and the server re-sequences into the destination module, so
     *  the number is a "next free" guess until Save lands. */
    get movePreview() {
        if (!this.moduleChanged) {
            return null;
        }
        const row = (this.moduleRows || []).find((r) => r.value === this.moduleId);
        if (!row) {
            return null;
        }
        return buildCaseCode({
            systemCode: row.systemCode,
            groupName: row.groupName,
            moduleName: row.moduleName,
            version: this.detail.version,
            sequence: null // server assigns the destination's next free number
        });
    }

    handleModuleChange(event) {
        this.moduleId = event.detail.value;
    }

    // ---- Test books --------------------------------------------------------------

    get isComplete() {
        return this.creationStatus === 'Complete';
    }

    get hasBooks() {
        return this.books.length > 0;
    }

    get bookRows() {
        return this.books.map((b) => ({ ...b, removeLabel: 'Remove from ' + b.bookName }));
    }

    get addBookLabel() {
        return this.isComplete ? 'Add to a test book' : 'Add to book when complete';
    }

    get addBookHelp() {
        return this.isComplete
            ? 'Adds this case to that book straight away. Every cycle running the book picks it up.'
            : 'Books only take Complete cases, so this queues the add: save this case as '
                + 'Complete and it is appended then, and this picker clears.';
    }

    /** The Complete picker is an action that fires and resets; the deferred
     *  one is a form field bound to Target_Book__c. */
    get addBookValue() {
        return this.isComplete ? '' : this.targetBookId;
    }

    /** Books this case isn't already in. Adding is immediate for a Complete
     *  case; for anything else the server refuses (a book feeds live cycles),
     *  so the same picker queues Target_Book__c instead. */
    get addBookOptions() {
        const joined = new Set(this.books.map((b) => b.bookId));
        const rows = (this.allBooks || []).filter((b) => !joined.has(b.id));
        const sentinel = this.isComplete
            ? { label: '— select a book —', value: '' }
            : { label: '— none —', value: '' };
        return [sentinel].concat(rows.map((b) => ({ label: b.name, value: b.id })));
    }

    /** Immediate add once Complete; otherwise the deferred pointer. */
    async handleAddBookChange(event) {
        const bookId = event.detail.value;
        if (!this.isComplete) {
            this.targetBookId = bookId;
            this.stepsDirty = true;
            return;
        }
        if (!bookId) {
            return;
        }
        const book = this.addBookOptions.find((o) => o.value === bookId);
        this.saving = true;
        try {
            await addCaseToBook({ bookId, caseId: this.caseId });
            toast(this, 'success', `Added to "${book ? book.label : 'the book'}".`);
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
            this.resetAddBookSelect();
        }
    }

    /** Same LWC quirk as revertTesterSelect: the combobox holds the value the
     *  user picked, and re-rendering with an unchanged '' won't clear it. */
    resetAddBookSelect() {
        if (!this.isComplete) {
            return;
        }
        const combobox = this.template.querySelector('[data-id="addbook-select"]');
        if (combobox) {
            combobox.value = '';
        }
    }

    handleRemoveBookClick(event) {
        const ds = event.currentTarget.dataset;
        this.confirm = {
            type: 'removeBook',
            bookItemId: ds.itemid,
            header: 'Remove from book: ' + ds.name,
            message: 'This case stops being part of "' + ds.name + '", so it stops '
                + 'reaching the cycles that run that book. Runs nobody has started '
                + 'yet are cleared; anything already recorded is kept.',
            confirmLabel: 'Remove from book'
        };
    }

    async handleSave() {
        this.saving = true;
        // The server appends the case to its pending book and clears the
        // pointer once the save lands with status Complete — mirror that
        // locally so the picker doesn't show a stale target.
        const pendingBook = this.creationStatus === 'Complete' && this.targetBookId
            ? (this.addBookOptions.find((o) => o.value === this.targetBookId) || {}).label
            : null;
        // A move rewrites Case_ID__c server-side, so the breadcrumb, meta line
        // and preview all have to come back from the server afterwards.
        const moved = this.moduleChanged;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            await saveCase({
                inputJson: JSON.stringify({
                    id: this.caseId,
                    title: this.title,
                    description: this.description,
                    preConditions: this.preConditions,
                    moduleId: this.moduleId || null,
                    version: this.detail.version,
                    sequence: this.detail.sequence,
                    testingSurface: this.detail.testingSurface,
                    creationStatus: this.creationStatus,
                    priority: this.priority,
                    estimatedEffort: this.estimatedEffort || null,
                    maxTestersOverride: this.maxTestersOverride
                        ? parseInt(this.maxTestersOverride, 10) : null,
                    targetBookId: this.targetBookId || null
                })
            });
            const fresh = await saveSteps({
                inputJson: JSON.stringify({
                    caseId: this.caseId,
                    steps: this.steps.map((s) => ({
                        id: s.id,
                        title: s.title,
                        condition: s.condition,
                        description: s.description,
                        expected: s.expected,
                        isExplore: s.isExplore,
                        explorePrompt: s.explorePrompt
                    }))
                })
            });
            this.steps = fresh.map((s) => ({ ...s, key: nextKey() }));
            this.stepsDirty = false;
            if (pendingBook) {
                this.targetBookId = '';
                toast(this, 'success', `Test case saved and added to "${pendingBook}".`);
            } else {
                toast(this, 'success', 'Test case saved.');
            }
            if (moved) {
                // Reload last: it replaces this.steps with the server's copy,
                // which the save above has already persisted.
                await this.load();
            }
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Viewing run ------------------------------------------------------------

    get hasExecutions() {
        return this.executions.length > 0;
    }

    get viewingOptions() {
        return this.executions.map((e) => ({ label: e.label, value: e.id }));
    }

    get testerOptions() {
        const base = [{ label: 'Unclaimed', value: UNCLAIMED }];
        return base.concat(this.teamMembers.map((m) => ({ label: m.label, value: m.testerId })));
    }

    get currentTesterValue() {
        return this.execView && this.execView.testerId ? this.execView.testerId : UNCLAIMED;
    }

    get execStatusBadge() {
        return this.execView ? this.execView.status : '';
    }

    get execResultBadge() {
        return this.execView && this.execView.result ? this.execView.result : '—';
    }

    async handleViewingChange(event) {
        this.saving = true;
        try {
            await this.selectExecution(event.detail.value);
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    /** 03 §2: a different tester = a different execution identity. Switch to
     *  that run if it exists; otherwise ask before creating one — browsing
     *  the dropdown must never silently put work in a tester's queue. */
    async handleTesterChange(event) {
        const picked = event.detail.value;
        const pickedTesterId = picked === UNCLAIMED ? null : picked;
        const currentTesterId = this.execView ? this.execView.testerId : null;
        if (pickedTesterId === currentTesterId) {
            return;
        }
        this.saving = true;
        try {
            const existing = await findExecutionForIdentity({
                caseId: this.caseId,
                cycleId: this.execView ? this.execView.cycleId : null,
                testerId: pickedTesterId
            });
            if (existing) {
                await this.selectExecution(existing.id);
                toast(this, 'success', 'Now viewing: ' + existing.label);
            } else {
                const option = this.testerOptions.find((o) => o.value === picked);
                const testerLabel = option ? option.label : 'that tester';
                const cycleLabel = (this.execView && this.execView.cycleName) || 'Standalone';
                this.confirm = {
                    type: 'createRun',
                    testerId: pickedTesterId,
                    header: 'Create run for ' + testerLabel,
                    message: pickedTesterId
                        ? 'No run exists for ' + testerLabel + ' in ' + cycleLabel
                            + '. Create one? It will appear in their queue as assigned work.'
                        : 'No unclaimed run exists in ' + cycleLabel
                            + '. Create one? It will appear in the team\'s queue as claimable work.',
                    confirmLabel: 'Create run'
                };
            }
        } catch (e) {
            toast(this, 'error', messageFrom(e));
            this.revertTesterSelect();
        } finally {
            this.saving = false;
        }
    }

    /** The combobox holds the picked value even though currentTesterValue
     *  didn't change (no re-render) — put it back explicitly. */
    revertTesterSelect() {
        const combobox = this.template.querySelector('[data-id="tester-select"]');
        if (combobox) {
            combobox.value = this.currentTesterValue;
        }
    }

    // ---- Tabs -----------------------------------------------------------------

    get isStepsTab() {
        return this.activeTab === 'steps';
    }

    get isReferenceTab() {
        return this.activeTab === 'reference';
    }

    get isEvidenceTab() {
        return this.activeTab === 'evidence';
    }

    get stepsTabClass() {
        return this.isStepsTab ? 'aud__tab aud__tab--active' : 'aud__tab';
    }

    get referenceTabClass() {
        return this.isReferenceTab ? 'aud__tab aud__tab--active' : 'aud__tab';
    }

    get evidenceTabClass() {
        return this.isEvidenceTab ? 'aud__tab aud__tab--active' : 'aud__tab';
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    // ---- Steps tab -------------------------------------------------------------

    get stepGroups() {
        const findings = new Map(
            (this.execView ? this.execView.stepResults : []).map((r) => [r.stepId, r])
        );
        const groups = [];
        const lastIndex = this.steps.length - 1;
        let current = null;
        this.steps.forEach((s, index) => {
            if (!current || current.condition !== (s.condition || '')) {
                // Keyed by the first member's client key, never the condition
                // text — a content-derived key remounts the whole <section>
                // (including the condition input) on every keystroke, which
                // drops focus after each typed character.
                current = { key: 'g-' + s.key, condition: s.condition || '', steps: [] };
                groups.push(current);
            }
            const finding = s.id ? findings.get(s.id) : null;
            current.steps.push({
                ...s,
                displayNumber: index + 1,
                isScripted: !s.isExplore,
                moveUpDisabled: this.busy || index === 0,
                moveDownDisabled: this.busy || index === lastIndex,
                findingActual: finding ? finding.actualResult : null,
                findingResult: finding ? finding.result : null,
                findingNotes: finding ? finding.exploreNotes : null,
                hasFinding: Boolean(finding && (finding.actualResult || finding.result || finding.exploreNotes))
            });
        });
        return groups;
    }

    get hasSteps() {
        return this.steps.length > 0;
    }

    get showFindings() {
        return this.execView !== null;
    }

    handleConditionChange(event) {
        const groupKey = event.currentTarget.dataset.group;
        const group = this.stepGroups.find((g) => g.key === groupKey);
        if (!group) {
            return;
        }
        const newValue = event.target.value;
        const keys = new Set(group.steps.map((s) => s.key));
        this.steps = this.steps.map((s) => (keys.has(s.key) ? { ...s, condition: newValue } : s));
        this.stepsDirty = true;
    }

    handleStepFieldChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = event.currentTarget.dataset.field;
        const value = event.target.value;
        this.steps = this.steps.map((s) => (s.key === key ? { ...s, [field]: value } : s));
        this.stepsDirty = true;
    }

    handleMoveStepUp(event) {
        this.moveStep(event.currentTarget.dataset.key, -1);
    }

    handleMoveStepDown(event) {
        this.moveStep(event.currentTarget.dataset.key, 1);
    }

    /** One visual slot per press. Inside a group that's a swap with the
     *  neighbor; at a group boundary the step instead adopts the destination
     *  group's condition in place (joining it as first/last member) so a move
     *  never splits the neighboring group. Nothing persists until Save. */
    moveStep(key, direction) {
        const steps = this.steps.map((s) => ({ ...s }));
        const i = steps.findIndex((s) => s.key === key);
        const j = i + direction;
        if (i < 0 || j < 0 || j >= steps.length) {
            return;
        }
        const moved = steps[i];
        const neighbor = steps[j];
        if ((neighbor.condition || '') !== (moved.condition || '')) {
            moved.condition = neighbor.condition;
        } else {
            steps[i] = neighbor;
            steps[j] = moved;
        }
        this.steps = steps;
        this.stepsDirty = true;
    }

    handleAddStep() {
        const lastCondition = this.steps.length
            ? this.steps[this.steps.length - 1].condition
            : 'Setup';
        this.steps = [...this.steps, {
            key: nextKey(), id: null, title: '', condition: lastCondition,
            description: '', expected: '', isExplore: false, explorePrompt: ''
        }];
        this.stepsDirty = true;
    }

    handleAddCondition() {
        this.steps = [...this.steps, {
            key: nextKey(), id: null, title: '', condition: 'New condition',
            description: '', expected: '', isExplore: false, explorePrompt: ''
        }];
        this.stepsDirty = true;
    }

    handleAddExplore() {
        const lastCondition = this.steps.length
            ? this.steps[this.steps.length - 1].condition
            : 'Exploratory';
        this.steps = [...this.steps, {
            key: nextKey(), id: null, title: '', condition: lastCondition,
            description: '', expected: '', isExplore: true, explorePrompt: ''
        }];
        this.stepsDirty = true;
    }

    handleRemoveStepClick(event) {
        const key = event.currentTarget.dataset.key;
        const step = this.steps.find((s) => s.key === key);
        const label = 'Step ' + (this.steps.indexOf(step) + 1);
        this.confirm = {
            type: 'step',
            key,
            header: 'Remove step: ' + label,
            message: 'Removing this step deletes its recorded results across EVERY '
                + 'execution of this case — every cycle it has ever run in, not just '
                + 'the one currently in view. The step definition and those results '
                + 'cannot be recovered.',
            confirmLabel: 'Remove step'
        };
    }

    // ---- Evidence & Feedback tab ------------------------------------------------

    get uxRatingDisplay() {
        return this.execView && this.execView.uxRating != null
            ? this.execView.uxRating + ' / 5'
            : 'Not rated yet';
    }

    get uxRecommendationDisplay() {
        return this.execView && this.execView.uxRecommendation
            ? this.execView.uxRecommendation
            : 'No suggestion left.';
    }

    get caseEvidence() {
        return this.execView ? this.execView.caseEvidence : [];
    }

    get hasCaseEvidence() {
        return this.caseEvidence.length > 0;
    }

    /** Per-step evidence, read-only (testers attach it, admins view it). */
    get stepEvidence() {
        if (!this.execView) {
            return [];
        }
        const numberByStep = new Map(this.steps.map((s, i) => [s.id, i + 1]));
        return this.execView.stepResults
            .filter((r) => r.files && r.files.length)
            .map((r) => ({
                stepId: r.stepId,
                label: 'Step ' + (numberByStep.get(r.stepId) || '?'),
                files: r.files
            }));
    }

    get hasStepEvidence() {
        return this.stepEvidence.length > 0;
    }

    handleRemoveEvidenceClick(event) {
        const ds = event.currentTarget.dataset;
        this.confirm = {
            type: 'evidence',
            contentDocumentId: ds.docid,
            recordId: this.viewingId,
            header: 'Remove evidence: ' + ds.title,
            message: 'The file is deleted for this run and cannot be recovered.',
            confirmLabel: 'Remove'
        };
    }

    // ---- Reference material tab ---------------------------------------------------

    get refRows() {
        if (!this.detail) {
            return [];
        }
        return this.detail.refMaterials.map((r) => ({
            ...r,
            isLink: r.type === 'Link',
            isFile: r.type === 'File',
            hasFile: r.type === 'File' && r.file != null,
            needsFile: r.type === 'File' && r.file == null,
            showThumb: r.type === 'File' && r.file != null && r.file.isImage,
            openUrl: r.type === 'Link' ? r.url : (r.file ? r.file.downloadUrl : null),
            displayLabel: r.label || (r.type === 'File' ? '(no file uploaded yet)' : r.url)
        }));
    }

    get hasRefRows() {
        return this.refRows.length > 0;
    }

    get addLinkOpen() {
        return this.addLink !== null;
    }

    get acceptedFormats() {
        return ['.png', '.jpg', '.jpeg', '.gif', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.txt', '.mp4'];
    }

    handleAddLinkOpen() {
        this.addLink = { label: '', url: '' };
    }

    handleAddLinkField(event) {
        this.addLink = { ...this.addLink, [event.currentTarget.dataset.field]: event.target.value };
    }

    handleAddLinkCancel() {
        this.addLink = null;
    }

    async handleAddLinkSave() {
        if (!this.addLink.label || !this.addLink.url) {
            toast(this, 'error', 'Links need both a label and a URL.');
            return;
        }
        this.saving = true;
        try {
            await saveReferenceLink({
                inputJson: JSON.stringify({ caseId: this.caseId, label: this.addLink.label, url: this.addLink.url })
            });
            this.addLink = null;
            toast(this, 'success', 'Link added.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    async handleAddFile() {
        this.saving = true;
        try {
            this.pendingFileRefId = await createReferenceFile({ caseId: this.caseId });
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    async handleUploadFinished(event) {
        const refId = event.currentTarget.dataset.refid;
        const docIds = event.detail.files.map((f) => f.documentId);
        try {
            await registerReferenceUpload({ refId, contentDocumentIds: docIds });
            this.pendingFileRefId = null;
            toast(this, 'success', 'File attached.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
    }

    handleRemoveRefClick(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.refRows.find((r) => r.id === id);
        this.confirm = {
            type: 'ref',
            id,
            header: 'Remove reference material: ' + row.displayLabel,
            message: 'Testers will stop seeing this on every run of this case. '
                + (row.isFile ? 'The attached file is deleted with it.' : ''),
            confirmLabel: 'Remove'
        };
    }

    // ---- Shared confirm modal -------------------------------------------------------

    get confirmOpen() {
        return this.confirm !== null;
    }

    handleConfirmCancel() {
        if (this.confirm && this.confirm.type === 'createRun') {
            this.revertTesterSelect();
        }
        this.confirm = null;
    }

    // ---- Retire / delete case (2026-08-05) ----------------------------------------

    get isRetired() {
        return this.creationStatus === 'Retired';
    }

    handleRetireClick() {
        this.confirm = {
            type: 'retire',
            variant: 'brand',
            header: 'Retire case: ' + (this.detail ? this.detail.caseCode : ''),
            message: 'Hides this case from the book and cycle pickers. It stays in every '
                + 'book and cycle it\'s already part of, and all recorded runs are kept. '
                + 'You can restore it any time.',
            confirmLabel: 'Retire case'
        };
    }

    /** Restore is non-destructive — no confirm needed. */
    async handleRestoreClick() {
        this.saving = true;
        try {
            await setCaseCreationStatus({ caseId: this.caseId, status: 'Complete' });
            toast(this, 'success', 'Case restored — it\'s back in the pickers as Complete.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    /** Blocked deletes pivot to Retire-instead; clear ones get the numbers. */
    async handleDeleteCaseClick() {
        this.saving = true;
        try {
            const impact = await getCaseDeleteImpact({ caseId: this.caseId });
            if (impact.blocked) {
                const parts = [];
                if (impact.bookNames.length) {
                    parts.push(`${impact.bookNames.length} book${impact.bookNames.length === 1 ? '' : 's'} `
                        + `(${impact.bookNames.join(', ')})`);
                }
                if (impact.cycleNames.length) {
                    parts.push(`${impact.cycleNames.length} cycle${impact.cycleNames.length === 1 ? '' : 's'} `
                        + `(${impact.cycleNames.join(', ')})`);
                }
                if (impact.executionCount > 0) {
                    parts.push(`${impact.executionCount} recorded run${impact.executionCount === 1 ? '' : 's'}`);
                }
                this.confirm = {
                    type: 'retireInstead',
                    variant: 'brand',
                    header: `Can't delete: ${impact.caseCode}`,
                    message: `It's in ${parts.join(', ')}. Remove it from those places first — `
                        + 'or retire it, which hides it from the pickers while keeping '
                        + 'everything it\'s already part of.',
                    confirmLabel: 'Retire instead'
                };
            } else {
                this.confirm = {
                    type: 'deleteCase',
                    header: 'Delete case: ' + impact.caseCode,
                    message: `Permanently deletes this case, its ${impact.stepCount} `
                        + `step${impact.stepCount === 1 ? '' : 's'}, and ${impact.refCount} `
                        + `reference item${impact.refCount === 1 ? '' : 's'}. Uploaded `
                        + 'reference files stay in their uploaders\' Files. This cannot be undone.',
                    confirmLabel: 'Delete case'
                };
            }
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    async handleConfirmProceed() {
        const c = this.confirm;
        this.saving = true;
        try {
            if (c.type === 'retire' || c.type === 'retireInstead') {
                await setCaseCreationStatus({ caseId: this.caseId, status: 'Retired' });
                this.confirm = null;
                toast(this, 'success', 'Case retired — it stays wherever it already is.');
                await this.load();
                return;
            }
            if (c.type === 'deleteCase') {
                await deleteCase({ caseId: this.caseId });
                this.confirm = null;
                toast(this, 'success', 'Case deleted.');
                this.handleBack(); // the record is gone; the list reloads behind us
                return;
            }
            if (c.type === 'step') {
                const step = this.steps.find((s) => s.key === c.key);
                if (step && step.id) {
                    await deleteStep({ stepId: step.id });
                }
                this.steps = this.steps.filter((s) => s.key !== c.key);
                toast(this, 'success', 'Step removed.');
            } else if (c.type === 'ref') {
                await deleteReferenceMaterial({ refId: c.id });
                toast(this, 'success', 'Reference material removed.');
                await this.load();
            } else if (c.type === 'removeBook') {
                await removeCaseFromBook({ bookItemId: c.bookItemId });
                toast(this, 'success', 'Removed from the book.');
                await this.load();
            } else if (c.type === 'evidence') {
                await deleteEvidence({ contentDocumentId: c.contentDocumentId, recordId: c.recordId });
                toast(this, 'success', 'Evidence removed.');
                await this.selectExecution(this.viewingId);
            } else if (c.type === 'createRun') {
                const resolved = await resolveExecutionForIdentity({
                    caseId: this.caseId,
                    cycleId: this.execView ? this.execView.cycleId : null,
                    testerId: c.testerId
                });
                this.executions = await getExecutionsForCase({ caseId: this.caseId });
                await this.selectExecution(resolved.id);
                toast(this, 'success', 'Run created — now viewing: ' + resolved.label);
            }
            this.confirm = null;
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Internals ---------------------------------------------------------------------

}