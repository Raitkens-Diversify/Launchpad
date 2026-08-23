/**
 * csvUtil — RFC 4180 CSV serialisation, filename construction, and browser
 * download. Pure module, no template — the uatCardUtil pattern: one owner for
 * anything two components would otherwise copy.
 *
 * Written for the Admin Console's Cycle Report export (adminUatReport), which
 * is the first surface in this org to produce a file. The serialiser in
 * bookOfBusinessUtils predates it and has never been called; this module fixes
 * two things that file would have shipped — the escape test omits \r, and the
 * cell resolver routes currency columns through a lossy compact formatter. An
 * export of a compliance record must never round.
 */

/** Cells are quoted only when they have to be. Embedded quotes double per RFC
 *  4180. \r is in the test deliberately: a value carrying a bare CR or a CRLF
 *  breaks the file open at the next row boundary if it escapes unquoted, and
 *  UAT long-text arrives with whatever line endings the tester's browser sent. */
export function escapeCsvValue(value) {
    // Not `value || ''` — 0 and false are real cell values.
    const text = value === null || value === undefined ? '' : String(value);
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/**
 * Serialise rows to CSV text. Always emits the header row, even for no data —
 * an empty export should still say what it was an export of.
 *
 * @param rows    array of plain objects
 * @param columns [{ label, fieldName }] or [{ label, value: (row) => any }].
 *                `value` wins when both are present, so a column can compute
 *                without the caller pre-flattening every row.
 * @param options { lineTerminator } — defaults to CRLF per RFC 4180 (Excel on
 *                Windows). bookOfBusinessUtils passes '\n' to keep its bytes.
 */
export function buildCsvContent(rows = [], columns = [], options = {}) {
    const terminator = options.lineTerminator || '\r\n';
    const cols = columns || [];
    const header = cols.map((column) => escapeCsvValue(column.label)).join(',');
    const lines = (rows || []).map((row) =>
        cols.map((column) => escapeCsvValue(cellValue(row, column))).join(',')
    );
    return [header, ...lines].join(terminator);
}

/** Resolve one column against one row. Exported because the workbook builder
 *  writes the same column specs into spreadsheet cells — two resolvers would
 *  eventually disagree about which one a column meant. */
export function cellValue(row, column) {
    if (!row || !column) {
        return '';
    }
    if (typeof column.value === 'function') {
        return column.value(row);
    }
    return row[column.fieldName];
}

/**
 * MIME types Lightning Locker is known to permit through createObjectURL.
 *
 * Ordered by how truthful they are about arbitrary bytes: an .xlsx really is a
 * zip container, and text/plain is the last resort. Both are safe substitutes
 * because the anchor's `download` attribute is what names the file and decides
 * which application opens it — the Blob's type never reaches the saved bytes.
 */
const SAFE_TYPES = ['application/zip', 'text/plain'];

/**
 * A Blob URL, or a named failure.
 *
 * Lightning Locker distorts URL.createObjectURL and rejects any Blob whose MIME
 * type is outside a fixed allowlist, throwing a bare "Unsupported MIME type"
 * that names neither the type nor the caller. That is what broke the Cycle
 * Report's Excel export from the day it shipped (this org runs Locker, not LWS:
 * Security settings, lockerServiceNext = false) and it will break the next
 * surface that invents a MIME type unless the retry and the error are both here.
 *
 * Re-wrapping preserves the bytes exactly — new Blob([blob]) copies the data —
 * so a fallback changes the declared type and nothing else.
 */
function objectUrlFor(blob) {
    const attempts = [blob.type, ...SAFE_TYPES.filter((t) => t !== blob.type)];
    let lastError;
    for (let i = 0; i < attempts.length; i++) {
        const type = attempts[i];
        try {
            return URL.createObjectURL(i === 0 ? blob : new Blob([blob], { type }));
        } catch (error) {
            lastError = error;
            // eslint-disable-next-line no-console
            console.warn(`[csvUtil] createObjectURL refused MIME type "${type}"`, error);
        }
    }
    throw new Error(
        `This browser session refused to download a "${blob.type}" file `
        + `(tried ${attempts.map((t) => `"${t}"`).join(', ')}). `
        + `Lightning Locker permits only a fixed set of file types. `
        + `Underlying error: ${(lastError && lastError.message) || 'unknown'}`
    );
}

/**
 * Save any Blob under the given filename.
 *
 * The org's one download mechanic. It lives here rather than beside the
 * spreadsheet writer because a repo with two of these grows a third: SheetJS
 * ships its own XLSX.writeFile that reaches into `document` itself, and
 * c/xlsxUtil deliberately does not call it — it hands the bytes here instead.
 */
export function downloadBlob(filename, blob) {
    if (typeof document === 'undefined' || !blob) {
        return;
    }
    const url = objectUrlFor(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.style.visibility = 'hidden';
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
}

/**
 * Save one CSV under the given filename.
 *
 * @param options { bom } — a UTF-8 BOM is prepended by default. Excel on
 *                Windows reads a BOM-less file as the system codepage, which
 *                mangles the U+203A separators in module paths. The BOM lives
 *                here rather than in buildCsvContent so the serialiser stays
 *                byte-clean and assertable.
 */
export function downloadCsv(filename, content, options = {}) {
    const parts = options.bom === false ? [content] : ['﻿', content];
    downloadBlob(filename, new Blob(parts, { type: 'text/csv;charset=utf-8;' }));
}

/** `<slug>_<grain>_<yyyy-mm-dd>.csv` — the export filename contract. */
export function csvFilename(slug, grain, dateIso) {
    return `${slug || 'export'}_${grain}_${dateIso}.csv`;
}

/** Full ISO 8601 UTC for real Datetimes. '' for anything unparseable, so a
 *  bad value leaves a blank cell rather than the string 'Invalid Date'. */
export function isoDateTime(value) {
    if (!value) {
        return '';
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? '' : date.toISOString();
}

/** Date-only, by slice — never by Date parse. Salesforce Date fields arrive as
 *  'YYYY-MM-DD' and new Date(iso) reads them as UTC midnight, which renders as
 *  the previous day west of Greenwich (the bug uatCardUtil.parseLocalDate
 *  exists for). A CSV must not shift a date by a day depending on who opens it. */
export function isoDate(value) {
    if (!value) {
        return '';
    }
    if (value instanceof Date) {
        return Number.isNaN(value.getTime()) ? '' : value.toISOString().slice(0, 10);
    }
    return String(value).slice(0, 10);
}

/** Uppercase TRUE/FALSE — Excel reads those as booleans, 'true'/'Yes' as text.
 *  null stays blank: "not applicable" and "false" are different answers. */
export function csvBoolean(value) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    return value ? 'TRUE' : 'FALSE';
}