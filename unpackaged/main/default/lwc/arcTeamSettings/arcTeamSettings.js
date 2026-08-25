import { LightningElement, api, wire } from "lwc";
import getMyTeams from "@salesforce/apex/ArcTeamSettingsController.getMyTeams";
import getTeam from "@salesforce/apex/ArcTeamSettingsController.getTeam";
import USER_ID from "@salesforce/user/Id";

/**
 * Team tab of the Arc settings surface.
 *
 * Three things, in the order the internal Financial Advisor Team layout puts
 * them: the team itself, the people on it with their role and permissions, and
 * the team's rep codes.
 *
 * Team and role are not the same thing and this component keeps them apart. The
 * team is the Financial Advisor Team; the role is the member's job on that team,
 * and the same person can hold a different role on each team they belong to. So
 * a role is never shown without the team it belongs to, and the "your
 * assignment" callout is rendered per team rather than once for the user.
 */

/** Above this many members the roster gets its own scroll rather than growing the page. */
const ROSTER_SCROLL_THRESHOLD = 12;

export default class ArcTeamSettings extends LightningElement {
  /**
   * Show one named team instead of the running user's own teams. Set by
   * surfaces that already know the team — a case's Financial Advisor Team, say.
   */
  @api teamId;

  teams = [];
  isLoading = true;
  errorMessage;
  activeTeamId;

  @wire(getMyTeams)
  wiredMyTeams({ data, error }) {
    if (this.teamId) {
      // A named team wins; this wire still fires but its result is not the
      // question being asked.
      return;
    }
    this.handleResult(data, error);
  }

  @wire(getTeam, { teamId: "$teamId" })
  wiredNamedTeam({ data, error }) {
    if (!this.teamId) {
      return;
    }
    this.handleResult(data ? [data] : data, error);
  }

  handleResult(data, error) {
    if (data) {
      this.teams = data.filter(Boolean);
      this.errorMessage = undefined;
      this.isLoading = false;
      if (!this.activeTeamId && this.teams.length) {
        this.activeTeamId = this.teams[0].id;
      }
      return;
    }

    if (error) {
      this.teams = [];
      this.errorMessage = this.reduceError(error);
      this.isLoading = false;
      // eslint-disable-next-line no-console
      console.error("[arcTeamSettings] Failed to load teams", error);
    }
  }

  // ---- Derived view state -------------------------------------------------

  get hasTeams() {
    return this.teams.length > 0;
  }

  get showEmptyState() {
    return !this.isLoading && !this.errorMessage && !this.hasTeams;
  }

  /**
   * Team chips, shown only when the user is on more than one. With a single
   * team a picker is noise, and the team's name is already in its heading.
   */
  get showTeamPicker() {
    return this.teams.length > 1;
  }

  get teamTabs() {
    return this.teams.map((team) => ({
      id: team.id,
      name: team.name,
      buttonClass:
        team.id === this.activeTeamId
          ? "team-tab team-tab--active"
          : "team-tab"
    }));
  }

  get activeTeam() {
    return this.teams.find((team) => team.id === this.activeTeamId);
  }

  /** Header facts for the active team, skipping anything the record leaves blank. */
  get teamFacts() {
    const team = this.activeTeam;
    if (!team) {
      return [];
    }

    const facts = [
      { key: "branch", label: "Branch", value: team.branchName },
      {
        key: "primary",
        label: "Primary Financial Advisor",
        value: team.primaryAdvisorName
      },
      { key: "status", label: "Status", value: team.status },
      { key: "rep", label: "Rep Number", value: team.repNumber },
      {
        key: "orion",
        label: "Orion ID",
        // A Number(18,0) arrives as a JS number; rendered as a plain integer
        // because it is an identifier, not a quantity to be grouped.
        value:
          team.orionId === null || team.orionId === undefined
            ? null
            : String(team.orionId)
      },
      { key: "states", label: "Registered States", value: team.registeredStates },
      { key: "owner", label: "Owner", value: team.ownerName },
      {
        key: "tiered",
        label: "Tiered IMA Advisory Fee",
        // Checkbox, not an amount — see the controller's wrapper note.
        value: team.hasTieredAdvisoryFee ? "Yes" : null
      }
    ];

    return facts.filter((fact) => fact.value !== null && fact.value !== "" && fact.value !== undefined);
  }

  /**
   * The roster. Each member carries their permissions already resolved to
   * labels, so the template does no lookups.
   */
  get members() {
    const team = this.activeTeam;
    if (!team?.members) {
      return [];
    }

    const labels = this.permissionLabelsByField;

    return team.members.map((member) => ({
      ...member,
      isSelf: member.userId === USER_ID,
      roleLabel: member.role || "—",
      rowClass:
        member.userId === USER_ID
          ? "roster__row roster__row--self"
          : "roster__row",
      permissionChips: (member.permissions || []).map((field) => ({
        key: `${member.memberId}-${field}`,
        label: labels[field] || field
      })),
      hasPermissions: (member.permissions || []).length > 0
    }));
  }

  get memberCount() {
    return this.members.length;
  }

  get rosterClass() {
    return this.memberCount > ROSTER_SCROLL_THRESHOLD
      ? "roster roster--scrolls"
      : "roster";
  }

  /** field API name → label, taken from the permission rows the server sent. */
  get permissionLabelsByField() {
    const out = {};
    (this.activeTeam?.permissions || []).forEach((row) => {
      out[row.field] = row.label;
    });
    return out;
  }

  /**
   * Team-level permissions: one row per permission naming who holds it.
   * Rows nobody holds are kept — "nobody on this team can trade" is the
   * answer someone auditing permissions came for.
   */
  get permissionRows() {
    return (this.activeTeam?.permissions || []).map((row) => ({
      ...row,
      holderText: row.holders?.length ? row.holders.join(", ") : "No one assigned",
      holderClass: row.holders?.length
        ? "permissions__holders"
        : "permissions__holders permissions__holders--empty",
      count: row.holders?.length || 0
    }));
  }

  get repCodes() {
    return (this.activeTeam?.repCodes || []).map((code) => ({
      ...code,
      codeTypeLabel: code.codeType || "—",
      statusLabel: code.status || "—"
    }));
  }

  get hasRepCodes() {
    return this.repCodes.length > 0;
  }

  /**
   * The running user's own membership of the active team. Answers "what am I on
   * this team" without making them find themselves in the roster.
   *
   * Plural on purpose. A user can hold more than one active membership of the
   * same team — two do in this org — and each membership carries its own role
   * and its own permissions. Picking the first would report one of two roles as
   * though it were the only one, so every role is listed and the permissions
   * are the union across them.
   */
  get myAssignment() {
    const mine = this.members.filter((member) => member.isSelf);
    if (!mine.length) {
      return null;
    }

    const roles = mine
      .map((member) => member.role)
      .filter(Boolean);

    const chips = [];
    const seenLabels = new Set();
    mine.forEach((member) => {
      member.permissionChips.forEach((chip) => {
        if (!seenLabels.has(chip.label)) {
          seenLabels.add(chip.label);
          chips.push(chip);
        }
      });
    });

    return {
      role: roles.length ? [...new Set(roles)].join(", ") : "No role assigned",
      isPrimary: mine.some((member) => member.isPrimary),
      permissionChips: chips,
      hasPermissions: chips.length > 0,
      teamName: this.activeTeam?.name
    };
  }

  // ---- Events -------------------------------------------------------------

  handleTeamSelect(event) {
    const id = event.currentTarget.dataset.id;
    if (id) {
      this.activeTeamId = id;
    }
  }

  reduceError(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "Something went wrong loading your team."
    );
  }
}