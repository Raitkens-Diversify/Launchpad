import { LightningElement, api } from 'lwc';

/**
 * dsPage — the ONE page frame for every Help Center / Resource Center /
 * Events route (docs/ui-standards.md §3, docs/help-center-visual-audit.md §E).
 *
 * Every route composes  c-ds-chrome > c-ds-page > page  and puts the
 * full-bleed pieces (c-ds-hero, c-resource-help-band) OUTSIDE the frame as
 * siblings. The frame is identical everywhere, so moving between pages never
 * shifts the content edges:
 *   max-width 1440px · gutter 24px (16px ≤640px) · padding 32px top / 48px bottom
 * `column` centres a 1040px reading column inside that frame (hub body,
 * resource/event detail, events page, guide); wide pages with a sidebar
 * (topic pages, search results) use the full frame.
 *
 * The five --ds-page-* / --ds-column-max tokens are declared once, here, on
 * :host; nothing else in the repo may declare its own page width or gutter.
 */
export default class DsPage extends LightningElement {
    /** Centre a reading-width column instead of using the full frame. */
    @api column = false;

    get innerClass() {
        return this.column ? 'ds-page__inner ds-page__column' : 'ds-page__inner';
    }
}