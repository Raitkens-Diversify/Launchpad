import { LightningElement, api } from 'lwc';

/**
 * uatStepNav — the runner's sidebar step navigator: one row per step with a
 * status marker (number while unanswered, result icon once answered), the
 * step's title (falling back to its instruction) as the row text, and a
 * paperclip when the step already has evidence. Test_Condition__c is a heading SHARED by consecutive
 * steps, so it renders once as a group label above its run of steps — never
 * per row, where it would make every row read identically. Every row is a
 * real button — the server accepts answers in any order, so jumping is
 * always allowed; the host autosaves the departing step before honoring
 * `stepselect`.
 *
 * Pure presentation: the host owns the step array and the current index.
 *
 * @api heading: card title (default 'Test progress'; empty string hides it)
 * @api steps: the runner's RunnerStepDTO array
 * @api currentIndex: 0-based index of the step in the workspace
 * Emits `stepselect` { index } on row click.
 */
const RESULT_MARKER = {
    Pass: { icon: 'utility:check', mod: 'pass' },
    Fail: { icon: 'utility:close', mod: 'fail' },
    Blocked: { icon: 'utility:ban', mod: 'blocked' },
    'N/A': { icon: 'utility:dash', mod: 'na' }
};

export default class UatStepNav extends LightningElement {
    @api heading = 'Test progress';
    @api steps = [];
    @api currentIndex = 0;

    get stepViews() {
        const current = Number(this.currentIndex);
        let previousGroup = null;
        return (this.steps || []).map((s, i) => {
            const isCurrent = i === current;
            const marker = s.result ? RESULT_MARKER[s.result] : null;
            const mod = marker ? marker.mod : (isCurrent ? 'current' : 'todo');
            const group = s.isExplore ? 'Exploratory testing' : (s.condition || '');
            const groupLabel = group && group !== previousGroup ? group : '';
            previousGroup = group;
            const title = s.stepTitle
                || (s.isExplore ? s.explorePrompt : s.description)
                || group || 'Step ' + (i + 1);
            return {
                key: s.stepId,
                index: i,
                numberLabel: String(i + 1),
                groupLabel,
                title,
                srStatus: s.result ? s.result : 'No result yet',
                showIcon: Boolean(marker),
                iconName: marker ? marker.icon : '',
                hasEvidence: (s.evidenceCount || 0) > 0,
                ariaCurrent: isCurrent ? 'step' : undefined,
                itemClass: 'usn__item' + (groupLabel ? ' usn__item--grouped' : ''),
                rowClass: 'usn__row' + (isCurrent ? ' usn__row--current' : ''),
                markerClass: 'usn__marker usn__marker--' + mod
            };
        });
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('stepselect', {
            detail: { index: Number(event.currentTarget.dataset.index) }
        }));
    }
}