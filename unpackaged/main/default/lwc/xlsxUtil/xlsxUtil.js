/**
 * xlsxUtil — load SheetJS from the static resource and turn plain arrays into
 * an .xlsx Blob. Pure service module, no template, no UAT knowledge: it takes
 * [{ name, rows }] and gives back bytes.
 *
 * The library is Apache-2.0 SheetJS Community Edition, mini build (writes
 * .xlsx; no legacy readers, no codepage tables) — see the static resource's
 * description for the pinned version.
 */
import { loadScript } from 'lightning/platformResourceLoader';
import XLSX_RESOURCE from '@salesforce/resourceUrl/xlsx';

/** Excel's own limits, enforced here so a bad sheet name fails at build time
 *  rather than producing a file Excel refuses to open. */
const SHEET_NAME_MAX = 31;
const SHEET_NAME_ILLEGAL = /[[\]:*?/\\]/g;

/**
 * `application/zip`, NOT the OOXML spreadsheet type.
 *
 * Lightning Locker's URL.createObjectURL rejects any Blob outside a fixed MIME
 * allowlist, and 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
 * is not on it — every Excel export died there with a bare "Unsupported MIME
 * type" (see c/csvUtil.objectUrlFor). This is not a workaround dressed as a
 * type: an .xlsx file IS a zip container of XML parts, so 'application/zip'
 * describes these bytes accurately. The '.xlsx' filename on the download
 * attribute is what makes the browser save it correctly and Excel open it.
 */
export const XLSX_BLOB_TYPE = 'application/zip';

/**
 * One shared load per page, not per component instance.
 *
 * Memoised at module scope and cleared on failure so a transient network error
 * doesn't poison every later attempt — the notificationCenter idiom. `loadScript`
 * itself is idempotent per resource, but the promise identity matters: without
 * it, two export buttons clicked in the same tick each start their own load.
 */
let loadPromise;

export function loadXlsx(component) {
    if (!loadPromise) {
        loadPromise = loadScript(component, XLSX_RESOURCE)
            .then(() => assertUsable())
            .catch((error) => {
                loadPromise = undefined;
                throw error;
            });
    }
    return loadPromise;
}

/** Test seam: drops the memo so a suite can assert the load happens once. */
export function resetXlsxForTest() {
    loadPromise = undefined;
}

function getXlsx() {
    return typeof window === 'undefined' ? undefined : window.XLSX;
}

export const XLSX_NOT_LOADED = 'The spreadsheet library did not load — window.XLSX is undefined.';
export const XLSX_NOT_REGISTERED =
    'The spreadsheet library loaded but registered nothing usable — window.XLSX exists with no '
    + 'utils, which means a module loader on the page captured the bundle instead of the global.';

/**
 * The three entry points the writer actually calls.
 *
 * Truthiness is NOT enough, which is the whole reason this exists. The vendor
 * file is a UMD bundle: its tail hands the factory to `define()` when the page
 * has an AMD-style loader and then still runs `window.XLSX = XLSX` — publishing
 * an EMPTY object. A truthiness check passes on that, and the failure then lands
 * an unnamed `TypeError: Cannot read properties of undefined (reading
 * 'book_new')` one line deeper, where no message survives to the user. Verified
 * against the real 279 KB bundle: with `define.amd` present, `window.XLSX` is an
 * object whose `utils`, `write` and `version` are all undefined.
 */
function isUsable(xlsx) {
    return Boolean(
        xlsx && xlsx.utils && xlsx.utils.book_new && xlsx.utils.aoa_to_sheet && xlsx.write
    );
}

/** Named failures for the two distinguishable states, so a toast can say which
 *  one happened instead of "something went wrong". */
function assertUsable() {
    const xlsx = getXlsx();
    if (!xlsx) {
        throw new Error(XLSX_NOT_LOADED);
    }
    if (!isUsable(xlsx)) {
        throw new Error(XLSX_NOT_REGISTERED);
    }
    return xlsx;
}

/**
 * Trim a sheet name to something Excel will actually open.
 *
 * Excel caps names at 31 characters and rejects []:*?/\ outright. A workbook
 * that violates either opens as "unreadable content" with no useful message,
 * so this is a silent repair rather than a throw — the caller's names are
 * hand-written constants, and losing a character off a tab beats losing the file.
 */
export function safeSheetName(name, fallback = 'Sheet') {
    const cleaned = String(name === null || name === undefined ? '' : name)
        .replace(SHEET_NAME_ILLEGAL, ' ')
        .trim();
    return (cleaned || fallback).slice(0, SHEET_NAME_MAX);
}

/**
 * Build the workbook and hand back its bytes.
 *
 * Deliberately NOT XLSX.writeFile: that reaches into `document` to create and
 * click its own anchor, which is precisely the kind of DOM access Lightning Web
 * Security intercepts, and it would give this repo a second download mechanic.
 * We take the array and pass it to c/csvUtil's downloadBlob like everything else.
 *
 * @param sheets [{ name, rows }] where rows is an array of arrays — row 0 is
 *               the header. Empty sheets are kept: a workbook that silently
 *               drops "Findings" reads as "no findings", which is a different
 *               claim from "this tab exists and is empty".
 */
export function sheetsToXlsxBlob(sheets = []) {
    const xlsx = assertUsable();
    const list = (sheets || []).filter(Boolean);
    if (!list.length) {
        throw new Error('There is nothing to export.');
    }
    const book = xlsx.utils.book_new();
    const used = new Set();
    list.forEach((sheet, index) => {
        let name = safeSheetName(sheet.name, `Sheet${index + 1}`);
        // Excel rejects duplicate tab names outright.
        while (used.has(name.toLowerCase())) {
            name = safeSheetName(`${name} ${index + 1}`, `Sheet${index + 1}`);
        }
        used.add(name.toLowerCase());
        xlsx.utils.book_append_sheet(book, xlsx.utils.aoa_to_sheet(sheet.rows || [[]]), name);
    });
    const bytes = xlsx.write(book, { bookType: 'xlsx', type: 'array' });
    return new Blob([bytes], { type: XLSX_BLOB_TYPE });
}

/** `<slug>_<name>_<yyyy-mm-dd>.xlsx` — the workbook's half of the filename
 *  contract csvUtil.csvFilename owns for CSVs. Blank segments are dropped so a
 *  cycle-wide export doesn't carry a stray double underscore. */
export function xlsxFilename(...parts) {
    const segments = parts.map((part) => String(part || '').trim()).filter(Boolean);
    return `${segments.join('_') || 'export'}.xlsx`;
}