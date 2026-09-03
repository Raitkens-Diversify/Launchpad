import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGuide from '@salesforce/apex/HelpGuideController.getGuide';
import getSupportSettings from '@salesforce/apex/NexSKnowledgeController.getSupportSettings';
import { linkContext, goToArticle } from 'c/contextNav';

/**
 * helpGuide — config-driven "Get Help" decision tree. Loads a published guide
 * (HelpGuideController.getGuide) and walks it client-side. Terminal targets:
 *  - node     → advance to the next question
 *  - category → categoryselect event (embedded) or Resource Center deep link
 *  - resource → resourceselect event (embedded) or Resource Center deep link
 *  - article  → opens the Help Center article (helpCenterBaseUrl)
 *  - case     → opens the case/contact page (caseUrl)
 *
 * @api guideKey             — which guide to run (default 'get_help')
 * @api helpCenterBaseUrl    — absolute Help Center base, for article targets
 *                              (article deep links are /article?name=<urlName>;
 *                              c/contextNav picks the site URL or the
 *                              core-app tab per surface)
 * @api caseUrl              — contact/case target; defaults to the
 *                              Resource_Center_Setting__mdt support mailbox
 * @api resourceCenterBaseUrl — optional; when set, category/resource targets
 *                              open the RC site by URL instead of firing events
 */
export default class HelpGuide extends NavigationMixin(LightningElement) {
    @api guideKey = 'get_help';
    @api helpCenterBaseUrl;
    @api caseUrl;
    @api resourceCenterBaseUrl;

    supportSettings;
    /** {surface, helpBase, resourceBase} from c/contextNav; null until resolved. */
    linkCtx = null;

    @wire(getSupportSettings)
    wiredSupportSettings({ data }) {
        if (data) {
            this.supportSettings = data;
        }
    }

    get effectiveHelpCenterBaseUrl() {
        return this.helpCenterBaseUrl || (this.linkCtx && this.linkCtx.helpBase);
    }

    get effectiveCaseUrl() {
        if (this.caseUrl) {
            return this.caseUrl;
        }
        const email = this.supportSettings && this.supportSettings.supportEmail;
        return email ? 'mailto:' + email : null;
    }

    guide;
    nodesByKey = {};
    currentKey;
    history = []; // [{ key, label }]
    loading = true;
    error;

    connectedCallback() {
        linkContext().then((ctx) => {
            this.linkCtx = ctx;
        });
        getGuide({ guideKey: this.guideKey })
            .then((data) => {
                this.loading = false;
                if (!data) {
                    this.guide = undefined;
                    return;
                }
                this.guide = data;
                (data.nodes || []).forEach((n) => {
                    this.nodesByKey[n.nodeKey] = n;
                });
                this.currentKey = data.rootNodeKey;
            })
            .catch(() => {
                this.loading = false;
                this.error = 'We could not load the guide right now.';
            });
    }

    get currentNode() {
        return this.currentKey ? this.nodesByKey[this.currentKey] : undefined;
    }
    get hasGuide() {
        return !!this.guide && !!this.currentNode;
    }
    get options() {
        const node = this.currentNode;
        return node && node.options ? node.options : [];
    }
    get showBreadcrumb() {
        return this.history.length > 0;
    }

    handleOption(event) {
        const { type, value, label } = event.currentTarget.dataset;
        if (type === 'node') {
            const next = this.nodesByKey[value];
            if (next) {
                this.history = [...this.history, { key: this.currentKey, label }];
                this.currentKey = value;
            }
            return;
        }
        this.navigateTerminal(type, value);
    }

    navigateTerminal(type, value) {
        if (type === 'category' || type === 'resource') {
            // Unchanged: a Builder-supplied base is an explicit external
            // override; otherwise the guide is embedded (the only deployment
            // today) and the host swaps the view in place. This is an
            // embedded-vs-standalone question, not a surface one, so it does
            // NOT go through contextNav — routing it there would turn the
            // Resource Center's inline swap into a full page load.
            if (this.resourceCenterBaseUrl) {
                const base = this.resourceCenterBaseUrl.replace(/\/$/, '');
                window.open(`${base}?rcview=${type}&rcslug=${encodeURIComponent(value)}`, '_self');
                return;
            }
            const name = type === 'category' ? 'categoryselect' : 'resourceselect';
            this.dispatchEvent(new CustomEvent(name, {
                detail: { slug: value }, bubbles: true, composed: true
            }));
        } else if (type === 'article') {
            goToArticle(this, this.linkCtx, { urlName: value });
        } else if (type === 'case' && this.effectiveCaseUrl) {
            window.open(this.effectiveCaseUrl, '_self');
        }
    }

    handleCrumb(event) {
        const idx = parseInt(event.currentTarget.dataset.idx, 10);
        const target = this.history[idx];
        this.history = this.history.slice(0, idx);
        this.currentKey = target.key;
    }

    handleStartOver() {
        this.history = [];
        this.currentKey = this.guide ? this.guide.rootNodeKey : this.currentKey;
    }
}