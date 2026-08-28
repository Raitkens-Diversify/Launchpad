import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";

/** Route urlPrefix of the Settings page (ARC1 sfdc_cms__route/Settings__c). */
const SETTINGS_PATH = "/settings";
/** Route urlPrefix of the Help Center page (ARC1 sfdc_cms__route/Help_Center__c). */
const HELP_CENTER_PATH = "/help-center";

/**
 * Right-hand header action group: search (grows to fill available space) +
 * notifications + settings + help + avatar, laid out as a single flex row so
 * the search box dynamically claims whatever width the fixed-size icons and
 * avatar don't need, always ending flush with the right edge of the header.
 */
export default class ArcHeaderActions extends NavigationMixin(
  LightningElement
) {
  /**
   * The gear opens Settings. A native click is composed, so listening on the
   * host is enough and arcHeaderIconButton stays the dumb button it is.
   * standard__webPage with a site-relative url is how arcNavigation moves
   * between pages of this site.
   */
  handleSettingsClick() {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: SETTINGS_PATH }
    });
  }

  /**
   * The "?" opens the Help Center (nexsLanding, the same help center shown
   * at Diversify_Help_Center1's own /help/ site) -- distinct from the
   * Resource Center still reachable from the left nav's Resource item.
   */
  handleHelpClick() {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: HELP_CENTER_PATH }
    });
  }
}