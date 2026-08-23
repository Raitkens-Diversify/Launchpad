import { LightningElement, api } from 'lwc';

/**
 * Author: Mile Cacanovic
 *
 * envelopeSectionNav — the floating "Form Navigation FAB" pinned to the bottom of a section-based
 * screen (the account interview and Review Missing Items). It shows the current position
 * ("Section X of Y") and Previous / Next controls for stepping between the page's sections, whose
 * count varies as sections are added or removed.
 *
 * Presentational only: the host owns the ordered section list, the active index, and the scrolling.
 * This component takes `total` and `activeIndex` in, disables the appropriate end, and dispatches
 * `previous` / `next` — from the icon buttons and from the Ctrl+ArrowUp / Ctrl+ArrowDown shortcuts.
 */
export default class EnvelopeSectionNav extends LightningElement {
    // Number of navigable sections on the page.
    @api total = 0;

    // Zero-based index of the section currently in view.
    @api activeIndex = 0;

    // One-based position for display.
    get position() {
        return Math.min(this.activeIndex + 1, this.total);
    }

    get isFirst() {
        return this.activeIndex <= 0;
    }

    get isLast() {
        return this.activeIndex >= this.total - 1;
    }

    get previousHintClass() {
        return this.isFirst ? 'fab__hint fab__hint_disabled' : 'fab__hint';
    }

    get nextHintClass() {
        return this.isLast ? 'fab__hint fab__hint_disabled' : 'fab__hint';
    }

    connectedCallback() {
        document.addEventListener('keydown', this._handleKeydown);
    }

    disconnectedCallback() {
        document.removeEventListener('keydown', this._handleKeydown);
    }

    handlePrevious() {
        if (this.isFirst) {
            return;
        }
        this.dispatchEvent(new CustomEvent('previous'));
    }

    handleNext() {
        if (this.isLast) {
            return;
        }
        this.dispatchEvent(new CustomEvent('next'));
    }

    // Ctrl+ArrowUp → previous section, Ctrl+ArrowDown → next (as drawn on the FAB). Ignored while at
    // the corresponding end, and when other modifiers are held so it doesn't shadow OS/browser combos.
    _handleKeydown = (event) => {
        if (!event.ctrlKey || event.altKey || event.metaKey || event.shiftKey) {
            return;
        }
        if (event.key === 'ArrowUp' && !this.isFirst) {
            event.preventDefault();
            this.dispatchEvent(new CustomEvent('previous'));
        } else if (event.key === 'ArrowDown' && !this.isLast) {
            event.preventDefault();
            this.dispatchEvent(new CustomEvent('next'));
        }
    };
}