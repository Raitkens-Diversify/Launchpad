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
    const reason = event?.detail?.reason || "close";
    this.close({
      refreshed: reason === "save" || reason === "delete",
      reason
    });
  }
}