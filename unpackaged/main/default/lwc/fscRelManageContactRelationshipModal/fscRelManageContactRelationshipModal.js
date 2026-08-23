/*
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 */
import { api, track } from "lwc";
import LightningModal from "lightning/modal";
import saveMemberAccountRelationships from "@salesforce/apex/FscRelHouseholdController.saveMemberAccountRelationships";
import deleteMemberAccountRelationships from "@salesforce/apex/FscRelHouseholdController.deleteMemberAccountRelationships";
import FscRelCreateReciprocalRoleModal from "c/fscRelCreateReciprocalRoleModal";
import FscRelCreateRecordModal from "c/fscRelCreateRecordModal";
import { buildModalSaveMessage, ensureFscRelModalStyles, isReadOnlyMemberRelationshipRecordType } from "c/fscRelUtils";

const PERSON_ACCOUNT_FILTER = Object.freeze({
  criteria: [
    {
      fieldPath: "IsPersonAccount",
      operator: "eq",
      value: true
    }
  ]
});

export default class FscRelManageContactRelationshipModal extends LightningModal {
  @api memberAccountId;
  @api memberName;
  @api recordTypeDeveloperName;
  @api recordTypeLabel;
  @api reciprocalRoleRecordTypeDeveloperName;
  @api initialRelationships = [];
  @api savedCallback;
  @api selectMemberFromClients = false;
  @api clientMemberAccountIds = [];
  @api clientMembers = [];

  personAccountFilter = PERSON_ACCOUNT_FILTER;

  @track relationshipRows = [];
  @track pendingDeleteRelationIds = [];
  @track bannerMessage = "";
  @track bannerVariant = "error";
  @track isSaving = false;

  nextRowId = 1;
  savedSinceOpen = false;
  _initialRelationships = [];

  connectedCallback() {
    ensureFscRelModalStyles(this);

    this._initialRelationships = Array.isArray(this.initialRelationships)
      ? JSON.parse(JSON.stringify(this.initialRelationships))
      : [];

    if (this.isClientSelectMode) {
      this.relationshipRows = this.buildInitialRows(this._initialRelationships);
      return;
    }

    this.relationshipRows = this.buildInitialRows(this._initialRelationships);
  }

  get isClientSelectMode() {
    return this.selectMemberFromClients === true;
  }

  get allowedClientMemberAccountIds() {
    if (Array.isArray(this.clientMembers) && this.clientMembers.length > 0) {
      return this.clientMembers.map((member) => member.accountId).filter(Boolean);
    }

    return Array.isArray(this.clientMemberAccountIds)
      ? this.clientMemberAccountIds.filter(Boolean)
      : [];
  }

  get resolvedMemberAccountId() {
    return this.memberAccountId;
  }

  get roleLookupRecordTypeDeveloperName() {
    return (
      this.reciprocalRoleRecordTypeDeveloperName ||
      this.recordTypeDeveloperName ||
      ""
    ).trim();
  }

  get resolvedHeaderName() {
    if (this.isClientSelectMode) {
      return this.recordTypeLabel || "Household members";
    }

    return this.memberName || "This member";
  }

  get resolvedMemberName() {
    return this.memberName || "This member";
  }

  resolveMemberAccountLabel(memberAccountId) {
    if (!memberAccountId) {
      return "";
    }

    const matchedMember = (this.clientMembers || []).find(
      (member) => member.accountId === memberAccountId
    );

    return matchedMember?.name || "";
  }

  resolveRowMemberName(row) {
    return (
      row?.memberAccountName ||
      this.resolveMemberAccountLabel(row?.memberAccountId) ||
      "Selected client"
    );
  }

  get isReadOnly() {
    return isReadOnlyMemberRelationshipRecordType(this.recordTypeDeveloperName);
  }

  get isSubjectLookupCreateEnabled() {
    return false;
  }

  get isRelationshipEditorDisabled() {
    return this.isReadOnly;
  }

  get modalTitle() {
    const verb = this.isReadOnly ? "View" : "Manage";
    return `${verb} ${this.recordTypeLabel || "Member"} Contacts`;
  }

  get cancelButtonLabel() {
    if (this.isReadOnly) {
      return "Close";
    }

    return this.isSaving ? "Saving..." : "Cancel";
  }

  get saveButtonLabel() {
    return this.isSaving ? "Saving..." : "Save";
  }

  get isSaveDisabled() {
    return this.isSaving || !this.hasUnsavedChanges;
  }

  get hasUnsavedChanges() {
    if (this.pendingDeleteRelationIds.length > 0) {
      return true;
    }

    return this.relationshipRows.some((row) => this.isRowDirty(row));
  }

  get relationshipInstruction() {
    if (this.isReadOnly) {
      return `Review ${this.resolvedMemberName}'s ${this.recordTypeLabel || "member"} relationships. These contacts cannot be changed here.`;
    }

    if (this.isClientSelectMode) {
      return "For each row, select a household client account, then define their role relative to the related person on the other side of the relationship.";
    }

    return `For each row, ${this.resolvedMemberName} is the selected role of the related person, who is the selected role on the other side of the relationship.`;
  }

  get roleFieldLabel() {
    if (this.isClientSelectMode) {
      return "Client role";
    }

    return `${this.resolvedMemberName}'s role`;
  }

  get editableRelationshipSentenceClass() {
    const classes = ["relationship-sentence"];

    if (this.isClientSelectMode) {
      classes.push("relationship-sentence_client-select");
    }

    return classes.join(" ");
  }

  get addRowButtonLabel() {
    const recordType = (this.recordTypeLabel || "").trim();
    return recordType ? `Add ${recordType} Contact` : "Add Contact";
  }

  get showReadOnlyEmptyState() {
    return this.isReadOnly && this.relationshipRows.length === 0;
  }

  get modalTableClass() {
    const classes = ["modal-table"];

    if (this.isReadOnly) {
      classes.push("modal-table_read-only");
    }

    if (this.showReadOnlyEmptyState) {
      classes.push("modal-table_read-only-empty");
    }

    return classes.join(" ");
  }

  get rowViewModels() {
    return this.relationshipRows.map((row, index) => {
      const isPendingDelete = row.isPendingDelete === true;
      const isExisting = row.isExisting === true;
      const hasError = Boolean(row.errorMessage);
      const rowWrapperClass = [
        "modal-table__row-wrapper",
        isPendingDelete ? "modal-table__row-wrapper_pending-delete" : "",
        hasError ? "modal-table__row-wrapper_error" : ""
      ]
        .filter(Boolean)
        .join(" ");
      const roleLabel = row.reciprocalRoleName || row.role || "";
      const inverseRoleLabel =
        row.inverseReciprocalRoleName || row.inverseRole || "";
      const subjectName = this.isClientSelectMode
        ? this.resolveRowMemberName(row)
        : this.resolvedMemberName;
      const readOnlySentence = this.buildRelationshipSentence({
        subjectName,
        roleLabel,
        inverseRoleLabel,
        relatedAccountName: row.relatedAccountName || "related person account",
        includePlaceholderRole: false
      });

      return {
        ...row,
        isPendingDelete,
        hasError,
        rowWrapperClass,
        subjectName,
        isMemberAccountDisabled: this.isReadOnly || isPendingDelete,
        isRelatedAccountDisabled: this.isReadOnly || isPendingDelete,
        isRoleDisabled: this.isReadOnly || isPendingDelete,
        isInverseRoleDisabled: this.isReadOnly || isPendingDelete,
        isActiveDisabled:
          this.isReadOnly ||
          isPendingDelete ||
          !row.relatedAccountId ||
          (this.isClientSelectMode && !row.memberAccountId),
        canRemove: !this.isReadOnly && !isPendingDelete && (isExisting || index > 0),
        roleLabel,
        inverseRoleLabel,
        readOnlySentence,
        activeStatusLabel: row.isActive ? "Active" : "Inactive",
        pendingSentence: this.buildRelationshipSentence({
          subjectName,
          roleLabel,
          inverseRoleLabel,
          relatedAccountName: row.relatedAccountName || "related person account",
          includePlaceholderRole: !roleLabel
        })
      };
    });
  }

  get hasBanner() {
    return Boolean(this.bannerMessage);
  }

  get bannerClass() {
    const variant =
      this.bannerVariant === "success"
        ? "slds-theme_success"
        : this.bannerVariant === "warning"
          ? "slds-theme_warning"
          : "slds-theme_error";
    return `modal-banner slds-notify slds-notify_alert ${variant}`;
  }

  buildInitialRows(initialRelationships) {
    const rows = [];

    (initialRelationships || []).forEach((relationship) => {
      const rowId = this.nextRowId;
      this.nextRowId += 1;

      rows.push({
        id: rowId,
        relationId: relationship.relationId || "",
        isExisting: Boolean(relationship.relationId),
        memberAccountId:
          relationship.memberAccountId ||
          (this.isClientSelectMode ? "" : this.memberAccountId || ""),
        memberAccountName:
          relationship.memberAccountName ||
          this.resolveMemberAccountLabel(relationship.memberAccountId) ||
          "",
        relatedAccountId: relationship.relatedAccountId || "",
        relatedAccountName: relationship.relatedAccountName || "",
        reciprocalRoleId: relationship.reciprocalRoleId || "",
        reciprocalRoleName: relationship.role || "",
        role: relationship.role || "",
        inverseReciprocalRoleId: relationship.inverseReciprocalRoleId || "",
        inverseReciprocalRoleName: relationship.inverseRole || "",
        inverseRole: relationship.inverseRole || "",
        isActive: relationship.isActive !== false,
        errorMessage: "",
        isPendingDelete: false
      });
    });

    if (!this.isReadOnly) {
      rows.push(this.createEmptyRow(this.nextRowId));
      this.nextRowId += 1;
    }

    return rows;
  }

  createEmptyRow(rowId) {
    return {
      id: rowId,
      relationId: "",
      isExisting: false,
      memberAccountId: this.isClientSelectMode ? "" : this.memberAccountId || "",
      memberAccountName: this.isClientSelectMode
        ? ""
        : this.memberName || "",
      relatedAccountId: "",
      relatedAccountName: "",
      reciprocalRoleId: "",
      reciprocalRoleName: "",
      role: "",
      inverseReciprocalRoleId: "",
      inverseReciprocalRoleName: "",
      inverseRole: "",
      isActive: true,
      errorMessage: "",
      isPendingDelete: false
    };
  }

  buildRelationshipSentence({
    subjectName,
    roleLabel,
    inverseRoleLabel,
    relatedAccountName,
    includePlaceholderRole = false
  }) {
    const subject = subjectName || "Selected client";
    const roleText = roleLabel || (includePlaceholderRole ? "role" : "—");
    const relatedText = relatedAccountName || "related person account";
    const inverseText =
      inverseRoleLabel || (includePlaceholderRole ? "role" : "—");

    return `${subject} is the ${roleText} of ${relatedText}, who is the ${inverseText}`;
  }

  handleAddRow() {
    if (this.isRelationshipEditorDisabled || this.isReadOnly) {
      return;
    }

    this.relationshipRows = [
      ...this.relationshipRows,
      this.createEmptyRow(this.nextRowId)
    ];
    this.nextRowId += 1;
  }

  handleRemoveRow(event) {
    if (this.isReadOnly) {
      return;
    }

    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const target = this.relationshipRows.find((row) => row.id === rowId);
    if (!target) {
      return;
    }

    if (target.isExisting && target.relationId) {
      if (!this.pendingDeleteRelationIds.includes(target.relationId)) {
        this.pendingDeleteRelationIds = [
          ...this.pendingDeleteRelationIds,
          target.relationId
        ];
      }
      this.updateRow(rowId, { isPendingDelete: true });
      return;
    }

    if (this.relationshipRows.length <= 1) {
      return;
    }

    this.relationshipRows = this.relationshipRows.filter(
      (row) => row.id !== rowId
    );
  }

  handleUndoRemoveRow(event) {
    if (this.isReadOnly) {
      return;
    }

    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const target = this.relationshipRows.find((row) => row.id === rowId);
    if (!target) {
      return;
    }

    if (target.relationId) {
      this.pendingDeleteRelationIds = this.pendingDeleteRelationIds.filter(
        (id) => id !== target.relationId
      );
    }
    this.updateRow(rowId, { isPendingDelete: false });
  }

  handleMemberAccountChange(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const value = event.detail?.recordId || "";
    const label = event.detail?.recordLabel || "";

    this.updateRow(rowId, {
      memberAccountId: value,
      memberAccountName: label,
      errorMessage: ""
    });
  }

  handleReciprocalRoleChange(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const value = event.detail?.recordId || "";
    const label = event.detail?.recordLabel || "";

    this.updateRow(rowId, {
      reciprocalRoleId: value,
      reciprocalRoleName: label,
      role: label,
      errorMessage: ""
    });
  }

  handleInverseReciprocalRoleChange(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const value = event.detail?.recordId || "";
    const label = event.detail?.recordLabel || "";

    this.updateRow(rowId, {
      inverseReciprocalRoleId: value,
      inverseReciprocalRoleName: label,
      inverseRole: label,
      errorMessage: ""
    });
  }

  async handleReciprocalRoleCreateRequest(event) {
    const rowId = this.resolveRowId(event);
    const field = event.currentTarget?.dataset?.field || "reciprocalRole";
    if (!rowId) {
      return;
    }

    const result = await FscRelCreateReciprocalRoleModal.open({
      size: "small",
      headerLabel: "New Reciprocal Role",
      recordTypeDeveloperName:
        this.reciprocalRoleRecordTypeDeveloperName ||
        this.recordTypeDeveloperName
    });

    if (!result?.recordId) {
      return;
    }

    const roleLabel = result.roleLabel || "";
    const patch =
      field === "inverseReciprocalRole"
        ? {
            inverseReciprocalRoleId: result.recordId,
            inverseReciprocalRoleName: roleLabel,
            inverseRole: roleLabel,
            errorMessage: ""
          }
        : {
            reciprocalRoleId: result.recordId,
            reciprocalRoleName: roleLabel,
            role: roleLabel,
            errorMessage: ""
          };

    this.updateRow(rowId, patch);

    window.requestAnimationFrame(() => {
      const lookup = this.template.querySelector(
        `c-fsc-rel-record-lookup[data-row-id="${rowId}"][data-field="${field}"]`
      );
      lookup?.applySelection?.(result.recordId, roleLabel);
    });
  }

  handleRelatedAccountChange(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const value = event.detail?.recordId || "";
    const targetRow = this.relationshipRows.find((row) => row.id === rowId);
    const memberAccountId = this.isClientSelectMode
      ? targetRow?.memberAccountId
      : this.resolvedMemberAccountId;

    if (value && value === memberAccountId) {
      this.updateRow(rowId, {
        relatedAccountId: "",
        relatedAccountName: "",
        errorMessage: "A member cannot be related to themselves."
      });
      return;
    }

    this.updateRow(rowId, {
      relatedAccountId: value,
      relatedAccountName: event.detail?.recordLabel || "",
      errorMessage: ""
    });
  }

  async handleRelatedAccountCreateRequest(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    const detail = event.detail || {};
    const result = await FscRelCreateRecordModal.open({
      size: "large",
      objectApiName: detail.objectApiName || "Account",
      recordTypeId: detail.recordTypeId,
      headerLabel: detail.headerLabel || "New Person Account"
    });

    if (!result?.recordId) {
      return;
    }

    const targetRow = this.relationshipRows.find((row) => row.id === rowId);
    const memberAccountId = this.isClientSelectMode
      ? targetRow?.memberAccountId
      : this.resolvedMemberAccountId;

    if (result.recordId === memberAccountId) {
      this.updateRow(rowId, {
        relatedAccountId: "",
        relatedAccountName: "",
        errorMessage: "A member cannot be related to themselves."
      });
      return;
    }

    this.updateRow(rowId, {
      relatedAccountId: result.recordId,
      relatedAccountName: "",
      errorMessage: ""
    });
  }

  handleActiveChange(event) {
    const rowId = this.resolveRowId(event);
    if (!rowId) {
      return;
    }

    this.updateRow(rowId, {
      isActive: event.target.checked === true,
      errorMessage: ""
    });
  }

  handleModalBodyClick() {
    this.bannerMessage = "";
  }

  resolveRowMemberAccountId(row) {
    if (this.isClientSelectMode) {
      return row?.memberAccountId || "";
    }

    return this.resolvedMemberAccountId || "";
  }

  async handleSave() {
    if (this.isReadOnly || this.isSaving || !this.hasUnsavedChanges) {
      return;
    }

    this.bannerMessage = "";
    this.clearRowErrors();

    const { validated, skippedCount } = this.collectCommittableRows();
    const hasDeletes = this.pendingDeleteRelationIds.length > 0;

    if (validated.length === 0 && !hasDeletes) {
      if (skippedCount > 0) {
        this.bannerMessage = "Fix the highlighted rows before saving.";
        this.bannerVariant = "error";
      }
      return;
    }

    this.isSaving = true;

    try {
      let deletedCount = 0;
      let deleteFailedMessage = "";

      if (hasDeletes) {
        try {
          await deleteMemberAccountRelationships({
            relationIds: this.pendingDeleteRelationIds
          });
          deletedCount = this.pendingDeleteRelationIds.length;
          this.pendingDeleteRelationIds = [];
        } catch (error) {
          deleteFailedMessage =
            error?.body?.message ||
            error?.message ||
            "Failed to delete member relationships.";
        }
      }

      let totalSuccessCount = 0;
      let saveFailedMessage = "";

      if (validated.length > 0 && !deleteFailedMessage) {
        const rowsByMemberAccountId = validated.reduce((groupedRows, row) => {
          const memberAccountId = this.resolveRowMemberAccountId(row);
          if (!groupedRows.has(memberAccountId)) {
            groupedRows.set(memberAccountId, []);
          }
          groupedRows.get(memberAccountId).push(row);
          return groupedRows;
        }, new Map());

        for (const [memberAccountId, rows] of rowsByMemberAccountId.entries()) {
          const payload = rows.map((row) => ({
            relationId: row.relationId || null,
            relatedAccountId: row.relatedAccountId,
            reciprocalRoleId: row.reciprocalRoleId || "",
            inverseReciprocalRoleId: row.inverseReciprocalRoleId || "",
            role: row.role || "",
            inverseRole: row.inverseRole || "",
            isActive: row.isActive !== false,
            rowKey: String(row.id)
          }));

          const saveResult = await saveMemberAccountRelationships({
            memberAccountId,
            recordTypeDeveloperName: this.recordTypeDeveloperName,
            relationshipsJson: JSON.stringify(payload)
          });

          if (!saveResult) {
            continue;
          }

          this.applySaveResults(saveResult, 0, "");
          totalSuccessCount += saveResult.successCount ?? 0;

          if (saveResult.success !== true) {
            saveFailedMessage = saveResult.message || "Failed to save member relationships.";
            break;
          }
        }
      }

      if (deleteFailedMessage) {
        this.bannerMessage = deleteFailedMessage;
        this.bannerVariant = "error";
        return;
      }

      if (saveFailedMessage) {
        return;
      }

      if (totalSuccessCount > 0 || deletedCount > 0) {
        const message = buildModalSaveMessage({
          successCount: totalSuccessCount,
          deletedCount,
          subject: this.isClientSelectMode
            ? this.recordTypeLabel || "member relationships"
            : this.resolvedMemberName
        });

        this.savedSinceOpen = true;
        if (typeof this.savedCallback === "function") {
          this.savedCallback({
            confirmed: true,
            message
          });
        }
        this.close({
          confirmed: true,
          message,
          memberAccountId: this.resolvedMemberAccountId || ""
        });
      }
    } catch (error) {
      this.bannerMessage =
        error?.body?.message ||
        error?.message ||
        "Failed to save member relationships.";
      this.bannerVariant = "error";
    } finally {
      this.isSaving = false;
    }
  }

  handleCancel() {
    this.close({
      confirmed: this.savedSinceOpen,
      message: this.savedSinceOpen
        ? buildModalSaveMessage({ subject: this.resolvedMemberName })
        : "",
      memberAccountId: this.resolvedMemberAccountId || ""
    });
  }

  applySaveResults(saveResult, deletedCount, deleteFailedMessage) {
    if (deleteFailedMessage) {
      this.bannerMessage = deleteFailedMessage;
      this.bannerVariant = "error";
      return;
    }

    if (!saveResult) {
      return;
    }

    const rowResults = Array.isArray(saveResult.rowResults)
      ? saveResult.rowResults
      : [];
    let saveFailedCount = 0;

    rowResults.forEach((result) => {
      if (result?.success) {
        return;
      }

      saveFailedCount += 1;
      const message =
        Array.isArray(result.messages) && result.messages.length > 0
          ? result.messages[0]
          : "Failed to save this row.";
      this.updateRow(Number(result.rowKey), { errorMessage: message });
    });

    if (saveResult.success === true) {
      this.savedSinceOpen = true;
      return;
    }

    this.savedSinceOpen = deletedCount > 0;

    const successCount =
      saveResult.successCount ??
      rowResults.filter((result) => result?.success).length;

    this.bannerMessage = `${successCount} saved, ${saveFailedCount} failed. See errors below each row.`;
    this.bannerVariant = "error";
  }

  isRowChanged(row) {
    if (!row.isExisting || !row.relationId) {
      return true;
    }

    const original = this._initialRelationships.find(
      (relationship) => relationship.relationId === row.relationId
    );
    if (!original) {
      return true;
    }

    return (
      (row.memberAccountId || "") !== (original.memberAccountId || "") ||
      (row.relatedAccountId || "") !== (original.relatedAccountId || "") ||
      (row.reciprocalRoleId || "") !== (original.reciprocalRoleId || "") ||
      (row.inverseReciprocalRoleId || "") !==
        (original.inverseReciprocalRoleId || "") ||
      (row.role || "") !== (original.role || "") ||
      (row.inverseRole || "") !== (original.inverseRole || "") ||
      row.isActive !== (original.isActive !== false)
    );
  }

  isRowDirty(row) {
    if (row.isPendingDelete) {
      return false;
    }

    const hasAnyData =
      row.memberAccountId ||
      row.relatedAccountId ||
      row.reciprocalRoleId ||
      row.inverseReciprocalRoleId ||
      row.role ||
      row.inverseRole ||
      row.isActive === false;

    if (!hasAnyData) {
      return false;
    }

    if (!row.isExisting || !row.relationId) {
      return true;
    }

    return this.isRowChanged(row);
  }

  collectCommittableRows() {
    const validated = [];
    const seenRelationshipKeys = new Map();
    let skippedCount = 0;

    this.relationshipRows.forEach((row) => {
      if (row.isPendingDelete) {
        return;
      }

      const hasAnyData =
        row.memberAccountId ||
        row.relatedAccountId ||
        row.reciprocalRoleId ||
        row.inverseReciprocalRoleId ||
        row.role ||
        row.inverseRole ||
        row.isActive === false;
      if (!hasAnyData) {
        return;
      }

      const memberAccountId = this.resolveRowMemberAccountId(row);

      if (this.isClientSelectMode && !memberAccountId) {
        this.updateRow(row.id, {
          errorMessage: "Select a household client account from the list."
        });
        skippedCount += 1;
        return;
      }

      if (!row.relatedAccountId) {
        this.updateRow(row.id, {
          errorMessage: "Select a related person account from the list."
        });
        skippedCount += 1;
        return;
      }

      if (!row.reciprocalRoleId) {
        this.updateRow(row.id, {
          errorMessage: "Select a reciprocal role from the list."
        });
        skippedCount += 1;
        return;
      }

      if (!row.inverseReciprocalRoleId) {
        this.updateRow(row.id, {
          errorMessage: "Select an inverse reciprocal role from the list."
        });
        skippedCount += 1;
        return;
      }

      if (row.relatedAccountId === memberAccountId) {
        this.updateRow(row.id, {
          errorMessage: "A member cannot be related to themselves."
        });
        skippedCount += 1;
        return;
      }

      if (row.isExisting && row.relationId && !this.isRowChanged(row)) {
        return;
      }

      const relationshipKey = `${memberAccountId}:${row.relatedAccountId}`;
      if (seenRelationshipKeys.has(relationshipKey)) {
        this.updateRow(row.id, {
          errorMessage:
            "This person account is already related for the selected client. Remove the duplicate row."
        });
        skippedCount += 1;
        return;
      }

      seenRelationshipKeys.set(relationshipKey, row.id);
      validated.push(row);
    });

    return { validated, skippedCount };
  }

  clearRowErrors() {
    this.relationshipRows = this.relationshipRows.map((row) => ({
      ...row,
      errorMessage: ""
    }));
  }

  updateRow(rowId, patch) {
    this.relationshipRows = this.relationshipRows.map((row) =>
      row.id === rowId ? { ...row, ...patch } : row
    );
  }

  resolveRowId(event) {
    const raw = event.currentTarget?.dataset?.rowId;
    if (!raw) {
      return null;
    }

    const parsed = Number(raw);
    return Number.isNaN(parsed) ? null : parsed;
  }
}