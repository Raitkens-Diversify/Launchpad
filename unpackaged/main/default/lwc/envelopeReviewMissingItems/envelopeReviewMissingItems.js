import { LightningElement, api } from "lwc";
import {
  changeClearsAnswers,
  clearHiddenAnswers,
  isBooleanField,
  isEmptyValue,
  isFieldOutstanding,
  shapeVisibleFields
} from "c/envelopeFormSchema";

/**
 * Author: Mile Cacanovic
 *
 * envelopeReviewMissingItems — the "Review Missing Items" screen for envelopeShellV2.
 *
 * Consolidates the action items that still have missing inputs into a single view: an "Action
 * Items" rail (c-envelope-toc tree) on the left — each action item expanding into its section
 * groups, and each group into its sections, mirroring the action interview's TOC one level up —
 * and the action items on the right, each rendered as its title plus, per group, a heading above
 * one card whose parts (each either fields to fill in or the Related Parties requirement blocks)
 * are stacked with dividers. The focused top bar carries the screen title, envelope name,
 * missing-inputs count, and the Close action, so this view renders only the rail + action items.
 *
 * The `actionItems` prop is a shell-owned snapshot taken when the screen opens: items stay listed
 * while the user fills them in (statuses update; the set doesn't shrink), and re-opening the screen
 * re-snapshots. Field rendering and conditional visibility mirror the action interview
 * (envelopeActionDetails): each field is shown via `envelopeFieldControl` and filtered by its Shown
 * WHERE statement against the owning action item's draft, seeded from the action's saved values so
 * gates answered in the interview keep their dependents visible here.
 *
 * A floating section-nav (envelopeSectionNav) steps between the card parts across all action
 * items; scroll-spy keeps its position — and the rail highlight — in sync as the user scrolls.
 */

// Distance below the scroll container's top edge where a part becomes "active": the active
// part is the last one whose top has crossed this line (matches envelopeActionDetails' scroll-spy).
const SPY_ACTIVATION_OFFSET = 120;

// How long after the last scroll event a rail/section-nav pick keeps the scroll spy suppressed —
// long enough to outlive the smooth-scroll animation, short enough to feel instant afterwards.
const SPY_IDLE_MS = 150;

// Separator appended to a part's anchor key to key each per-role Related Parties TOC leaf. Anchor
// keys never contain it, so key.split(ROLE_KEY_SEP)[0] recovers the part's scroll anchor.
const ROLE_KEY_SEP = "::rp::";

export default class EnvelopeReviewMissingItems extends LightningElement {
  // Action items to review: [{ key, title, allFields, values, sections: [{ key, title, parts:
  // [Part] }] }] — `allFields` is the action's full raw schema fields (the hidden-answer-clearing
  // scope), `values` its saved form data filtered to schema field paths (the draft seed). A
  // section is a layout group (e.g. "Individual Details") and each Part one of its card's blocks:
  // either a fields part ({ key, title?, badge?, statusLabel?, fields: [FieldMetadata] }) or the
  // Related Parties part ({ key, title, statusLabel?, requirements: [{ key, title, max?, group?,
  // statusLabel?, owners?, emptyState: { title, message, actions: [{ key, label }] } }] }) — a
  // `group` marks roles that share one minimum and so are satisfied together. Each
  // field carries
  // the raw Envelope_Field__mdt shape (fieldPath, label, type, inputType, required,
  // picklistOptions, shownWhereStatement) plus an optional seed `value`.
  @api actionItems = [];

  // Optional progressive save-status shown as a chip on the "Action Items" title row: 'pending' |
  // 'saving' | 'saved' render it; anything else (incl. 'idle' / unset) hides it. Owned by the shell.
  @api saveStatus;

  // Running-user attributes for `$User.<field>` WHERE conditions (e.g. a field shown only when
  // `$User.Relationship_to_Firm__c = 'Dual'`). Supplied by the shell; forwarded into the Shown WHERE
  // filter so a hidden, user-gated field is not surfaced as a missing item.
  @api userContext = {};

  // Working values keyed by action item key, then field API name. The same field API name can be
  // missing on two action items at once (e.g. two accounts), so a flat draft would collide; the
  // per-action level also lets the shell map each value back into its owning action's form data
  // at save time. Seeded per mount from each item's saved values, so conditional field visibility
  // sees the interview's answers; may span more keys than the rendered fields (seeded values and
  // cleared hidden answers). The shell diffs against the saved form data at save time, so the
  // untouched seed never persists.
  draft = {};

  // The active part's composite anchor key ("<actionItemKey>::<sectionKey>::<partKey>"), driving
  // the rail highlight and the floating section-nav. Seeded to the first part; updated when the
  // user picks a rail leaf, uses the section-nav, or scrolls (scroll-spy).
  activeAnchorKey = null;

  // Scroll-spy plumbing: the scroll container currently listened to, and a flag coalescing
  // scroll events into one measurement per animation frame.
  _scrollPane = null;
  _spyScheduled = false;

  // True while a rail/section-nav pick is animating the scroll; the spy skips tracking so the
  // marker doesn't tick through the parts it passes (see _armSpyIdle).
  _spySuppressed = false;
  _spyIdleTimer = null;

  // A Key Point edit held back while its confirmation dialog is open: { itemKey, field, value },
  // applied on confirm and dropped on cancel.
  _pendingKeyPoint = null;

  connectedCallback() {
    // Seed each item's draft from its action's saved values (attached to the shell's snapshot),
    // mirroring the interview's seed (envelopeActionDetails): Shown WHERE conditions referencing
    // gates answered in the interview evaluate against the real answers instead of an empty
    // draft. Once per mount — the shell remounts this screen per open (spinner swap while the
    // snapshot rebuilds), so re-opening re-seeds from fresh form data. Must run before the
    // anchorKeys read below, which derives from draft-dependent visibility.
    this.draft = Object.fromEntries(
      (this.actionItems || []).map((item) => [
        item.key,
        { ...(item.values || {}) }
      ])
    );
    const [firstAnchor] = this.anchorKeys;
    this.activeAnchorKey = firstAnchor || null;
  }

  renderedCallback() {
    this._bindScrollSpy();
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

  // Action items shaped for rendering: each section group becomes a heading above one card of
  // parts. A fields part keeps only its currently-visible fields and is dropped when none remain;
  // the Related Parties part is always kept. Sections left with no parts are dropped, and action
  // items left with no sections too, so nothing empty shows. Each part carries a composite anchor
  // key — the scroll target and rail leaf — and the active part gets the left marker stripe
  // (mirrors the interview's active form section). Field mapping mirrors
  // envelopeActionDetails.visibleSections.
  get visibleActionItems() {
    return (this.actionItems || [])
      .map((actionItem) => {
        const itemDraft = this.draft[actionItem.key] || {};
        const sections = (actionItem.sections || [])
          .map((section) => {
            // Composite rail key: section keys aren't guaranteed unique across action items.
            const railKey = `${actionItem.key}::${section.key}`;
            const parts = (section.parts || [])
              .map((part) => this._buildPart(part, itemDraft))
              .filter((part) => part !== null)
              .map((part) => this._anchorPart(part, railKey));
            return {
              key: section.key,
              railKey,
              title: section.title,
              status: this._sectionStatus(parts),
              parts
            };
          })
          .filter((section) => section.parts.length > 0);
        return {
          key: actionItem.key,
          title: actionItem.title,
          status: this._itemStatus(sections),
          sections
        };
      })
      .filter((actionItem) => actionItem.sections.length > 0);
  }

  // The visible action items shaped into c-envelope-toc's tree: each action item is a top-level
  // parent, each section group a nested parent, and each part a leaf keyed by its composite anchor
  // key — the same groups → sections tree the action interview shows, one level up. The Related
  // Parties part expands into one leaf per party role (each keyed off the part anchor so it scrolls
  // to the shared card). Drives the "Action Items" rail.
  get tocItems() {
    return this.visibleActionItems.map((item) => ({
      key: item.key,
      label: item.title,
      status: item.status,
      children: item.sections.map((section) => ({
        key: section.railKey,
        label: section.title,
        status: section.status,
        children: section.parts.flatMap((part) =>
          part.requirements
            ? part.requirements.map((requirement) => ({
                key: `${part.anchorKey}${ROLE_KEY_SEP}${requirement.key}`,
                label: requirement.title,
                status: requirement.isSatisfied ? "complete" : "incomplete"
              }))
            : [
                {
                  key: part.anchorKey,
                  label: part.title,
                  status: part.status
                }
              ]
        )
      }))
    }));
  }

  get hasActionItems() {
    return this.visibleActionItems.length > 0;
  }

  // Flat, ordered list of visible part anchor keys — the model for the floating section-nav
  // (envelopeSectionNav). Recomputed each render, so it tracks parts appearing/disappearing.
  get anchorKeys() {
    return this.visibleActionItems.flatMap((item) =>
      item.sections.flatMap((section) =>
        section.parts.map((part) => part.anchorKey)
      )
    );
  }

  get sectionTotal() {
    return this.anchorKeys.length;
  }

  get activeSectionIndex() {
    return Math.max(0, this.anchorKeys.indexOf(this.activeAnchorKey));
  }

  // The section-nav is only useful once there is more than one part to move between.
  get showSectionNav() {
    return this.sectionTotal > 1;
  }

  // Navigate to a part leaf picked from the rail. c-envelope-toc emits `select` on leaf clicks
  // only (parent clicks toggle collapse), so its detail carries the part's composite anchor key.
  // The spy is suppressed during the animated scroll so the marker doesn't tick through the
  // parts it passes.
  handleTocSelect(event) {
    const key = event.detail?.key;
    if (!key) {
      return;
    }
    // Party-role leaves carry a ROLE_KEY_SEP suffix; the scroll anchor (and active part) is the base.
    const anchorKey = key.split(ROLE_KEY_SEP)[0];
    if (anchorKey === this.activeAnchorKey) {
      return;
    }
    this._setActiveAnchor(anchorKey);
    this._armSpyIdle();
    const anchor = this.template.querySelector(
      `[data-section-key="${anchorKey}"]`
    );
    if (anchor) {
      anchor.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  // Step to the previous / next part from the floating section-nav (envelopeSectionNav).
  handleSectionPrevious() {
    this._goToAnchor(this.activeSectionIndex - 1);
  }

  handleSectionNext() {
    this._goToAnchor(this.activeSectionIndex + 1);
  }

  // The current draft values, pulled by the shell at save time (mirrors envelopeActionDetails'
  // getFormData). Grouped by action item key — the action id — so the shell can merge each
  // group back into its owning action's form data.
  @api
  getFormData() {
    this.flushPendingEdits();
    const valuesByAction = {};
    Object.keys(this.draft).forEach((key) => {
      valuesByAction[key] = { ...this.draft[key] };
    });
    return { valuesByAction };
  }

  /**
   * Ask every field control to commit whatever keystroke it is still holding, so a save can never
   * read a draft that is a character behind what the user typed (mirrors the interview's
   * envelopeActionDetails.flushPendingEdits). LWC dispatches events synchronously, so each commit
   * runs all the way through handleFieldChange and lands in `this.draft` before this returns.
   */
  @api
  flushPendingEdits() {
    this.template
      .querySelectorAll("c-envelope-field-control")
      .forEach((control) => {
        if (typeof control.flushPendingEdits === "function") {
          control.flushPendingEdits();
        }
      });
  }

  // Record a field change under its owning action item so dependent Shown WHERE conditions
  // re-evaluate immediately, and signal the shell that the user is editing (it debounces the
  // autosave off this). The owning item's key rides on the field control's data attribute.
  //
  // Re-answering a Key Point also clears the answers it has just hidden, spanning the item's full
  // schema like the interview — but scoped to the item whose draft the change landed in. That is
  // confirmed with the user only when it would actually discard something; an answer that merely
  // reveals further questions loses nothing and must not interrupt.
  handleFieldChange(event) {
    const { field, value } = event.detail || {};
    const itemKey = event.currentTarget.dataset.item;
    if (!field || !itemKey) {
      return;
    }
    const fields = this._itemFields(itemKey);
    const isKeyPoint = fields.some(
      (entry) => entry.fieldPath === field && entry.keyDecision
    );
    if (
      isKeyPoint &&
      changeClearsAnswers(fields, this.draft[itemKey] || {}, this.userContext, field, value)
    ) {
      this._pendingKeyPoint = { itemKey, field, value };
      this.refs.keyPointModal.open();
      return;
    }
    this._commitFieldChange(itemKey, field, value);
  }

  // The user accepted the consequences: release the held-back edit through the ordinary path.
  handleKeyPointConfirm() {
    this.refs.keyPointModal.close();
    const pending = this._pendingKeyPoint;
    this._pendingKeyPoint = null;
    if (pending) {
      this._commitFieldChange(pending.itemKey, pending.field, pending.value);
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
    const control = this.template.querySelector(
      `c-envelope-field-control[data-item="${pending.itemKey}"][data-field="${pending.field}"]`
    );
    if (control && typeof control.resetValue === "function") {
      control.resetValue();
    }
  }

  // Write an accepted edit into the owning item's draft and signal the shell.
  _commitFieldChange(itemKey, field, value) {
    const fields = this._itemFields(itemKey);
    const next = { ...(this.draft[itemKey] || {}), [field]: value };
    const isKeyPoint = fields.some(
      (entry) => entry.fieldPath === field && entry.keyDecision
    );
    this.draft = {
      ...this.draft,
      [itemKey]: isKeyPoint
        ? clearHiddenAnswers(fields, next, this.userContext)
        : next
    };
    this.dispatchEvent(new CustomEvent("formactivity"));
  }

  // Every schema field of the given action item (raw Envelope_Field__mdt shapes, attached by the
  // shell) — the scope hidden-answer clearing spans, mirroring the interview's _allFields. The
  // snapshot's own parts hold only the missing subset; clearing against them would miss the
  // answered fields a re-answered Key Point has just hidden.
  _itemFields(itemKey) {
    const item = (this.actionItems || []).find(
      (actionItem) => actionItem.key === itemKey
    );
    return item?.allFields || [];
  }

  // Bubble a requirement's empty-state action (Select Existing / Create New) up to the shell. The
  // `part` detail carries the requirement key — the slot the shell writes the pick back into.
  handleOwnerAction(event) {
    const { action, part, item } = event.currentTarget.dataset;
    this.dispatchEvent(
      new CustomEvent("owneraction", {
        detail: { action, part, actionItemKey: item }
      })
    );
  }

  // Bubble an owner card's Remove up to the shell: the requirement/item context comes from the
  // card's data-attributes (`part` is the requirement key), the owner id from the card's own
  // event detail.
  handleOwnerRemove(event) {
    const { part, item } = event.currentTarget.dataset;
    const { id } = event.detail || {};
    this.dispatchEvent(
      new CustomEvent("ownerremove", {
        detail: { part, actionItemKey: item, id }
      })
    );
  }

  // Shape one part for rendering. A fields part keeps only its currently-visible fields (Shown
  // WHERE against the owning item's draft, via the interview's shared shaping) and returns null
  // when none remain so the caller can drop it; it is outstanding while any visible field still
  // owes input (a blank required field or a value failing its format rule — the same measure the
  // interview uses) or a Key Point is still blank. The Related Parties part shapes each
  // requirement block and is outstanding while any requirement is still unsatisfied. Once
  // satisfied, a part's "Inputs missing" status clears (the part itself stays — snapshot
  // semantics) and its rail leaf turns complete.
  _buildPart(part, draft) {
    if (part.requirements) {
      // Roles sharing a minimum are satisfied together, so an owner on any of them satisfies all
      // of them. Collected up front because a requirement's status can depend on a later one.
      const satisfiedGroups = new Set(
        part.requirements
          .filter(
            (requirement) =>
              requirement.group && (requirement.owners || []).length > 0
          )
          .map((requirement) => requirement.group)
      );
      const requirements = part.requirements.map((requirement) => {
        const owners = requirement.owners || [];
        // A requirement at its slot limit disables its add actions (Select Existing / Create
        // New) in both the owners and empty states — same cap as the interview's subsections.
        const atLimit =
          typeof requirement.max === "number" &&
          owners.length >= requirement.max;
        // `hasOwners` chooses the block's body — the owner cards or the empty state — and so
        // stays about this role alone; `isSatisfied` answers whether anything is still owed and
        // so takes the shared minimum into account.
        const isSatisfied =
          owners.length > 0 || satisfiedGroups.has(requirement.group);
        return {
          ...requirement,
          owners,
          hasOwners: owners.length > 0,
          isSatisfied,
          statusLabel: isSatisfied ? null : requirement.statusLabel,
          emptyState: {
            ...requirement.emptyState,
            actions: (requirement.emptyState?.actions || []).map((action) => ({
              ...action,
              disabled: atLimit
            }))
          }
        };
      });
      const hasOutstanding = requirements.some(
        (requirement) => !requirement.isSatisfied
      );
      return {
        key: part.key,
        ...this._buildPartHeader(
          part,
          hasOutstanding ? part.statusLabel : null
        ),
        isFieldsPart: false,
        hasOutstanding,
        status: hasOutstanding ? "incomplete" : "complete",
        requirements
      };
    }

    const fields = shapeVisibleFields(part.fields, draft, this.userContext);
    if (fields.length === 0) {
      return null;
    }
    const hasOutstanding = fields.some(
      (field) =>
        isFieldOutstanding(field) ||
        (field.keyDecision && isEmptyValue(field.value) && !isBooleanField(field))
    );
    return {
      key: part.key,
      ...this._buildPartHeader(part, hasOutstanding ? part.statusLabel : null),
      isFieldsPart: true,
      hasOutstanding,
      status: hasOutstanding ? "incomplete" : "complete",
      fields
    };
  }

  // The part-header slice of the render shape, with the status resolved by the caller (a satisfied
  // part clears it).
  _buildPartHeader(part, statusLabel) {
    return {
      showHeader: Boolean(part.title || part.badge || statusLabel),
      title: part.title || null,
      badge: part.badge || null,
      statusLabel: statusLabel || null
    };
  }

  // Stamp a shaped part with its composite anchor key (the scroll target and rail leaf key) and
  // the active-part card class — the left marker stripe follows scroll-spy / rail / section-nav,
  // mirroring the action interview's active form section.
  _anchorPart(part, railKey) {
    const anchorKey = `${railKey}::${part.key}`;
    return {
      ...part,
      anchorKey,
      partClass:
        anchorKey === this.activeAnchorKey
          ? "missing__part missing__part_active"
          : "missing__part"
    };
  }

  // A section group is complete when every part is satisfied: a fields part has no outstanding
  // field left (required or Key Point), the Related Parties part has all requirements owned.
  _sectionStatus(parts) {
    const complete = parts.every((part) => !part.hasOutstanding);
    return complete ? "complete" : "incomplete";
  }

  // An action item is complete when all of its section groups are.
  _itemStatus(sections) {
    const complete = sections.every((section) => section.status === "complete");
    return complete ? "complete" : "incomplete";
  }

  // Move to the part at `index` in the ordered anchor list and scroll it into view, suppressing
  // the spy like a rail pick.
  _goToAnchor(index) {
    const anchorKey = this.anchorKeys[index];
    if (!anchorKey) {
      return;
    }
    this._setActiveAnchor(anchorKey);
    this._armSpyIdle();
    const anchor = this.template.querySelector(
      `[data-section-key="${anchorKey}"]`
    );
    if (anchor) {
      anchor.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  // Mark the active part — drives the rail highlight (the active leaf in c-envelope-toc), the
  // card stripe, and the floating section-nav position.
  _setActiveAnchor(anchorKey) {
    if (anchorKey === this.activeAnchorKey) {
      return;
    }
    this.activeAnchorKey = anchorKey;
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

  // Bind the scroll spy to the page's scroll container once it mounts (rebinds only if the
  // element changes across re-renders).
  _bindScrollSpy() {
    const pane = this.template.querySelector(".missing__scroll");
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
      // A rail pick is animating the scroll: keep the picked part active and push the idle
      // window out until the programmatic scroll settles, rather than tracking the passing parts.
      if (this._spySuppressed) {
        this._armSpyIdle();
        return;
      }
      this._updateActiveFromScroll();
    });
  };

  // Mark the part currently at the top of the view: the last anchor whose top has crossed the
  // activation line. Deterministic, so the active item can't stick on an earlier/taller part.
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
    let anchorKey = anchors[0].dataset.sectionKey;
    for (const anchor of anchors) {
      if (anchor.getBoundingClientRect().top <= line) {
        anchorKey = anchor.dataset.sectionKey;
      } else {
        break;
      }
    }
    this._setActiveAnchor(anchorKey);
  }
}