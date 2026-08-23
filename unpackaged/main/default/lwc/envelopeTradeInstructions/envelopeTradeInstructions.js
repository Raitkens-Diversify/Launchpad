import { LightningElement, api } from 'lwc';
import {
    COMMIT_IDLE_MS,
    normalizeStrategyRows,
    strategyRowsEqual,
    strategyTotals
} from 'c/envelopeFormSchema';

// Buffer keys for the two inputs this component owns directly. The allocation rows buffer inside
// envelopeStrategyList, which owns their inputs.
const EXPECTED = 'expected';
const NOTES = 'notes';

/**
 * envelopeTradeInstructions — the Trade Instructions section body: one Allocations table where
 * fixed-vs-modeled is a per-row attribute (see envelopeStrategyList), and a footer that shows the
 * remainder arithmetic instead of describing it — account value, minus the fixed carve-outs, equals
 * the modeled pool the percentage rows must cover.
 *
 * Controlled by its `value` object ({ expectedAccountValue, strategies, advisorNotes }); emits
 * `tradechange` with the recomputed object. The rows pass through to the table as the one persisted
 * array — nothing is split, so envelopes saved by any previous build keep loading.
 *
 * `funded` reflects the entry point. New Account setup and Change Management style establish an
 * account value, so the Expected Account Value is captured and the footer can do the dollar math.
 * Editing existing Trade Instructions has no funded amount available, so that field and every
 * dollar figure are absent there rather than computed from a number we don't have.
 *
 * ---
 *
 * Two invariants hold this section together. They are the reason it is built this way, and undoing
 * either one reintroduces a browser-locking loop rather than a cosmetic bug.
 *
 * I1 — No echo may become an edit. A reported value equal to the one already held must not propagate.
 * Guarded here, in envelopeStrategyList, in envelopeFieldControl and again in
 * envelopeActionDetails.handleFieldChange, so no single guard is load-bearing.
 *
 * I2 — While a control is being edited, the value bound to it is exactly what that control last
 * reported. Typing buffers into `_pending` verbatim — never parsed, never reformatted — and the
 * template hands that same value straight back, so the prop patch is provably a no-op. The commit
 * (blur, or a short idle window) is the only moment a parsed value reaches the draft. I2 must also
 * hold at the commit boundary: once the buffer empties, the bound value is the committed value
 * rendered back to the string form the control reported — a fall-back to the parsed number would
 * flip the bound type, reassign the input, and a base input answers a programmatic assignment with
 * another change event. This is also
 * why neither editable input carries `formatter="currency"`: a formatter makes the displayed value a
 * function of the bound value rather than a copy of it, which makes I2 unachievable by construction.
 * Formatted figures are read-outs and live in read-only text — the footer ledger below the input, and
 * each row's Est. dollars cell.
 */
export default class EnvelopeTradeInstructions extends LightningElement {
    /**
     * { expectedAccountValue, strategies: [...], advisorNotes }.
     *
     * Accessors rather than a plain field so an emit can be remembered until the owner acknowledges it.
     * A commit reaches the draft synchronously, but the resulting prop write comes back on a later
     * render — so two commits in one turn (which is exactly what flushPendingEdits does when the
     * advisor typed an amount and a note and then navigated away) would both build on the same stale
     * object, and the second would silently revert the first. `_emittedValue` closes that window and the
     * setter drops it the moment the owner speaks, so the owner stays the source of truth.
     */
    @api
    get value() {
        return this._value;
    }

    set value(next) {
        this._value = next;
        this._emittedValue = null;
    }

    _value = {};
    _emittedValue = null;

    // The value to build the next edit from: what we last emitted if the owner has not answered yet,
    // otherwise what the owner holds.
    get _current() {
        return this._emittedValue || this._value || {};
    }

    // All strategy options: [{ label, value, allowedBasis }]. An accessor so the plain copy the
    // template hands out (pickerOptions) and the label index are rebuilt exactly once per real prop
    // write — the engine only patches a prop when its identity changes, and the shell assigns
    // strategyOptions wholesale rather than mutating it in place. Rebuilding here instead of in a
    // render-time getter is what keeps a keystroke from re-walking the membrane.
    @api
    get options() {
        return this._options;
    }

    set options(next) {
        this._options = next;
        // Named field access only — Object.keys would walk the membrane's internals.
        this._plainOptions = (next || []).map((option) => ({
            label: option.label,
            value: option.value,
            allowedBasis: option.allowedBasis,
            classification: option.classification
        }));
        this._labelByValue = new Map(
            this._plainOptions.map((option) => [option.value, option.label])
        );
    }

    _options = [];
    _plainOptions = [];
    _labelByValue = new Map();

    // Whether this entry point has a funded amount to work from.
    @api funded = false;

    // Values typed but not yet committed, keyed by EXPECTED / NOTES. Reactive on purpose: the footer
    // ledger and the modeled-% status have to move as the advisor types. Each entry holds exactly what
    // the control reported (see I2) — the parsing happens at commit, not here.
    _pending = {};

    // Commit timers, held in a plain object whose properties are mutated so arming one never triggers
    // a re-render. Deliberately not a class field per timer: a field write is reactive.
    _timers = { byId: {} };



    disconnectedCallback() {
        Object.keys(this._timers.byId).forEach((id) =>
            clearTimeout(this._timers.byId[id])
        );
        this._timers.byId = {};
    }

    get expectedAccountValue() {
        if (EXPECTED in this._pending) {
            return this._pending[EXPECTED];
        }
        // Always a string (or null). The commit empties the buffer, and falling back to the committed
        // NUMBER here would flip the bound value's type — a changed prop is reassigned into the input,
        // and a base input answers a programmatic assignment with another change event, once per idle
        // window. Rendered back as the string the input reported, the patch is identity-equal and the
        // input is never touched. See I2.
        const committed = this._current.expectedAccountValue;
        return committed === null || committed === undefined ? null : String(committed);
    }

    get advisorNotes() {
        return NOTES in this._pending
            ? this._pending[NOTES]
            : this._current.advisorNotes || '';
    }

    // The expected value the arithmetic runs on: the buffered figure while the advisor is typing, so
    // the ledger tracks the keystrokes rather than lagging a commit behind them.
    get _expectedNumber() {
        return this._toNumber(this.expectedAccountValue);
    }

    get rows() {
        return this._rows;
    }

    /**
     * A plain, un-proxied copy of the strategy options for the allocation list.
     *
     * `options` reaches this section as a reactive proxy that has been re-wrapped at every @api hop
     * from the shell down (shell → action-details → form-section → here). Handing that already
     * deeply-nested proxy straight to envelopeStrategyList — one hop deeper again, and read per row by
     * its picker — made LWC's reactive membrane recurse on element access for several seconds, a
     * synchronous freeze the moment the section mounted. Rebuilding the array as plain objects severs
     * that chain, so the list receives a shallow, cheap-to-observe copy. Only label/value/allowedBasis
     * are load-bearing (the picker and the basis rule); classification is carried for parity with the
     * source shape.
     *
     * Built in the options setter, not here: typing re-renders this section per character, and a fresh
     * copy per render would both re-walk the membrane every time and patch the table's `options` prop
     * with a new identity — re-rendering every row and its picker per keystroke, which is the same
     * freeze paid on the typing path instead of at mount. This copy is identity-stable until the
     * options actually change.
     */
    get pickerOptions() {
        return this._plainOptions;
    }

    get hasRows() {
        return this._rows.length > 0;
    }

    get totals() {
        return strategyTotals(this._rows, this.funded ? this._expectedNumber : null);
    }

    // The dollars left for the percentage sleeves once the carve-outs are taken out. Null where no
    // funded amount exists, which keeps every derived figure out of that entry point.
    get remainder() {
        return this.funded ? this.totals.remainder : null;
    }

    // --- Footer ------------------------------------------------------------------------------

    // The dollar arithmetic needs a positive account value; strategyTotals resolves the remainder
    // only then, so its null doubles as "nothing to compute from yet".
    get _expectedKnown() {
        return this.funded && this.totals.remainder !== null;
    }

    get showDollarMath() {
        return this.hasRows && this._expectedKnown;
    }

    // The subtraction lines appear once a fixed-dollar amount is actually entered — a "−$0" line
    // for a table with no carve-outs would be exactly the $0 noise the footer exists to kill.
    get showFixedLines() {
        return this.showDollarMath && this.totals.fixedDollarSum > 0;
    }

    get showEnterValueHint() {
        return this.hasRows && this.funded && !this._expectedKnown;
    }

    // The footer div holds only the dollar ledger and its hint; the percentage status renders in
    // its own always-present live region, so it never forces an empty footer into unfunded mode.
    get showFooter() {
        return this.showDollarMath || this.showEnterValueHint;
    }

    get accountValueDisplay() {
        return this._currency(this._expectedNumber);
    }

    get fixedDisplay() {
        return `−${this._currency(this.totals.fixedDollarSum)}`;
    }

    get poolDisplay() {
        return this._currency(this.totals.remainder);
    }

    // The modeled-allocation status: green at exactly 100%, amber under, red over — over-allocation
    // blocks (percentage rows must total 100%), so red is consistent with the submit rule.
    get _modeledStatus() {
        const totals = this.totals;
        if (!this.hasRows || !totals.hasPercentRows) {
            return null;
        }
        const cents = Math.round(totals.percentSum * 100);
        const pct = this._round(totals.percentSum);
        if (cents === 100 * 100) {
            const pool =
                this._expectedKnown && totals.remainder >= 0
                    ? ` (${this._currency(totals.remainder)})`
                    : '';
            return { text: `Modeled allocated: 100%${pool} ✓`, tone: 'ok' };
        }
        if (cents < 100 * 100) {
            return {
                text: `Modeled allocated: ${pct}% — ${this._round(100 - totals.percentSum)}% remaining to allocate`,
                tone: 'warn'
            };
        }
        return {
            text: `Modeled allocated: ${pct}% — over-allocated by ${this._round(totals.percentSum - 100)}%`,
            tone: 'error'
        };
    }

    get modeledStatusText() {
        return this._modeledStatus?.text ?? '';
    }

    get modeledStatusClass() {
        return `trade__status-line trade__status-line_${this._modeledStatus?.tone ?? 'ok'}`;
    }

    // --- Messages ----------------------------------------------------------------------------

    // The section explains itself only once the advisor has engaged, so an untouched section
    // doesn't open under a red alert. Decided from the memoized totals rather than by building
    // mismatchMessage — the template already evaluates the message once where it shows it, and this
    // getter runs on every render.
    get showMismatch() {
        return this._touched && this.totals.incompleteRows.length > 0;
    }

    get showOverFundedWarning() {
        return this.funded && this.totals.isOverFunded;
    }

    // Names the sleeves that still need input, so the advisor knows where to look. The percentage
    // total no longer needs a sentence here — the footer status carries that arithmetic live.
    get mismatchMessage() {
        const unfinished = this.totals.incompleteRows;
        if (!unfinished.length) {
            return '';
        }
        const named = unfinished.map((row) => this._strategyLabel(row)).filter(Boolean);
        const subject = named.length
            ? named.join(', ')
            : `${unfinished.length} ${unfinished.length === 1 ? 'sleeve' : 'sleeves'}`;
        return `Needs a strategy and an amount: ${subject}.`;
    }

    get overFundedMessage() {
        const totals = this.totals;
        return `Fixed-dollar sleeves total ${this._currency(totals.fixedDollarSum)}, more than the ${this._currency(
            this._expectedNumber
        )} expected account value. You can still submit — the amounts are recorded as entered.`;
    }

    // --- Editing --------------------------------------------------------------------------------

    // Typing buffers and arms a commit; it does not propagate. See I2: the value goes in verbatim and
    // the template hands that same value back to the same control, so nothing is ever pushed into an
    // input the user is working in.
    handleExpectedChange(event) {
        this._buffer(EXPECTED, event.detail.value);
    }

    // Leaving the field commits. The idle timer is the fallback for a blur that never comes — the
    // footer ledger and the section's completion dot shouldn't wait on one.
    handleExpectedBlur() {
        this._commitExpected();
    }

    handleNotesChange(event) {
        this._buffer(NOTES, event.detail.value);
    }

    handleNotesBlur() {
        this._commitNotes();
    }

    // The table has already decided this is a real edit — it emits only when a row actually changed.
    // Compared again here anyway: I1 holds at every hop, so a regression in the table cannot on its own
    // reopen the loop. The comparison has to be by value, not identity: the rows the table reports are
    // its own objects, normalized from the read-only view it was handed, so they are never the same
    // objects these are (see strategyRowsEqual).
    handleRowsChange(event) {
        const strategies = event.detail?.strategies || [];
        if (strategyRowsEqual(strategies, this._rows)) {
            return;
        }
        this._touched = true;
        this._emit({ ...this._current, strategies });
    }

    /**
     * Commit everything still buffered here and in the allocation table, so a save or a validity sweep
     * never misses the last thing typed. Called by envelopeFormSection on behalf of
     * envelopeActionDetails.getFormData / reportValidity and the shell's pending-save flush.
     */
    @api
    flushPendingEdits() {
        this._commitExpected();
        this._commitNotes();
        const table = this.refs?.table;
        if (table && typeof table.flushPendingEdits === 'function') {
            // The table's commit comes back through handleRowsChange, which rebuilds from `_current` —
            // so it carries the two commits above rather than overwriting them.
            table.flushPendingEdits();
        }
    }

    _touched = false;

    _buffer(id, reported) {
        // I1 at the buffer hop: an echo of the value already bound to the control must not reassign
        // the reactive buffer (a render per echo) nor postpone the armed commit.
        const bound = id === EXPECTED ? this.expectedAccountValue : this.advisorNotes;
        if (reported === bound) {
            return;
        }
        this._pending = { ...this._pending, [id]: reported };
        clearTimeout(this._timers.byId[id]);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timers.byId[id] = setTimeout(() => {
            if (id === EXPECTED) {
                this._commitExpected();
            } else {
                this._commitNotes();
            }
        }, COMMIT_IDLE_MS);
    }

    // Take a buffered entry out of the buffer and hand it back. Clearing before the caller emits is
    // what makes flushPendingEdits re-entrant: the commit's own event can travel all the way back
    // around into another flush, and it must find nothing left to do.
    _takePending(id) {
        clearTimeout(this._timers.byId[id]);
        delete this._timers.byId[id];
        if (!(id in this._pending)) {
            return { has: false, reported: undefined };
        }
        const reported = this._pending[id];
        const { [id]: _dropped, ...rest } = this._pending;
        this._pending = rest;
        return { has: true, reported };
    }

    _commitExpected() {
        const { has, reported } = this._takePending(EXPECTED);
        if (!has) {
            return;
        }
        const expectedAccountValue = this._toNumber(reported);
        if (expectedAccountValue === (this._current.expectedAccountValue ?? null)) {
            return;
        }
        this._touched = true;
        this._emit({ ...this._current, expectedAccountValue });
    }

    _commitNotes() {
        const { has, reported } = this._takePending(NOTES);
        if (!has) {
            return;
        }
        const advisorNotes = reported || '';
        if (advisorNotes === (this._current.advisorNotes || '')) {
            return;
        }
        this._emit({ ...this._current, advisorNotes });
    }

    get _rows() {
        return normalizeStrategyRows(this._current.strategies);
    }

    // Label lookup goes through the index built in the options setter — never through `this.options`,
    // whose per-element reads cross the reactive membrane (see pickerOptions).
    _strategyLabel(row) {
        return this._labelByValue.get(row.strategy) || '';
    }

    // Uniquely named (not 'change') so the parent's listener isn't also triggered by the bubbling,
    // composed 'change' events of the inner base inputs — which would overwrite the value with a raw string.
    _emit(value) {
        // Held so a second commit in the same turn builds on this rather than on the prop the owner has
        // not written back yet. Dropped by the `value` setter as soon as the owner answers.
        this._emittedValue = value;
        this.dispatchEvent(new CustomEvent('tradechange', { detail: { value } }));
    }

    _toNumber(value) {
        if (value === '' || value === null || value === undefined) {
            return null;
        }
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }

    _round(value) {
        return Number.isFinite(value) ? Math.round(value * 100) / 100 : 0;
    }

    // Whole dollars in the footer: the arithmetic is a read-out, and cents would only add noise.
    _currency(value) {
        const amount = Number.isFinite(value) ? Math.round(value) : 0;
        return amount < 0
            ? `−$${Math.abs(amount).toLocaleString('en-US')}`
            : `$${amount.toLocaleString('en-US')}`;
    }
}