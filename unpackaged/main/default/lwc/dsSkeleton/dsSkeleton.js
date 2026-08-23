import { LightningElement, api } from 'lwc';

const VARIANTS = ['card', 'row', 'text'];

/**
 * dsSkeleton — pulsing placeholder blocks for loading states (fills the gap
 * Phase 0 found: no skeleton component exists anywhere in Help Center,
 * Resource Center, or the UAT portal). Respects prefers-reduced-motion —
 * the pulse becomes a static gray block, matching the one existing
 * precedent (tourOverlay.css).
 *
 * @api variant: 'card'|'row'|'text' — the placeholder shape
 * @api count: how many to repeat
 */
export default class DsSkeleton extends LightningElement {
    @api variant = 'card';
    @api count = 1;

    get blocks() {
        const n = Number(this.count) > 0 ? Number(this.count) : 1;
        return Array.from({ length: n }, (_, i) => ({ key: 'skel' + i }));
    }

    get cssClass() {
        const v = VARIANTS.includes(this.variant) ? this.variant : 'card';
        return `ds-skel ds-skel--${v}`;
    }
}