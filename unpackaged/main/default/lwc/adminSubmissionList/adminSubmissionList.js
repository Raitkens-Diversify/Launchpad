import { LightningElement } from 'lwc';
import listMySubmissions from '@salesforce/apex/ArticleSubmissionController.listMySubmissions';

/**
 * adminSubmissionList — "My submissions" for contributors (admins without the
 * Knowledge User license). Emits `edit` { submissionId } and `create`.
 */
const STATUS_CLASSES = {
    Draft: 'asl-badge asl-badge--draft',
    Submitted: 'asl-badge asl-badge--submitted',
    'Changes requested': 'asl-badge asl-badge--changes',
    Promoted: 'asl-badge asl-badge--promoted'
};

export default class AdminSubmissionList extends LightningElement {
    rows = [];
    loading = true;
    errorMessage;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const data = await listMySubmissions();
            this.rows = (data || []).map((r) => ({
                ...r,
                statusClass: STATUS_CLASSES[r.status] || 'asl-badge',
                showNotes: r.status === 'Changes requested' && r.reviewNotes
            }));
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage =
                (e && e.body && e.body.message) || 'Could not load your submissions.';
        } finally {
            this.loading = false;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleRefresh() {
        this.load();
    }

    handleCreate() {
        this.dispatchEvent(new CustomEvent('create'));
    }

    handleEdit(event) {
        this.dispatchEvent(
            new CustomEvent('edit', {
                detail: { submissionId: event.currentTarget.dataset.id }
            })
        );
    }
}