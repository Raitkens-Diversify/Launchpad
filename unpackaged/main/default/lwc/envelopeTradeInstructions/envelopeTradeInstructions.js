import { LightningElement, api } from 'lwc';
import {
    COMMIT_IDLE_MS,
    formatMoney,
    normalizeStrategyRows,
    resolveExpectedValue,
    strategyRowsEqual,
    strategyTotals
} from 'c/envelopeFormSchema';

// Buffer keys for the two inputs this component owns directly. The allocation rows buffer inside
// envelopeStrategyList, which owns their inputs.
const EXPECTED = 'expected';
const NOTES = 'notes';

/**
 * envelopeTradeInstructions — the Trade Instructions section body: one Allocations table where
 * fixed-vs-percentage is a per-row attribute (see envelopeStrategyList), and a footer that shows the
 * ledger instead of describing it — account value, minus what the sleeves allocate and minus any
 * excluded sleeves, equals the remaining balance, which reconciles to zero when the account is
 * fully allocated.
 *
 * Controlled by its `value` object ({ expectedAccountValue, strategies, advisorNotes }); emits
 * `tradechange` with the recomputed object. The rows pass through to the table as the one persisted
 * array — nothing is split, so envelopes saved by any previous build keep loading.
 *
 * Every entry point captures an Expected Account Value, because every row needs a denominator: the
 * allocation table shows each sleeve as both a target weight and a dollar figure, and neither can be
 * calculated from the other without one. Where the advisor has not typed a value, `fallbackAccountValue`
 * stands in — the Financial Account's Source of Funds Amount on a new account, the current allocation's
 * expected value on a Manage DMS Instructions case. The fallback is only ever read: it is never written
 * into the draft, so the section keeps tracking its source if that source later changes.
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
 * the calculated cell of any row whose strategy is locked to one unit.
 *
 * I3 — the model base is computed HERE and handed down as one scalar (`allocationBase`), and it
 * lags the table's uncommitted keystrokes by design. Exception sleeves reduce the base every other
 * row's weight is a share of, so their dollars are the one input that legitimately moves other
 * rows' figures. This section does not see the table's `_pending` buffer, so typing in an exception
 * row's amount does NOT move the other rows until that amount commits — on blur, or after the
 * short idle window. **That deferral is deliberate and load-bearing, not a rough edge.** Were the
 * base live per keystroke, one character typed in one row would reassign a calculated cell on every
 * other row, each reassignment answering back with a change event that I1 then has to swallow —
 * N events per keystroke, which is precisely the shape that locked the browser twice on this
 * surface. The base is also passed as a single prop rather than beside the raw account value, so
 * two scalars can never be read in a half-updated pair (see the `allocationBase` prop on
 * envelopeStrategyList).
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
            classification: option.classification,
            excluded: option.excluded === true
        }));
    }

    _options = [];
    _plainOptions = [];

    /**
     * The account value to fall back on where the advisor has not typed an Expected Account Value.
     *
     * Display and derivation only — deliberately never merged into the emitted value. Writing it into
     * the draft would freeze it at whatever the source held the first time this section rendered, and
     * the advisor would have no way to tell an inherited number from one they entered.
     */
    @api fallbackAccountValue;

    // Values typed but not yet committed, keyed by EXPECTED / NOTES. Reactive on purpose: the footer
    // ledger and the allocation status have to move as the advisor types. Each entry holds exactly what
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
        return resolveExpectedValue(this.expectedAccountValue, this.fallbackAccountValue);
    }

    // True while the arithmetic is running on the fallback rather than on a typed figure, which the
    // footer says out loud so an inherited number is never mistaken for an entered one.
    get usingFallback() {
        return (
            this._expectedNumber !== null &&
            // Resolved against no fallback, so a typed figure the resolver would reject anyway
            // (zero, blank, unparseable) counts as nothing typed — the same reading both getters use.
            resolveExpectedValue(this.expectedAccountValue, null) === null
        );
    }

    // Shown in the empty Expected Account Value input so the advisor can see the number the section
    // is already using, without it being submitted as though they had typed it.
    get expectedPlaceholder() {
        const fallback = this._toNumber(this.fallbackAccountValue);
        return fallback === null ? '' : String(fallback);
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
     * that chain, so the list receives a shallow, cheap-to-observe copy. label/value/allowedBasis
     * feed the picker and the basis rule, `excluded` feeds the ledger's excluded split and the row's
     * tag; classification is carried for parity with the source shape.
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
        return strategyTotals(this._rows, this._expectedNumber, this._plainOptions);
    }

    /**
     * The model base the table derives every calculated cell from: the resolved account value less
     * every exception sleeve's dollars. Read straight off the same `strategyTotals` call the footer
     * ledger uses, so no derived cell can run on a different basis than the ledger it reconciles to.
     *
     * Computed HERE rather than in the table, and handed down as a single scalar, because a base the
     * table derived itself would make every row's figures a function of every other row — one
     * keystroke reassigning N calculated cells, which is the echo shape that locked the browser
     * twice. The cost is documented as accepted behavior in the class header: an exception row's
     * dollars do not move the other rows until they commit.
     */
    get allocationBase() {
        return this.totals.allocationBase;
    }

    // --- Footer ------------------------------------------------------------------------------

    // The dollar arithmetic needs a positive account value — typed or inherited.
    get _expectedKnown() {
        return this._expectedNumber !== null;
    }

    get showDollarMath() {
        return this.hasRows && this._expectedKnown;
    }

    // The subtraction lines appear once a finished row actually holds dollars — a "−$0" line for an
    // untouched table would be exactly the $0 noise the footer exists to kill. The total line shows
    // with them: a remaining balance is only meaningful once something subtracts from the account.
    get showLedgerLines() {
        return this.showDollarMath && (this.totals.allocatedAmount > 0 || this.totals.excludedAmount > 0);
    }

    get showAllocatedLine() {
        return this.showDollarMath && this.totals.allocatedAmount > 0;
    }

    // Only where an excluded sleeve holds dollars — the ledger names exclusions, it does not
    // advertise the feature on every table.
    get showExcludedLine() {
        return this.showDollarMath && this.totals.excludedAmount > 0;
    }

    // The model base is a subtotal in the middle of the subtraction, so it earns a line only when
    // something was actually subtracted to produce it. With no exception sleeve it equals the
    // account value on the line above, and printing the same figure twice would read as an error.
    get showModelBaseLine() {
        return this.showExcludedLine;
    }

    get modelBaseDisplay() {
        return this._currency(this.totals.allocationBase);
    }

    get showEnterValueHint() {
        return this.hasRows && !this._expectedKnown;
    }

    // The footer div holds only the dollar ledger and its hint; the percentage status renders in
    // its own always-present live region, so it never forces an empty footer onto a table that has
    // no dollar arithmetic to show yet.
    get showFooter() {
        return this.showDollarMath || this.showEnterValueHint;
    }

    get accountValueDisplay() {
        return this._currency(this._expectedNumber);
    }

    get allocatedDisplay() {
        return `−${this._currency(this.totals.allocatedAmount)}`;
    }

    get excludedDisplay() {
        return `−${this._currency(this.totals.excludedAmount)}`;
    }

    get remainingDisplay() {
        return this._currency(this.totals.remainingBalance);
    }

    // The allocation status, judged the same way completeness is. With an account value known it
    // reads off the ledger — green when the remaining balance reconciles to zero, amber under,
    // amber over too (over-allocation warns without blocking, see strategyTotals). Without one
    // there is no ledger, so the percentage reading stands: green at exactly 100%, amber under,
    // red over — with no denominator the 100% rule is still the blocker.
    get _allocationStatus() {
        const totals = this.totals;
        if (!this.hasRows) {
            return null;
        }
        // Nothing is finished yet, so there is no allocation to report on. A blank row still counts
        // toward hasPercentRows — strategyTotals sets that before it decides the row is incomplete —
        // so without this the section opens under an amber "Allocated: $0.00 remaining" line before
        // the advisor has done anything. Judged here rather than in strategyTotals, where the
        // row counts also feed isComplete.
        if (totals.incompleteRows.length === this._rows.length) {
            return null;
        }
        if (this._expectedKnown) {
            // The exhausted-base state, judged before the ledger: with no model base left, every
            // model weight prices to $0 and the remaining balance reconciles at zero, so the
            // ledger reading would report success on a table where nothing is funded.
            if (totals.hasModelRows && this._cents(totals.allocationBase) <= 0) {
                return {
                    text:
                        'Excluded sleeves use the whole account value — nothing is left to ' +
                        'allocate to the other strategies.',
                    tone: 'warn'
                };
            }
            const balance = totals.remainingBalance;
            // Measured against the model base, which is what the weights are shares of. With no
            // exception sleeve the base IS the account value, so this reads exactly as it did.
            const ofBase = `${this._currency(totals.allocatedAmount)} of ${this._currency(totals.allocationBase)}`;
            const balanceCents = this._cents(balance);
            if (balanceCents === 0) {
                return { text: `Allocated: ${ofBase} ✓`, tone: 'ok' };
            }
            if (balanceCents > 0) {
                return {
                    text: `Allocated: ${ofBase} — ${this._currency(balance)} remaining`,
                    tone: 'warn'
                };
            }
            return {
                text: `Allocated: ${ofBase} — over by ${this._currency(-balance)}`,
                tone: 'warn'
            };
        }
        if (!totals.hasPercentRows) {
            return null;
        }
        const cents = Math.round(totals.percentSum * 100);
        const pct = this._round(totals.percentSum);
        if (cents === 100 * 100) {
            return { text: `Allocated: 100% ✓`, tone: 'ok' };
        }
        if (cents < 100 * 100) {
            return {
                text: `Allocated: ${pct}% — ${this._round(100 - totals.percentSum)}% remaining`,
                tone: 'warn'
            };
        }
        return {
            text: `Allocated: ${pct}% — over by ${this._round(totals.percentSum - 100)}%`,
            tone: 'error'
        };
    }

    get allocationStatusText() {
        return this._allocationStatus?.text ?? '';
    }

    get allocationStatusClass() {
        return `trade__status-line trade__status-line_${this._allocationStatus?.tone ?? 'ok'}`;
    }

    // --- Messages ----------------------------------------------------------------------------

    get showOverFundedWarning() {
        return this.totals.isOverFunded;
    }

    // Names the actual overrun, and names it against the figure it actually overran: the excluded
    // sleeves can exceed the account value, or the model rows can exceed what those sleeves left
    // behind. Reporting the second against the account value would understate it.
    get overFundedMessage() {
        const totals = this.totals;
        const expected = this._expectedNumber;
        const tail = ' You can still submit — the amounts are recorded as entered.';
        if (this._cents(totals.excludedAmount) > this._cents(expected)) {
            return (
                `Excluded sleeves total ${this._currency(totals.excludedAmount)}, more than the ` +
                `${this._currency(expected)} expected account value.${tail}`
            );
        }
        const against =
            totals.excludedAmount > 0
                ? `${this._currency(totals.allocationBase)} left to allocate after excluded sleeves`
                : `${this._currency(totals.allocationBase)} expected account value`;
        return (
            `Allocations total ${this._currency(totals.allocatedAmount)}, more than the ` +
            `${against}.${tail}`
        );
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

    // Cent precision for every comparison the status line and the warning make, matching how
    // strategyTotals judges completeness — so the section can never call a table finished that
    // strategyTotals holds open, or the reverse, over a float artifact. Null reads as zero: an
    // absent figure has not overrun anything.
    _cents(value) {
        return Number.isFinite(value) ? Math.round(value * 100) : 0;
    }

    // Up to four decimals with trailing zeros dropped, matching the table's derived-weight
    // precision, so the status line never rounds a 99.9995% total up to a clean "100%".
    _round(value) {
        return Number.isFinite(value) ? Math.round(value * 10000) / 10000 : 0;
    }

    // Dollars at two decimals in the footer — a ledger asked to reconcile to zero has to show the
    // cents it reconciles at. Shared rounding with the table's read-outs (formatMoney), so the
    // ledger and a row can never disagree about the same figure.
    _currency(value) {
        const amount = Number.isFinite(value) ? value : 0;
        return amount < 0 ? `−$${formatMoney(Math.abs(amount))}` : `$${formatMoney(amount)}`;
    }
}