import { LightningElement, api } from "lwc";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";

/**
 * Reusable 36x36 header icon button (matches arcNavigationButton's sizing).
 * Renders a Phosphor SVG (from the arcicon static resource) via mask-image,
 * same technique as the sidebar nav icons, so color/hover follow currentColor
 * instead of SLDS's icon styling. Inert placeholder until a real
 * destination/action is defined for it.
 */
export default class ArcHeaderIconButton extends LightningElement {
  /** Static-resource filename in the arcicon bundle, e.g. "bell.svg". */
  @api icon = "gear-six.svg";
  @api label = "";

  get iconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${this.icon}');`;
  }
}