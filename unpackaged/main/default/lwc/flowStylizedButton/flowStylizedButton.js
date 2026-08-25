/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * LWC port of cmp_FlowStylizedButton for screen flows in LWR / Experience Cloud.
 */
import { LightningElement, api } from "lwc";
import {
  FlowAttributeChangeEvent,
  FlowNavigationNextEvent,
  FlowNavigationPauseEvent,
} from "lightning/flowSupport";

const CLICKABLE_BUTTON_TYPES = new Set([
  "Active Button",
  "Pause Button",
  "Link Button",
  "Link",
]);

export default class FlowStylizedButton extends LightningElement {
  @api ButtonText;
  @api ButtonType;
  @api Size;
  @api ValueClicked;

  get buttonClass() {
    const type = this.ButtonType;
    const size = this.Size;

    if (type === "Link") {
      return "linkButton";
    }

    if (size === "Large") {
      if (type === "Blank Button") {
        return "blankButton";
      }
      if (type === "Inactive Button") {
        return "largeButtonInactive";
      }
      return "largeButton";
    }

    if (size === "Medium") {
      return "mediumButton";
    }

    return "smallButton";
  }

  get isDisabled() {
    return this.ButtonType === "Inactive Button";
  }

  get isClickable() {
    return CLICKABLE_BUTTON_TYPES.has(this.ButtonType);
  }

  handleClick() {
    if (!this.isClickable || this.isDisabled) {
      return;
    }

    if (this.ButtonType === "Link Button") {
      if (this.ValueClicked) {
        window.open(this.ValueClicked, "_blank", "noopener,noreferrer");
      }
      return;
    }

    this.dispatchEvent(
      new FlowAttributeChangeEvent("ValueClicked", this.ButtonText)
    );

    if (this.ButtonType === "Pause Button") {
      this.dispatchEvent(new FlowNavigationPauseEvent());
      return;
    }

    this.dispatchEvent(new FlowNavigationNextEvent());
  }
}