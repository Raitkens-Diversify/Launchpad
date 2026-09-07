import { LightningElement, api } from 'lwc';

/**
 * itemPathTag — the small muted "where this item lives" tag under a card or
 * row title on a topic page: the item's node path relative to the selected
 * node ("Forms Required › Accounts" on the Operations page, "Accounts" once
 * Forms Required is selected, hidden at the node itself). Shared by the Help
 * Center rows and the Resource Center cards; the host computes the label
 * with c/treeUtil.pathTag.
 *
 * @api label    the relative path text; renders nothing when blank
 * @api nodeKey  the node the tag names (tree key)
 *
 * Clicking the tag selects that node: emits `pathselect { key }` (bubbles +
 * composed, so the page hosting the list catches it across shadow roots
 * and routes exactly like a pill or sidebar click).
 */
export default class ItemPathTag extends LightningElement {
    @api label;
    @api nodeKey;

    get show() {
        return Boolean(this.label);
    }

    get hint() {
        return `Show ${this.label}`;
    }

    handleClick(event) {
        event.preventDefault();
        event.stopPropagation(); // never doubles as the card's own select
        this.dispatchEvent(new CustomEvent('pathselect', {
            detail: { key: this.nodeKey }, bubbles: true, composed: true
        }));
    }
}