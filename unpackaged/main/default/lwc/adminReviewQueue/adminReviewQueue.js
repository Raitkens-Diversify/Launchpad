import { LightningElement } from 'lwc';
import listReviewQueue from '@salesforce/apex/ArticleSubmissionController.listReviewQueue';
import promote from '@salesforce/apex/ArticleSubmissionController.promote';
import requestChanges from '@salesforce/apex/ArticleSubmissionController.requestChanges';
import { messageFrom, toast } from 'c/messageUtil';

/**
 * adminReviewQueue — the licensed Knowledge user's inbox of contributor
 * submissions. Preview → Promote (creates a real Knowledge draft; publish
 * happens from the Articles list) or Request changes with notes.
 */
export default class AdminReviewQueue extends LightningElement {
    rows = [];
    loading = true;
    working = false;
    errorMessage;

    selected;      // submission being previewed
    notesOpen = false;
    notesText = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const data = await listReviewQueue();
            this.rows = data || [];
            this.errorMessage = undefined;
            if (this.selected && !this.rows.find((r) => r.id === this.selected.id)) {
                this.selected = undefined;
            }
        } catch (e) {
            this.errorMessage =
                (e && e.body && e.body.message) || 'Could not load the review queue.';
        } finally {
            this.loading = false;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get selectedCategories() {
        return this.selected ? (this.selected.categoryNames || []).join(', ') : '';
    }

    get selectedSuggested() {
        return this.selected ? (this.selected.suggestedUrlNames || []).join(', ') : '';
    }

    get selectedResourceCount() {
        return this.selected ? (this.selected.relatedResourceIds || []).length : 0;
    }

    handleRefresh() {
        this.load();
    }

    handleOpen(event) {
        this.selected = this.rows.find(
            (r) => r.id === event.currentTarget.dataset.id
        );
    }

    handleClosePreview() {
        this.selected = undefined;
    }

    // ---- Promote --------------------------------------------------------------------

    async handlePromote() {
        if (!this.selected) {
            return;
        }
        this.working = true;
        try {
            await promote({ submissionId: this.selected.id });
            toast(this, 
                'success',
                'Promoted — it is now a Knowledge draft. Publish it from the Articles tab when ready.'
            );
            this.selected = undefined;
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.working = false;
        }
    }

    // ---- Request changes -----------------------------------------------------------

    handleNotesOpen() {
        this.notesText = '';
        this.notesOpen = true;
    }

    handleNotesChange(event) {
        this.notesText = event.target.value;
    }

    handleNotesCancel() {
        this.notesOpen = false;
    }

    async handleNotesSend() {
        if (!this.notesText.trim()) {
            toast(this, 'error', 'Add a note so the author knows what to change.');
            return;
        }
        this.notesOpen = false;
        this.working = true;
        try {
            await requestChanges({
                submissionId: this.selected.id,
                notes: this.notesText
            });
            toast(this, 'success', 'Sent back to the author with your notes.');
            this.selected = undefined;
            await this.load();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.working = false;
        }
    }

    // ---- Utils --------------------------------------------------------------------

}