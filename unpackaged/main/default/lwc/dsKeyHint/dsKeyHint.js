import { LightningElement, api } from 'lwc';

/**
 * dsKeyHint — small keycap-style label for a keyboard shortcut, hidden on
 * touch devices (no keyboard to hint about). Used by uatRunner.
 */
export default class DsKeyHint extends LightningElement {
    @api letter = '';
}