/**
 * ARC (LWR) port of aura/cmp_FlowStylizedButton — the Advertising Review
 * flow's choice buttons. Same property names as the Aura original so the
 * ARC flow copies only swap the extension name. A click stores the button's
 * text in ValueClicked and advances the flow; Pause pauses it; the Link
 * Button variant opens ValueClicked as a URL (detached anchor — LWS eats
 * window.open's return value on this site).
 */
import { LightningElement, api } from 'lwc';
import {
    FlowAttributeChangeEvent,
    FlowNavigationNextEvent,
    FlowNavigationPauseEvent
} from 'lightning/flowSupport';

export default class ArcFlowStylizedButton extends LightningElement {
    @api ButtonText = '';
    @api ButtonType = '';
    @api ValueClicked = '';
    @api Size = '';
    @api Class = '';

    get isActive() {
        return this.ButtonType === 'Active Button';
    }
    get isPause() {
        return this.ButtonType === 'Pause Button';
    }
    get isLinkButton() {
        return this.ButtonType === 'Link Button';
    }
    get isInactive() {
        return this.ButtonType === 'Inactive Button';
    }
    get isSelected() {
        return this.ButtonType === 'Selected Button';
    }
    get isBlank() {
        return this.ButtonType === 'Blank Button';
    }
    get isLink() {
        return this.ButtonType === 'Link';
    }

    /** The Aura original's doInit: Size + ButtonType pick the css class. */
    get computedClass() {
        const base = 'sb';
        if (this.ButtonType === 'Link') {
            return `${base} sb--link-text`;
        }
        if (this.Size === 'Large') {
            if (this.isBlank) {
                return `${base} sb--blank sb--large`;
            }
            if (this.isInactive) {
                return `${base} sb--inactive sb--large`;
            }
            return `${base} sb--brand sb--large`;
        }
        if (this.Size === 'Medium') {
            return `${base} sb--brand sb--medium`;
        }
        if (this.Size === 'Small') {
            return `${base} sb--brand sb--small`;
        }
        return this.isBlank
            ? `${base} sb--blank sb--medium`
            : `${base} sb--brand sb--medium`;
    }

    get baseVariantClass() {
        // Selected / Blank / Link render the Aura base variant: plain text.
        return `${this.computedClass} sb--base`;
    }

    handleClick() {
        this.ValueClicked = this.ButtonText;
        this.dispatchEvent(
            new FlowAttributeChangeEvent('ValueClicked', this.ButtonText)
        );
        this.dispatchEvent(new FlowNavigationNextEvent());
    }

    handlePauseClick() {
        this.ValueClicked = this.ButtonText;
        this.dispatchEvent(
            new FlowAttributeChangeEvent('ValueClicked', this.ButtonText)
        );
        this.dispatchEvent(new FlowNavigationPauseEvent());
    }

    handleLinkClick() {
        const url = this.ValueClicked;
        if (!url) {
            return;
        }
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.target = '_blank';
        anchor.rel = 'noopener';
        anchor.click();
    }
}