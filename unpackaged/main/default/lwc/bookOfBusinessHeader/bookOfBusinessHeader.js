/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-22
 */
import { LightningElement, api } from "lwc";

export default class BookOfBusinessHeader extends LightningElement {
  @api title;
  @api subtitle;
  @api accountCount;
  @api totalAumLabel;
}