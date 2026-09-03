import { LightningElement, api } from 'lwc';

/**
 * dsAgendaRow — one agenda line: a date block, a title, a meta line, and
 * exactly one call-to-action (or a note when there is nothing to do yet).
 * Presentational and Apex-free; the host owns routing and decides the CTA
 * (e.g. webinarAgenda maps a server-derived lifecycle onto it).
 *
 * @api item: {
 *   id: string,
 *   title: string,
 *   datetime: string,        // ISO-8601, rendered by c-ds-date-block
 *   meta: string?,           // "10:00 AM · Jane Doe · 45 min"
 *   note: string?,           // shown instead of a CTA ("Recording coming soon")
 *   cta: { label, href? }?   // href → <a target="_blank" rel="noopener noreferrer">
 *                            // (the action leaves the site); no href → <button>
 *                            // emitting rowselect; absent → no action rendered
 * }
 *
 * Emits `rowselect { id }` (plain — the host listens on the element) from the
 * button CTA only; the anchor CTA never fires it, the browser owns that
 * navigation.
 */
export default class DsAgendaRow extends LightningElement {
    @api item;

    get safeItem() {
        return this.item || {};
    }
    get hasHref() {
        const cta = this.safeItem.cta;
        return Boolean(cta && cta.href);
    }
    get isButton() {
        const cta = this.safeItem.cta;
        return Boolean(cta && cta.label && !cta.href);
    }
    get ctaLabel() {
        return this.safeItem.cta ? this.safeItem.cta.label : '';
    }
    get ctaHref() {
        return this.safeItem.cta ? this.safeItem.cta.href : undefined;
    }

    handleSelect() {
        this.dispatchEvent(new CustomEvent('rowselect', { detail: { id: this.safeItem.id } }));
    }
}