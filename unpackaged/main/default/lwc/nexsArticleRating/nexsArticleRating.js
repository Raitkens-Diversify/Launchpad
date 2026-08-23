import { LightningElement, api } from 'lwc';
import getEngagement from '@salesforce/apex/NexSArticleEngagementController.getEngagement';
import castVote from '@salesforce/apex/NexSArticleEngagementController.castVote';
import submitFeedback from '@salesforce/apex/NexSArticleEngagementController.submitFeedback';

// Server-side mirror: NexSArticleEngagementController.MAX_COMMENT — change both together.
const MAX_COMMENT = 4000;

/**
 * nexsArticleRating
 *
 * "Was this article helpful?" thumbs at the foot of an article. Votes ride the
 * native Vote object (via Apex), so they roll into KnowledgeArticleVoteStat and
 * match the standard voting widget on the internal Knowledge record page. A
 * thumbs-down opens an optional "What could be better?" comment box
 * (Article_Feedback__c); a thumbs-up offers the same box behind a quiet link.
 *
 * Composed only inside nexsArticleViewer (not exposed). Imperative Apex (not
 * @wire) for the same reason as the viewer, and because vote state must be
 * fresh after voting, never client-cached.
 *
 * Engagement is optional plumbing: if the initial state load fails (e.g. a
 * user without the permission set), the widget hides rather than erroring —
 * rating must never get in the way of reading.
 */
export default class NexsArticleRating extends LightningElement {
    voteType = null;          // 'Up' | 'Down' | null
    available = false;        // getEngagement succeeded — safe to render
    showComment = false;
    commentSubmitted = false;
    busy = false;
    error;
    _articleId;

    @api
    get articleId() {
        return this._articleId;
    }
    set articleId(value) {
        this._articleId = value;
        this.reset();
        if (value) {
            this.loadState();
        }
    }

    reset() {
        this.voteType = null;
        this.available = false;
        this.showComment = false;
        this.commentSubmitted = false;
        this.busy = false;
        this.error = undefined;
    }

    async loadState() {
        const requestedId = this._articleId;
        try {
            const state = await getEngagement({ articleId: requestedId });
            if (requestedId !== this._articleId) {
                return; // article changed while loading
            }
            // A historical vote pre-selects a thumb but never auto-opens the
            // comment box — that's only for a fresh thumbs-down.
            this.voteType = state.voteType || null;
            this.available = true;
        } catch (e) {
            this.available = false;
        }
    }

    async handleVote(event) {
        const type = event.currentTarget.dataset.vote;
        if (this.busy || this.voteType === type) {
            return;
        }
        this.busy = true;
        this.error = undefined;
        try {
            this.voteType = await castVote({ articleId: this._articleId, voteType: type });
            this.commentSubmitted = false;
            this.showComment = type === 'Down';
        } catch (e) {
            this.error = e?.body?.message || 'Could not save your vote.';
        } finally {
            this.busy = false;
        }
    }

    handleAddComment() {
        this.showComment = true;
    }

    handleDismissComment() {
        this.showComment = false;
    }

    async handleSubmitComment() {
        const field = this.template.querySelector('.nexs-rating__textarea');
        const text = (field?.value || '').trim();
        if (!text || this.busy) {
            return;
        }
        this.busy = true;
        this.error = undefined;
        try {
            await submitFeedback({
                articleId: this._articleId,
                voteType: this.voteType,
                comments: text
            });
            this.showComment = false;
            this.commentSubmitted = true;
        } catch (e) {
            this.error = e?.body?.message || 'Could not save your feedback.';
        } finally {
            this.busy = false;
        }
    }

    get maxComment() {
        return MAX_COMMENT;
    }

    get hasVoted() {
        return !!this.voteType;
    }

    get showThanks() {
        return this.hasVoted && !this.showComment;
    }

    get thanksMessage() {
        return this.commentSubmitted
            ? 'Thanks — your feedback helps us improve this article.'
            : 'Thanks for your feedback.';
    }

    // The comment invite only makes sense before a comment lands.
    get showCommentLink() {
        return this.hasVoted && !this.showComment && !this.commentSubmitted;
    }

    get commentPrompt() {
        return this.voteType === 'Down'
            ? 'What could be better?'
            : 'Anything to add?';
    }

    get upClass() {
        return this.voteType === 'Up'
            ? 'nexs-rating__thumb nexs-rating__thumb--active'
            : 'nexs-rating__thumb';
    }

    get downClass() {
        return this.voteType === 'Down'
            ? 'nexs-rating__thumb nexs-rating__thumb--active'
            : 'nexs-rating__thumb';
    }

    get upPressed() {
        return this.voteType === 'Up' ? 'true' : 'false';
    }

    get downPressed() {
        return this.voteType === 'Down' ? 'true' : 'false';
    }
}