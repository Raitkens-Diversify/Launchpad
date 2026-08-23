/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Reusable informational banner with optional action link for Experience Cloud.
 */
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { buildEnvelopeWizardUrl } from 'c/recordNavigationCommunityUtils';

const DEFAULT_REGULATED_FIELDS_MESSAGE =
  'Regulated fields cannot be edited. In order to make changes, you will need to create an envelope, make edits and submit an envelope to home office.';

export default class ArcInfoBanner extends NavigationMixin(LightningElement) {
  @api variant = 'info';
  @api message = DEFAULT_REGULATED_FIELDS_MESSAGE;
  @api actionLabel = '';
  @api linkTarget = 'envelope';
  @api linkUrl = '';

  get showAction() {
    return Boolean(String(this.actionLabel || '').trim());
  }

  get bannerClass() {
    return `info-banner info-banner_${this.variant || 'info'}`;
  }

  get actionAriaLabel() {
    return this.actionLabel || 'Open linked page';
  }

  handleActionClick(event) {
    event.preventDefault();

    const url = this.resolveActionUrl();
    if (!url) {
      return;
    }

    this[NavigationMixin.Navigate]({
      type: 'standard__webPage',
      attributes: { url }
    });
  }

  handleActionKeyDown(event) {
    if (event.key !== 'Enter' && event.key !== ' ') {
      return;
    }

    event.preventDefault();
    this.handleActionClick(event);
  }

  resolveActionUrl() {
    const customUrl = String(this.linkUrl || '').trim();
    if (this.linkTarget === 'custom' && customUrl) {
      return customUrl;
    }

    if (this.linkTarget === 'envelope') {
      return buildEnvelopeWizardUrl();
    }

    return customUrl || null;
  }
}