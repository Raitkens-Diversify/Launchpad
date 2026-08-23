import { LightningElement, api, wire } from 'lwc';
import getGuide from '@salesforce/apex/HelpGuideController.getGuide';
import getSupportSettings from '@salesforce/apex/NexSKnowledgeController.getSupportSettings';
import getHelpCenterLinkBase from '@salesforce/apex/ResourceCenterService.getHelpCenterLinkBase';

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
 *                              (article deep links use /?article=<urlName> —
 *                              the site has no /article/ route)
 * @api caseUrl              — contact/case target; defaults to the
 *                              Resource_Center_Setting__mdt support mailbox
 * @api resourceCenterBaseUrl — optional; when set, category/resource targets
 *                              open the RC site by URL instead of firing events
 */
export default class HelpGuide extends LightningElement {
    @api guideKey = 'get_help';
    @api helpCenterBaseUrl;
    @api caseUrl;
    @api resourceCenterBaseUrl;

    supportSettings;
    resolvedHelpBase;

    @wire(getSupportSettings)
    wiredSupportSettings({ data }) {
        if (data) {
            this.supportSettings = data;
        }
    }

    @wire(getHelpCenterLinkBase)
    wiredHelpBase({ data }) {
        if (data) {
            this.resolvedHelpBase = data;
        }
    }

    get effectiveHelpCenterBaseUrl() {
        return this.helpCenterBaseUrl || this.resolvedHelpBase;
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
            if (this.resourceCenterBaseUrl) {
                const base = this.resourceCenterBaseUrl.replace(/\/$/, '');
                window.open(`${base}?rcview=${type}&rcslug=${encodeURIComponent(value)}`, '_self');
            } else {
                const name = type === 'category' ? 'categoryselect' : 'resourceselect';
                this.dispatchEvent(new CustomEvent(name, {
                    detail: { slug: value }, bubbles: true, composed: true
                }));
            }
        } else if (type === 'article' && this.effectiveHelpCenterBaseUrl) {
            // Query-param deep link handled by nexsLanding — the LWR site has
            // no /article/ route.
            const base = this.effectiveHelpCenterBaseUrl.replace(/\/$/, '');
            window.open(`${base}/?article=${encodeURIComponent(value)}`, '_blank', 'noopener');
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