/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-14
 */
import { api } from "lwc";
import LightningModal from "lightning/modal";

export default class SignificantEventCreateActionModal extends LightningModal {
  @api recordId;
  @api editMode = false;

  handleActionClose(event) {
    event?.stopPropagation();
    this.close({
      refreshed: true,
      reason: event?.detail?.reason || "close"
    });
  }
}