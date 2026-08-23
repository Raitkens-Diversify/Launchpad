/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Regulated-fields notice for Experience Cloud record pages. Wraps arcInfoBanner
 * with the default copy and Create Envelope action.
 */
import { LightningElement, api } from 'lwc';

const DEFAULT_MESSAGE =
  'Regulated fields cannot be edited. In order to make changes, you will need to create an envelope, make edits and submit an envelope to home office.';

const CREATE_ENVELOPE_LABEL = 'Create Envelope';

export default class ArcRegulatedFieldBanner extends LightningElement {
  @api message = DEFAULT_MESSAGE;
  @api actionLabel = CREATE_ENVELOPE_LABEL;
  @api visible;

  get shouldRender() {
    return this.visible !== false;
  }
}