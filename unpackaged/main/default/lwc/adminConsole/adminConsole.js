import { LightningElement, wire } from 'lwc';
import diversifyLogo from '@salesforce/resourceUrl/DiversifyLogoV2';
import getAccess from '@salesforce/apex/AdminAccessService.getAccess';

/**
 * adminConsole — the consolidated Admin tab for the Resource Center / Help
 * Center / Get Help features. Same orchestrator + branded-chrome pattern as
 * resourceCenter: a left rail swaps sections inline; no page navigation.
 *
 * Access: the Admin_Console tab is granted by Resource_Center_Admin and
 * UAT_Admin, but that only hides the entry point — sections render exclusively
 * from AdminAccessService.getAccess() (server-side describe/perm checks plus
 * the Help_Center_Console / UAT_Console persona custom permissions carried by
 * those perm sets), and every Admin*Controller method re-checks on the server.
 *
 * Phase (a) ships the shell: rail, chrome, access gating, and per-section
 * placeholders. Later phases replace the placeholders with the real section
 * components (articles → resources/categories → guides embed → analytics).
 */
// Rail sections, in display order within their group. Group headers render
// only when the user can see sections in more than one group, so Help-Center
// admins without UAT access (and vice versa) see the same flat rail as before.
// UAT group target order (added as each phase ships): Test Cycles, Test Books,
// Test Cases, Taxonomy, Teams. Cycle Report closes the group: every section
// above it is a management surface, it is the only read-out.
const SECTIONS = [
    { key: 'articles', gate: 'articles', label: 'Articles', icon: 'utility:knowledge_base', group: 'Help Center' },
    { key: 'resources', gate: 'resources', label: 'Resources', icon: 'utility:file', group: 'Help Center' },
    { key: 'categories', gate: 'categories', label: 'Categories', icon: 'utility:hierarchy', group: 'Help Center' },
    { key: 'guides', gate: 'guides', label: 'Help Guides', icon: 'utility:questions_and_answers', group: 'Help Center' },
    { key: 'analytics', gate: 'analytics', label: 'Analytics', icon: 'utility:chart', group: 'Help Center' },
    { key: 'uatDashboard', gate: 'uatDashboard', label: 'Cycle Dashboard', icon: 'utility:home', group: 'UAT Testing' },
    { key: 'uatCycles', gate: 'uatCycles', label: 'Test Cycles', icon: 'utility:retail_execution', group: 'UAT Testing' },
    { key: 'uatBooks', gate: 'uatBooks', label: 'Test Books', icon: 'utility:open_folder', group: 'UAT Testing' },
    { key: 'uatCases', gate: 'uatCases', label: 'Test Cases', icon: 'utility:task', group: 'UAT Testing' },
    { key: 'uatTaxonomy', gate: 'uatTaxonomy', label: 'Taxonomy', icon: 'utility:layers', group: 'UAT Testing' },
    { key: 'uatTeams', gate: 'uatTeams', label: 'Teams', icon: 'utility:groups', group: 'UAT Testing' },
    { key: 'uatCoverage', gate: 'uatCoverage', label: 'Pool Health', icon: 'utility:metrics', group: 'UAT Testing' },
    { key: 'uatReport', gate: 'uatReport', label: 'Cycle Report', icon: 'utility:page', group: 'UAT Testing' }
];

export default class AdminConsole extends LightningElement {
    logoUrl = diversifyLogo;

    access;
    errorMessage;
    section = 'articles';

    // Articles section subview state.
    // Views: list | editor (article) | queue | mysubs | subeditor | synonyms
    articlesView = 'list';
    editKaId = null;
    editSubmissionId = null;

    // Resources section subview state: list | editor
    resourcesView = 'list';
    editResourceId = null;

    // UAT cross-section navigation context (uatnavigate event): a cycle to
    // open in the Cycles editor, a case (+ origin cycle for the breadcrumb)
    // to open in the Cases detail, or a book to open in the Books editor
    // (Create-book-from-module-group). Cleared on direct rail clicks.
    uatCycleOpenId = null;
    uatCaseContext = null;
    uatBookOpenId = null;

    @wire(getAccess)
    wiredAccess({ data, error }) {
        if (data) {
            this.access = data;
            this.errorMessage = undefined;
            // Contributors (no Knowledge license) land on My Submissions.
            this.articlesView = data.articles ? 'list' : 'mysubs';
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

    /**
     * Permissions say "author articles" but the User record lacks the Knowledge
     * User license checkbox (which no permission set can grant) — say so
     * instead of silently hiding the Articles section.
     */
    get showLicenseNote() {
        return this.ready && this.access.articlePerms && !this.access.knowledgeUser;
    }

    sectionVisible(s) {
        if (s.key === 'articles') {
            // Licensed authors OR submission contributors both live here.
            return !!(this.access.articles || this.access.submissions);
        }
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

    get isArticlesSection() {
        return this.section === 'articles';
    }

    get isResourcesSection() {
        return this.section === 'resources';
    }

    get isCategoriesSection() {
        return this.section === 'categories';
    }

    get isGuidesSection() {
        return this.section === 'guides';
    }

    get isAnalyticsSection() {
        return this.section === 'analytics';
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

    get isResourceList() {
        return this.resourcesView === 'list';
    }

    get isResourceEditor() {
        return this.resourcesView === 'editor';
    }

    get isArticlesList() {
        return this.articlesView === 'list';
    }

    get isArticlesEditor() {
        return this.articlesView === 'editor';
    }

    get isReviewQueue() {
        return this.articlesView === 'queue';
    }

    get isMySubmissions() {
        return this.articlesView === 'mysubs';
    }

    get isSubmissionEditor() {
        return this.articlesView === 'subeditor';
    }

    get isArticlesSynonyms() {
        return this.articlesView === 'synonyms';
    }

    /** Sub-tabs vary by role: licensed author vs. submission contributor. */
    get articleTabs() {
        if (!this.access) {
            return [];
        }
        const tabs = [];
        if (this.access.articles) {
            tabs.push({ key: 'list', label: 'Articles' });
            if (this.access.submissions) {
                tabs.push({ key: 'queue', label: 'Review queue' });
            }
        } else if (this.access.submissions) {
            tabs.push({ key: 'mysubs', label: 'My submissions' });
        }
        if (this.access.synonyms) {
            tabs.push({ key: 'synonyms', label: 'Search synonyms' });
        }
        // The editor views belong to their parent tab for highlighting.
        const activeKey =
            this.articlesView === 'editor'
                ? 'list'
                : this.articlesView === 'subeditor'
                  ? 'mysubs'
                  : this.articlesView;
        return tabs.map((t) => ({
            ...t,
            cssClass:
                t.key === activeKey
                    ? 'ac-subnav__item ac-subnav__item--active'
                    : 'ac-subnav__item'
        }));
    }

    get showArticleSubnav() {
        return this.articleTabs.length > 1;
    }

    // ---- Handlers ---------------------------------------------------------------

    handleSectionClick(event) {
        this.section = event.currentTarget.dataset.key;
        this.uatCycleOpenId = null;
        this.uatCaseContext = null;
        this.uatBookOpenId = null;
    }

    /** UAT sections raise uatnavigate to jump across sections: book usage
     *  line -> cycle editor, Run this book -> cycle editor, execution chip ->
     *  case detail with the cycle breadcrumb, Create book from module group
     *  -> book editor. */
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

    handleArticlesSubnav(event) {
        this.articlesView = event.currentTarget.dataset.view;
        this.editKaId = null;
        this.editSubmissionId = null;
    }

    handleArticleEdit(event) {
        this.editKaId = event.detail.kaId;
        this.articlesView = 'editor';
    }

    handleArticleCreate() {
        this.editKaId = null;
        this.articlesView = 'editor';
    }

    handleEditorBack() {
        this.articlesView = 'list';
        this.editKaId = null;
    }

    handleSubmissionEdit(event) {
        this.editSubmissionId = event.detail.submissionId;
        this.articlesView = 'subeditor';
    }

    handleSubmissionCreate() {
        this.editSubmissionId = null;
        this.articlesView = 'subeditor';
    }

    handleSubmissionBack() {
        this.articlesView = 'mysubs';
        this.editSubmissionId = null;
    }

    handleResourceEdit(event) {
        this.editResourceId = event.detail.resourceId;
        this.resourcesView = 'editor';
    }

    handleResourceCreate() {
        this.editResourceId = null;
        this.resourcesView = 'editor';
    }

    handleResourceBack() {
        this.resourcesView = 'list';
        this.editResourceId = null;
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