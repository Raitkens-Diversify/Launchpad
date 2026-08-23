import { LightningElement, api } from "lwc";
import ARC_LOADING_SPINNER from "@salesforce/resourceUrl/arcLoadingSpinner";

const SIZE_CLASS = {
  "xx-small": "arc-loading-spinner__icon--xx-small",
  "x-small": "arc-loading-spinner__icon--x-small",
  small: "arc-loading-spinner__icon--small",
  medium: "arc-loading-spinner__icon--medium",
  large: "arc-loading-spinner__icon--large"
};

/**
 * Drop-in replacement for lightning-spinner using the branded ARC mark
 * instead of the SLDS ring, so a page/section that's still loading reads
 * as "the app is working on it" rather than a stalled blank screen. Same
 * absolute-center-in-nearest-positioned-ancestor behavior as
 * lightning-spinner, so it can swap in wherever that pattern was used
 * (a wrapping container with position:relative and a min-height).
 */
export default class ArcLoadingSpinner extends LightningElement {
  @api alternativeText = "Loading";
  @api size = "medium";

  get iconUrl() {
    return ARC_LOADING_SPINNER;
  }

  get iconClass() {
    const sizeClass = SIZE_CLASS[this.size] || SIZE_CLASS.medium;
    return `arc-loading-spinner__icon ${sizeClass}`;
  }
}