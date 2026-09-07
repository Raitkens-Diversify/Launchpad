import { LightningElement, api } from "lwc";
import ARC_ICONS from "@salesforce/resourceUrl/arcicon";
import ARC_LOGO from "@salesforce/resourceUrl/ArcLogoLite";
import BUILT_BY_DIVERSIFY from "@salesforce/resourceUrl/ArcBuiltByDiversify";
import { STATIC_NAV_ITEMS } from "c/arcNavTrailState";

/**
 * arcTourPreview
 *
 * A scaled-down replica of ARC, used by the first-login walkthrough. Every step
 * tells it which screen to draw and which part of that screen to light up.
 *
 * WHY A REPLICA AND NOT THE APP. The walkthrough used to drive the real thing:
 * navigate, wait for the route, wait for the @wire, then spotlight what
 * arrived. Every step cost a route transition plus a server round trip — most
 * of a second of dead screen, ten times over — and it could only show a case if
 * the user happened to have an open one. Here "highlight the sidebar" is a CSS
 * class on an element this component owns, so a step change is one paint and
 * always lands in the right place.
 *
 * WHY NOT SCREENSHOTS, which would be pixel-exact and a fraction of this code:
 * every real screen in this org is full of real client data — household names,
 * case numbers, the names of real people. Shipping that to every user who logs
 * in is not something a welcome tour should do. A DOM replica is scrubbed by
 * construction, scales with the viewport, and can be corrected in a diff.
 *
 * WHAT KEEPS IT HONEST.
 *  - The chrome cannot drift: the sidebar comes from c/arcNavTrailState's
 *    STATIC_NAV_ITEMS with the icons from the arcicon resource, the Contacts
 *    tab strip from that group's own submenu, and the wordmark and rail footer
 *    from the same static resources the real header and rail use.
 *  - The SCREENS map below was written against the real pages, screen by
 *    screen: breadcrumbs, headings, subtitles, tab names, toolbar shape and
 *    column headers all match what those pages actually render. That part IS
 *    hand-maintained — if a page gains a column or loses a tab, correct it here.
 *    Where each list's columns come from, so they can be re-checked:
 *      Contacts, Cases, Tasks, Accounts, Advertising Reviews — the
 *        c:arcRecordListView placement on the page in
 *        digitalExperiences/site/Arc1/sfdc_cms__view/<Page>/content.json
 *        (viewTabs[].columns, else defaultColumns, else the list view's own
 *        columns), with pillFields naming the columns drawn as pills;
 *      Home's Work table — c/workTable COLUMNS;
 *      the case page — c/arcCaseDetail, c/caseOverviewTile, the three track
 *        cards and c/caseCurrentTask;
 *      the Resource Center — c/resourceCenter over c/resourceCategoryPage.
 *    Last reconciled against the launchpad org on 2026-09-07.
 *  - Row values are invented. They illustrate shape, and are deliberately
 *    ordinary-looking rather than copied out of the org.
 *
 * Sizes are absolute rather than token-derived: this is a picture of the app at
 * roughly half scale, so it must not inherit page type sizes and grow out of
 * the modal it sits in. Type is held at a readable floor rather than scaled
 * proportionally — a true 0.45 scale would put body text at 6px.
 */

/** Cell kinds a list row can hold, mapped to classes in mapRows. */
const CELL = {
  LEAD: "lead",
  TEXT: "text",
  MUTED: "muted",
  PILL: "pill"
};

/**
 * Column headers. A plain string is an equal-share column. `{ label, flex }`
 * is a weighted share. `{ label, width }` pins the column to that many pixels:
 * used, with `dense: true`, for the lists whose real tables carry more columns
 * than fit at a readable size. Such a column grows into spare room but never
 * shrinks below its width, so a table that fits fills the row and one that
 * does not is clipped at the edge, the way the real table scrolls sideways.
 */
const columnStyle = (def) => {
  if (def.width) {
    return `flex: 1 0 ${def.width}px; min-width: 0`;
  }
  if (def.flex) {
    return `flex: ${def.flex}`;
  }
  return "";
};

const columnDef = (col) => (typeof col === "string" ? { label: col } : col);

/*
 * The Cases list, Home's Work table and the Tasks list share the same column
 * vocabulary, so the same sample cases appear in all three — a new user should
 * recognise 00012418 wherever it turns up.
 */
const CASE_COLUMNS = [
  { label: "Case Number", width: 58 },
  { label: "Case", width: 84 },
  { label: "Household", width: 64 },
  { label: "Assignee | Current Task Subject", width: 124 },
  { label: "Case Overall Status", width: 76 },
  { label: "Milestone", width: 52 },
  { label: "Case Owner", width: 60 },
  { label: "Date/Time Opened", width: 64 },
  { label: "Financial Advisor Team", width: 96 }
];

const caseRow = (
  number,
  branchName,
  household,
  assigneeTask,
  overall,
  milestone,
  owner,
  opened,
  team
) => [
  { kind: CELL.LEAD, value: number },
  { kind: CELL.TEXT, value: branchName },
  { kind: CELL.LEAD, value: household },
  { kind: assigneeTask ? CELL.TEXT : CELL.MUTED, value: assigneeTask || "–" },
  { kind: CELL.TEXT, value: overall },
  { kind: milestone ? CELL.TEXT : CELL.MUTED, value: milestone || "–" },
  { kind: CELL.TEXT, value: owner },
  { kind: CELL.TEXT, value: opened },
  { kind: CELL.TEXT, value: team }
];

const CASE_ROWS = [
  caseRow(
    "00012418",
    "Account Opening | Joint | SCHWAB | AMS | RIA | Whitfield | Alex Morgan | $ 250,000",
    "Whitfield Household",
    "Alex Morgan | Collect updated ID",
    "On Track",
    "HO Submission",
    "Alex Morgan",
    "1/8/2026",
    "Morgan Advisors"
  ),
  caseRow(
    "00012402",
    "Account Opening | Roth IRA | FIDELITY | DMS | RIA | Reyes | Alex Morgan | $ 40,000",
    "Reyes Household",
    "Alex Morgan | Prep Account Opening Paperwork",
    "On Track",
    "HO Submission",
    "Alex Morgan",
    "1/6/2026",
    "Morgan Advisors"
  ),
  caseRow(
    "00012377",
    "Account Servicing | Trustee Change | Brennan Family Trust",
    "Brennan Family Trust",
    "Home Office | Review trustee documents",
    "HO Pit Stop",
    "HO Approval",
    "Dana Whitlock",
    "12/29/2025",
    "Whitlock Wealth Partners"
  ),
  caseRow(
    "00012351",
    "Account Opening | 401(k) | FIDELITY | DMS | RIA | Kesler Dental Group | Dana Whitlock | $ 1,200,000",
    "Kesler Dental Group",
    "Dana Whitlock | Collect plan documents",
    "On Track",
    "HO Submission",
    "Dana Whitlock",
    "12/22/2025",
    "Whitlock Wealth Partners"
  ),
  caseRow(
    "00012340",
    "Account Servicing | Plan Amendment | Marsh & Doyle 401(k)",
    "Marsh & Doyle 401(k)",
    "Branch | Missing signature page",
    "Branch Pit Stop",
    "HO Approval",
    "Dana Whitlock",
    "12/18/2025",
    "Whitlock Wealth Partners"
  ),
  caseRow(
    "00012322",
    "Account Servicing | Beneficiary Update | Raman",
    "Raman Household",
    "Alex Morgan | Confirm beneficiary",
    "On Track",
    "Branch Goal",
    "Alex Morgan",
    "12/15/2025",
    "Morgan Advisors"
  ),
  caseRow(
    "00012318",
    "Account Servicing | Address Change | Delgado",
    "Delgado Household",
    null,
    "Completed",
    "Branch Goal",
    "Alex Morgan",
    "12/11/2025",
    "Morgan Advisors"
  ),
  caseRow(
    "00012301",
    "Account Opening | Transfer | SCHWAB | AMS | RIA | Hartley | Alex Morgan | $ 85,000",
    "Hartley Household",
    "Alex Morgan | Request transfer paperwork",
    "On Track",
    "HO Submission",
    "Alex Morgan",
    "12/8/2025",
    "Morgan Advisors"
  ),
  caseRow(
    "00012288",
    "Account Opening | SEP IRA | FIDELITY | DMS | RIA | Northfield Bakery | Dana Whitlock | $ 60,000",
    "Northfield Bakery",
    null,
    "Completed",
    "Branch Goal",
    "Dana Whitlock",
    "12/3/2025",
    "Whitlock Wealth Partners"
  )
];

/** Home's Work table is the Cases columns minus Household (c/workTable). */
const WORK_COLUMNS = CASE_COLUMNS.filter((col) => col.label !== "Household");
const WORK_ROWS = CASE_ROWS.slice(0, 3).map((cells) =>
  cells.filter((cell, index) => index !== 2)
);

/** kind: "dashboard" | "list" | "record" | "resources" | "settings" */
const SCREENS = {
  home: {
    kind: "dashboard",
    greeting: "Welcome, Alex",
    date: "Mon, 12 January",
    actions: ["Envelope Wizard", "New Advertising Request", "Check Log"],
    announcement: {
      title: "Announcement message title goes here",
      body: "Additional information about announcement goes here"
    },
    /* c/arcHomeMetrics tiles, labels and subtexts as it renders them. */
    tiles: [
      { key: "m1", label: "Cases", value: "10", sub: "Assigned to me" },
      { key: "m2", label: "Tasks", value: "22", sub: "Assigned to me" },
      { key: "m3", label: "Cases", value: "20", sub: "Assigned to my teams’" },
      { key: "m4", label: "Tasks", value: "62", sub: "Assigned to my teams’" },
      {
        key: "m5",
        label: "My Pitstop Tasks",
        value: "3",
        sub: "Branch and home office"
      }
    ],
    donuts: [
      {
        key: "d1",
        title: "My Cases",
        sub: "By milestone",
        legend: "Started",
        value: "10"
      },
      {
        key: "d2",
        title: "My Team Cases",
        sub: "By milestone",
        legend: "Started",
        value: "20"
      }
    ],
    workTitle: "Work",
    workScopes: ["My", "My Team"],
    workSearch: "Search work...",
    workColumns: WORK_COLUMNS,
    workRows: WORK_ROWS,
    bars: [
      {
        key: "b1",
        title: "My Tasks",
        sub: "Main track vs pit stop",
        rows: [
          {
            key: "b1a",
            label: "Main track",
            value: "7",
            barStyle: "width: 44%",
            tone: "tp-bar--blue"
          },
          {
            key: "b1b",
            label: "HO pit stop",
            value: "6",
            barStyle: "width: 38%",
            tone: "tp-bar--green"
          },
          {
            key: "b1c",
            label: "Branch pit stop",
            value: "9",
            barStyle: "width: 56%",
            tone: "tp-bar--violet"
          }
        ]
      },
      {
        key: "b2",
        title: "My Team Tasks",
        sub: "Main track vs pit stop",
        rows: [
          {
            key: "b2a",
            label: "Main track",
            value: "38",
            barStyle: "width: 76%",
            tone: "tp-bar--blue"
          },
          {
            key: "b2b",
            label: "HO pit stop",
            value: "12",
            barStyle: "width: 24%",
            tone: "tp-bar--green"
          },
          {
            key: "b2c",
            label: "Branch pit stop",
            value: "12",
            barStyle: "width: 24%",
            tone: "tp-bar--violet"
          }
        ]
      }
    ]
  },

  /* Account_List page, "All Contacts" tab. Permanent State is the pill. */
  contacts: {
    kind: "list",
    crumbs: ["Contacts", "All Contacts"],
    title: "Contacts",
    contactTabs: true,
    columns: [
      { label: "Contact Name", flex: 1.4 },
      "Permanent State",
      "Phone",
      "Type",
      "Record Type",
      { label: "Financial Advisor Team", flex: 1.3 }
    ],
    rows: [
      [
        { kind: CELL.LEAD, value: "Ana Reyes" },
        { kind: CELL.PILL, value: "Colorado", tone: "indigo" },
        { kind: CELL.TEXT, value: "(303) 555-0142" },
        { kind: CELL.TEXT, value: "Active Client" },
        { kind: CELL.TEXT, value: "Person Account" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Whitfield Household" },
        { kind: CELL.PILL, value: "Oregon", tone: "teal" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Active Client" },
        { kind: CELL.TEXT, value: "Household" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Brennan Family Trust" },
        { kind: CELL.PILL, value: "Illinois", tone: "amber" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Active Client" },
        { kind: CELL.TEXT, value: "Trust" },
        { kind: CELL.TEXT, value: "Whitlock Wealth Partners" }
      ],
      [
        { kind: CELL.LEAD, value: "Kesler Dental Group" },
        { kind: CELL.PILL, value: "Texas", tone: "indigo" },
        { kind: CELL.TEXT, value: "(512) 555-0188" },
        { kind: CELL.TEXT, value: "Prospect" },
        { kind: CELL.TEXT, value: "Business" },
        { kind: CELL.TEXT, value: "Whitlock Wealth Partners" }
      ],
      [
        { kind: CELL.LEAD, value: "Marsh & Doyle 401(k)" },
        { kind: CELL.PILL, value: "Ohio", tone: "teal" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Active Client" },
        { kind: CELL.TEXT, value: "Retirement Plan" },
        { kind: CELL.TEXT, value: "Whitlock Wealth Partners" }
      ],
      [
        { kind: CELL.LEAD, value: "Priya Raman" },
        { kind: CELL.PILL, value: "Washington", tone: "indigo" },
        { kind: CELL.TEXT, value: "(206) 555-0117" },
        { kind: CELL.TEXT, value: "Prospect" },
        { kind: CELL.TEXT, value: "Person Account" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Delgado Household" },
        { kind: CELL.PILL, value: "Arizona", tone: "amber" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Active Client" },
        { kind: CELL.TEXT, value: "Household" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Northfield Bakery" },
        { kind: CELL.PILL, value: "Minnesota", tone: "teal" },
        { kind: CELL.TEXT, value: "(612) 555-0163" },
        { kind: CELL.TEXT, value: "Prospect" },
        { kind: CELL.TEXT, value: "Business" },
        { kind: CELL.TEXT, value: "Whitlock Wealth Partners" }
      ],
      [
        { kind: CELL.LEAD, value: "Owen Hartley" },
        { kind: CELL.PILL, value: "Georgia", tone: "indigo" },
        { kind: CELL.TEXT, value: "(404) 555-0129" },
        { kind: CELL.TEXT, value: "Active Client" },
        { kind: CELL.TEXT, value: "Person Account" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ]
    ]
  },

  /*
   * Case_List page, "All Cases" tab — the nine columns every Cases tab shares.
   * Status and Priority are configured as pills there but are not among the
   * columns, so nothing in this table is drawn as a pill.
   */
  cases: {
    kind: "list",
    crumbs: ["Work", "Cases"],
    title: "Cases",
    tabs: ["All Cases", "My Open Cases", "My Team's Open Cases"],
    dense: true,
    columns: CASE_COLUMNS,
    rows: CASE_ROWS
  },

  /* Task_List page, "All Tasks" tab. Status is the pill. */
  tasks: {
    kind: "list",
    crumbs: ["Work", "Tasks"],
    title: "Tasks",
    tabs: ["All Tasks", "My Open Tasks", "My Team's Open Tasks"],
    dense: true,
    columns: [
      { label: "Subject", width: 96 },
      { label: "Case Number", width: 58 },
      { label: "Household", width: 60 },
      { label: "Client", width: 54 },
      { label: "Due Date", width: 50 },
      { label: "Last Modified", width: 60 },
      { label: "Assigned To", width: 60 },
      { label: "Financial Advisor Team", width: 96 },
      { label: "Priority", width: 44 },
      { label: "Status", width: 60 },
      { label: "Last Modified By Alias", width: 90 },
      { label: "Created By", width: 70 }
    ],
    rows: [
      [
        { kind: CELL.LEAD, value: "Collect updated ID" },
        { kind: CELL.LEAD, value: "00012418" },
        { kind: CELL.LEAD, value: "Whitfield Household" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "1/14/2026" },
        { kind: CELL.TEXT, value: "1/9/2026" },
        { kind: CELL.TEXT, value: "Alex Morgan" },
        { kind: CELL.TEXT, value: "Morgan Advisors" },
        { kind: CELL.TEXT, value: "Normal" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Alex Morgan" }
      ],
      [
        { kind: CELL.LEAD, value: "Advisor review" },
        { kind: CELL.LEAD, value: "00012418" },
        { kind: CELL.LEAD, value: "Whitfield Household" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "1/16/2026" },
        { kind: CELL.TEXT, value: "1/8/2026" },
        { kind: CELL.TEXT, value: "Alex Morgan" },
        { kind: CELL.TEXT, value: "Morgan Advisors" },
        { kind: CELL.TEXT, value: "Normal" },
        { kind: CELL.PILL, value: "Not Started", tone: "grey" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Alex Morgan" }
      ],
      [
        { kind: CELL.LEAD, value: "Prep Account Opening Paperwork" },
        { kind: CELL.LEAD, value: "00012402" },
        { kind: CELL.LEAD, value: "Reyes Household" },
        { kind: CELL.LEAD, value: "Ana Reyes" },
        { kind: CELL.TEXT, value: "1/15/2026" },
        { kind: CELL.TEXT, value: "1/6/2026" },
        { kind: CELL.TEXT, value: "Alex Morgan" },
        { kind: CELL.TEXT, value: "Morgan Advisors" },
        { kind: CELL.TEXT, value: "High" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Alex Morgan" }
      ],
      [
        { kind: CELL.LEAD, value: "Notify Client - New Account Is Open" },
        { kind: CELL.LEAD, value: "00012402" },
        { kind: CELL.LEAD, value: "Reyes Household" },
        { kind: CELL.LEAD, value: "Ana Reyes" },
        { kind: CELL.TEXT, value: "1/20/2026" },
        { kind: CELL.TEXT, value: "1/6/2026" },
        { kind: CELL.MUTED, value: "Unassigned" },
        { kind: CELL.TEXT, value: "Morgan Advisors" },
        { kind: CELL.TEXT, value: "Normal" },
        { kind: CELL.PILL, value: "Not Started", tone: "grey" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Alex Morgan" }
      ],
      [
        { kind: CELL.LEAD, value: "Review trustee documents" },
        { kind: CELL.LEAD, value: "00012377" },
        { kind: CELL.LEAD, value: "Brennan Family Trust" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "1/12/2026" },
        { kind: CELL.TEXT, value: "1/5/2026" },
        { kind: CELL.TEXT, value: "Home Office" },
        { kind: CELL.TEXT, value: "Whitlock Wealth Partners" },
        { kind: CELL.TEXT, value: "Normal" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.TEXT, value: "dwhitlock" },
        { kind: CELL.TEXT, value: "Dana Whitlock" }
      ],
      [
        { kind: CELL.LEAD, value: "Collect plan documents" },
        { kind: CELL.LEAD, value: "00012351" },
        { kind: CELL.LEAD, value: "Kesler Dental Group" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "1/18/2026" },
        { kind: CELL.TEXT, value: "12/30/2025" },
        { kind: CELL.TEXT, value: "Dana Whitlock" },
        { kind: CELL.TEXT, value: "Whitlock Wealth Partners" },
        { kind: CELL.TEXT, value: "Normal" },
        { kind: CELL.PILL, value: "Not Started", tone: "grey" },
        { kind: CELL.TEXT, value: "dwhitlock" },
        { kind: CELL.TEXT, value: "Dana Whitlock" }
      ],
      [
        { kind: CELL.LEAD, value: "Missing signature page" },
        { kind: CELL.LEAD, value: "00012340" },
        { kind: CELL.LEAD, value: "Marsh & Doyle 401(k)" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "1/22/2026" },
        { kind: CELL.TEXT, value: "12/29/2025" },
        { kind: CELL.TEXT, value: "Dana Whitlock" },
        { kind: CELL.TEXT, value: "Whitlock Wealth Partners" },
        { kind: CELL.TEXT, value: "High" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.TEXT, value: "dwhitlock" },
        { kind: CELL.TEXT, value: "Dana Whitlock" }
      ],
      [
        { kind: CELL.LEAD, value: "Confirm beneficiary" },
        { kind: CELL.LEAD, value: "00012322" },
        { kind: CELL.LEAD, value: "Raman Household" },
        { kind: CELL.LEAD, value: "Priya Raman" },
        { kind: CELL.TEXT, value: "1/23/2026" },
        { kind: CELL.TEXT, value: "12/22/2025" },
        { kind: CELL.TEXT, value: "Alex Morgan" },
        { kind: CELL.TEXT, value: "Morgan Advisors" },
        { kind: CELL.TEXT, value: "Normal" },
        { kind: CELL.PILL, value: "Not Started", tone: "grey" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Alex Morgan" }
      ],
      [
        { kind: CELL.LEAD, value: "Request transfer paperwork" },
        { kind: CELL.LEAD, value: "00012301" },
        { kind: CELL.LEAD, value: "Hartley Household" },
        { kind: CELL.LEAD, value: "Owen Hartley" },
        { kind: CELL.TEXT, value: "1/26/2026" },
        { kind: CELL.TEXT, value: "12/15/2025" },
        { kind: CELL.MUTED, value: "Unassigned" },
        { kind: CELL.TEXT, value: "Morgan Advisors" },
        { kind: CELL.TEXT, value: "Normal" },
        { kind: CELL.PILL, value: "Not Started", tone: "grey" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Alex Morgan" }
      ]
    ]
  },

  /*
   * DFPG_Financial_Account_List page: a single saved view ("Accounts"), so the
   * real page draws no tab strip and — its title being blank in the Builder —
   * no heading either. Account Status is the pill.
   */
  isas: {
    kind: "list",
    crumbs: ["Investments & Services", "Accounts"],
    title: "",
    columns: [
      { label: "Financial Account Name", flex: 1.6 },
      "Type",
      "Account Status",
      "Account Number",
      "Primary Owner",
      "Household",
      "Balance",
      "Created Date"
    ],
    rows: [
      [
        { kind: CELL.LEAD, value: "Whitfield - Joint" },
        { kind: CELL.TEXT, value: "Joint" },
        { kind: CELL.PILL, value: "Normal Downloading", tone: "green" },
        { kind: CELL.TEXT, value: "••••4182" },
        { kind: CELL.TEXT, value: "Grace Whitfield" },
        { kind: CELL.TEXT, value: "Whitfield Household" },
        { kind: CELL.TEXT, value: "$250,000.00" },
        { kind: CELL.TEXT, value: "6/23/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Reyes - Roth IRA" },
        { kind: CELL.TEXT, value: "Roth IRA" },
        { kind: CELL.PILL, value: "Pending", tone: "amber" },
        { kind: CELL.TEXT, value: "••••3067" },
        { kind: CELL.TEXT, value: "Ana Reyes" },
        { kind: CELL.TEXT, value: "Reyes Household" },
        { kind: CELL.TEXT, value: "$40,000.00" },
        { kind: CELL.TEXT, value: "7/16/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Brennan Family Trust - Trust" },
        { kind: CELL.TEXT, value: "Trust" },
        { kind: CELL.PILL, value: "Normal Downloading", tone: "green" },
        { kind: CELL.TEXT, value: "••••2915" },
        { kind: CELL.TEXT, value: "Brennan Family Trust" },
        { kind: CELL.TEXT, value: "Brennan Family Trust" },
        { kind: CELL.TEXT, value: "$1,150,000.00" },
        { kind: CELL.TEXT, value: "8/11/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Kesler Dental Group - 401(k)" },
        { kind: CELL.TEXT, value: "Defined Contribution Plan" },
        { kind: CELL.PILL, value: "Manually Managed", tone: "grey" },
        { kind: CELL.TEXT, value: "••••7734" },
        { kind: CELL.TEXT, value: "Kesler Dental Group" },
        { kind: CELL.TEXT, value: "Kesler Dental Group" },
        { kind: CELL.TEXT, value: "$1,200,000.00" },
        { kind: CELL.TEXT, value: "9/2/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Raman - Traditional IRA" },
        { kind: CELL.TEXT, value: "Traditional IRA" },
        { kind: CELL.PILL, value: "Normal Downloading", tone: "green" },
        { kind: CELL.TEXT, value: "••••5520" },
        { kind: CELL.TEXT, value: "Priya Raman" },
        { kind: CELL.TEXT, value: "Raman Household" },
        { kind: CELL.TEXT, value: "$96,500.00" },
        { kind: CELL.TEXT, value: "9/18/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Whitfield - Individual" },
        { kind: CELL.TEXT, value: "Individual" },
        { kind: CELL.PILL, value: "Advisor Only", tone: "blue" },
        { kind: CELL.TEXT, value: "••••6688" },
        { kind: CELL.TEXT, value: "Grace Whitfield" },
        { kind: CELL.TEXT, value: "Whitfield Household" },
        { kind: CELL.TEXT, value: "$72,300.00" },
        { kind: CELL.TEXT, value: "10/2/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Delgado - Joint" },
        { kind: CELL.TEXT, value: "Joint" },
        { kind: CELL.PILL, value: "Normal Downloading", tone: "green" },
        { kind: CELL.TEXT, value: "••••8841" },
        { kind: CELL.TEXT, value: "Luis Delgado" },
        { kind: CELL.TEXT, value: "Delgado Household" },
        { kind: CELL.TEXT, value: "$310,000.00" },
        { kind: CELL.TEXT, value: "10/14/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Northfield Bakery - SEP IRA" },
        { kind: CELL.TEXT, value: "SEP IRA" },
        { kind: CELL.PILL, value: "Pending", tone: "amber" },
        { kind: CELL.TEXT, value: "••••6203" },
        { kind: CELL.TEXT, value: "Northfield Bakery" },
        { kind: CELL.TEXT, value: "Northfield Bakery" },
        { kind: CELL.TEXT, value: "$60,000.00" },
        { kind: CELL.TEXT, value: "11/1/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Hartley - Rollover IRA" },
        { kind: CELL.TEXT, value: "Rollover IRA" },
        { kind: CELL.PILL, value: "Pending", tone: "amber" },
        { kind: CELL.TEXT, value: "••••4417" },
        { kind: CELL.TEXT, value: "Owen Hartley" },
        { kind: CELL.TEXT, value: "Hartley Household" },
        { kind: CELL.TEXT, value: "$85,000.00" },
        { kind: CELL.TEXT, value: "11/19/2025" }
      ]
    ]
  },

  /*
   * Advertising_Reviews page, "My Team's Requests" tab. The tabs carry no
   * column list of their own, so the columns are the saved list view's:
   * Name, Advertising Type, Review Case, Status (the pill).
   */
  compliance: {
    kind: "list",
    crumbs: ["Compliance", "Advertising Reviews"],
    title: "Advertising Reviews",
    subtitle: "Advertising items submitted for compliance review",
    primaryAction: "New Advertising Item",
    tabs: ["My Team's Requests", "All Items"],
    columns: [
      { label: "Advertising Item Name", flex: 1.6 },
      "Advertising Type",
      "Review Case",
      "Status"
    ],
    rows: [
      [
        { kind: CELL.LEAD, value: "Q1 client newsletter" },
        { kind: CELL.TEXT, value: "Newsletter/Circular" },
        { kind: CELL.LEAD, value: "00012455" },
        { kind: CELL.PILL, value: "Approved", tone: "green" }
      ],
      [
        { kind: CELL.LEAD, value: "Retirement seminar invitation" },
        { kind: CELL.TEXT, value: "Event" },
        { kind: CELL.LEAD, value: "00012461" },
        { kind: CELL.PILL, value: "Under Review", tone: "indigo" }
      ],
      [
        { kind: CELL.LEAD, value: "Branch letterhead refresh" },
        { kind: CELL.TEXT, value: "Letterhead" },
        { kind: CELL.LEAD, value: "00012466" },
        { kind: CELL.PILL, value: "Conditionally Approved", tone: "amber" }
      ],
      [
        { kind: CELL.LEAD, value: "Advisor business cards" },
        { kind: CELL.TEXT, value: "Business Card" },
        { kind: CELL.LEAD, value: "00012470" },
        { kind: CELL.PILL, value: "Approved", tone: "green" }
      ],
      [
        { kind: CELL.LEAD, value: "Annual review form letter" },
        { kind: CELL.TEXT, value: "Form Letter" },
        { kind: CELL.LEAD, value: "00012472" },
        { kind: CELL.PILL, value: "Under Review", tone: "indigo" }
      ],
      [
        { kind: CELL.LEAD, value: "Quarterly market update" },
        { kind: CELL.TEXT, value: "Newsletter/Circular" },
        { kind: CELL.LEAD, value: "00012481" },
        { kind: CELL.PILL, value: "Approved", tone: "green" }
      ],
      [
        { kind: CELL.LEAD, value: "Seminar handout" },
        { kind: CELL.TEXT, value: "Seminar Handout" },
        { kind: CELL.LEAD, value: "00012484" },
        { kind: CELL.PILL, value: "Rejected", tone: "grey" }
      ],
      [
        { kind: CELL.LEAD, value: "Team email signature" },
        { kind: CELL.TEXT, value: "Email Signature" },
        { kind: CELL.LEAD, value: "00012488" },
        { kind: CELL.PILL, value: "Under Review", tone: "indigo" }
      ]
    ]
  },

  /*
   * Case_Detail page (c/arcCaseDetail). The header carries the subject, the
   * priority and type pills and one Actions menu; the key facts are Case
   * Number, Household, Case Owner and Financial Advisor Team. The status path
   * below them is switched off on the real page (SHOW_STATUS_PATH = false), so
   * where a case stands is read from the overview tile and the Current Task
   * card, not from a path.
   */
  case: {
    kind: "record",
    crumbs: ["Work", "Cases", "Account Opening"],
    eyebrow: "Case",
    title: "Account Opening",
    priorityPill: "Medium Priority",
    typePill: "New Financial Account",
    actionsMenu: "Actions",
    facts: [
      { key: "f1", label: "Case Number", value: "00012418" },
      {
        key: "f2",
        label: "Household",
        value: "Whitfield Household",
        link: true
      },
      { key: "f3", label: "Case Owner", value: "Alex Morgan" },
      { key: "f4", label: "Financial Advisor Team", value: "Morgan Advisors" }
    ],
    overview: {
      badge: "On Track",
      title:
        "Account Opening | Joint | SCHWAB | AMS | RIA | Whitfield | Alex Morgan | $ 250,000",
      waitingOn: "Alex Morgan | Collect updated ID",
      ratio: "2/5",
      ratioLabel: "Main Track Tasks",
      milestones: [
        { label: "HO Submission", state: "complete" },
        { label: "HO Approval", state: "current" },
        { label: "Branch Goal", state: "upcoming" }
      ]
    },
    tracks: [
      {
        title: "Branch Pit Stop Tasks",
        rows: [
          {
            subject: "Missing signature page",
            status: "In Progress",
            owner: "Alex Morgan",
            completed: "–"
          }
        ]
      },
      {
        title: "Main Track Tasks",
        rows: [
          {
            subject: "Prep Account Opening Paperwork",
            status: "Completed",
            owner: "Alex Morgan",
            completed: "1/9/2026"
          },
          {
            subject: "Collect updated ID",
            status: "In Progress",
            owner: "Alex Morgan",
            completed: "–"
          },
          {
            subject: "Final Review - New Account",
            status: "Not Started",
            owner: "Home Office",
            completed: "–"
          }
        ]
      },
      { title: "Home Office Pit Stop Tasks", rows: [] }
    ],
    currentTask: {
      eyebrow: "CURRENT TASK",
      title: "Collect updated ID",
      assignedLabel: "Assigned To",
      assigned: "Alex Morgan",
      dueLabel: "Due Date",
      due: "2026-01-14",
      descriptionLabel: "Description",
      description: "Upload a copy of the client's current driver's license.",
      action: "Mark Complete"
    },
    sideCards: ["Case Comments", "Order Tickets", "Related Products"],
    sideTabs: ["Feed", "Related"]
  },

  /*
   * Learning page (c/resourceCenter, branding hidden). Its own header bar holds
   * the search box and the Get Help / Help Center links; the landing is the
   * topic rail (the real Resource_Category__c names) with the first topic's
   * cards open.
   */
  resources: {
    kind: "resources",
    searchPlaceholder: "Search resources…",
    links: ["Get Help", "Help Center"],
    topicsHeading: "All topics",
    topics: [
      "Advisor Solutions",
      "Asset Management",
      "Brand Assets",
      "Client Communications",
      "Compliance",
      "Egnyte",
      "Forms & Documents",
      "How-to Guides",
      "IT Services",
      "JumpAI",
      "Marketing & Branding",
      "Operations"
    ],
    crumbs: ["Resource Center", "Advisor Solutions"],
    categoryTitle: "Advisor Solutions",
    categoryDescription:
      "Guides, forms and contacts for the Advisor Solutions team.",
    cards: [
      {
        key: "rc1",
        badge: "Guide",
        title: "Getting started in ARC",
        body: "A short walk through your first envelope.",
        action: "Open"
      },
      {
        key: "rc2",
        badge: "Form",
        title: "New account checklist",
        body: "Everything the home office needs to open an account.",
        action: "Download"
      },
      {
        key: "rc3",
        badge: "Video",
        title: "Submitting an envelope",
        body: "Five minutes on the Envelope Wizard.",
        action: "Watch"
      },
      {
        key: "rc4",
        badge: "Article",
        title: "Who to contact",
        body: "The Advisor Solutions team and what each person covers.",
        action: "Open"
      },
      {
        key: "rc5",
        badge: "Form",
        title: "Transfer request",
        body: "Initiate an ACAT or direct transfer.",
        action: "Download"
      },
      {
        key: "rc6",
        badge: "Guide",
        title: "Pit stop tasks explained",
        body: "What a branch or home office pit stop means for your case.",
        action: "Open"
      }
    ]
  },

  /* Settings page (c/arcSettings), My Details tab. */
  settings: {
    kind: "settings",
    title: "Settings",
    subtitle: "Additional info text goes here.",
    tabs: ["My Details", "Password", "Team", "Version", "Notifications"],
    sectionTitle: "Personal info",
    sectionBody: "Update your photo and personal details here.",
    rows: [
      { key: "s1", label: "Name", value: "Alex", second: "Morgan" },
      { key: "s2", label: "Email address", value: "alex.morgan@example.com" },
      {
        key: "s3",
        label: "Your photo",
        photo: true,
        hint: "SVG, PNG, JPG or GIF (max. 800×400px)"
      },
      { key: "s4", label: "Role", value: "Advisor" },
      { key: "s5", label: "Country", value: "United States" },
      { key: "s6", label: "Bio", value: "", area: true }
    ]
  }
};

const CONTACTS_GROUP_ID = "arc-nav-contacts";
const CONTACT_TABS_SHOWN = 5;

export default class ArcTourPreview extends LightningElement {
  /** Key into SCREENS — which page to draw. */
  @api screen = "home";

  /** data id of the nav entry to light, e.g. "arc-nav-work-cases". */
  @api navId;

  /**
   * Which part of the drawn screen to light: "tiles", "charts", "list",
   * "tabs", "tracks", "current-task", "hero" or "header". Anything else
   * lights nothing, which is a valid step.
   */
  @api region;

  logoUrl = ARC_LOGO;
  builtByUrl = BUILT_BY_DIVERSIFY;

  /*
   * The header's own glyphs, masked from the arcicon bundle exactly as
   * c/arcHeaderIconButton does it — the replica should not be drawing circles
   * where the real header draws a bell, a question mark and a gear.
   */
  collapseIconStyle = `--tp-icon-url: url('${ARC_ICONS}/sidebar-collapse.svg')`;
  searchIconStyle = `--tp-icon-url: url('${ARC_ICONS}/magnifying-glass.svg')`;
  bellIconStyle = `--tp-icon-url: url('${ARC_ICONS}/bell.svg')`;
  helpIconStyle = `--tp-icon-url: url('${ARC_ICONS}/question.svg')`;
  gearIconStyle = `--tp-icon-url: url('${ARC_ICONS}/gear-six.svg')`;

  // ---- sidebar -----------------------------------------------------------

  /**
   * The real sidebar, one level deep. A group is expanded only when it holds
   * the lit entry, so the rail stays short enough to read at this scale
   * without pushing the thing the step points at off the bottom.
   */
  get navItems() {
    return STATIC_NAV_ITEMS.filter(
      (item) => !item.hidden && item.type !== "Divider"
    ).map((item) => {
      const children = (item.subMenu || []).filter((child) => !child.hidden);
      const litChild = children.find((child) => child.id === this.navId);
      const lit = item.id === this.navId;
      /*
       * Expanded when the group holds the lit entry OR is itself the subject.
       * The Contacts step is the second case: its whole point is that clients
       * are filed as individuals, households, businesses and so on, and the
       * rail is where those names live — collapsing them would make the copy
       * refer to something not on screen.
       */
      const expanded = Boolean(litChild) || lit;

      return {
        id: item.id,
        label: item.label,
        hasIcon: Boolean(item.icon),
        iconStyle: item.icon
          ? `--tp-icon-url: url('${ARC_ICONS}/${item.icon}')`
          : "",
        rowClass: lit ? "tp-nav__row tp-nav__row--lit" : "tp-nav__row",
        hasChevron: children.length > 0,
        chevron: expanded ? "⌄" : "›",
        showChildren: expanded,
        children: expanded
          ? children.map((child) => ({
              id: child.id,
              label: child.label,
              rowClass:
                child.id === this.navId
                  ? "tp-nav__child tp-nav__child--lit"
                  : "tp-nav__child"
            }))
          : []
      };
    });
  }

  // ---- screen ------------------------------------------------------------

  get config() {
    return SCREENS[this.screen] || SCREENS.home;
  }

  get isDashboard() {
    return this.config.kind === "dashboard";
  }

  get isList() {
    return this.config.kind === "list";
  }

  get isRecord() {
    return this.config.kind === "record";
  }

  get isResources() {
    return this.config.kind === "resources";
  }

  get isSettings() {
    return this.config.kind === "settings";
  }

  get crumbs() {
    const crumbs = this.config.crumbs || [];
    return crumbs.map((label, index) => ({
      key: `crumb-${index}`,
      label,
      showCaret: index < crumbs.length - 1,
      className:
        index === crumbs.length - 1 ? "tp-crumb tp-crumb--last" : "tp-crumb"
    }));
  }

  get hasCrumbs() {
    return (this.config.crumbs || []).length > 0;
  }

  /**
   * Contacts draws its tab strip from the nav group's own children rather than
   * a second hand-written list — those tabs and those nav entries are the same
   * seven things, and STATIC_NAV_ITEMS already documents that order as
   * positional and easy to get wrong. The real page shows five and folds the
   * rest behind "More", which is reproduced here.
   */
  get tabs() {
    let labels = this.config.tabs || [];
    let overflow = false;

    if (this.config.contactTabs) {
      const group = STATIC_NAV_ITEMS.find(
        (item) => item.id === CONTACTS_GROUP_ID
      );
      const all = (group?.subMenu || [])
        .filter((child) => !child.hidden)
        .map((child) => child.label);
      overflow = all.length > CONTACT_TABS_SHOWN;
      labels = all.slice(0, CONTACT_TABS_SHOWN);
    }

    const mapped = labels.map((label, index) => ({
      key: `tab-${index}`,
      label,
      className: index === 0 ? "tp-tab tp-tab--on" : "tp-tab"
    }));

    if (overflow) {
      mapped.push({ key: "tab-more", label: "More ⌄", className: "tp-tab" });
    }
    return mapped;
  }

  get hasTabs() {
    return this.tabs.length > 0;
  }

  /**
   * The real list header is the page title plus, when a tab defines them, a
   * tagline and a New button. A page whose title is blank draws none of it.
   */
  get hasListHead() {
    return Boolean(
      this.config.title || this.config.subtitle || this.config.primaryAction
    );
  }

  // ---- tables ------------------------------------------------------------

  mapColumns(list, prefix) {
    return (list || []).map((col, index) => {
      const def = columnDef(col);
      return {
        key: `${prefix}-${index}`,
        label: def.label,
        style: columnStyle(def)
      };
    });
  }

  /** Rows of cell objects; each cell takes its column's width rule. */
  mapRows(rows, columns, prefix) {
    const defs = (columns || []).map(columnDef);
    return (rows || []).map((cells, rowIndex) => ({
      key: `${prefix}-${rowIndex}`,
      cells: cells.map((cell, cellIndex) => {
        const kind = cell.kind || CELL.TEXT;
        return {
          key: `${prefix}-cell-${rowIndex}-${cellIndex}`,
          value: cell.value,
          isPill: kind === CELL.PILL,
          cellClass: `tp-td tp-td--${kind}`,
          pillClass: `tp-pill tp-pill--${cell.tone || "grey"}`,
          style: columnStyle(defs[cellIndex] || {})
        };
      })
    }));
  }

  get columns() {
    return this.mapColumns(this.config.columns, "col");
  }

  get rows() {
    return this.mapRows(this.config.rows, this.config.columns, "row");
  }

  get rowClass() {
    return this.config.dense ? "tp-tr tp-tr--dense" : "tp-tr";
  }

  get headRowClass() {
    return `${this.rowClass} tp-tr--head`;
  }

  /** The dashboard's Work table, reusing the list cell model. */
  get workColumns() {
    return this.mapColumns(this.config.workColumns, "wcol");
  }

  get workRows() {
    return this.mapRows(this.config.workRows, this.config.workColumns, "wrow");
  }

  get workScopes() {
    return (this.config.workScopes || []).map((label, index) => ({
      key: `scope-${index}`,
      label,
      className: index === 0 ? "tp-seg__btn tp-seg__btn--on" : "tp-seg__btn"
    }));
  }

  // ---- record screen -----------------------------------------------------

  get facts() {
    return (this.config.facts || []).map((fact) => ({
      ...fact,
      valueClass: fact.link
        ? "tp-fact__value tp-fact__value--link"
        : "tp-fact__value"
    }));
  }

  get milestones() {
    const stages = this.config.overview?.milestones || [];
    return stages.map((stage, index) => ({
      key: `ms-${index}`,
      label: stage.label,
      className: `tp-milestone tp-milestone--${stage.state}`
    }));
  }

  get tracks() {
    return (this.config.tracks || []).map((track, trackIndex) => {
      const rows = track.rows || [];
      return {
        key: `track-${trackIndex}`,
        title: track.title,
        hasRows: rows.length > 0,
        rows: rows.map((row, rowIndex) => ({
          key: `track-${trackIndex}-${rowIndex}`,
          ...row
        }))
      };
    });
  }

  get sideTabs() {
    return (this.config.sideTabs || []).map((label, index) => ({
      key: `side-tab-${index}`,
      label,
      className: index === 0 ? "tp-tab tp-tab--on" : "tp-tab"
    }));
  }

  /** Settings rows; Bio is a multi-line field, drawn taller even when empty. */
  get settingsRows() {
    return (this.config.rows || []).map((row) => ({
      ...row,
      inputClass: row.area ? "tp-input tp-input--area" : "tp-input"
    }));
  }

  // ---- resource centre ---------------------------------------------------

  get topics() {
    return (this.config.topics || []).map((label, index) => ({
      key: `topic-${index}`,
      label,
      className: index === 0 ? "tp-rc__topic tp-rc__topic--on" : "tp-rc__topic"
    }));
  }

  // ---- highlight ---------------------------------------------------------

  /** `base` plus the lit modifier when this step's region is `name`. */
  regionClass(base, name) {
    return this.region === name ? `${base} tp-lit` : base;
  }

  get tilesClass() {
    return this.regionClass("tp-tiles", "tiles");
  }

  get chartsClass() {
    return this.regionClass("tp-charts", "charts");
  }

  get tabsClass() {
    return this.regionClass("tp-tabs", "tabs");
  }

  get listClass() {
    return this.regionClass("tp-table", "list");
  }

  get tracksClass() {
    return this.regionClass("tp-tracks", "tracks");
  }

  get currentTaskClass() {
    return this.regionClass("tp-side__card", "current-task");
  }

  get heroClass() {
    return this.regionClass("tp-hero", "hero");
  }

  get formClass() {
    return this.regionClass("tp-form", "list");
  }

  get headerActionsClass() {
    return this.regionClass("tp-chrome__actions", "header");
  }
}