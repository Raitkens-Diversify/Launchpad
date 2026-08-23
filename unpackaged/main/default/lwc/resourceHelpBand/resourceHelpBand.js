import { LightningElement, api, wire } from 'lwc';
import getSupportSettings from '@salesforce/apex/NexSKnowledgeController.getSupportSettings';

/**
 * resourceHelpBand — the ONE "Need more help?" contact band, shared by the
 * Help Center (nexsHome, nexsArticleBrowser) and Resource Center surfaces
 * (this replaced two copy-pasted .nexs-help variants).
 *
 * Contact targets come from Resource_Center_Setting__mdt via
 * NexSKnowledgeController.getSupportSettings; the @api values override the
 * settings when a surface needs different targets. A card without a target
 * hides itself — no more href="#" placeholders in production.
 */
export default class ResourceHelpBand extends LightningElement {
    @api heading = 'Need more help?';
    @api subtitle = 'Can’t find what you’re looking for? Reach the support team and we’ll help you out.';
    /** Override for the settings-driven support mailbox. */
    @api contactEmail;
    @api contactLabel = 'Get in touch';
    @api contactText = 'Email the support team with your question.';
    /** Override for the settings-driven request target (URL or mailto:). */
    @api requestUrl;
    @api requestLabel = 'Submit a request';
    @api requestText = 'Open a support request and we’ll follow up with you.';

    settings;

    @wire(getSupportSettings)
    wiredSettings({ data }) {
        if (data) {
            this.settings = data;
        }
    }

    get effectiveEmail() {
        return this.contactEmail || (this.settings && this.settings.supportEmail);
    }

    get effectiveRequestUrl() {
        const url = this.requestUrl || (this.settings && this.settings.supportRequestUrl);
        return url && url !== '#' ? url : null;
    }

    get showContact() {
        return Boolean(this.effectiveEmail);
    }

    get showRequest() {
        return Boolean(this.effectiveRequestUrl);
    }

    get showBand() {
        return this.showContact || this.showRequest;
    }

    get mailto() {
        return 'mailto:' + this.effectiveEmail;
    }
}