import { LightningElement, api } from "lwc";
import ARC_LOGO from "@salesforce/resourceUrl/ArcLogoLite";

/**
 * arcWelcomeModal
 *
 * The one panel a new user meets, in two stages: the welcome message, then the
 * walkthrough. Purely presentational — it holds no opinion about whether it
 * should be shown, which step is current, or whether the tour has been seen.
 * Its parent (c/arcWelcomeExperience) owns all of that, so there is exactly one
 * place that knows the rules.
 *
 * ONE MODAL, TWO STAGES, on purpose. Closing a welcome dialog and opening a
 * separate tour dialog reads as two interruptions; keeping the same frame up
 * and swapping what is inside it reads as one thing continuing, and there is no
 * backdrop flash between "Let's Go" and the first step. The frame widens for
 * the walkthrough because the preview needs the room — see modalStyle.
 *
 * Chrome is c/dsModalV2 rather than a hand-rolled dialog: it already carries
 * the backdrop, the focus trap, Escape-to-close and focus restore, and it is
 * what every other ARC modal is built on, so this one behaves identically to
 * them. The welcome stage's layout follows c/arcUpgradeModal — logo in the
 * header slot, copy in the body, action in the footer. That is not consistency
 * for its own sake: dsModalV2's header is a shrink-to-fit flex child inside its
 * own shadow root, so a centred logo is not reachable from out here without
 * editing dsModalV2 and every modal already on it.
 *
 * Events: `start` (take the tour), `next`, `back`, `skip`, and `dismiss` for
 * the × or Escape. The parent decides what each of them means.
 */

/** Widths per stage. Only dsModalV2's `small` container honours the override. */
const WELCOME_WIDTH = "520px";
const TOUR_WIDTH = "940px";

export default class ArcWelcomeModal extends LightningElement {
  /** Parent-controlled. The panel renders no DOM at all while this is false. */
  @api isOpen = false;

  /** "welcome" for the opening message, "tour" for the walkthrough. */
  @api stage = "welcome";

  // ---- current step (tour stage only) ------------------------------------

  @api stepTitle = "";
  @api stepBody = "";
  /** Zero-based. */
  @api stepIndex = 0;
  @api stepCount = 0;

  // ---- what the preview should draw --------------------------------------

  @api screen;
  @api navId;
  @api region;

  logoUrl = ARC_LOGO;

  get isWelcome() {
    return this.stage !== "tour";
  }

  get isTour() {
    return this.stage === "tour";
  }

  /**
   * The frame is sized from out here rather than by swapping dsModalV2's
   * `size`, because only its `small` container reads --ds-modal-width; medium
   * and large are fixed at 560px and 750px, and the preview needs more than
   * either. The width change itself is not animated — the container it applies
   * to lives in dsModalV2's shadow root, so a transition would have to be
   * declared there and would then apply to all sixteen modals on it.
   */
  get modalStyle() {
    const width = this.isTour ? TOUR_WIDTH : WELCOME_WIDTH;
    return [
      `--ds-modal-width: ${width}`,
      "--ds-modal-radius: 12px",
      "--ds-modal-padding: 24px",
      "--ds-modal-body-padding: 0 24px 4px",
      "--ds-modal-backdrop-bg: rgba(7, 28, 49, 0.6)",
      "--ds-modal-backdrop-blur: 4px",
      "--ds-modal-shadow: 0 24px 64px rgba(9, 36, 63, 0.22), 0 2px 8px rgba(9, 36, 63, 0.14)"
    ].join("; ");
  }

  get progressLabel() {
    return `${this.stepIndex + 1} of ${this.stepCount}`;
  }

  get dots() {
    return Array.from({ length: this.stepCount }, (unused, index) => ({
      key: `dot-${index}`,
      className:
        index === this.stepIndex
          ? "welcome-tour__dot welcome-tour__dot--on"
          : "welcome-tour__dot"
    }));
  }

  get showBack() {
    return this.stepIndex > 0;
  }

  get isLastStep() {
    return this.stepIndex >= this.stepCount - 1;
  }

  get nextLabel() {
    return this.isLastStep ? "Finish" : "Next";
  }

  // ---- events ------------------------------------------------------------

  handleStart() {
    this.dispatchEvent(new CustomEvent("start"));
  }

  handleNext() {
    this.dispatchEvent(new CustomEvent("next"));
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent("back"));
  }

  handleSkip() {
    this.dispatchEvent(new CustomEvent("skip"));
  }

  /**
   * dsModalV2's `close` is composed and bubbling, so without stopping it here
   * it would keep travelling past this component and out into the page. The
   * parent gets the intent as `dismiss` instead.
   */
  handleDismiss(event) {
    event.stopPropagation();
    this.dispatchEvent(new CustomEvent("dismiss"));
  }
}