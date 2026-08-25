import { LightningElement, track } from 'lwc';
import markWelcomeSeen from '@salesforce/apex/ArcWelcomeController.markWelcomeSeen';

// Static Resource URL for the welcome video. Null until the video exists —
// wire it with: import WELCOME_VIDEO from '@salesforce/resourceUrl/<name>';
const WELCOME_VIDEO = null;

/**
 * arcWelcomeVideo
 *
 * First-login welcome banner on the help center home page. While no video
 * asset exists the media pane is hidden (previously an empty placeholder
 * player rendered AND the seen-flag burned on mount — first-login users
 * spent their one welcome on a blank box).
 *
 * The seen flag now writes on "Got it": the banner shows until the user
 * acknowledges it, then never again. Surface-agnostic — emits `continue`
 * and lets the host hide the banner.
 */
export default class ArcWelcomeVideo extends LightningElement {
    @track saveError;

    get videoUrl() {
        return WELCOME_VIDEO;
    }

    get hasVideo() {
        return Boolean(this.videoUrl);
    }

    handleContinue() {
        // Fire-and-forget: don't block the dismiss on the flag write.
        markWelcomeSeen().catch((e) => {
            this.saveError = e?.body?.message || 'Could not save your welcome state.';
            // eslint-disable-next-line no-console
            console.error('arcWelcomeVideo markWelcomeSeen failed', e);
        });
        this.dispatchEvent(new CustomEvent('continue'));
    }
}