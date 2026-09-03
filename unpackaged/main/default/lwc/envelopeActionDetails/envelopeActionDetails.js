import { LightningElement, api } from "lwc";
import {
  RELATED_PARTIES_FIELD_KEY,
  waivedRelatedPartyKeys,
  ACCOUNT_GROUP_IDS,
  isDmsPlatform,
  shapeVisibleFields,
  clearHiddenAnswers,
  clearDependentCustodian,
  hasPriorAnswer,
  draftValuesEqual,
  sectionStatus,
  markUpdatedFields,
  resolveRelatedPartyRequirements,
  relatedPartyPeers,
  relatedPartiesStatus,
  resolveExpectedValue,
  strategyTotals,
  STRATEGY_BASIS,
  actionCompletion
} from "c/envelopeFormSchema";

/**
 * Author: Mile Cacanovic
 *
 * envelopeActionDetails — the action-details (interview) page shown in place of the workspace when an
 * action card is opened. Its layout is a pinned header over two independently-scrolling panes: a
 * reusable Table-of-Contents rail (envelopeToc) on the left and the metadata-driven form on the right.
 *
 * The `sections` prop carries the ordered Envelope_Field__mdt schema for the entity's record type.
 * Field visibility follows each field's Shown WHERE statement, re-evaluated against the local form
 * draft as values change. Record types are still flat today, so the sections are wrapped under one
 * synthetic parent group to exercise the nested TOC; when metadata gains real grouping only the
 * `groups` transform changes. The TOC drives navigation — clicking a section scrolls it into view, and
 * scrolling the form moves the active marker (scroll-spy) — and shows a per-section completion dot.
 * Re-dispatches `back` to the shell.
 */

// Distance below the form pane's top edge where a section becomes "active": as the form scrolls, the
// active section is the last one whose top has crossed this line (a stable top-of-pane scroll spy).
const SPY_ACTIVATION_OFFSET = 96;

// Idle window after the last scroll frame before the scroll spy resumes. While a TOC click animates the
// scroll, the spy is suppressed so the marker jumps straight to the clicked section instead of ticking
// through the ones it passes; it resumes this long after the programmatic scroll settles.
const SPY_IDLE_MS = 150;

// Separator appended to the Related Parties section key to key each per-role TOC leaf. The base
// section keys never contain it, so key.split(ROLE_KEY_SEP)[0] recovers the section's scroll anchor.
const ROLE_KEY_SEP = "::rp::";

// The Trade Instructions section, shown for a Financial Account whose Managed Account Platform is a
// DMS platform (DMS or DMS (Wrap)); the platform is read live from the form draft, so the section
// appears and disappears as that selection changes. Its whole value persists under this draft key as
// one JSON object. The default carries one empty, non-removable strategy row.
const TRADE_FIELD_KEY = "tradeInstructions";

// The Financial Account field whose selected value gates the Trade Instructions section. The draft is
// keyed by field API name, so this doubles as the draft lookup key.
const MANAGED_ACCOUNT_PLATFORM_FIELD = "Managed_Account_Platform__c";
const DEFAULT_TRADE = {
  expectedAccountValue: null,
  strategies: [
    {
      id: "s-1",
      strategy: "",
      type: STRATEGY_BASIS.PERCENT,
      fundingAmount: null,
      fundingPercent: null
    }
  ],
  advisorNotes: ""
};

// The cases-group action types whose interviews also carry Trade Instructions. Update DMS
// Instructions edits an existing account's sleeve allocation (seeded by the shell from the account's
// current instructions, expected account value included); Update Management Style moves the account
// onto a managed platform. Both capture an Expected Account Value, as New Account setup does.
const DMS_UPDATE_CASE_TYPE = "updateDmsInstructions";
const MANAGEMENT_STYLE_CASE_TYPE = "updateManagementStyle";

// The draft keys the Trade Instructions section falls back to when no Expected Account Value has
// been typed, tried in order. The draft is keyed by field API name — the same convention as
// MANAGED_ACCOUNT_PLATFORM_FIELD. The org's live ISA - Fin Acct form captures the source-of-funds
// amount as Case Amount__c in its "Source of Funds" section (Envelope_Field ISA_SOF_Amount) — the
// Source_of_Funds_Amount__c form field exists only in this repo, its CMDT record was deleted
// org-side — so both are tried; entity types with neither rely on the typed figure.
const SOURCE_OF_FUNDS_AMOUNT_FIELDS = ["Source_of_Funds_Amount__c", "Amount__c"];

export default class EnvelopeActionDetails extends LightningElement {
  // The opened action's context: { actionId, entityId, entityName, entityType, entityGroupId,
  // actionTitle, statusLabel }. `entityType` and `entityGroupId` together identify the record type,
  // selecting which custom sections apply.
  @api action;

  // The envelope's household, so the Related Parties section's "Select Existing" picker can be
  // scoped to parties already linked to this household rather than the user's whole book.
  @api householdId;

  // The current envelope, so the "Select Existing" picker can still offer a member just added to
  // this envelope (and never a still-in-progress draft from a different, unrelated envelope).
  @api envelopeId;

  // Ordered form schema for the entity's record type: [{ name, fields: [FieldMetadata] }].
  // Empty when the type has no configured fields (renders the empty state).
  @api sections = [];

  // Section layout for the entity's record type: [{ parentName, parentOrder, childSections }] from
  // Section__mdt, grouping the flat sections under ordered parent sections. Null when the type has no
  // configured layout (the form then renders a single default group).
  @api sectionLayout;

  // The saved form values for this action (from the shell's model), used to prefill the draft when
  // the action opens. Empty for an untouched action.
  @api savedValues;

  // The frozen values this action's request started from, keyed by field API name — the comparison
  // point behind the "Updated" markers on the header badge, the section headings and the individual
  // fields. Only an action item raised against an existing member carries one; null everywhere else,
  // which renders the page exactly as it did before.
  @api originalValues = null;

  // The shell's progressive save-status ('idle' | 'pending' | 'saving' | 'saved'), passed through to
  // the TOC's save indicator (the save-status state machine lives in the shell).
  @api saveStatus;

  // Registration_Type__mdt attributes keyed by registration value, prefetched by the shell. Selects
  // which related parties a Financial Account owes; unused by household member actions, which
  // resolve their parties from the member type instead.
  @api registrationAttributes;

  // Running-user attributes for `$User.<field>` WHERE conditions (e.g. a field shown only when
  // `$User.Relationship_to_Firm__c = 'Dual'`). Supplied by the shell; forwarded into shapeVisibleFields.
  @api userContext = {};

  // Strategy__c options for the Trade Instructions sleeve rows: [{ label, value }] with the record
  // Id as value. Prefetched once by the shell and threaded through the trade section node.
  @api strategyOptions = [];

  // Working values keyed by field API name. Seeded from savedValues when the action opens; drives
  // conditional field visibility and section completion, and is the source the shell pulls to save.
  draft = {};

  // The active section's key (bound to the TOC's active marker and the form's active-section marker).
  // Seeded to the first section and updated on TOC selection or scroll.
  activeKey;

  // The action id the draft was last seeded for, so a re-render (or the shell writing back this same
  // action's saved values) doesn't reseed and clobber in-progress edits.
  _seededActionId;

  // A Key Point edit held back while its confirmation dialog is open: { field, value }, applied on
  // confirm and dropped on cancel.
  _pendingKeyPoint = null;

  // Scroll-spy plumbing: the form pane currently listened to, and a flag coalescing scroll events
  // into one measurement per animation frame.
  _scrollPane;
  _spyScheduled = false;

  // While a TOC click animates the scroll, the spy is suppressed so the clicked section stays active;
  // an idle timer resumes it once the programmatic scroll settles.
  _spySuppressed = false;
  _spyIdleTimer = null;

  // The last built `groups` view-model and the inputs it was built from (compared by identity).
  //
  // Deliberately one plain object whose *properties* are mutated, not two class fields. Class fields
  // are reactive, and writing one from inside a getter the template reads is a mutation during
  // rendering: LWC notifies the template's observer, marks the component dirty, then clears that flag
  // when the same render returns — so the write silently loses the re-render it asked for and logs
  // "Updating the template ... has side effects" in debug mode. Mutating this holder's properties is
  // invisible to the reactivity system, which is exactly what a cache wants.
  _groupsMemo = { inputs: null, value: null };

  // Header title: "<entity> - <action>".
  get title() {
    const action = this.action || {};
    return [action.entityName, action.actionTitle].filter(Boolean).join(" - ");
  }

  get isComplete() {
    return actionCompletion(
      this.sections,
      { groupId: this.action?.entityGroupId, type: this.action?.entityType },
      this.draft,
      this.userContext,
      this.registrationAttributes
    ).isComplete;
  }

  // Whether this request has moved anything off the value it started from. Only ever true for an
  // interview that was given a baseline (see originalValues).
  get hasUpdates() {
    return this.groups.some((group) =>
      group.sections.some((section) => section.updated)
    );
  }

  // "Updated" outranks "Completed" here, which it does nowhere else. An action item against an
  // existing member opens prefilled from that member's record, so it is complete from the first
  // render and a completion badge would say nothing; what the page has to report is whether the
  // request changes anything.
  get statusLabel() {
    if (this.hasUpdates) {
      return "Updated";
    }
    return this.isComplete ? "Completed" : this.action?.statusLabel || "";
  }

  get statusVariant() {
    if (this.hasUpdates) {
      return "updated";
    }
    return this.isComplete ? "complete" : "warning";
  }

  get removeMenuLabel() {
    return this.action?.removeMenuLabel || "Remove action";
  }

  // The form's nested view-model: the visible metadata sections (each shaped for envelopeFieldControl
  // and tagged with a completion status) arranged into parent groups. When a Section__mdt layout is
  // provided, sections group under their ordered parent sections and any section not named in the
  // layout falls into a trailing "Other" group. Related Parties is promoted to its own group ahead of
  // "Other"; Trade Instructions closes "Other". Without a layout, the metadata sections and Trade
  // Instructions form the "Other" group. Sections whose fields are all hidden drop out.
  //
  // Cached against the inputs it derives from, none of which is the active section. The scroll spy
  // writes `activeKey` at every section boundary; rebuilding on those writes handed each section a new
  // object and each field a new value — including a fresh empty array for every untouched
  // multi-select — so moving the active marker re-rendered every control on the page from inside a
  // scroll handler. Caching also collapses the several reads per render (hasFields, the template's
  // for:each, tocItems, sectionKeys) into a single build. Identity comparison is sound because `draft`
  // is always replaced wholesale, never mutated in place.
  //
  // This cache only actually hits across shell re-renders because `applyLookupOptions` is memoized —
  // before that, `sections` arrived as a fresh array on every read and the cache missed every time,
  // rebuilding all 38 shaped fields four to six times per autosave cycle.
  get groups() {
    const memo = this._groupsMemo;
    const inputs = [
      this.sections,
      this.sectionLayout,
      this.draft,
      this.userContext,
      this.registrationAttributes,
      this.action,
      this.strategyOptions,
      this.originalValues
    ];
    if (memo.value && memo.inputs.every((input, index) => input === inputs[index])) {
      return memo.value;
    }
    memo.inputs = inputs;
    memo.value = this._buildGroups();
    return memo.value;
  }

  _buildGroups() {
    const draft = this.draft;
    const shapedSections = (this.sections || [])
      .map((section, index) => {
        const fields = markUpdatedFields(
          shapeVisibleFields(section.fields, draft, this.userContext),
          this.originalValues
        );
        return {
          key: `sec-${index}`,
          label: section.name,
          status: sectionStatus(fields),
          updated: fields.some((field) => field.updated),
          fields
        };
      })
      .filter((section) => section.fields.length > 0);

    // Related Parties and Trade Instructions each stand as their own named group, after the
    // configured sections.
    const relatedGroup = this._relatedPartiesGroup(draft);
    const tradeGroup = this._tradeGroup(draft);

    // No configured layout: the metadata sections form the "Other" group.
    if (!this.sectionLayout || !this.sectionLayout.length) {
      const other = [...shapedSections, ...this._otherCustomSections()];
      const groups = [];
      if (relatedGroup) {
        groups.push(relatedGroup);
      }
      if (other.length) {
        groups.push(this._wrapGroup("grp-other", "Other", other));
      }
      if (tradeGroup) {
        groups.push(tradeGroup);
      }
      return groups;
    }

    // Layout present: build parent groups, then collect anything unclaimed into a trailing group.
    //
    // Group keys are namespaced by producer, never by running position. Keying the trailing group off
    // `groups.length` collided with a layout parent's index key whenever an earlier parent contributed
    // no visible children — live on ISA - Fin Acct, whose two Section__mdt parents tie at
    // Parent_Section_Order__c = 1 and whose Source of Funds children are all hidden until a source is
    // picked: groups would come out as ['grp-1'] and the leftover group would claim 'grp-1' too.
    // envelopeToc flattens groups and their sections into a single for:each, so a duplicate key there
    // breaks keyed reconciliation of the whole rail while logging nothing — the same defect class as
    // the sec-trade/grp-trade collision below.
    const sectionByName = new Map(
      shapedSections.map((section) => [section.label, section])
    );
    const used = new Set();
    const groups = [];
    this.sectionLayout.forEach((parent, index) => {
      const children = (parent.childSections || [])
        .map((name) => sectionByName.get(name))
        .filter(Boolean);
      children.forEach((section) => used.add(section.label));
      if (children.length) {
        groups.push(this._wrapGroup(`grp-p${index}`, parent.parentName, children));
      }
    });

    if (relatedGroup) {
      groups.push(relatedGroup);
    }

    const leftover = shapedSections.filter((section) => !used.has(section.label));
    leftover.push(...this._otherCustomSections());
    if (leftover.length) {
      groups.push(this._wrapGroup("grp-other", "Other", leftover));
    }
    if (tradeGroup) {
      groups.push(tradeGroup);
    }
    return groups;
  }

  // Wrap a set of shaped sections into a group node, deriving the group's completion status from them.
  _wrapGroup(key, label, sections) {
    const hasIncomplete = sections.some(
      (section) => section.status === "incomplete"
    );
    return {
      key,
      label,
      status: hasIncomplete ? "incomplete" : "complete",
      sections
    };
  }

  // The custom (non-metadata) sections that belong in the "Other" group, in render order. Related
  // Parties and Trade Instructions are intentionally excluded — each forms its own group (see
  // _relatedPartiesGroup / _tradeGroup). Empty today; kept as the extension point for the next
  // custom section that does belong under "Other".
  _otherCustomSections() {
    return [];
  }

  // Trade Instructions as a standalone group, like Related Parties: it is the whole subject of the
  // request on a DMS interview, so it carries its own heading rather than landing under "Other".
  //
  // The group key must NOT repeat its section's key. envelopeToc flattens the group and its children
  // into one list (see its _flatten) and renders them from a single for:each, so a group keyed the
  // same as its only child is a duplicated `key` in that iteration — which breaks LWC's keyed
  // reconciliation of the whole TOC. The scroll spy is not a reason to mirror it: `data-section-key`
  // is rendered only on sections, and sectionKeys is built only from section keys, so a group key is
  // never something activeKey can hold.
  _tradeGroup(draft) {
    const section = this._tradeSection(draft);
    return section ? this._wrapGroup("grp-trade", "Trade Instructions", [section]) : null;
  }

  // Related Parties as a standalone group ahead of "Other", or null when the entity has no related
  // parties configured. Its key is distinct from the section's for the same reason as _tradeGroup
  // above.
  _relatedPartiesGroup(draft) {
    const section = this._relatedPartiesSection(draft);
    return section
      ? this._wrapGroup("grp-related-parties", "Related Parties", [section])
      : null;
  }

  // The Trade Instructions section, shown in three interviews: a Financial Account (the Accounts and
  // DPI/Sponsor groups) whose Managed Account Platform selected in the form is a DMS platform (DMS or
  // DMS (Wrap)) — New Account setup; the Update Management Style case — Change Management style; and
  // the Update DMS Instructions case — editing existing instructions. Its whole value comes from the
  // draft (default until edited), and it's complete when every sleeve carries a strategy and a
  // positive value and the model allocations total 100%.
  //
  // All three capture an Expected Account Value, because each allocation row is shown as both a
  // target weight and a dollar figure and neither can be calculated without a denominator. Where the
  // advisor leaves it blank the Financial Account's Source of Funds Amount stands in — read out of
  // this same draft, and never written back into it.
  _tradeSection(draft) {
    const groupId = this.action?.entityGroupId;
    const entityType = this.action?.entityType;
    const isDmsAccount =
      ACCOUNT_GROUP_IDS.has(groupId) &&
      isDmsPlatform(draft[MANAGED_ACCOUNT_PLATFORM_FIELD]);
    const isCase = groupId === "cases";
    const isDmsUpdateCase = isCase && entityType === DMS_UPDATE_CASE_TYPE;
    const isManagementStyleCase = isCase && entityType === MANAGEMENT_STYLE_CASE_TYPE;
    if (!isDmsAccount && !isDmsUpdateCase && !isManagementStyleCase) {
      return null;
    }
    const value = draft[TRADE_FIELD_KEY] || DEFAULT_TRADE;
    const fallbackAccountValue =
      SOURCE_OF_FUNDS_AMOUNT_FIELDS.map((field) => draft[field]).find(
        (held) => held !== null && held !== undefined && held !== ""
      ) ?? null;
    // Options are load-bearing here, not cosmetic. They used to control only how the footer
    // itemized the ledger — the bottom line was identical either way, so this call omitted them.
    // Exception sleeves changed that: without options an excluded row is priced as a model row, the
    // model base collapses to the whole account value, and this dot reports complete on a table the
    // section itself shows as unfinished. Same array identity the section gets, so the totals memo
    // is shared rather than duplicated.
    const valid = strategyTotals(
      value.strategies,
      resolveExpectedValue(value.expectedAccountValue, fallbackAccountValue),
      this.strategyOptions
    ).isComplete;
    return {
      key: "sec-trade",
      label: "Trade Instructions",
      type: "tradeInstructions",
      fieldKey: TRADE_FIELD_KEY,
      value,
      options: this.strategyOptions,
      fallbackAccountValue,
      status: valid ? "complete" : "incomplete"
    };
  }

  // The Related Parties section, shown for entity types with configured related parties (see
  // envelopeFormSchema). Which subsections apply can depend on the draft — a Financial Account's
  // slots follow its selected registration — so the requirements are resolved on every read. A
  // subsection with a zero minimum is offered rather than owed, so the section can be present while
  // nothing about it is outstanding. The whole section persists under one draft key as party lists
  // keyed by requirement.
  _relatedPartiesSection(draft) {
    const requirements = resolveRelatedPartyRequirements(
      { groupId: this.action?.entityGroupId, type: this.action?.entityType },
      draft,
      this.registrationAttributes
    );
    if (!requirements.length) {
      return null;
    }
    const value = draft[RELATED_PARTIES_FIELD_KEY] || {};
    const waived = waivedRelatedPartyKeys(requirements, draft);
    return {
      key: "sec-related-parties",
      label: "Related Parties",
      type: "relatedParties",
      fieldKey: RELATED_PARTIES_FIELD_KEY,
      // The standalone group's heading already names this section, so it suppresses its own header.
      hideHeader: true,
      requirements,
      value,
      // Carried so the existing-member picker can leave this record out of its own party list.
      entityId: this.action?.entityId,
      // Carried so the existing-member picker can scope its search to this one household.
      householdId: this.householdId,
      // Carried so the existing-member picker can still offer a member just added to this
      // envelope, alongside the household's already-formalized roster.
      envelopeId: this.envelopeId,
      // Which roles are currently waived, so the body can show the affirmation ticked and the
      // status agrees with it. Passed as a joined string rather than an array: this descriptor is
      // rebuilt by a getter on every render, and a fresh array identity each time reads to LWC as a
      // changed @api value, re-rendering the section body in a loop. A primitive compares by value.
      waived: Array.from(waived).join(','),
      // The same set as a list, for the status calls. Kept separate from `waived` above because
      // that one is an @api value on a child and must stay a primitive, while a Set or list here is
      // what unmetRelatedPartyRequirements expects — handed a string it would iterate characters.
      waivedKeys: Array.from(waived),
      status: relatedPartiesStatus(requirements, value, waived)
    };
  }

  // The `groups` view-model reduced to the TOC's node shape. The Related Parties section expands into
  // one leaf per party role; every other section is a single leaf.
  get tocItems() {
    return this.groups.map((group) => ({
      key: group.key,
      label: group.label,
      status: group.status,
      children: group.sections.flatMap((section) =>
        section.type === "relatedParties"
          ? this._relatedPartyTocChildren(section)
          : [
              {
                key: section.key,
                label: section.label,
                status: section.status
              }
            ]
      )
    }));
  }

  // One TOC leaf per party role of the Related Parties section, keyed off the section anchor so a
  // click scrolls to the shared panel; status reflects whether that role's minimum is met. Roles
  // sharing a minimum are judged against the group rather than in isolation, so satisfying one of
  // them completes every leaf it stands in for.
  _relatedPartyTocChildren(section) {
    return (section.requirements || []).map((requirement) => ({
      key: `${section.key}${ROLE_KEY_SEP}${requirement.key}`,
      label: requirement.title,
      status: relatedPartiesStatus(
        relatedPartyPeers(section.requirements, requirement.key),
        section.value,
        section.waivedKeys
      )
    }));
  }

  get hasFields() {
    return this.groups.length > 0;
  }

  // Flat, ordered list of visible section keys — the model for the bottom section-nav
  // (envelopeSectionNav). Recomputed each render, so it tracks sections appearing/disappearing.
  get sectionKeys() {
    return this.groups.flatMap((group) =>
      group.sections.map((section) => section.key)
    );
  }

  get sectionTotal() {
    return this.sectionKeys.length;
  }

  get activeSectionIndex() {
    return Math.max(0, this.sectionKeys.indexOf(this.activeKey));
  }

  get showSectionNav() {
    return this.sectionTotal > 1;
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent("back"));
  }

  // Overflow-menu selection. Route "remove" up to the shell as the same `cardmenu` event an action
  // card emits, carrying this action's context so the shell reuses its card-removal handler.
  handleHeaderAction(event) {
    if (event.detail?.action !== "remove") {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("cardmenu", {
        detail: {
          action: "remove",
          id: this.action?.actionId,
          title: this.action?.actionTitle
        }
      })
    );
  }

  // The current form values, pulled by the shell at save time (the syncToParent analog).
  @api
  getFormData() {
    this.flushPendingEdits();
    return { actionId: this.action?.actionId, values: { ...this.draft } };
  }

  /**
   * Commit any edit a section body is still holding locally, so a save can never miss the last thing
   * typed.
   *
   * The Trade Instructions section buffers keystrokes and commits on blur (or a short idle window)
   * rather than on every character — that is what keeps a controlled currency input from being handed
   * back a value it did not itself report. The cost is a window in which the section holds an edit the
   * draft has not seen, so every path that reads the draft as truth flushes first. This is safe to
   * call at any time and cheap when nothing is buffered: LWC dispatches events synchronously, so each
   * child's commit runs all the way through handleFieldChange and lands in `this.draft` before this
   * method returns.
   */
  @api
  flushPendingEdits() {
    this.template
      .querySelectorAll("c-envelope-form-section")
      .forEach((section) => {
        if (typeof section.flushPendingEdits === "function") {
          section.flushPendingEdits();
        }
      });
  }

  // Overwrite one draft value on the host's behalf, for a value the host resolves while the form is
  // open (a related party whose person record has just been created and now carries a real id).
  // Addressed by action id, so a resolve that lands after the user moved on can't leak into the
  // interview now showing.
  @api
  applyResolvedValue(actionId, field, value) {
    if (!field || actionId !== this.action?.actionId) {
      return;
    }
    this.draft = { ...this.draft, [field]: value };
  }

  // Report validity across every section, surfacing each field's inline message. Reports all
  // sections (no short-circuit) so nothing invalid is hidden; returns true only when all pass.
  // A seam for a future submit gate — not called during editing, autosave, or navigation.
  @api
  reportValidity() {
    // Validate what the user actually typed, not what the draft happens to have caught up to.
    this.flushPendingEdits();
    const sections = this.template.querySelectorAll("c-envelope-form-section");
    let valid = true;
    sections.forEach((section) => {
      if (!section.reportValidity()) {
        valid = false;
      }
    });
    return valid;
  }

  // Record a field change so dependent Shown WHERE conditions and section completion re-evaluate, and
  // signal the shell that the user is editing (it debounces the autosave off this).
  //
  // Re-answering a Key Point rebuilds the branch below it, and the answers that branch no longer asks
  // for are cleared. That is only confirmed with the user when it would actually discard something:
  // an answer that merely reveals further questions — the first pick, another option ticked on a
  // multi-select, a Key Point nothing depends on — loses nothing and must not interrupt.
  handleFieldChange(event) {
    const { field, value } = event.detail || {};
    if (!field) {
      return;
    }
    // An echo is not an edit. Every control on this page — metadata fields, Related Parties, Trade
    // Instructions — funnels through here, and this is the only place a reported value becomes a new
    // `draft` identity plus a `formactivity` that flips the shell's save status and re-renders the
    // whole form. Accepting a value the draft already holds is what let one stray change event
    // sustain itself: the re-render re-set the control, the control reported again, and round it
    // went. Bailing cannot lose an edit — an echo carries no information the draft does not have.
    if (draftValuesEqual(this.draft[field], value)) {
      return;
    }
    if (this._isKeyPoint(field) && hasPriorAnswer(this.draft, field)) {
      this._pendingKeyPoint = { field, value };
      this.refs.keyPointModal.open();
      return;
    }
    this._commitFieldChange(field, value);
  }

  // The user accepted the consequences: release the held-back edit through the ordinary path.
  handleKeyPointConfirm() {
    this.refs.keyPointModal.close();
    const pending = this._pendingKeyPoint;
    this._pendingKeyPoint = null;
    if (pending) {
      this._commitFieldChange(pending.field, pending.value);
    }
  }

  // The user backed out: drop the edit and put the control back on the draft's answer. The draft never
  // changed, so nothing re-renders on its own — the control still shows the uncommitted pick.
  handleKeyPointCancel() {
    this.refs.keyPointModal.close();
    const pending = this._pendingKeyPoint;
    this._pendingKeyPoint = null;
    if (!pending) {
      return;
    }
    this.template
      .querySelectorAll("c-envelope-form-section")
      .forEach((section) => {
        if (typeof section.resetField === "function") {
          section.resetField(pending.field);
        }
      });
  }

  // Every configured field across the schema, flattened — the scope the draft spans.
  get _allFields() {
    return (this.sections || []).flatMap((section) => section.fields || []);
  }

  _isKeyPoint(apiName) {
    return this._allFields.some(
      (field) => field.fieldPath === apiName && field.keyDecision
    );
  }

  // Write an accepted edit into the draft and signal the shell. A Key Point also clears the answers it
  // has just hidden: the fields disappearing from the form must not keep their values in the saved
  // draft. A BD_or_RIA__c edit similarly clears Custodian__c, whose own options just narrowed.
  _commitFieldChange(field, value) {
    const next = clearDependentCustodian(field, { ...this.draft, [field]: value });
    this.draft = this._isKeyPoint(field)
      ? clearHiddenAnswers(this._allFields, next, this.userContext)
      : next;
    this.dispatchEvent(new CustomEvent("formactivity"));
  }

  // is suppressed during the animated scroll so the marker doesn't tick through the sections it passes.
  handleTocSelect(event) {
    const key = event.detail?.key;
    if (!key) {
      return;
    }
    this.activeKey = key;
    this._armSpyIdle();
    // Party-role leaves carry a ROLE_KEY_SEP suffix; the scroll anchor is the base section key.
    const anchorKey = key.split(ROLE_KEY_SEP)[0];
    const anchor = this.template.querySelector(
      `[data-section-key="${anchorKey}"]`
    );
    if (anchor) {
      anchor.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  // Suppress the scroll spy and (re)start the idle timer that resumes it once scrolling stops.
  _armSpyIdle() {
    this._spySuppressed = true;
    if (this._spyIdleTimer) {
      clearTimeout(this._spyIdleTimer);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._spyIdleTimer = setTimeout(() => {
      this._spyIdleTimer = null;
      this._spySuppressed = false;
    }, SPY_IDLE_MS);
  }

  // Step to the previous / next section from the bottom section-nav (envelopeSectionNav), mirroring
  // a TOC selection. Scroll-spy keeps activeKey — and so the counter — in sync on manual scroll.
  handleSectionPrevious() {
    this._goToSection(this.activeSectionIndex - 1);
  }

  handleSectionNext() {
    this._goToSection(this.activeSectionIndex + 1);
  }

  renderedCallback() {
    this._seedDraftIfActionChanged();
    this._bindScrollSpy();
    // Once the new action's sections render, pick the first as active (seed reset it to undefined).
    if (!this.activeKey) {
      this._updateActiveFromScroll();
    }
  }

  // Seed the draft from the saved values whenever the open action changes. Guarded by actionId so a
  // re-render — or the shell writing this same action's values back through savedValues — can't reseed
  // and wipe in-progress edits.
  _seedDraftIfActionChanged() {
    const actionId = this.action?.actionId;
    if (actionId === this._seededActionId) {
      return;
    }
    this._seededActionId = actionId;
    this.draft = { ...(this.savedValues || {}) };
    this.activeKey = undefined;
  }

  // Move to the section at `index` in the ordered section list and scroll it into view. Suppress the
  // scroll spy during the animated scroll (as a TOC selection does) so the counter jumps straight to
  // the target instead of ticking through the sections the smooth scroll passes.
  _goToSection(index) {
    const key = this.sectionKeys[index];
    if (!key) {
      return;
    }
    this.activeKey = key;
    this._armSpyIdle();
    this._scrollToSection(key);
  }

  _scrollToSection(key) {
    const anchor = this.template.querySelector(`[data-section-key="${key}"]`);
    if (anchor) {
      anchor.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  // Bind the scroll spy to the page's scroll container once it mounts (rebinds only if the element
  // changes, e.g. leaving/returning from the empty state).
  _bindScrollSpy() {
    const pane = this.template.querySelector(".action-details__scroll");
    if (!pane || pane === this._scrollPane) {
      return;
    }
    if (this._scrollPane) {
      this._scrollPane.removeEventListener("scroll", this._handleScroll);
    }
    this._scrollPane = pane;
    this._scrollPane.addEventListener("scroll", this._handleScroll, {
      passive: true
    });
    this._updateActiveFromScroll();
  }

  disconnectedCallback() {
    if (this._scrollPane) {
      this._scrollPane.removeEventListener("scroll", this._handleScroll);
      this._scrollPane = null;
    }
    if (this._spyIdleTimer) {
      clearTimeout(this._spyIdleTimer);
      this._spyIdleTimer = null;
    }
  }

  // Coalesce scroll events into one measurement per frame.
  _handleScroll = () => {
    if (this._spyScheduled) {
      return;
    }
    this._spyScheduled = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      this._spyScheduled = false;
      // A TOC click is animating the scroll: keep the clicked section active and push the idle
      // window out until the programmatic scroll settles, rather than tracking the passing sections.
      if (this._spySuppressed) {
        this._armSpyIdle();
        return;
      }
      this._updateActiveFromScroll();
    });
  };

  // Mark the section currently at the top of the form: the last anchor whose top has crossed the
  // activation line. Deterministic, so the active item can't stick on an earlier/taller section.
  _updateActiveFromScroll() {
    const pane = this._scrollPane;
    if (!pane) {
      return;
    }
    const anchors = [...this.template.querySelectorAll("[data-section-key]")];
    if (anchors.length === 0) {
      return;
    }
    const line = pane.getBoundingClientRect().top + SPY_ACTIVATION_OFFSET;
    let activeKey = anchors[0].dataset.sectionKey;
    for (const anchor of anchors) {
      if (anchor.getBoundingClientRect().top <= line) {
        activeKey = anchor.dataset.sectionKey;
      } else {
        break;
      }
    }
    if (activeKey !== this.activeKey) {
      this.activeKey = activeKey;
    }
  }
}