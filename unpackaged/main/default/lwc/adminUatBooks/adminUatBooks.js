import { LightningElement, api } from 'lwc';
import getBooks from '@salesforce/apex/UatBookAdminController.getBooks';
import getBookDetail from '@salesforce/apex/UatBookAdminController.getBookDetail';
import saveBook from '@salesforce/apex/UatBookAdminController.saveBook';
import addCaseToBook from '@salesforce/apex/UatBookAdminController.addCaseToBook';
import removeCaseFromBook from '@salesforce/apex/UatBookAdminController.removeCaseFromBook';
import reorderBookCases from '@salesforce/apex/UatBookAdminController.reorderBookCases';
import runBook from '@salesforce/apex/UatBookAdminController.runBook';
import deleteBook from '@salesforce/apex/UatBookAdminController.deleteBook';
import { messageFrom, toast } from 'c/messageUtil';
import { humanizeCaseCode } from 'c/uatTitleUtil';

/**
 * adminUatBooks — the UAT Test Books section of the Admin Console: list
 * (name, description, case count, Edit, "Run this book") and the book editor
 * (a drill-in page, not a modal — it needs room):
 *  - name/description with explicit Save;
 *  - the usage line naming every cycle that uses this book (blast radius —
 *    clickable navigation lands with the Cycles section phase);
 *  - the dual picker: in-book cases with drag-and-drop run ordering (the
 *    console's reorder control, superseding the spec's arrows) + Remove, and
 *    all other cases with search + System filter + Add.
 *
 * Reorder follows the console's optimistic convention: apply locally, persist
 * with stale-set validation, reload only on failure.
 */
export default class AdminUatBooks extends LightningElement {
    view = 'list'; // list | editor
    bookId = null;

    /** Container-driven deep link (uatnavigate from the Taxonomy section's
     *  Create-book-from-module-group): open straight into a book's editor. */
    @api
    get openBookId() {
        return null;
    }
    set openBookId(value) {
        if (value) {
            this.bookId = value;
            this.view = 'editor';
            this.loadDetail();
        }
    }

    rows = [];
    detail;
    loading = true;
    saving = false;
    errorMessage;

    name = '';
    description = '';
    confirm = null;

    connectedCallback() {
        this.loadList();
    }

    async loadList() {
        this.loading = true;
        try {
            this.rows = await getBooks();
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    async loadDetail() {
        this.loading = true;
        try {
            this.detail = await getBookDetail({ bookId: this.bookId });
            this.name = this.detail.name;
            this.description = this.detail.description || '';
            this.errorMessage = undefined;
        } catch (e) {
            this.errorMessage = messageFrom(e);
        } finally {
            this.loading = false;
        }
    }

    // ---- View machine -------------------------------------------------------------

    get isList() {
        return this.view === 'list';
    }

    get isEditor() {
        return this.view === 'editor';
    }

    get busy() {
        return this.loading || this.saving;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleNewBook() {
        this.bookId = null;
        this.detail = { items: [], candidates: [], usedByCycles: [] };
        this.name = '';
        this.description = '';
        this.view = 'editor';
        this.loading = false;
    }

    handleEdit(event) {
        this.bookId = event.currentTarget.dataset.id;
        this.view = 'editor';
        this.loadDetail();
    }

    handleBack() {
        this.view = 'list';
        this.bookId = null;
        this.detail = undefined;
        this.loadList();
    }

    async handleRunBook(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.saving = true;
        try {
            const cycleId = await runBook({ bookId: id });
            toast(this, 'success', `Cycle "${name} Run" created.`);
            // Land on the new cycle's editor, per spec.
            this.dispatchEvent(new CustomEvent('uatnavigate', {
                detail: { section: 'uatCycles', view: 'editor', recordId: cycleId }
            }));
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    /** Usage line: jump straight to the cycle that uses this book. */
    handleUsageClick(event) {
        this.dispatchEvent(new CustomEvent('uatnavigate', {
            detail: { section: 'uatCycles', view: 'editor', recordId: event.currentTarget.dataset.id }
        }));
    }

    // ---- Editor: fields --------------------------------------------------------------

    get editorTitle() {
        return this.bookId ? 'Edit book' : 'New book';
    }

    get isExistingBook() {
        return this.bookId !== null;
    }

    get hasUsage() {
        return this.detail && this.detail.usedByCycles.length > 0;
    }

    handleNameChange(event) {
        this.name = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    async handleSave() {
        if (!this.name || !this.name.trim()) {
            toast(this, 'error', 'Book name is required.');
            return;
        }
        this.saving = true;
        try {
            // Serialized to JSON: custom-Apex-type @AuraEnabled params arrive
            // null/blank from LWC in this org.
            const savedId = await saveBook({
                inputJson: JSON.stringify({ id: this.bookId, name: this.name, description: this.description })
            });
            const isNew = !this.bookId;
            this.bookId = savedId;
            toast(this, 'success', 'Book saved.');
            if (isNew) {
                await this.loadDetail();
            }
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Editor: dual picker ------------------------------------------------------------

    // Title leads; the Case ID slug demotes to the sublabel, which the
    // picker's search still covers (it matches label + sublabel).
    get pickerSelected() {
        return this.detail
            ? this.detail.items.map((i) => ({
                id: i.id,
                label: i.title || humanizeCaseCode(i.caseCode),
                sublabel: `${i.caseCode} · ${i.moduleName}`
            }))
            : [];
    }

    get pickerAvailable() {
        return this.detail
            ? this.detail.candidates.map((c) => ({
                id: c.id,
                label: c.title || humanizeCaseCode(c.caseCode),
                sublabel: `${c.caseCode} · ${c.moduleName}`,
                systemId: c.systemId
            }))
            : [];
    }

    get pickerSystemOptions() {
        const seen = new Map();
        (this.detail ? this.detail.candidates : []).forEach((c) => {
            if (c.systemId && !seen.has(c.systemId)) {
                seen.set(c.systemId, { label: c.systemName, value: c.systemId });
            }
        });
        return [...seen.values()];
    }

    get pickerDisabled() {
        return !this.bookId;
    }

    async handlePickerAdd(event) {
        this.saving = true;
        try {
            await addCaseToBook({ bookId: this.bookId, caseId: event.detail.id });
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    /** Auto-detach-then-delete in one confirmed action; the copy is built
     *  from the already-on-screen usage line (the server re-checks). */
    handleDeleteBook() {
        const cycles = (this.detail && this.detail.usedByCycles) || [];
        const cases = (this.detail && this.detail.items) ? this.detail.items.length : 0;
        const caseText = `${cases} case link${cases === 1 ? '' : 's'}`;
        const message = cycles.length
            ? `Detaches this book from ${cycles.length} cycle${cycles.length === 1 ? '' : 's'} `
                + `(${cycles.map((c) => c.cycleName).join(', ')}) — unstarted runs from this `
                + 'book are removed from those cycles; claimed, in-progress, and completed '
                + `runs are kept. Then the book and its ${caseText} are deleted. `
                + 'The cases themselves are kept.'
            : `Deletes this book and its ${caseText}. The cases themselves are kept.`;
        this.confirm = {
            action: 'deleteBook',
            header: 'Delete book: ' + this.name,
            message,
            confirmLabel: 'Delete book'
        };
    }

    handlePickerRemove(event) {
        this.confirm = {
            action: 'removeItem',
            itemId: event.detail.id,
            header: 'Remove case: ' + event.detail.label,
            message: 'Cycles using this book will stop showing this case going forward. '
                + 'Execution history that already exists for it is NOT deleted.',
            confirmLabel: 'Remove from book'
        };
    }

    async handlePickerReorder(event) {
        // Optimistic apply (console convention), reload on failure.
        const orderedIds = event.detail.orderedIds;
        const byId = new Map(this.detail.items.map((i) => [i.id, i]));
        this.detail = { ...this.detail, items: orderedIds.map((id) => byId.get(id)) };
        try {
            await reorderBookCases({ bookId: this.bookId, orderedItemIds: orderedIds });
        } catch (e) {
            toast(this, 'error', messageFrom(e));
            await this.loadDetail();
        }
    }

    // ---- Confirm modal ---------------------------------------------------------------------

    get confirmOpen() {
        return this.confirm !== null;
    }

    handleConfirmCancel() {
        this.confirm = null;
    }

    async handleConfirmProceed() {
        this.saving = true;
        try {
            if (this.confirm.action === 'deleteBook') {
                await deleteBook({ bookId: this.bookId });
                this.confirm = null;
                toast(this, 'success', 'Book deleted — its cases are untouched.');
                this.handleBack(); // the record is gone; the editor has nothing to reload
                return;
            }
            await removeCaseFromBook({ bookItemId: this.confirm.itemId });
            this.confirm = null;
            toast(this, 'success', 'Case removed from book.');
            await this.loadDetail();
        } catch (e) {
            toast(this, 'error', messageFrom(e));
        } finally {
            this.saving = false;
        }
    }

    // ---- Internals ------------------------------------------------------------------------------

}