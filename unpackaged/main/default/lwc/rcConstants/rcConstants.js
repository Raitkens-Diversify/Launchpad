/**
 * rcConstants — the single client-side source for the Resource_Type__c
 * vocabulary (previously copied into four components with two divergent
 * option orders). Server-side mirror: ResourceAdminController.FILE_TYPES —
 * change both together, and only when the picklist changes.
 */

/** Resource_Type__c values, in the canonical display order. */
export const RESOURCE_TYPES = ['PDF', 'Form', 'Video', 'Template', 'External Link'];

/** The subset backed by an uploaded file (download flows key on this). */
export const FILE_TYPES = ['PDF', 'Form', 'Template'];

export const TYPE_VIDEO = 'Video';
export const TYPE_EXTERNAL_LINK = 'External Link';
export const DEFAULT_TYPE = 'PDF';

export function isFileType(resourceType) {
    return FILE_TYPES.includes(resourceType);
}

/** ['A','B'] → combobox options; prepend entries for filter dropdowns. */
export function toOptions(values) {
    return values.map((v) => ({ label: v, value: v }));
}