import { LightningElement, api } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import getFindings from '@salesforce/apex/UatRunController.getFindings';
import saveFinding from '@salesforce/apex/UatRunController.saveFinding';
import deleteFinding from '@salesforce/apex/UatRunController.deleteFinding';
import { messageFrom, toast } from 'c/messageUtil';
import {
    DEFECT_SEVERITIES, SEVERITY_VARIANT, FINDING_TYPES, FINDING_TYPE_DEFECT,
    FINDING_TYPE_VARIANT, EVIDENCE_REQUIRED_SEVERITIES, toOptions
} from 'c/uatConstants';

const TITLE_MIN = 10;

/**
 * uatExploratoryLog — the per-cycle Exploratory Testing log: TEAM-VISIBLE,
 * author-owned (the 2026-08 session build superseded the original any-member
 * rule — the server enforces it; this UI just stops advertising it). Every
 * finding shows what was being tested / expected / happened, optional result
 * and severity badges, a session chip when it was logged inside an
 * exploratory session, evidence thumbnails, and who logged it when. Edit and
 * Delete render only on your own entries. "+ Add finding" opens the form with
 * optional result/severity and multi-file evidence upload (evidence attaches
 * after the finding is saved — Files need a record to link to). This is a
 * DELIBERATE divergence from uatSessionWorkspace's staged-evidence flow
 * (2026-08-05): the log has no session record to stage uploads against, a
 * tester's ContentDocumentLink rights on the cycle are unverified, and this
 * form is inline on the page (no clipping modal) — so save-first stays.
 */
const TYPE_OPTIONS = toOptions(FINDING_TYPES);
const SEVERITY_OPTIONS = [{ label: 'No severity', value: '' }].concat(toOptions(DEFECT_SEVERITIES));

export default class UatExploratoryLog extends LightningElement {
    @api cycleId;
    @api cycleName;

    findings = [];
    loading = true;
    saving = false;
    errorMessage;

    form = null;    // {id, whatTesting, whatExpected, whatHappened, result}
    confirm = null;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.findings = await getFindings({ cycleId: this.cycleId });
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    get busy() {
        return this.loading || this.saving;
    }

    get title() {
        return 'Exploratory Testing — ' + (this.cycleName || '');
    }

    /* Since the 2026-08-06 unification this list carries BOTH flows: findings
     * logged off-script in a session and defects raised against a scripted
     * step. Source is the only thing that separates them, which is why it is
     * the first filter. */
    sourceFilter = '';
    typeFilter = '';

    get filteredFindings() {
        return this.findings.filter((f) =>
            (!this.sourceFilter || f.source === this.sourceFilter)
            && (!this.typeFilter || f.type === this.typeFilter));
    }

    /** Counts come from the UNFILTERED set, so a chip always says how much is
     *  behind it rather than how much survived the other chip. */
    get sourceChips() {
        const count = (v) => this.findings.filter((f) => f.source === v).length;
        return [
            { value: '', label: 'All sources', count: this.findings.length },
            { value: 'Session', label: 'Ad-hoc', count: count('Session') },
            { value: 'Test case', label: 'Test case', count: count('Test case') }
        ];
    }

    get typeChips() {
        const count = (v) => this.findings.filter((f) => f.type === v).length;
        return [{ value: '', label: 'All types', count: this.findings.length }]
            .concat(FINDING_TYPES.map((t) => ({ value: t, label: t, count: count(t) })));
    }

    handleSourceFilter(event) {
        this.sourceFilter = event.detail.value;
    }

    handleTypeFilter(event) {
        this.typeFilter = event.detail.value;
    }

    get rows() {
        return this.filteredFindings.map((f) => ({
            ...f,
            headline: f.title || f.whatHappened,
            metaLine: (f.testerName || 'Unknown') + (f.dateLogged ? ' · ' + f.dateLogged : ''),
            hasType: Boolean(f.type),
            typeVariant: FINDING_TYPE_VARIANT[f.type] || 'default',
            hasSeverity: Boolean(f.severity),
            severityVariant: SEVERITY_VARIANT[f.severity] || 'default',
            // Where it came from: the session it was logged in, or the case it
            // was raised against.
            sessionChip: f.sessionId ? `${f.sessionName} · ${f.sessionTitle}` : null,
            caseChip: f.executionId ? f.caseTitle : null,
            isMine: f.testerId === USER_ID
        }));
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasAnyFindings() {
        return this.findings.length > 0;
    }

    get severityOptions() {
        return SEVERITY_OPTIONS;
    }

    get formOpen() {
        return this.form !== null;
    }

    get formTitle() {
        return this.form && this.form.id ? 'Edit finding' : 'Add finding';
    }

    get formHasId() {
        return this.form && this.form.id;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleAddOpen() {
        this.form = {
            id: null, title: '', type: FINDING_TYPE_DEFECT, whatTesting: '',
            whatExpected: '', whatHappened: '', severity: '', noEvidenceReason: ''
        };
    }

    /** Severity describes a defect and nothing else. */
    get formIsDefect() {
        return this.form && this.form.type === FINDING_TYPE_DEFECT;
    }

    get formNeedsEvidence() {
        return this.formIsDefect
            && EVIDENCE_REQUIRED_SEVERITIES.includes(this.form.severity);
    }

    get typeOptions() {
        return TYPE_OPTIONS;
    }

    handleEditOpen(event) {
        const f = this.findings.find((x) => x.id === event.currentTarget.dataset.id);
        this.form = {
            id: f.id,
            title: f.title || '',
            type: f.type || FINDING_TYPE_DEFECT,
            whatTesting: f.whatTesting || '',
            whatExpected: f.whatExpected || '',
            whatHappened: f.whatHappened || '',
            severity: f.severity || '',
            noEvidenceReason: f.noEvidenceReason || ''
        };
    }

    handleFormField(event) {
        this.form = { ...this.form, [event.currentTarget.dataset.field]: event.target.value };
    }

    handleFormType(event) {
        this.form = { ...this.form, type: event.detail.value };
    }

    handleFormSeverity(event) {
        this.form = { ...this.form, severity: event.detail.value };
    }

    handleFormCancel() {
        this.form = null;
    }

    async handleFormSave() {
        // Mirrors the server rules so the tester hears about a gap without a
        // round trip; UatRunController.saveFinding is still the authority.
        if (!this.form.title || this.form.title.trim().length < TITLE_MIN) {
            toast(this, 'error', `Give the finding a title of at least ${TITLE_MIN} characters `
                + '— it is what someone triaging sees first.');
            return;
        }
        if (!this.form.whatHappened || !this.form.whatHappened.trim()) {
            toast(this, 'error', 'Describe what happened — that field is required.');
            return;
        }
        if (this.formIsDefect && !this.form.severity) {
            toast(this, 'error', 'A defect needs a severity.');
            return;
        }
        this.saving = true;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            const savedId = await saveFinding({
                inputJson: JSON.stringify({
                    id: this.form.id,
                    cycleId: this.cycleId,
                    title: this.form.title,
                    type: this.form.type,
                    whatTesting: this.form.whatTesting,
                    whatExpected: this.form.whatExpected,
                    whatHappened: this.form.whatHappened,
                    noEvidenceReason: this.form.noEvidenceReason,
                    severity: this.form.severity
                })
            });
            const wasNew = !this.form.id;
            // Keep the form open on create so evidence can attach to the record.
            this.form = wasNew ? { ...this.form, id: savedId } : null;
            toast(this, 'success', wasNew ? 'Finding logged — add evidence below.' : 'Finding updated.');
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    handleDeleteClick(event) {
        const id = event.currentTarget.dataset.id;
        this.confirm = {
            id,
            header: 'Delete finding',
            message: 'The finding and its evidence are deleted for the whole team and '
                + 'cannot be recovered.',
            confirmLabel: 'Delete'
        };
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
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

}