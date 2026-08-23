import { LightningElement, api } from 'lwc';

const VARIANT_CLASS = {
    track: 'ds-progress__seg ds-progress__seg--track',
    accent: 'ds-progress__seg ds-progress__seg--accent',
    success: 'ds-progress__seg ds-progress__seg--success',
    warning: 'ds-progress__seg ds-progress__seg--warning',
    error: 'ds-progress__seg ds-progress__seg--error'
};
const VARIANTS = ['default', 'light'];

/**
 * dsProgressBar — segmented horizontal progress bar. Shows composition (how
 * much is passed/failed/blocked/in-progress/not-started), not just a bare
 * completion percentage, since that's what actually answers "is this cycle
 * healthy" at a glance.
 *
 * @api segments: [{ value: Number, variant: 'accent'|'success'|'warning'|'error', label?: String }]
 * Zero-value segments are dropped; an all-zero/empty list renders one full
 * track segment so the bar never looks broken while data loads.
 * @api variant: 'default'|'light' — 'light' swaps the accent segment to
 * --ds-light-blue for use on a navy/accent-colored background (the plain
 * --slds-g-color-accent-1 accent segment would be nearly invisible there —
 * confirmed against the exact gradient the UAT dashboards' hero uses).
 */
export default class DsProgressBar extends LightningElement {
    @api segments = [];
    @api ariaLabel = 'Progress';
    @api variant = 'default';

    get rootClass() {
        const v = VARIANTS.includes(this.variant) ? this.variant : 'default';
        return v === 'light' ? 'ds-progress ds-progress--light' : 'ds-progress';
    }

    get segmentViews() {
        const total = (this.segments || []).reduce((sum, s) => sum + (s.value || 0), 0);
        if (!total) {
            return [{ key: 'track', cssClass: VARIANT_CLASS.track, style: 'width: 100%' }];
        }
        return this.segments
            .filter((s) => s.value > 0)
            .map((s, i) => ({
                key: (s.variant || 'accent') + i,
                cssClass: VARIANT_CLASS[s.variant] || VARIANT_CLASS.accent,
                style: `width: ${(s.value / total) * 100}%`,
                label: s.label
            }));
    }

    /* Percent of the total that isn't the neutral "track" (remaining/not-
     * started) segment — a generic, variant-agnostic definition of "how much
     * progress", since this component doesn't know what each caller's
     * segments mean beyond that one convention. */
    get ariaValueNow() {
        const total = (this.segments || []).reduce((sum, s) => sum + (s.value || 0), 0);
        if (!total) {
            return 0;
        }
        const track = (this.segments || [])
            .filter((s) => s.variant === 'track')
            .reduce((sum, s) => sum + (s.value || 0), 0);
        return Math.round(((total - track) / total) * 100);
    }
}