import { LightningElement, api } from 'lwc';
import getSessionWorkspace from '@salesforce/apex/UatSessionController.getSessionWorkspace';
import addSessionNote from '@salesforce/apex/UatSessionController.addSessionNote';
import updateSessionNote from '@salesforce/apex/UatSessionController.updateSessionNote';
import deleteSessionNote from '@salesforce/apex/UatSessionController.deleteSessionNote';
import claimNoteFiles from '@salesforce/apex/UatSessionController.claimNoteFiles';
import finishSession from '@salesforce/apex/UatSessionController.finishSession';
import deleteSession from '@salesforce/apex/UatSessionController.deleteSession';
import saveFinding from '@salesforce/apex/UatRunController.saveFinding';
import deleteFinding from '@salesforce/apex/UatRunController.deleteFinding';
import discardStagedFiles from '@salesforce/apex/UatRunController.discardStagedFiles';
import claimStagedFiles from '@salesforce/apex/UatRunController.claimStagedFiles';
import { messageFrom, toast, logError } from 'c/messageUtil';
import {
    DEFECT_SEVERITIES, FINDING_TYPES, FINDING_TYPE_DEFECT,
    EVIDENCE_REQUIRED_SEVERITIES, SESSION_STATUS_VARIANT,
    findingViewModel, toOptions
} from 'c/uatConstants';
import { relativeTime, joinMeta, formatTime } from 'c/uatCardUtil';

const TICK_MS = 30000;
const TITLE_MIN = 10;

const TYPE_OPTIONS = toOptions(FINDING_TYPES);
const SEVERITY_OPTIONS = toOptions(DEFECT_SEVERITIES);

/**
 * uatSessionWorkspace — one ad-hoc session as a working surface.
 *
 * The page is a LOG, not a form. Its centre is a timeline of discrete entries
 * (Session_Note__c), oldest first, with a composer pinned underneath. This
 * replaced a single 32k textarea whose only route to a finding was a hidden
 * select-the-text gesture that nobody found — so findings got created empty.
 * Now every entry carries a visible "Promote to finding" action that pre-fills
 * the form from the entry's own text, timestamp, and attachments.
 *
 * Evidence attaches to an ENTRY, never to the session as a whole, so it is
 * always clear what a screenshot is evidence FOR. The composer stages uploads
 * against the session (lightning-file-upload needs a record id and the entry
 * does not exist yet) and claims them onto the entry the moment it is added —
 * the same staging dance the finding form does.
 *
 * Findings carry a TYPE (Defect / Works as expected / Suggestion / Question),
 * not a pass/fail verdict, and severity is shown only for a Defect. A High or
 * Critical defect needs a screenshot or a written reason there isn't one; that
 * is the single rule allowed to block Finish, and the server enforces it too.
 *
 * Copy carries no testing-methodology framing: "Ad-hoc session", tags rather
 * than focus prompts, no charter. The testers are business users.
 *
 * Embedded by uatTesterApp (view = 'session'); emits `exit`.
 */
export default class UatSessionWorkspace extends LightningElement {
    @api sessionId;

    session;
    notes = [];
    findings = [];
    prompts = [];
    loading = true;
    saving = false;
    errorMessage;
    viewerIsAdmin = false;

    // Composer
    draft = '';
    draftTag = '';
    composerOpen = false; // attachment tray

    // Entry editing
    editing = null;       // {id, text, tag}
    noteConfirm = null;   // delete-entry confirm

    // Finding form
    form = null;
    confirm = null;       // delete-finding confirm
    discard = null;       // staged-evidence discard confirm
    finishOpen = false;
    deleteSessionOpen = false;

    elapsedLabel = '';
    _tick = null;

    connectedCallback() {
        this.load();
        this._tick = setInterval(() => this.refreshElapsed(), TICK_MS);
    }

    disconnectedCallback() {
        clearInterval(this._tick);
    }

    /**
     * Native <textarea> has no value attribute — its value is its content, and
     * re-rendering that content would move the caret mid-typing. So the element
     * owns its value and this pushes state in only when the two have actually
     * drifted: first render, a cleared composer after Add, an edit box opening.
     */
    renderedCallback() {
        const composer = this.template.querySelector('.ues__composer-input');
        if (composer && composer.value !== this.draft) {
            composer.value = this.draft;
        }
        const editor = this.template.querySelector('.ues__entry-input');
        if (editor && this.editing && editor.value !== this.editing.text) {
            editor.value = this.editing.text;
        }
    }

    async load() {
        this.loading = true;
        try {
            const ws = await getSessionWorkspace({ sessionId: this.sessionId });
            this.session = ws.session;
            this.notes = ws.notes || [];
            this.findings = ws.findings || [];
            this.prompts = ws.prompts || [];
            this.viewerIsAdmin = ws.viewerIsAdmin === true;
            this.errorMessage = undefined;
            this.refreshElapsed();
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    async reload() {
        try {
            const ws = await getSessionWorkspace({ sessionId: this.sessionId });
            this.session = ws.session;
            this.notes = ws.notes || [];
            this.findings = ws.findings || [];
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        }
    }

    // ---- View state ---------------------------------------------------------------

    get readonly() {
        return !this.session || !this.session.isMine || this.session.status !== 'Active';
    }

    get canWork() {
        return !this.loading && this.session && !this.readonly;
    }

    get statusVariant() {
        return this.session ? (SESSION_STATUS_VARIANT[this.session.status] || 'default') : 'default';
    }

    /** Cycle · record name. The elapsed clock is deliberately NOT here — it is
     *  one line in the rail, not a countdown to perform against. */
    get headMetaLine() {
        const s = this.session;
        return s ? joinMeta([s.cycleName || 'No cycle', s.name]) : '';
    }

    refreshElapsed() {
        const s = this.session;
        if (!s || !s.startedAt) {
            this.elapsedLabel = '';
            return;
        }
        const end = s.finishedAt ? new Date(s.finishedAt).getTime() : Date.now();
        const mins = Math.max(0, Math.floor((end - new Date(s.startedAt).getTime()) / 60000));
        if (mins < 1) {
            this.elapsedLabel = 'under a minute';
        } else if (mins < 60) {
            this.elapsedLabel = `${mins} minute${mins === 1 ? '' : 's'}`;
        } else {
            const h = Math.floor(mins / 60);
            const m = mins % 60;
            this.elapsedLabel = m ? `${h}h ${m}m` : `${h}h`;
        }
    }

    get overviewRows() {
        if (!this.session) {
            return [];
        }
        const s = this.session;
        return [
            { key: 'looking', label: 'Looking at', value: s.areaText },
            { key: 'cycle', label: 'Cycle', value: s.cycleName || 'No cycle' },
            { key: 'started', label: 'Started', value: s.startedAt ? relativeTime(s.startedAt) : null },
            { key: 'elapsed', label: 'Elapsed', value: this.elapsedLabel },
            { key: 'findings', label: 'Findings', value: `${this.findings.length}` }
        ].filter((r) => r.value);
    }

    // ---- The log ---------------------------------------------------------------------

    get tagChips() {
        return this.prompts.map((p, i) => ({
            value: p.label,
            label: p.label,
            cssClass: 'ues__tag' + (this.draftTag === p.label ? ' ues__tag--on' : ''),
            key: `t${i}`
        }));
    }

    get hasTags() {
        return this.prompts.length > 0;
    }

    get noteRows() {
        return this.notes.map((n) => ({
            ...n,
            timeLabel: n.loggedAt ? formatTime(n.loggedAt) : '',
            relLabel: n.loggedAt ? relativeTime(n.loggedAt) : '',
            hasTag: Boolean(n.tag),
            hasFiles: Boolean(n.files && n.files.length),
            fromRun: Boolean(n.executionId),
            // One promotion per entry: once it has a finding the row shows the
            // badge instead of offering Promote again.
            isPromoted: Boolean(n.findingId),
            canPromote: this.canWork && !n.findingId,
            canEdit: this.canWork && (n.isMine || this.viewerIsAdmin),
            isEditing: Boolean(this.editing && this.editing.id === n.id)
        }));
    }

    get hasNotes() {
        return this.notes.length > 0;
    }

    handleDraftChange(event) {
        this.draft = event.target.value;
    }

    handleTagPick(event) {
        // Second click clears it — tagging is optional and must stay escapable.
        const picked = event.currentTarget.dataset.value;
        this.draftTag = this.draftTag === picked ? '' : picked;
    }

    /** Enter adds; Shift+Enter is a newline. */
    handleDraftKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleAddNote();
        }
    }

    get composerUploader() {
        return this.template.querySelector('.ues__composer-evidence');
    }

    get draftStagedDocIds() {
        const uploader = this.composerUploader;
        return uploader ? uploader.stagedDocumentIds : [];
    }

    get addDisabled() {
        return this.saving || !this.draft.trim();
    }

    /** The upload tray stays mounted once opened — unmounting it would throw
     *  away the staged doc ids the entry is about to claim. */
    get composerEvidenceClass() {
        return 'ues__composer-tray'
            + (this.composerOpen ? '' : ' ues__composer-tray--hidden');
    }

    handleToggleAttach() {
        this.composerOpen = !this.composerOpen;
    }

    async handleAddNote() {
        if (!this.draft.trim()) {
            return;
        }
        this.saving = true;
        try {
            const staged = this.draftStagedDocIds;
            const note = await addSessionNote({ inputJson: JSON.stringify({
                sessionId: this.sessionId,
                text: this.draft,
                tag: this.draftTag
            }) });
            if (staged.length) {
                // Files were staged on the session because the entry did not
                // exist yet; move them onto it now that it does.
                try {
                    await claimNoteFiles({ noteId: note.id, contentDocumentIds: staged });
                } catch (e) {
                    // The entry is saved either way — never lose the words over
                    // an attachment.
                    toast(this, 'error', messageFrom(e));
                }
            }
            this.draft = '';
            this.draftTag = '';
            this.composerOpen = false;
            await this.reload();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleEditNote(event) {
        const note = this.notes.find((n) => n.id === event.currentTarget.dataset.id);
        this.editing = { id: note.id, text: note.text, tag: note.tag || '' };
    }

    handleEditChange(event) {
        this.editing = { ...this.editing, text: event.target.value };
    }

    handleEditCancel() {
        this.editing = null;
    }

    async handleEditSave() {
        if (!this.editing.text.trim()) {
            toast(this, 'error', 'An entry cannot be empty — delete it instead.');
            return;
        }
        this.saving = true;
        try {
            await updateSessionNote({ inputJson: JSON.stringify({
                id: this.editing.id, text: this.editing.text, tag: this.editing.tag
            }) });
            this.editing = null;
            await this.reload();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleDeleteNoteClick(event) {
        this.noteConfirm = { id: event.currentTarget.dataset.id };
    }

    get noteConfirmOpen() {
        return this.noteConfirm !== null;
    }

    handleNoteConfirmCancel() {
        this.noteConfirm = null;
    }

    async handleNoteConfirmProceed() {
        this.saving = true;
        try {
            await deleteSessionNote({ noteId: this.noteConfirm.id });
            this.noteConfirm = null;
            await this.reload();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    async handleNoteFilesChange() {
        // An entry's attachment count changed — refresh so the strip matches.
        await this.reload();
    }

    // ---- Findings ---------------------------------------------------------------------

    get typeOptions() {
        return TYPE_OPTIONS;
    }

    get severityOptions() {
        return SEVERITY_OPTIONS;
    }

    /** The shape c-uat-finding-detail renders, plus this surface's own
     *  permission flag. Shared with the Cycle Report's viewer via
     *  findingViewModel so the two cannot describe a finding differently. */
    get findingRows() {
        return this.findings.map((f) => ({
            ...findingViewModel(f),
            canEdit: this.canWork
        }));
    }

    get hasFindings() {
        return this.findings.length > 0;
    }

    get formOpen() {
        return this.form !== null;
    }

    get formTitle() {
        return this.form && this.form.id ? 'Edit finding' : 'Add finding';
    }

    /** Severity is a property of a defect. For the other three types the field
     *  is hidden and the server clears whatever was there. */
    get formIsDefect() {
        return this.form && this.form.type === FINDING_TYPE_DEFECT;
    }

    /** The "why no evidence" box appears only when it is actually the thing
     *  standing between the tester and saving. */
    get formNeedsEvidence() {
        return this.formIsDefect
            && EVIDENCE_REQUIRED_SEVERITIES.includes(this.form.severity);
    }

    get formEvidenceHint() {
        return `A ${(this.form.severity || '').toLowerCase()} defect needs a screenshot `
            + 'or a note saying why there isn\'t one.';
    }

    blankForm(over = {}) {
        return {
            id: null, title: '', type: FINDING_TYPE_DEFECT, whatTesting: '',
            whatExpected: '', whatHappened: '', severity: '', noEvidenceReason: '',
            sourceNoteId: null, ...over
        };
    }

    handleAddOpen() {
        this.form = this.blankForm();
    }

    /**
     * The replacement for the select-text gesture: an explicit row action that
     * carries the entry's own words, moment, and attachments into the finding.
     * The title is a suggestion from the first line — editable, because the
     * first line of a note is rarely a good headline.
     */
    handlePromote(event) {
        const note = this.notes.find((n) => n.id === event.currentTarget.dataset.id);
        this.form = this.blankForm({
            title: suggestTitle(note.text),
            whatHappened: note.text,
            sourceNoteId: note.id
        });
    }

    handleFormField(event) {
        this.form = { ...this.form, [event.currentTarget.dataset.field]: event.target.value };
    }

    handleFormPick(event) {
        this.form = { ...this.form, [event.currentTarget.dataset.field]: event.detail.value };
    }

    get stagedDocIds() {
        // Scoped to the form: the composer holds a second uploader against the
        // same session record, and an unscoped query would claim its files.
        const uploader = this.template.querySelector('.ues__form c-uat-evidence-upload');
        return uploader ? uploader.stagedDocumentIds : [];
    }

    handleFormCancel() {
        const staged = this.form && !this.form.id ? this.stagedDocIds : [];
        if (staged.length) {
            this.discard = { docIds: staged };
            return;
        }
        this.form = null;
    }

    get discardOpen() {
        return this.discard !== null;
    }

    get discardMessage() {
        const n = this.discard ? this.discard.docIds.length : 0;
        return `The ${n} uploaded file${n === 1 ? '' : 's'} will be deleted and cannot be recovered.`;
    }

    handleDiscardCancel() {
        this.discard = null;
    }

    async handleDiscardConfirm() {
        this.saving = true;
        try {
            await discardStagedFiles({
                sessionId: this.sessionId,
                contentDocumentIds: this.discard.docIds
            });
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
            this.discard = null;
            this.form = null;
        }
    }

    /** Client-side mirror of the server rules, so the tester is told what is
     *  missing before a round trip. The server is still the authority. */
    formError() {
        const f = this.form;
        if (!f.title || f.title.trim().length < TITLE_MIN) {
            return `Give the finding a title of at least ${TITLE_MIN} characters — `
                + 'it is what someone triaging sees first.';
        }
        if (!f.whatHappened || !f.whatHappened.trim()) {
            return 'Describe what happened — that field is required.';
        }
        if (f.type === FINDING_TYPE_DEFECT && !f.severity) {
            return 'A defect needs a severity.';
        }
        return null;
    }

    async handleFormSave() {
        const problem = this.formError();
        if (problem) {
            toast(this, 'error', problem);
            return;
        }
        this.saving = true;
        try {
            const staged = this.stagedDocIds;
            const savedId = await saveFinding({ inputJson: JSON.stringify({
                id: this.form.id,
                sessionId: this.form.id ? null : this.sessionId,
                sourceNoteId: this.form.id ? null : this.form.sourceNoteId,
                title: this.form.title,
                type: this.form.type,
                whatTesting: this.form.whatTesting,
                whatExpected: this.form.whatExpected,
                whatHappened: this.form.whatHappened,
                severity: this.form.severity,
                noEvidenceReason: this.form.noEvidenceReason,
                stagedDocumentIds: staged
            }) });
            const wasNew = !this.form.id;
            // A failed claim used to raise an error toast that the unconditional
            // "Finding logged." then immediately contradicted — so a finding
            // saved WITHOUT the evidence just attached and the tester was told
            // it went fine. The outcome now names what is missing and what to
            // do, because the evidence is the finding's whole value.
            let evidenceFailed = false;
            if (wasNew && staged.length) {
                try {
                    await claimStagedFiles({ findingId: savedId, contentDocumentIds: staged });
                } catch (e) {
                    evidenceFailed = true;
                    logError('uatSessionWorkspace', 'claimStagedFiles', e);
                }
            }
            this.form = null;
            if (evidenceFailed) {
                const n = staged.length;
                toast(this, 'warning',
                    `Finding logged, but ${n === 1 ? 'its file' : `its ${n} files`} did not attach `
                        + '— open the finding and upload again.',
                    'Evidence not attached');
            } else {
                toast(this, 'success', wasNew ? 'Finding logged.' : 'Finding updated.');
            }
            await this.reload();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    /* Both arrive from c-uat-finding-detail now, so the id is on the event
     * detail rather than a data attribute. */
    handleEditFinding(event) {
        const f = this.findings.find((x) => x.id === event.detail.id);
        this.form = {
            id: f.id,
            title: f.title || '',
            type: f.type || FINDING_TYPE_DEFECT,
            whatTesting: f.whatTesting || '',
            whatExpected: f.whatExpected || '',
            whatHappened: f.whatHappened || '',
            severity: f.severity || '',
            noEvidenceReason: f.noEvidenceReason || '',
            sourceNoteId: f.sourceNoteId || null
        };
    }

    handleDeleteClick(event) {
        this.confirm = { id: event.detail.id };
    }

    get confirmOpen() {
        return this.confirm !== null;
    }

    handleConfirmCancel() {
        this.confirm = null;
    }

    async handleConfirmProceed() {
        this.saving = true;
        try {
            await deleteFinding({ findingId: this.confirm.id });
            this.confirm = null;
            toast(this, 'success', 'Finding deleted.');
            await this.reload();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Before finishing ----------------------------------------------------------

    /** Severe defects with neither evidence nor a stated reason. This is the
     *  ONE item that blocks — the server throws on it too. */
    get blockingFindings() {
        return this.findings.filter((f) =>
            f.type === FINDING_TYPE_DEFECT
            && EVIDENCE_REQUIRED_SEVERITIES.includes(f.severity)
            && !(f.files && f.files.length)
            && !(f.noEvidenceReason && f.noEvidenceReason.trim()));
    }

    get checklistRows() {
        const logged = this.notes.length > 0 || this.findings.length > 0;
        const defects = this.findings.filter((f) => f.type === FINDING_TYPE_DEFECT);
        const described = defects.filter((f) =>
            f.title && f.title.trim().length >= TITLE_MIN
            && f.whatHappened && f.whatHappened.trim());
        const blocking = this.blockingFindings.length;
        const rows = [
            {
                key: 'logged',
                done: logged,
                label: logged ? 'Something recorded' : 'Log a note or a finding'
            }
        ];
        if (defects.length) {
            rows.push({
                key: 'described',
                done: described.length === defects.length,
                label: described.length === defects.length
                    ? 'Every defect has a title and description'
                    : `${defects.length - described.length} defect(s) need a title or description`
            });
            rows.push({
                key: 'evidence',
                done: blocking === 0,
                blocking: blocking > 0,
                label: blocking === 0
                    ? 'Severe defects have evidence'
                    : `${blocking} severe defect(s) need a screenshot or a reason`
            });
        }
        return rows.map((r) => ({
            ...r,
            mark: r.done ? '✓' : (r.blocking ? '!' : '○'),
            itemClass: 'ues__check'
                + (r.done ? ' ues__check--done' : '')
                + (r.blocking ? ' ues__check--blocking' : '')
        }));
    }

    get finishDisabled() {
        return this.saving || this.blockingFindings.length > 0;
    }

    get finishBlockedLabel() {
        const n = this.blockingFindings.length;
        return n
            ? `${n} severe defect${n === 1 ? '' : 's'} still need${n === 1 ? 's' : ''} `
                + 'a screenshot or a reason'
            : '';
    }

    handleFinishClick() {
        this.finishOpen = true;
    }

    handleFinishCancel() {
        this.finishOpen = false;
    }

    get finishMessage() {
        const n = this.findings.length;
        return `The session becomes read-only. ${n} finding${n === 1 ? '' : 's'} `
            + `${n === 1 ? 'stays' : 'stay'} in the findings list.`;
    }

    async handleFinishConfirm() {
        this.saving = true;
        try {
            await finishSession({ inputJson: JSON.stringify({ sessionId: this.sessionId }) });
            this.finishOpen = false;
            toast(this, 'success', 'Session finished.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Session actions -------------------------------------------------------------

    get canDelete() {
        const s = this.session;
        return Boolean(s && ((s.isMine && s.status === 'Active') || this.viewerIsAdmin));
    }

    get isStandalone() {
        return Boolean(this.session && !this.session.cycleId);
    }

    get deleteSessionMessage() {
        return this.isStandalone
            ? 'The session, its log, and its findings are deleted — a session with no cycle has no findings list to keep them.'
            : 'The session and its log are deleted. Findings already logged stay in the cycle findings list.';
    }

    handleDeleteSessionClick() {
        this.deleteSessionOpen = true;
    }

    handleDeleteSessionCancel() {
        this.deleteSessionOpen = false;
    }

    async handleDeleteSessionConfirm() {
        this.saving = true;
        try {
            await deleteSession({ sessionId: this.sessionId });
            this.deleteSessionOpen = false;
            toast(this, 'success', 'Session deleted.');
            this.dispatchEvent(new CustomEvent('exit'));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleExit() {
        this.dispatchEvent(new CustomEvent('exit'));
    }
}

/** First line of an entry, capped — a starting point for the finding's title,
 *  never the final word. */
function suggestTitle(text) {
    if (!text) {
        return '';
    }
    const line = text.split('\n').find((l) => l.trim());
    if (!line) {
        return '';
    }
    const trimmed = line.trim();
    return trimmed.length > 255 ? trimmed.slice(0, 255) : trimmed;
}