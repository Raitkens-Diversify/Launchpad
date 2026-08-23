import { LightningElement, api } from 'lwc';
import { typeMeta } from 'c/resourceTypeIcons';
import { TYPE_EXTERNAL_LINK } from 'c/rcConstants';

/**
 * resourceCard — presentational tile for a single resource. Matches the NexS
 * card recipe (surface + border + 10px radius + navy-border/lift hover).
 *
 * Emits (bubbles + composed so the orchestrator catches them across shadow DOM):
 *  - `resourceselect { slug }`   — user opened the resource (card/title/View/Watch).
 *    File-backed types open the detail view too (preview there, download from its
 *    explicit button) — cards never download directly, so download counts stay real.
 */
export default class ResourceCard extends LightningElement {
    @api resource;

    get meta() {
        return typeMeta(this.resource && this.resource.resourceType);
    }
    get iconPath() {
        return this.meta.iconPath;
    }
    get badge() {
        return this.meta.badge;
    }
    get primaryLabel() {
        return this.meta.action;
    }
    get isExternal() {
        return this.resource && this.resource.resourceType === TYPE_EXTERNAL_LINK
            && !!this.resource.externalUrl;
    }
    get isOpenInApp() {
        return !this.isExternal;
    }

    fire(name, detail) {
        this.dispatchEvent(new CustomEvent(name, { detail, bubbles: true, composed: true }));
    }

    handleSelect() {
        this.fire('resourceselect', { slug: this.resource.slug });
    }

    handleKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleSelect();
        }
    }
}