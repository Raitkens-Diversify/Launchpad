import { LightningElement, api } from 'lwc';
import { referenceRowsOf } from 'c/uatConstants';

/**
 * uatCasePreview — one test case, read-only, as its tester would run it.
 *
 * Built for Open Pool (2026-08-14): the pool card only carried a 240-char blurb,
 * so a tester had to claim a seat to find out what a case actually asks for, then
 * release it. This renders the whole thing — description, pre-conditions, every
 * step's what-to-do and expected result, reference material — without a claim.
 *
 * Presentational only, the uatFindingDetail contract: it takes a RunnerDTO on
 * `preview` and imports no Apex. The server read is UatRunController.
 * getCasePreview, which is deliberately the ONE runner path that skips
 * ensureStepResults — nothing here may become a write.
 *
 * The modal shell stays OUTSIDE, in the host, so the same component can drop
 * into any other surface that needs a case body (uatDashboard's available-tests
 * cards read the identical PoolCardDTO).
 *
 * Test_Condition__c is a heading SHARED by consecutive steps, so it renders once
 * above its run of steps — the same rule uatStepNav follows. Per row it would
 * make every step read identically.
 *
 * @api preview: UatRunController.RunnerDTO
 */
export default class UatCasePreview extends LightningElement {
    @api preview;

    /** Never reach through `preview` in the template: an unset @api would make
     *  every expression a TypeError during the host's first render. */
    get dto() {
        return this.preview || {};
    }

    get hasDescription() {
        return Boolean(this.dto.description);
    }

    get hasPreConditions() {
        return Boolean(this.dto.preConditions);
    }

    get hasSteps() {
        return (this.dto.steps || []).length > 0;
    }

    get stepCountLabel() {
        const steps = this.dto.steps || [];
        const scripted = steps.filter((s) => !s.isExplore).length;
        const explore = steps.length - scripted;
        const parts = [];
        if (scripted) {
            parts.push(`${scripted} step${scripted === 1 ? '' : 's'}`);
        }
        if (explore) {
            parts.push(`${explore} exploratory`);
        }
        return parts.join(' · ');
    }

    get stepViews() {
        let previousGroup = null;
        return (this.dto.steps || []).map((s, i) => {
            const group = s.isExplore ? 'Exploratory testing' : (s.condition || '');
            const groupLabel = group && group !== previousGroup ? group : '';
            previousGroup = group;
            return {
                key: s.stepId,
                numberLabel: String(i + 1),
                groupLabel,
                showGroup: Boolean(groupLabel),
                title: s.stepTitle || '',
                showTitle: Boolean(s.stepTitle),
                isExplore: Boolean(s.isExplore),
                // An explore step's prompt is its instruction; a scripted step
                // states what to do and what should happen.
                instruction: s.isExplore ? s.explorePrompt : s.description,
                showInstruction: Boolean(s.isExplore ? s.explorePrompt : s.description),
                expected: s.expected,
                showExpected: Boolean(!s.isExplore && s.expected),
                itemClass: 'ucp__step' + (groupLabel ? ' ucp__step--grouped' : '')
            };
        });
    }

    get hasReferenceMaterials() {
        return (this.dto.referenceMaterials || []).length > 0;
    }

    get referenceRows() {
        return referenceRowsOf(this.dto.referenceMaterials);
    }

    /** "Area · Version" — whichever the case actually carries. */
    get metaLabel() {
        return [this.dto.moduleName, this.dto.version].filter(Boolean).join(' · ');
    }

    get hasMeta() {
        return Boolean(this.metaLabel);
    }
}