/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-18
 *
 * Date normalization and display helpers scoped to arcRecordDetail — keeps envelopeFormSchema
 * untouched while coercing Apex date shapes for native inputs and read-only rows.
 */

/**
 * Normalize a Salesforce date field value to YYYY-MM-DD without UTC day shifts.
 * @param {*} value
 * @returns {string|null}
 */
export function normalizeIsoDateString(value) {
  if (value === null || value === undefined) {
    return null;
  }
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) {
      return null;
    }
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  const text = String(value).trim();
  if (!text) {
    return null;
  }
  const isoPrefix = text.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (isoPrefix) {
    return `${isoPrefix[1]}-${isoPrefix[2]}-${isoPrefix[3]}`;
  }
  if (/^\d+$/.test(text)) {
    const parsed = new Date(Number(text));
    if (!Number.isNaN(parsed.getTime())) {
      const year = parsed.getFullYear();
      const month = String(parsed.getMonth() + 1).padStart(2, '0');
      const day = String(parsed.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    }
  }
  return null;
}

/**
 * Format a date value as MM/DD/YYYY for read-only record-detail rows.
 * @param {*} value
 * @returns {string}
 */
export function formatDateDisplayValue(value) {
  const iso = normalizeIsoDateString(value);
  if (!iso) {
    if (value === null || value === undefined || value === '') {
      return '';
    }
    return String(value);
  }
  const parts = iso.split('-');
  return `${parts[1]}/${parts[2]}/${parts[0]}`;
}

/**
 * Coerce loaded record values so date fields bind as YYYY-MM-DD in the draft.
 * @param {object} values  field apiName → value
 * @param {Array} sections  schema sections from ArcRecordDetailController.load
 * @returns {object}
 */
export function normalizeLoadedFieldValues(values = {}, sections = []) {
  const typeByField = new Map();

  for (const section of sections) {
    for (const field of section?.fields || []) {
      if (field?.fieldPath && field?.type) {
        typeByField.set(field.fieldPath, field.type);
      }
    }
  }

  const next = { ...values };

  for (const [apiName, raw] of Object.entries(next)) {
    if (typeByField.get(apiName) !== 'DATE' || raw === null || raw === '') {
      continue;
    }
    const iso = normalizeIsoDateString(raw);
    if (iso) {
      next[apiName] = iso;
    }
  }

  return next;
}