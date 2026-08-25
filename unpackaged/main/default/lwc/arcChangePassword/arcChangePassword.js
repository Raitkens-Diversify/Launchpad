import { LightningElement } from "lwc";
import LightningToast from "lightning/toast";
import changePassword from "@salesforce/apex/ArcPasswordController.changePassword";

/**
 * Password tab of the Arc settings surface.
 *
 * The avatar menu used to send "Change password" to /ARC/ChangePassword, a
 * route this site does not define, so it landed on the site's Invalid Page.
 * This is the branded replacement, and it lives inside Settings so it inherits
 * the tab strip and page chrome rather than being a page of its own.
 *
 * The org's password policy is the authority on what is acceptable. Only the
 * checks that can be made without a round trip are made here — the rest is left
 * to Apex, whose refusal is shown verbatim, so this component never claims a
 * rule the org does not actually enforce.
 */

/** Mirrors ArcPasswordController.MIN_LENGTH. */
const MIN_LENGTH = 8;

/** The three fields, in the order the form draws them. */
const FIELDS = ["current", "next", "confirm"];

export default class ArcChangePassword extends LightningElement {
  current = "";
  next = "";
  confirm = "";

  /** Which fields have had their reveal toggled on, keyed by field name. */
  revealed = {};

  isSaving = false;
  errorMessage = "";

  // ---- Field plumbing ----------------------------------------------------

  handleInput(event) {
    const field = event.target.dataset.field;
    if (FIELDS.includes(field)) {
      this[field] = event.target.value;
      // The banner describes the submission that just failed; the moment the
      // user edits anything it is describing something that no longer exists.
      this.errorMessage = "";
    }
  }

  handleToggleReveal(event) {
    const field = event.currentTarget.dataset.field;
    if (FIELDS.includes(field)) {
      this.revealed = { ...this.revealed, [field]: !this.revealed[field] };
    }
  }

  /**
   * One descriptor per row. Built as a list so the template draws the three
   * identical rows in a loop instead of repeating the markup three times.
   */
  get rows() {
    return [
      {
        key: "current",
        label: "Current password",
        help: "Confirm the password you use today.",
        autocomplete: "current-password",
        value: this.current
      },
      {
        key: "next",
        label: "New password",
        help: `Must be at least ${MIN_LENGTH} characters.`,
        autocomplete: "new-password",
        value: this.next
      },
      {
        key: "confirm",
        label: "Confirm new password",
        help: "Type your new password once more.",
        autocomplete: "new-password",
        value: this.confirm
      }
    ].map((row) => {
      const isRevealed = Boolean(this.revealed[row.key]);
      return {
        ...row,
        type: isRevealed ? "text" : "password",
        toggleLabel: isRevealed
          ? `Hide ${row.label.toLowerCase()}`
          : `Show ${row.label.toLowerCase()}`,
        toggleText: isRevealed ? "Hide" : "Show"
      };
    });
  }

  // ---- Requirements ------------------------------------------------------

  get isLongEnough() {
    return this.next.length >= MIN_LENGTH;
  }

  get isMatching() {
    return this.next.length > 0 && this.next === this.confirm;
  }

  get isChanged() {
    return this.next.length > 0 && this.next !== this.current;
  }

  /**
   * The live checklist under the form. Each entry reports only something this
   * component actually checks, so a tick is never a promise Apex might break.
   */
  get requirements() {
    return [
      {
        key: "length",
        label: `At least ${MIN_LENGTH} characters`,
        met: this.isLongEnough
      },
      {
        key: "match",
        label: "Both new password entries match",
        met: this.isMatching
      },
      {
        key: "changed",
        label: "Different from your current password",
        met: this.isChanged
      }
    ].map((entry) => ({
      ...entry,
      itemClass: entry.met
        ? "password-settings__requirement password-settings__requirement--met"
        : "password-settings__requirement",
      iconName: entry.met ? "utility:check" : "utility:dash",
      // The tick/dash is decorative — the wording already carries the state,
      // and the whole list is announced through aria-live on submit failure.
      status: entry.met ? "Met" : "Not met"
    }));
  }

  get canSubmit() {
    return (
      Boolean(this.current) &&
      this.isLongEnough &&
      this.isMatching &&
      this.isChanged
    );
  }

  get isSubmitDisabled() {
    return this.isSaving || !this.canSubmit;
  }

  get isResetDisabled() {
    return (
      this.isSaving || !(this.current || this.next || this.confirm)
    );
  }

  get submitLabel() {
    return this.isSaving ? "Updating…" : "Update password";
  }

  // ---- Submit ------------------------------------------------------------

  handleReset() {
    FIELDS.forEach((field) => {
      this[field] = "";
    });
    this.revealed = {};
    this.errorMessage = "";
  }

  async handleSubmit() {
    if (this.isSubmitDisabled) {
      return;
    }

    this.isSaving = true;
    this.errorMessage = "";

    try {
      await changePassword({
        oldPassword: this.current,
        newPassword: this.next,
        confirmPassword: this.confirm
      });

      // Nothing is kept once the change lands — leaving the old password in a
      // live component is a credential sitting in memory for no reason.
      this.handleReset();
      LightningToast.show(
        {
          label: "Password updated",
          message: "Use your new password the next time you sign in.",
          variant: "success"
        },
        this
      );
    } catch (error) {
      this.errorMessage = this.readError(
        error,
        "Your password could not be changed. Please try again."
      );
    } finally {
      this.isSaving = false;
    }
  }

  readError(error, fallback) {
    return (
      error?.body?.message ||
      error?.body?.output?.errors?.[0]?.message ||
      error?.message ||
      fallback
    );
  }
}