import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";

/** Route urlPrefix of the Settings page (ARC1 sfdc_cms__route/Settings__c). */
const SETTINGS_PATH = "/settings";
/** Route urlPrefix of the Resource Center page (ARC1 sfdc_cms__route/Learning__c). */
const RESOURCE_CENTER_PATH = "/learning";

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

  /** The "?" opens the Resource Center, same wired Learning route as the nav item. */
  handleHelpClick() {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: RESOURCE_CENTER_PATH }
    });
  }
}