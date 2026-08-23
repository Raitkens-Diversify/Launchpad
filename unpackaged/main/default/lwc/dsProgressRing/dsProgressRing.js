import { LightningElement, api } from 'lwc';

/**
 * dsProgressRing — a circular percent-complete indicator (SVG, no library).
 *
 * Both circles carry pathLength="100" so the stroke math works in percent
 * units regardless of radius; the value circle's dashoffset is bound as a
 * style string (same idiom as dsProgressBar's segment widths) so CSS can
 * transition it.
 */
export default class DsProgressRing extends LightningElement {
    @api percent;
    @api label = ''; // short caption under the number, e.g. "complete"

    get pct() {
        const n = Math.round(Number(this.percent));
        if (!Number.isFinite(n)) {
            return 0;
        }
        return Math.min(100, Math.max(0, n));
    }

    get pctLabel() {
        return `${this.pct}%`;
    }

    get dashStyle() {
        return `stroke-dashoffset: ${100 - this.pct};`;
    }

    get ariaLabelText() {
        return this.label ? `${this.label}: ${this.pct}%` : `${this.pct}%`;
    }
}