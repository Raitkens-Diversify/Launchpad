import { LightningElement, api } from 'lwc';
import startExecution from '@salesforce/apex/UatRunController.startExecution';
import claimAndStart from '@salesforce/apex/UatRunController.claimAndStart';
import saveStepResult from '@salesforce/apex/UatRunController.saveStepResult';
import saveFeedback from '@salesforce/apex/UatRunController.saveFeedback';
import saveAndExit from '@salesforce/apex/UatRunController.saveAndExit';
import submitExecution from '@salesforce/apex/UatRunController.submitExecution';
import logOffScript from '@salesforce/apex/UatSessionController.logOffScript';
import { messageFrom, toast } from 'c/messageUtil';
import { STEP_RESULTS, DEFECT_SEVERITIES, referenceRowsOf } from 'c/uatConstants';
import { humanizeCaseCode } from 'c/uatTitleUtil';
import { relativeTime, formatDateLong, joinMeta } from 'c/uatCardUtil';

/**
 * uatRunner — the step-by-step runner for one execution, laid out as a
 * two-column testing workspace: the step card (condition heading, read-only
 * What-to-do / Expected Result, FOUR LARGE result buttons — deliberate: speed
 * + tap-friendliness — then "Actual result and notes" and per-step evidence)
 * on the left; the step navigator, run details, and the collapsed reference /
 * run-level-evidence disclosures on the right. Explore steps swap the result
 * buttons for a free-text notes field.
 *
 * The verdict sits ABOVE the notes field on purpose (2026-08-14). With the
 * textarea first, the natural top-to-bottom path was type → "Save & next
 * step", which saves a step with prose and no verdict, reports "Saved", and
 * leaves the run In Progress — a tester filed that as a status bug after
 * submitting a case they believed was complete. The rollup was right; the
 * form order was the defect. Nothing here BLOCKS a partial submit — it stays a
 * real workflow — but every surface now says so out loud: an inline cue on an
 * unanswered step, "Saved — still needs a result", an alert-weight review
 * block, a "Submit incomplete" button, and a warning (not success) toast keyed
 * on the status the SERVER stored.
 *
 * Navigation is free-order: Previous / Save & next step, jump-anywhere rows
 * in the navigator (the departing step autosaves first), and a pinned bottom
 * bar. The last step's primary action opens a submit review modal
 * (c-ds-modal-v2) that lists unanswered steps, nudges on Fail/Blocked steps
 * with no notes or evidence, and hosts the run-level "How was this
 * experience?" feedback — submit itself never fires without that review.
 */
const RESULT_HINT = { Pass: 'P', Fail: 'F', Blocked: 'B', 'N/A': 'N' };
const RESULT_ICON = {
    Pass: 'utility:check',
    Fail: 'utility:close',
    Blocked: 'utility:ban',
    'N/A': 'utility:dash'
};
/* Status-aware coaching in the empty field; never touches a typed value. */
const RESULT_PLACEHOLDER = {
    Pass: 'Optional — anything worth noting.',
    Fail: 'What went wrong? What did you click, and what did you see?',
    Blocked: 'What stopped you from completing this step?',
    'N/A': 'Optional — why does this step not apply?'
};
const DEFAULT_PLACEHOLDER = 'Describe what happened when you followed the steps.';
/* LWS can retarget composedPath()[0] to the base component's host element
 * instead of the native input inside it — treat those hosts as typing too. */
const LIGHTNING_INPUT_TAGS = new Set([
    'LIGHTNING-INPUT', 'LIGHTNING-TEXTAREA', 'LIGHTNING-COMBOBOX',
    'LIGHTNING-INPUT-FIELD', 'LIGHTNING-RADIO-GROUP', 'LIGHTNING-CHECKBOX-GROUP',
    'LIGHTNING-DUAL-LISTBOX', 'LIGHTNING-FILE-UPLOAD'
]);
const RATINGS = [1, 2, 3, 4, 5];
const FEEDBACK_DEBOUNCE_MS = 800;

export default class UatRunner extends LightningElement {
    @api executionId;
    @api caseIndex;
    @api caseTotal;

    _claimOnStart = false;
    @api
    get claimOnStart() {
        return this._claimOnStart;
    }
    set claimOnStart(value) {
        this._claimOnStart = value === '' ? true : Boolean(value);
    }

    runner;
    loading = true;
    saving = false;
    errorMessage;

    stepIndex = 0;
    steps = [];
    uxRating = null;
    uxRecommendation = '';
    _feedbackTimer;
    _feedbackPending = false;

    saveState = 'idle'; // idle | saving | saved | error
    defectOpenStepId = null;
    submitModalOpen = false;
    _focusStepPending = false;

    connectedCallback() {
        this.load();
    }

    disconnectedCallback() {
        window.clearTimeout(this._feedbackTimer);
    }

    /* Shortcuts are handled ONLY at the template level (`onkeydown` on the
     * .ur root). This path never crosses a namespace/shadow boundary, so
     * Lightning Web Security can't filter or distort it, and event.target is
     * retargeted no deeper than our own children (e.g. LIGHTNING-TEXTAREA),
     * so the typing guard is exact.
     *
     * There is deliberately NO window-level listener. Under LWS a window
     * listener cannot reliably tell "typing in a field" from "no focus at
     * all" (composedPath() comes back filtered/empty and activeElement
     * lies across the sandbox boundary) — the org-observed failures were
     * exactly that: first shortcuts that never fired, then shortcuts firing
     * WHILE typing. Focus management replaces it: the step card takes focus
     * on load and every step change, and clicking dead space in the runner
     * reclaims focus for the card (handleTemplateClick), so keys land in
     * the template in every normal flow.
     *
     * A consumed key stops propagating so nothing above us double-handles. */
    handleTemplateKeydown(event) {
        if (this.processKey(event, event.target)) {
            event.stopPropagation();
        }
    }

    /* Clicking non-interactive space drops browser focus to <body>, which
     * would put the keyboard out of the template handler's reach — reclaim
     * it for the step card. Never steals from a real control: only fires
     * when nothing in the template holds focus. */
    handleTemplateClick() {
        if (!this.template.activeElement) {
            this.focusCardNow();
        }
    }

    /* Shortcut logic. Returns true when the key was consumed. */
    processKey(event, origin) {
        if (!this.runner || this.submitModalOpen) {
            return false; // the modal owns the keyboard (its own Escape/focus trap)
        }
        if (!origin) {
            return false;
        }
        const tag = origin.tagName || '';
        const isTyping = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'
            || origin.isContentEditable
            || LIGHTNING_INPUT_TAGS.has(tag);
        if (isTyping) {
            // The one shortcut that works while typing: Escape leaves the
            // field — and hands focus to the step card so the letter
            // shortcuts respond immediately (a bare blur() would drop focus
            // to <body>, outside the template handler's reach).
            if (event.key === 'Escape' && typeof origin.blur === 'function') {
                origin.blur();
                this.focusCardNow();
                return true;
            }
            return false;
        }
        // No button-focus guard needed: buttons activate on Enter/Space and
        // neither is bound here (Enter deliberately does nothing — it used to
        // race a focused button's own click and could double-submit).
        if (this.busy) {
            return false; // documented: shortcuts drop during save round-trips
        }
        const key = (event.key || '').toLowerCase();
        if (key === 'e') {
            event.preventDefault();
            const field = this.template.querySelector('[data-field="actual"], [data-field="notes"]');
            if (field && typeof field.focus === 'function') {
                field.focus();
            }
            return true;
        }
        const result = this.resultForHintKey(key);
        if (this.isScriptedStep && result) {
            event.preventDefault();
            this.selectResult(result);
            return true;
        }
        if (key === 'arrowright') {
            event.preventDefault();
            this.handleNext();
            return true;
        }
        if (key === 'arrowleft') {
            event.preventDefault();
            this.handlePrevious();
            return true;
        }
        if (key === 's') {
            event.preventDefault();
            this.handleSaveExit();
            return true;
        }
        return false;
    }

    resultForHintKey(key) {
        return STEP_RESULTS.find((r) => RESULT_HINT[r].toLowerCase() === key);
    }

    /* Focus the step card (tabindex="-1") after load and after each step
     * change: keystrokes then land inside the runner's own template, where
     * the primary handler lives, and a screen reader announces the new
     * step's position. Never fires on ordinary re-renders — that would
     * steal focus mid-typing. */
    renderedCallback() {
        if (!this._focusStepPending) {
            return;
        }
        this._focusStepPending = false;
        this.focusCardNow();
    }

    focusStepCard() {
        this._focusStepPending = true;
    }

    focusCardNow() {
        const card = this.template.querySelector('.ur__step-card');
        if (card && typeof card.focus === 'function') {
            card.focus({ preventScroll: true });
        }
    }

    async load() {
        this.loading = true;
        try {
            this.runner = this.claimOnStart
                ? await claimAndStart({ executionId: this.executionId })
                : await startExecution({ executionId: this.executionId });
            this.steps = this.runner.steps.map((s) => ({ ...s }));
            this.uxRating = this.runner.uxRating;
            this.uxRecommendation = this.runner.uxRecommendation || '';
            this.stepIndex = this.resumeIndex();
            this.errorMessage = undefined;
            this.focusStepCard();
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    /* Resume where the work is: the first step with nothing recorded. A fully
     * answered run lands on the last step, where Review & submit is at hand. */
    resumeIndex() {
        const open = this.steps.findIndex((s) => (s.isExplore ? !s.exploreNotes : !s.result));
        if (open !== -1) {
            return open;
        }
        return this.steps.length ? this.steps.length - 1 : 0;
    }

    // ---- Header ------------------------------------------------------------------

    get busy() {
        return this.loading || this.saving;
    }

    get hasSteps() {
        return this.steps.length > 0;
    }

    get currentStep() {
        return this.steps[this.stepIndex];
    }

    get displayTitle() {
        return this.runner.caseTitle || humanizeCaseCode(this.runner.caseCode);
    }

    get crumbItems() {
        return [{ label: 'My Test Cases', key: 'queue' }, { label: this.displayTitle }];
    }

    /* "Client Records · Helios 2.4 Regression · #1002" — the readable trail.
     * The full technical slug lives in the Run details card, not here. */
    get metaLine() {
        const tail = this.runner.caseCode ? this.runner.caseCode.split('-').pop() : '';
        return joinMeta([
            this.runner.moduleName,
            this.runner.cycleName || 'Standalone',
            tail ? '#' + tail : ''
        ]);
    }

    get conditionTag() {
        const s = this.currentStep;
        return s && s.isExplore ? 'Exploratory testing' : (s ? s.condition : '');
    }

    get hasPreConditions() {
        return Boolean(this.runner && this.runner.preConditions);
    }

    get stepCountLabel() {
        return `Step ${this.stepIndex + 1} of ${this.steps.length}`;
    }

    get progressPercent() {
        const scripted = this.steps.filter((s) => !s.isExplore);
        if (!scripted.length) {
            return 0;
        }
        const answered = scripted.filter((s) => s.result).length;
        return Math.round((answered / scripted.length) * 100);
    }

    /* Composition over the scripted steps (explore steps sit outside the
     * completion math, mirroring the Apex rollup denominator). */
    get progressSegments() {
        const scripted = this.steps.filter((s) => !s.isExplore);
        const count = (value) => scripted.filter((s) => s.result === value).length;
        const answered = scripted.filter((s) => s.result).length;
        return [
            { value: count('Pass'), variant: 'success' },
            { value: count('Fail'), variant: 'error' },
            { value: count('Blocked'), variant: 'warning' },
            { value: count('N/A'), variant: 'accent' },
            { value: scripted.length - answered, variant: 'track' }
        ];
    }

    get progressCaption() {
        return `${this.stepCountLabel} · ${this.progressPercent}% complete`;
    }

    get hasReferenceMaterials() {
        return this.runner && this.runner.referenceMaterials.length > 0;
    }

    get referenceRows() {
        return this.runner ? referenceRowsOf(this.runner.referenceMaterials) : [];
    }

    // ---- Run details sidebar card --------------------------------------------------

    get runDetails() {
        const r = this.runner;
        const rows = [
            { key: 'cycle', label: 'Test cycle', value: r.cycleName || 'Standalone' },
            { key: 'area', label: 'Area', value: r.moduleName },
            { key: 'version', label: 'Version', value: r.version },
            { key: 'target', label: 'Target date', value: r.targetDate ? formatDateLong(r.targetDate) : '' },
            { key: 'case', label: 'Case ID', value: r.caseCode, small: true },
            { key: 'claimed', label: 'Claimed', value: r.claimedDate ? relativeTime(r.claimedDate) : '' },
            { key: 'autosave', label: 'Autosave', value: this.showSaveIndicator ? this.saveIndicatorLabel : '' }
        ];
        return rows
            .filter((row) => row.value)
            .map((row) => ({
                ...row,
                valueClass: 'ur__detail-value' + (row.small ? ' ur__detail-value--small' : '')
            }));
    }

    // ---- Result buttons -----------------------------------------------------------

    get resultButtons() {
        const current = this.currentStep ? this.currentStep.result : null;
        return STEP_RESULTS.map((value) => ({
            value,
            hintLetter: RESULT_HINT[value],
            iconName: RESULT_ICON[value],
            ariaChecked: current === value ? 'true' : 'false',
            cssClass: 'ur__result'
                + ' ur__result--' + value.toLowerCase().replace('/', '')
                + (current === value ? ' ur__result--selected' : '')
        }));
    }

    get actualPlaceholder() {
        const result = this.currentStep ? this.currentStep.result : null;
        return RESULT_PLACEHOLDER[result] || DEFAULT_PLACEHOLDER;
    }

    get showEvidenceHint() {
        const result = this.currentStep ? this.currentStep.result : null;
        return this.isScriptedStep && (result === 'Fail' || result === 'Blocked');
    }

    // ---- Case position (optional — only set when opened from a screen that
    // already knows the tester's position within the cycle, e.g. My Queue) --

    get hasCasePosition() {
        return this.caseIndex != null && this.caseTotal != null;
    }

    get casePositionLabel() {
        return `Case ${this.caseIndex} of ${this.caseTotal} in this cycle`;
    }

    // ---- Defect disclosure (appears once a scripted step is marked Fail) ----------

    get showDefectToggle() {
        return this.isScriptedStep && this.currentStep && this.currentStep.result === 'Fail';
    }

    get isDefectOpen() {
        return Boolean(this.currentStep) && this.defectOpenStepId === this.currentStep.stepId;
    }

    get hasLoggedDefect() {
        return Boolean(this.currentStep && this.currentStep.defectSeverity);
    }

    get defectToggleLabel() {
        if (this.isDefectOpen) {
            return '▴ Hide defect details';
        }
        if (this.hasLoggedDefect) {
            return `Defect logged: ${this.currentStep.defectSeverity} · Edit`;
        }
        return '▾ Log a defect';
    }

    get defectSeverityOptions() {
        return DEFECT_SEVERITIES.map((s) => ({ label: s, value: s }));
    }

    toggleDefect() {
        this.defectOpenStepId = this.isDefectOpen ? null : (this.currentStep ? this.currentStep.stepId : null);
    }

    handleDefectSeverityChange(event) {
        this.updateCurrent({ defectSeverity: event.detail.value });
        this.persistCurrentStep();
    }

    handleDefectSummaryChange(event) {
        this.updateCurrent({ defectSummary: event.target.value });
    }

    // ---- Save indicator -------------------------------------------------------------

    get showSaveIndicator() {
        return this.saveState !== 'idle';
    }

    get saveIndicatorLabel() {
        if (this.saveState === 'saving') {
            return 'Saving…';
        }
        if (this.saveState === 'error') {
            return "Couldn't save — will retry on your next change";
        }
        // A bare "Saved" over a step with notes but no verdict is the exact
        // false confirmation that shipped runs with unanswered steps: the
        // tester's prose IS saved, and the step still doesn't count.
        return this.needsResult ? 'Saved — still needs a result' : 'Saved';
    }

    /** A scripted step the tester is standing on with no verdict picked. Drives
     *  the inline cue and the save indicator's wording. */
    get needsResult() {
        return Boolean(this.isScriptedStep && !this.currentStep.result);
    }

    get saveIndicatorClass() {
        return 'ur__saveindicator' + (this.saveState === 'error' ? ' ur__saveindicator--error' : '');
    }

    get isExploreStep() {
        return this.currentStep && this.currentStep.isExplore;
    }

    get isScriptedStep() {
        return this.currentStep && !this.currentStep.isExplore;
    }

    async handleResultClick(event) {
        const value = event.currentTarget.dataset.value;
        await this.selectResult(value);
    }

    async selectResult(value) {
        this.updateCurrent({ result: value });
        if (value === 'Fail') {
            this.defectOpenStepId = this.currentStep.stepId;
        }
        await this.persistCurrentStep();
    }

    handleActualChange(event) {
        this.updateCurrent({ actualResult: event.target.value });
    }

    handleNotesChange(event) {
        this.updateCurrent({ exploreNotes: event.target.value });
    }

    updateCurrent(patch) {
        this.steps = this.steps.map((s, i) => (i === this.stepIndex ? { ...s, ...patch } : s));
    }

    async persistCurrentStep() {
        const s = this.currentStep;
        if (!s || !s.resultId) {
            return;
        }
        this.saving = true;
        this.saveState = 'saving';
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            await saveStepResult({
                inputJson: JSON.stringify({
                    resultId: s.resultId,
                    actualResult: s.actualResult,
                    result: s.result,
                    exploreNotes: s.exploreNotes,
                    defectSeverity: s.defectSeverity,
                    defectSummary: s.defectSummary
                })
            });
            this.saveState = 'saved';
        } catch (e) {
            this.saveState = 'error';
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Step evidence -------------------------------------------------------------

    get currentResultId() {
        return this.currentStep ? this.currentStep.resultId : null;
    }

    handleStepEvidenceChange(event) {
        const count = event.detail ? event.detail.count : undefined;
        if (count !== undefined) {
            this.updateCurrent({ evidenceCount: count });
        }
    }

    // ---- Run-level feedback (lives in the submit review modal) ----------------------

    get ratingButtons() {
        return RATINGS.map((value) => ({
            value,
            label: String(value),
            cssClass: 'ur__rating' + (this.uxRating === value ? ' ur__rating--selected' : '')
        }));
    }

    handleRatingClick(event) {
        this.uxRating = Number(event.currentTarget.dataset.value);
        this.queueFeedbackSave();
    }

    handleRecommendationChange(event) {
        this.uxRecommendation = event.target.value;
        this.queueFeedbackSave();
    }

    queueFeedbackSave() {
        this._feedbackPending = true;
        window.clearTimeout(this._feedbackTimer);
        this._feedbackTimer = window.setTimeout(() => this.persistFeedback(), FEEDBACK_DEBOUNCE_MS);
    }

    async persistFeedback() {
        this._feedbackPending = false;
        try {
            await saveFeedback({
                inputJson: JSON.stringify({
                    executionId: this.executionId,
                    uxRating: this.uxRating,
                    uxRecommendation: this.uxRecommendation
                })
            });
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
    }

    /* A rating picked <800ms before submit/exit must not lose the debounce
     * race — cancel the timer and persist now. */
    async flushFeedback() {
        window.clearTimeout(this._feedbackTimer);
        if (this._feedbackPending) {
            await this.persistFeedback();
        }
    }

    // ---- Navigation ----------------------------------------------------------------

    get previousDisabled() {
        return this.busy || this.stepIndex === 0;
    }

    get isLastStep() {
        return this.stepIndex >= this.steps.length - 1;
    }

    get nextLabel() {
        return this.isLastStep ? 'Review & submit' : 'Save & next step';
    }

    async handlePrevious() {
        await this.persistCurrentStep();
        if (this.stepIndex > 0) {
            this.stepIndex--;
            this.focusStepCard();
            this.scrollToTop();
        }
    }

    async handleNext() {
        await this.persistCurrentStep();
        if (this.isLastStep) {
            this.submitModalOpen = true;
            return;
        }
        this.stepIndex++;
        this.focusStepCard();
        this.scrollToTop();
    }

    /* Jump-anywhere from the step navigator: the departing step autosaves
     * first (same contract as Previous/Next). */
    async handleStepJump(event) {
        const index = event.detail.index;
        if (index === this.stepIndex || index < 0 || index >= this.steps.length) {
            return;
        }
        await this.persistCurrentStep();
        this.stepIndex = index;
        this.focusStepCard();
        this.scrollToTop();
    }

    async handleSaveExit() {
        await this.persistCurrentStep();
        await this.flushFeedback();
        try {
            await saveAndExit({ executionId: this.executionId });
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
        this.dispatchEvent(new CustomEvent('exit'));
    }

    handleBackToQueue() {
        this.handleSaveExit();
    }

    // ---- Submit review modal ---------------------------------------------------------

    closeSubmitModal() {
        this.submitModalOpen = false;
    }

    handleReviewJump(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.submitModalOpen = false;
        if (index >= 0 && index < this.steps.length) {
            this.stepIndex = index;
            this.focusStepCard();
            this.scrollToTop();
        }
    }

    get scriptedSteps() {
        return this.steps
            .map((s, index) => ({ ...s, index }))
            .filter((s) => !s.isExplore);
    }

    get unansweredSteps() {
        return this.scriptedSteps
            .filter((s) => !s.result)
            .map((s) => ({
                key: s.stepId,
                index: s.index,
                label: `Step ${s.index + 1}` + (s.condition ? ' — ' + s.condition : '')
            }));
    }

    get hasUnanswered() {
        return this.unansweredSteps.length > 0;
    }

    get unansweredTitle() {
        const n = this.unansweredSteps.length;
        return `${n} step${n === 1 ? ' has' : 's have'} no result yet`;
    }

    /** The button names what it will actually do. "Submit test case" over a run
     *  the server will store as In Progress is the claim that misled a tester
     *  into reporting a completed case as a status bug (2026-08-13). */
    get submitLabel() {
        return this.hasUnanswered ? 'Submit incomplete' : 'Submit test case';
    }

    /** "Step 3 still needs a result" / "2 steps still need a result". The
     *  no-rows fallback covers a server verdict of incomplete the client can't
     *  attribute — e.g. an admin added a step to the case mid-run, which grows
     *  the rollup's denominator (UatExecutionService.recomputeForCases). */
    get missingResultLabel() {
        const rows = this.unansweredSteps;
        if (rows.length === 0) {
            return 'some steps still need a result';
        }
        if (rows.length === 1) {
            return `Step ${rows[0].index + 1} still needs a result`;
        }
        return `${rows.length} steps still need a result`;
    }

    get needsDetailSteps() {
        return this.scriptedSteps
            .filter((s) => (s.result === 'Fail' || s.result === 'Blocked')
                && !(s.actualResult && s.actualResult.trim())
                && !(s.evidenceCount > 0))
            .map((s) => ({
                key: s.stepId,
                index: s.index,
                label: `Step ${s.index + 1} — marked ${s.result}, no notes or evidence`
            }));
    }

    get hasNeedsDetail() {
        return this.needsDetailSteps.length > 0;
    }

    get reviewSummary() {
        const scripted = this.scriptedSteps;
        const answered = scripted.filter((s) => s.result).length;
        const counts = STEP_RESULTS
            .map((value) => ({ value, count: scripted.filter((s) => s.result === value).length }))
            .filter((c) => c.count > 0)
            .map((c) => `${c.count} ${c.value}`);
        const tally = counts.length ? ' — ' + counts.join(' · ') : '';
        return `${answered} of ${scripted.length} steps answered${tally}.`;
    }

    async handleConfirmSubmit() {
        await this.flushFeedback();
        this.saving = true;
        try {
            const summary = await submitExecution({ executionId: this.executionId });
            // Keyed on what the SERVER stored, not on hasUnanswered — that is
            // the status My Queue will show, and a green "Success" over an
            // In Progress run is how a half-answered case reads as finished.
            const incomplete = summary.status !== 'Complete';
            toast(this, incomplete ? 'warning' : 'success',
                incomplete
                    ? `Submitted, but ${this.missingResultLabel} — this case stays In Progress.`
                    : `Submitted — ${summary.status}${summary.result ? ' · ' + summary.result : ''}.`,
                incomplete ? 'Submitted — incomplete' : undefined);
            this.dispatchEvent(new CustomEvent('submitted', { detail: summary }));
        } catch (e) {
            toast(this, 'error', messageFrom(e)); // modal stays open for retry
        } finally {
            this.saving = false;
        }
    }

    scrollToTop() {
        // The new step should be read from its beginning, not wherever the
        // tester had scrolled to (spec).
        window.scrollTo({ top: 0, behavior: 'auto' });
        const host = this.template.querySelector('.ur');
        if (host && typeof host.scrollIntoView === 'function') {
            host.scrollIntoView({ block: 'start' });
        }
    }

    // ---- Off-script notes ------------------------------------------------------------
    //
    // Most testing runs through scripted cases, but a tester will see things no
    // case covers. Before this they had to abandon the run to write it down,
    // which meant it went unwritten. The composer is a modal on purpose:
    // stepIndex, the current step's unsaved input, and scroll position are all
    // untouched, so "note it and carry on" is literally what happens.

    offScriptOpen = false;
    offScriptText = '';
    offScriptSaving = false;

    get offScriptDisabled() {
        return this.offScriptSaving || !this.offScriptText.trim();
    }

    handleOffScriptOpen() {
        this.offScriptText = '';
        this.offScriptOpen = true;
    }

    handleOffScriptCancel() {
        this.offScriptOpen = false;
    }

    handleOffScriptChange(event) {
        this.offScriptText = event.target.value;
    }

    async handleOffScriptSave() {
        if (!this.offScriptText.trim()) {
            return; // the disabled button is an affordance, not the rule
        }
        this.offScriptSaving = true;
        try {
            // The server finds-or-creates the tester's ad-hoc session in THIS
            // run's cycle and links the entry back to the run, so the note
            // carries its context without the client naming a session.
            await logOffScript({ inputJson: JSON.stringify({
                executionId: this.executionId,
                text: this.offScriptText
            }) });
            this.offScriptOpen = false;
            this.offScriptText = '';
            toast(this, 'success', 'Noted in your ad-hoc log — carry on.');
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.offScriptSaving = false;
        }
    }

}