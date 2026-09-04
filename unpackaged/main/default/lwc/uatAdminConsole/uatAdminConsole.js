import { LightningElement, wire } from 'lwc';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import getAccess from '@salesforce/apex/UatAdminAccessService.getAccess';

/**
 * uatAdminConsole — the Helios UAT admin console. Split out of adminConsole
 * (2026-09-04) so the Help Center / Resource Center admin console can ship to
 * production with no UAT metadata; this root keeps the same shell, rail,
 * chrome, token block, and section components the sections always had.
 *
 * Access: the UAT_Admin_Console tab is granted by UAT_Admin, but that only
 * hides the entry point — sections render exclusively from
 * UatAdminAccessService.getAccess() (server-side describe checks on each
 * section's backing object), and every Uat*AdminController method re-checks
 * on the server.
 *
 * Section order: every management surface first, Cycle Report last — it is
 * the only read-out.
 */
const SECTIONS = [
    { key: 'uatDashboard', gate: 'uatDashboard', label: 'Cycle Dashboard', icon: 'utility:home', group: 'UAT Testing' },
    { key: 'uatCycles', gate: 'uatCycles', label: 'Test Cycles', icon: 'utility:retail_execution', group: 'UAT Testing' },
    { key: 'uatBooks', gate: 'uatBooks', label: 'Test Books', icon: 'utility:open_folder', group: 'UAT Testing' },
    { key: 'uatCases', gate: 'uatCases', label: 'Test Cases', icon: 'utility:task', group: 'UAT Testing' },
    { key: 'uatTaxonomy', gate: 'uatTaxonomy', label: 'Taxonomy', icon: 'utility:layers', group: 'UAT Testing' },
    { key: 'uatTeams', gate: 'uatTeams', label: 'Teams', icon: 'utility:groups', group: 'UAT Testing' },
    { key: 'uatCoverage', gate: 'uatCoverage', label: 'Pool Health', icon: 'utility:metrics', group: 'UAT Testing' },
    { key: 'uatReport', gate: 'uatReport', label: 'Cycle Report', icon: 'utility:page', group: 'UAT Testing' }
];

export default class UatAdminConsole extends LightningElement {
    logoUrl = diversifyLogo;

    access;
    errorMessage;
    section = 'uatDashboard';

    // Cross-section navigation context (uatnavigate event): a cycle to open
    // in the Cycles editor, a case (+ origin cycle for the breadcrumb) to open
    // in the Cases detail, or a book to open in the Books editor
    // (Create-book-from-module-group). Cleared on direct rail clicks.
    uatCycleOpenId = null;
    uatCaseContext = null;
    uatBookOpenId = null;

    @wire(getAccess)
    wiredAccess({ data, error }) {
        if (data) {
            this.access = data;
            this.errorMessage = undefined;
            this.ensureAccessibleSection();
        } else if (error) {
            this.errorMessage =
                (error.body && error.body.message) ||
                'Could not load your admin permissions. Refresh to try again.';
        }
    }

    // ---- Derived state --------------------------------------------------------

    get loading() {
        return !this.access && !this.errorMessage;
    }

    get ready() {
        return !!this.access;
    }

    get noAccess() {
        return this.ready && !this.access.anySection;
    }

    get hasSections() {
        return this.ready && this.access.anySection;
    }

    sectionVisible(s) {
        return !!this.access[s.gate];
    }

    get railItems() {
        if (!this.access) {
            return [];
        }
        return SECTIONS.filter((s) => this.sectionVisible(s)).map((s) => ({
            key: s.key,
            label: s.label,
            icon: s.icon,
            group: s.group,
            cssClass:
                s.key === this.section
                    ? 'ac-rail__item ac-rail__item--active'
                    : 'ac-rail__item',
            ariaCurrent: s.key === this.section ? 'page' : null
        }));
    }

    /** Rail items bucketed by group; group labels only when >1 group shows. */
    get railGroups() {
        const items = this.railItems;
        const groups = [];
        for (const item of items) {
            let g = groups.find((x) => x.name === item.group);
            if (!g) {
                g = { name: item.group, items: [] };
                groups.push(g);
            }
            g.items.push(item);
        }
        const showLabels = groups.length > 1;
        return groups.map((g) => ({ ...g, showLabel: showLabels }));
    }

    get activeSection() {
        return SECTIONS.find((s) => s.key === this.section);
    }

    get activeLabel() {
        const active = this.activeSection;
        return active ? active.label : '';
    }

    get isUatDashboardSection() {
        return this.section === 'uatDashboard';
    }

    get isUatCyclesSection() {
        return this.section === 'uatCycles';
    }

    get isUatBooksSection() {
        return this.section === 'uatBooks';
    }

    get isUatCasesSection() {
        return this.section === 'uatCases';
    }

    get isUatTaxonomySection() {
        return this.section === 'uatTaxonomy';
    }

    get isUatTeamsSection() {
        return this.section === 'uatTeams';
    }

    get isUatCoverageSection() {
        return this.section === 'uatCoverage';
    }

    get isUatReportSection() {
        return this.section === 'uatReport';
    }

    // ---- Handlers ---------------------------------------------------------------

    handleSectionClick(event) {
        this.section = event.currentTarget.dataset.key;
        this.uatCycleOpenId = null;
        this.uatCaseContext = null;
        this.uatBookOpenId = null;
    }

    /** Sections raise uatnavigate to jump across sections: book usage line ->
     *  cycle editor, Run this book -> cycle editor, execution chip -> case
     *  detail with the cycle breadcrumb, Create book from module group ->
     *  book editor. */
    handleUatNavigate(event) {
        const { section, recordId, context } = event.detail;
        if (section === 'uatCycles') {
            this.uatCycleOpenId = recordId;
            this.uatCaseContext = null;
            this.uatBookOpenId = null;
        } else if (section === 'uatCases') {
            this.uatCaseContext = {
                caseId: recordId,
                executionId: context ? context.executionId : null,
                cycleId: context ? context.cycleId : null,
                cycleName: context ? context.cycleName : null
            };
            this.uatCycleOpenId = null;
            this.uatBookOpenId = null;
        } else if (section === 'uatBooks') {
            this.uatBookOpenId = recordId;
            this.uatCycleOpenId = null;
            this.uatCaseContext = null;
        }
        this.section = section;
    }

    // ---- Internals ----------------------------------------------------------------

    ensureAccessibleSection() {
        const current = SECTIONS.find((s) => s.key === this.section);
        if (current && this.sectionVisible(current)) {
            return;
        }
        const first = SECTIONS.find((s) => this.sectionVisible(s));
        if (first) {
            this.section = first.key;
        }
    }
}