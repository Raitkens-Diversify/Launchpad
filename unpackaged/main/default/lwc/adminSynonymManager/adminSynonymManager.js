import { LightningElement } from 'lwc';
import getSynonyms from '@salesforce/apex/SynonymAdminController.getSynonyms';
import saveSynonym from '@salesforce/apex/SynonymAdminController.saveSynonym';
import setSynonymActive from '@salesforce/apex/SynonymAdminController.setSynonymActive';
import { messageFrom, toast } from 'c/messageUtil';

/**
 * adminSynonymManager — Search_Synonym__mdt editor for the Admin Console.
 *
 * Writes are Metadata API deploys (async). There is no draft record to poll
 * (unlike guide publish), so after a save this polls getSynonyms() until the
 * change is visible, then stops. If the deploy hasn't landed within the window,
 * the admin is pointed at Setup → Deployment Status.
 */
const POLL_MS = 3000;
const POLL_MAX = 20;

export default class AdminSynonymManager extends LightningElement {
    rows = [];
    loading = true;
    deploying = false;
    errorMessage;

    // Modal state
    modalOpen = false;
    editingDeveloperName = null;
    formTerm = '';
    formSynonyms = '';
    formBidirectional = true;

    _pollTimer;

    connectedCallback() {
        this.load();
    }

    disconnectedCallback() {
        window.clearTimeout(this._pollTimer);
    }

    async load() {
        this.loading = true;
        try {
            const data = await getSynonyms();
            this.rows = (data || []).map((r) => this.decorate(r));
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    decorate(row) {
        return {
            ...row,
            statusLabel: row.active ? 'Active' : 'Inactive',
            statusClass: row.active ? 'asm-badge asm-badge--on' : 'asm-badge asm-badge--off',
            directionLabel: row.bidirectional ? 'Both ways' : 'Term → synonyms',
            toggleLabel: row.active ? 'Deactivate' : 'Restore'
        };
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get busy() {
        return this.loading || this.deploying;
    }

    get modalTitle() {
        return this.editingDeveloperName ? 'Edit synonym group' : 'New synonym group';
    }

    // ---- Modal -------------------------------------------------------------------

    handleNew() {
        this.editingDeveloperName = null;
        this.formTerm = '';
        this.formSynonyms = '';
        this.formBidirectional = true;
        this.modalOpen = true;
    }

    handleEdit(event) {
        const row = this.rows.find(
            (r) => r.developerName === event.currentTarget.dataset.name
        );
        if (!row) {
            return;
        }
        this.editingDeveloperName = row.developerName;
        this.formTerm = row.term;
        this.formSynonyms = row.synonyms;
        this.formBidirectional = row.bidirectional;
        this.modalOpen = true;
    }

    handleModalCancel() {
        this.modalOpen = false;
    }

    handleTermChange(event) {
        this.formTerm = event.target.value;
    }
    handleSynonymsChange(event) {
        this.formSynonyms = event.target.value;
    }
    handleBidirectionalChange(event) {
        this.formBidirectional = event.target.checked;
    }

    // ---- Writes ------------------------------------------------------------------

    async handleModalSave() {
        if (!this.formTerm || !this.formTerm.trim()) {
            toast(this, 'error', 'Term is required.');
            return;
        }
        if (!this.formSynonyms || !this.formSynonyms.trim()) {
            toast(this, 'error', 'At least one synonym is required.');
            return;
        }
        this.modalOpen = false;
        this.deploying = true;
        const expected = {
            term: this.formTerm.trim().toLowerCase(),
            synonyms: this.formSynonyms.trim().toLowerCase(),
            active: true
        };
        try {
            const devName = await saveSynonym({
                developerName: this.editingDeveloperName,
                term: this.formTerm,
                synonyms: this.formSynonyms,
                bidirectional: this.formBidirectional
            });
            this.pollUntilVisible(devName, expected, POLL_MAX);
        } catch (e) {
            this.deploying = false;
            toast(this, 'error', messageFrom(e));
        }
    }

    async handleToggleActive(event) {
        const row = this.rows.find(
            (r) => r.developerName === event.currentTarget.dataset.name
        );
        if (!row) {
            return;
        }
        this.deploying = true;
        const expected = {
            term: row.term,
            synonyms: row.synonyms,
            active: !row.active
        };
        try {
            await setSynonymActive({
                developerName: row.developerName,
                active: !row.active
            });
            this.pollUntilVisible(row.developerName, expected, POLL_MAX);
        } catch (e) {
            this.deploying = false;
            toast(this, 'error', messageFrom(e));
        }
    }

    // ---- Deploy polling -------------------------------------------------------------

    pollUntilVisible(devName, expected, attemptsLeft) {
        this._pollTimer = window.setTimeout(async () => {
            let visible = false;
            try {
                const data = await getSynonyms();
                const rows = data || [];
                const match = rows.find((r) => r.developerName === devName);
                visible =
                    !!match &&
                    match.term === expected.term &&
                    match.synonyms === expected.synonyms &&
                    match.active === expected.active;
                if (visible) {
                    this.rows = rows.map((r) => this.decorate(r));
                }
            } catch (e) {
                // keep polling; transient errors shouldn't abort the wait
            }
            if (visible) {
                this.deploying = false;
                toast(this, 'success', 'Synonym deployed. Search picks it up immediately.');
            } else if (attemptsLeft > 1) {
                this.pollUntilVisible(devName, expected, attemptsLeft - 1);
            } else {
                this.deploying = false;
                toast(this, 
                    'warning',
                    'The deploy is taking longer than expected — check Setup → Deployment Status, then refresh this list.'
                );
                this.load();
            }
        }, POLL_MS);
    }

    handleRefresh() {
        this.load();
    }

    // ---- Utils --------------------------------------------------------------------

}