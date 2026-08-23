import { LightningElement } from 'lwc';
import EMPTY_ACTIONS from '@salesforce/resourceUrl/EmptyActions';

/**
 * Author: Mile Cacanovic
 *
 * envelopeEmptyState — empty-envelope placeholder shown in the content area when no
 * household members or ISAs have been added yet. Illustration + short guidance copy.
 */
export default class EnvelopeEmptyState extends LightningElement {
    illustration = EMPTY_ACTIONS;
}