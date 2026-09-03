import { LightningElement, track } from 'lwc';
import getDraftTours from '@salesforce/apex/TutorialAdminController.getDraftTours';
import getDraftTour from '@salesforce/apex/TutorialAdminController.getDraftTour';
import saveDraftTour from '@salesforce/apex/TutorialAdminController.saveDraftTour';
import deleteDraftTour from '@salesforce/apex/TutorialAdminController.deleteDraftTour';
import saveDraftStep from '@salesforce/apex/TutorialAdminController.saveDraftStep';
import deleteDraftStep from '@salesforce/apex/TutorialAdminController.deleteDraftStep';
import reorderSteps from '@salesforce/apex/TutorialAdminController.reorderSteps';
import publish from '@salesforce/apex/TutorialAdminController.publish';

const PUBLISH_POLL_MS = 2000;
const PUBLISH_POLL_MAX = 15; // ~30s
const STAGE_TILES = 4;

/**
 * Tour Builder admin app (Lightning App Page). Lists draft tours, edits tours
 * and steps, reorders via drag-and-drop (with keyboard fallbacks), previews
 * the draft with the real runtime overlay against a sample stage, and
 * publishes to custom metadata (async — polls the draft for the outcome).
 *
 * Errors surface as inline banners (nexs convention — no toasts).
 */
export default class TourBuilder extends LightningElement {
    @track tours = [];
    @track tour = null; // selected tour detail incl. steps
    selectedStep = null;

    loadingTours = false;
    saving = false;
    errorMessage = '';
    successMessage = '';

    // Tour form fields
    formLabel = '';
    formKey = '';
    formVersion = 1;
    formActive = true;
    formAutoStart = true;
    _formTourId = null;
    _confirmingTourDelete = false;

    // Drag state (index-based; dataTransfer payloads are unreliable under LWS)
    _dragIndex = null;
    dropIndex = null;

    // Preview state
    previewing = false;
    previewActive = false;
    previewIndex = 0;
    previewTarget = null;

    // Publish polling
    publishing = false;
    _pollTimer = null;
    _pollCount = 0;

    connectedCallback() {
        this._loadTours();
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // ---- data loading ---------------------------------------------------------

    async _loadTours() {
        this.loadingTours = true;
        try {
            this.tours = await getDraftTours();
        } catch (e) {
            this._fail('Could not load tours', e);
        } finally {
            this.loadingTours = false;
        }
    }

    async _loadTour(tourId) {
        try {
            this.tour = await getDraftTour({ tourId });
            this._formTourId = this.tour.recordId;
            this.formLabel = this.tour.label;
            this.formKey = this.tour.tourKey;
            this.formVersion = this.tour.version;
            this.formActive = this.tour.active;
            this.formAutoStart = this.tour.autoStart;
            this._confirmingTourDelete = false;
        } catch (e) {
            this._fail('Could not load tour', e);
        }
    }

    // ---- template state ---------------------------------------------------------

    get tourRows() {
        return this.tours.map((t) => ({
            ...t,
            className:
                this.tour && this.tour.recordId === t.recordId
                    ? 'tb__tour tb__tour--selected'
                    : 'tb__tour',
            statusLabel: t.published ? 'Published' : 'Draft',
            statusClass: t.published ? 'tb__status tb__status--published' : 'tb__status',
            lastPublishedLabel: t.lastPublished
                ? `Last published ${new Date(t.lastPublished).toLocaleString()}`
                : ''
        }));
    }

    get showEmptyTours() {
        return !this.loadingTours && this.tours.length === 0;
    }

    get hasSelectedTour() {
        return Boolean(this.tour);
    }

    get showTourForm() {
        return Boolean(this.tour) || this._formTourId === null;
    }

    get showWelcome() {
        return !this.tour && this._formTourId !== null;
    }

    get tourFormTitle() {
        return this.tour ? 'Tour settings' : 'New tour';
    }

    get keyLocked() {
        return Boolean(this.tour && this.tour.lastPublished);
    }

    get deleteTourLabel() {
        return this._confirmingTourDelete ? 'Confirm delete' : 'Delete tour';
    }

    get stepRows() {
        if (!this.tour || !this.tour.steps) {
            return [];
        }
        const last = this.tour.steps.length - 1;
        return this.tour.steps.map((s, i) => ({
            ...s,
            className: i === this.dropIndex ? 'tb__step tb__step--drop' : 'tb__step',
            isFirst: i === 0,
            isLast: i === last
        }));
    }

    get hasSteps() {
        return Boolean(this.tour && this.tour.steps && this.tour.steps.length);
    }

    get showEmptySteps() {
        return Boolean(this.tour) && !this.hasSteps;
    }

    get stepEditorTitle() {
        return this.selectedStep && this.selectedStep.recordId ? 'Edit step' : 'New step';
    }

    get previewDisabled() {
        return !this.hasSteps;
    }

    get publishDisabled() {
        return !this.hasSteps || this.publishing || this.saving;
    }

    get publishLabel() {
        return this.publishing ? 'Publishing…' : 'Publish';
    }

    get publishStatusLabel() {
        if (this.publishing) {
            return 'Publishing — deploying custom metadata…';
        }
        if (this.tour && this.tour.publishError) {
            return `Last publish failed: ${this.tour.publishError}`;
        }
        if (this.tour && this.tour.published && this.tour.lastPublished) {
            return `Published v${this.tour.version} — ${new Date(this.tour.lastPublished).toLocaleString()}`;
        }
        if (this.tour && this.tour.lastPublished) {
            return 'Draft has unpublished changes.';
        }
        return '';
    }

    get publishStatusClass() {
        if (this.tour && this.tour.publishError && !this.publishing) {
            return 'tb__publish-status tb__publish-status--error';
        }
        if (this.tour && this.tour.published && !this.publishing) {
            return 'tb__publish-status tb__publish-status--ok';
        }
        return 'tb__publish-status';
    }

    // ---- tour actions -------------------------------------------------------------

    handleSelectTour(event) {
        this._clearBanners();
        this._stopPolling();
        this.selectedStep = null;
        this._loadTour(event.currentTarget.dataset.id);
    }

    handleNewTour() {
        this._clearBanners();
        this._stopPolling();
        this.tour = null;
        this.selectedStep = null;
        this._formTourId = null;
        this.formLabel = '';
        this.formKey = '';
        this.formVersion = 1;
        this.formActive = true;
        this.formAutoStart = true;
    }

    handleFormLabel(event) {
        this.formLabel = event.detail.value;
    }

    handleFormKey(event) {
        this.formKey = event.detail.value;
    }

    handleFormVersion(event) {
        this.formVersion = event.detail.value;
    }

    handleFormActive(event) {
        this.formActive = event.detail.checked;
    }

    handleFormAutoStart(event) {
        this.formAutoStart = event.detail.checked;
    }

    async handleSaveTour() {
        this._clearBanners();
        this.saving = true;
        try {
            const tourId = await saveDraftTour({
                recordId: this.tour ? this.tour.recordId : null,
                tourKey: this.formKey,
                label: this.formLabel,
                active: this.formActive,
                autoStart: this.formAutoStart,
                version: Number(this.formVersion) || 1
            });
            this.successMessage = 'Tour saved.';
            await this._loadTours();
            await this._loadTour(tourId);
        } catch (e) {
            this._fail('Could not save tour', e);
        } finally {
            this.saving = false;
        }
    }

    async handleDeleteTour() {
        if (!this._confirmingTourDelete) {
            this._confirmingTourDelete = true;
            return;
        }
        this._clearBanners();
        try {
            await deleteDraftTour({ tourId: this.tour.recordId });
            this.successMessage = 'Tour deleted. (Already-published metadata stays until deactivated and republished.)';
            this.handleNewTour();
            await this._loadTours();
        } catch (e) {
            this._fail('Could not delete tour', e);
        }
    }

    // ---- step actions ---------------------------------------------------------------

    handleSelectStep(event) {
        this._clearBanners();
        const id = event.currentTarget.dataset.id;
        this.selectedStep = this.tour.steps.find((s) => s.recordId === id) || null;
    }

    handleAddStep() {
        this._clearBanners();
        this.selectedStep = {
            recordId: null,
            stepOrder: null,
            title: '',
            targetSelector: '',
            body: '',
            placement: 'auto',
            advanceOn: 'button'
        };
    }

    async handleStepSave(event) {
        this._clearBanners();
        this.saving = true;
        const step = event.detail.step;
        try {
            await saveDraftStep({
                recordId: step.recordId,
                tourId: this.tour.recordId,
                stepOrder: step.stepOrder,
                targetSelector: step.targetSelector,
                title: step.title,
                body: step.body,
                placement: step.placement,
                advanceOn: step.advanceOn
            });
            this.successMessage = 'Step saved.';
            this.selectedStep = null;
            await this._loadTour(this.tour.recordId);
            await this._loadTours();
        } catch (e) {
            this._fail('Could not save step', e);
        } finally {
            this.saving = false;
        }
    }

    async handleStepDelete(event) {
        this._clearBanners();
        try {
            await deleteDraftStep({ stepId: event.detail.recordId });
            this.successMessage = 'Step deleted.';
            this.selectedStep = null;
            await this._loadTour(this.tour.recordId);
        } catch (e) {
            this._fail('Could not delete step', e);
        }
    }

    // ---- reorder: drag-and-drop + keyboard fallback -----------------------------------

    handleDragStart(event) {
        this._dragIndex = Number(event.currentTarget.dataset.index);
        // Some browsers need data set for a drag to start; the payload is unused.
        if (event.dataTransfer) {
            event.dataTransfer.effectAllowed = 'move';
            try {
                event.dataTransfer.setData('text/plain', String(this._dragIndex));
            } catch (e) {
                /* LWS may block setData — index state carries the payload */
            }
        }
    }

    handleDragOver(event) {
        event.preventDefault();
        this.dropIndex = Number(event.currentTarget.dataset.index);
    }

    handleDragLeave() {
        this.dropIndex = null;
    }

    handleDrop(event) {
        event.preventDefault();
        const from = this._dragIndex;
        const to = Number(event.currentTarget.dataset.index);
        this.dropIndex = null;
        this._dragIndex = null;
        if (from === null || from === to) {
            return;
        }
        const ids = this.tour.steps.map((s) => s.recordId);
        const [moved] = ids.splice(from, 1);
        ids.splice(to, 0, moved);
        this._applyOrder(ids);
    }

    handleDragEnd() {
        this.dropIndex = null;
        this._dragIndex = null;
    }

    handleMoveUp(event) {
        const i = Number(event.currentTarget.dataset.index);
        if (i <= 0) {
            return;
        }
        const ids = this.tour.steps.map((s) => s.recordId);
        [ids[i - 1], ids[i]] = [ids[i], ids[i - 1]];
        this._applyOrder(ids);
    }

    handleMoveDown(event) {
        const i = Number(event.currentTarget.dataset.index);
        const ids = this.tour.steps.map((s) => s.recordId);
        if (i >= ids.length - 1) {
            return;
        }
        [ids[i], ids[i + 1]] = [ids[i + 1], ids[i]];
        this._applyOrder(ids);
    }

    async _applyOrder(orderedIds) {
        this._clearBanners();
        // Optimistic local reorder, rolled back by reload on failure.
        const byId = new Map(this.tour.steps.map((s) => [s.recordId, s]));
        this.tour = {
            ...this.tour,
            steps: orderedIds.map((id, i) => ({ ...byId.get(id), stepOrder: i + 1 }))
        };
        try {
            await reorderSteps({ tourId: this.tour.recordId, orderedStepIds: orderedIds });
        } catch (e) {
            this._fail('Could not reorder steps', e);
            await this._loadTour(this.tour.recordId);
        }
    }

    // ---- preview ------------------------------------------------------------------------

    handlePreview() {
        this._clearBanners();
        this.previewIndex = 0;
        this.previewing = true;
        this._setPreviewTarget();
        requestAnimationFrame(() => {
            this.previewActive = true;
        });
    }

    handlePreviewNext() {
        if (this.previewIndex >= this.previewCount - 1) {
            this.handlePreviewExit();
            return;
        }
        this.previewIndex++;
        this._setPreviewTarget();
    }

    handlePreviewBack() {
        if (this.previewIndex > 0) {
            this.previewIndex--;
            this._setPreviewTarget();
        }
    }

    handlePreviewExit() {
        this.previewActive = false;
        setTimeout(() => {
            this.previewing = false;
            this.previewTarget = null;
        }, 220);
    }

    _setPreviewTarget() {
        // Draft steps map round-robin onto the sample tiles — resolved from the
        // builder's OWN template, so the preview never touches the host page.
        this.previewTarget = this.template.querySelector(
            `[data-preview-index="${this.previewIndex % STAGE_TILES}"]`
        );
    }

    get previewStep() {
        return this.tour && this.tour.steps ? this.tour.steps[this.previewIndex] : null;
    }

    get previewTitle() {
        return this.previewStep ? this.previewStep.title : '';
    }

    get previewBody() {
        return this.previewStep ? this.previewStep.body : '';
    }

    get previewPlacement() {
        return this.previewStep ? this.previewStep.placement : 'auto';
    }

    get previewAdvanceOn() {
        return this.previewStep ? this.previewStep.advanceOn : 'button';
    }

    get previewCount() {
        return this.tour && this.tour.steps ? this.tour.steps.length : 0;
    }

    // ---- publish ---------------------------------------------------------------------------

    async handlePublish() {
        this._clearBanners();
        this.publishing = true;
        try {
            await publish({ tourId: this.tour.recordId });
            this._pollCount = 0;
            this._pollTimer = setInterval(() => this._pollPublish(), PUBLISH_POLL_MS);
        } catch (e) {
            this.publishing = false;
            this._fail('Could not start publish', e);
        }
    }

    async _pollPublish() {
        this._pollCount++;
        try {
            const fresh = await getDraftTour({ tourId: this.tour.recordId });
            if (fresh.published || fresh.publishError) {
                this._stopPolling();
                this.tour = fresh;
                if (fresh.published) {
                    this.successMessage = `Published "${fresh.label}" v${fresh.version}.`;
                } else {
                    this.errorMessage = `Publish failed: ${fresh.publishError}`;
                }
                await this._loadTours();
                return;
            }
        } catch (e) {
            this._stopPolling();
            this._fail('Lost track of the publish — reload to check its status', e);
            return;
        }
        if (this._pollCount >= PUBLISH_POLL_MAX) {
            this._stopPolling();
            this.errorMessage =
                'The publish is still running — check back in a minute (the status updates when the deploy finishes).';
        }
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
        this.publishing = false;
    }

    // ---- helpers ---------------------------------------------------------------------------

    _clearBanners() {
        this.errorMessage = '';
        this.successMessage = '';
        this._confirmingTourDelete = false;
    }

    _fail(prefix, e) {
        const detail =
            (e && e.body && e.body.message) || (e && e.message) || 'Unexpected error';
        this.errorMessage = `${prefix}: ${detail}`;
        // eslint-disable-next-line no-console
        console.error(prefix, e);
    }
}