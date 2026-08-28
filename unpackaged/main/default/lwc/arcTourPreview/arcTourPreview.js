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
 *  - Row values are invented. They illustrate shape, and are deliberately
 *    ordinary-looking rather than copied out of the org.
 *
 * Sizes are absolute rather than token-derived: this is a picture of the app at
 * roughly half scale, so it must not inherit page type sizes and grow out of
 * the modal it sits in. Type is held at a readable floor rather than scaled
 * proportionally — a true 0.45 scale would put body text at 6px.
 */

/** Cell kinds a list row can hold, mapped to classes in mapRow. */
const CELL = {
  LEAD: "lead",
  TEXT: "text",
  MUTED: "muted",
  AVATAR: "avatar",
  PILL: "pill"
};

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
    tiles: [
      { key: "m1", label: "Cases", value: "10", sub: "Assigned to me" },
      { key: "m2", label: "Tasks", value: "22", sub: "Assigned to me" },
      { key: "m3", label: "Cases", value: "20", sub: "Assigned to my teams" },
      { key: "m4", label: "Tasks", value: "62", sub: "Assigned to my teams" },
      { key: "m5", label: "Awaiting", value: "3", sub: "Home office" }
    ],
    donuts: [
      {
        key: "d1",
        title: "My Cases",
        sub: "By milestone",
        legend: "Not set",
        value: "10"
      },
      {
        key: "d2",
        title: "My Team Cases",
        sub: "By milestone",
        legend: "Not set",
        value: "20"
      }
    ],
    workTitle: "Work",
    workColumns: ["Case", "Case No.", "Assignee", "Overall Status"],
    workRows: [
      ["Account maintenance", "00012418", "Alex Morgan", "On track"],
      ["New account opening", "00012402", "Alex Morgan", "Not started"],
      ["Trustee change", "00012377", "Dana Whitlock", "On track"]
    ],
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

  contacts: {
    kind: "list",
    crumbs: ["All Contacts"],
    title: "Contacts",
    contactTabs: true,
    columns: [
      "Contact Name",
      "Role",
      "Permanent State",
      "Phone",
      "Type",
      "Record Type"
    ],
    rows: [
      [
        { kind: CELL.AVATAR, value: "Ana Reyes" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Colorado", tone: "indigo" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Client" },
        { kind: CELL.TEXT, value: "Individual" }
      ],
      [
        { kind: CELL.AVATAR, value: "Whitfield Household" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Oregon", tone: "teal" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Client" },
        { kind: CELL.TEXT, value: "Household" }
      ],
      [
        { kind: CELL.AVATAR, value: "Brennan Family Trust" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Illinois", tone: "amber" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Client" },
        { kind: CELL.TEXT, value: "Trust" }
      ],
      [
        { kind: CELL.AVATAR, value: "Kesler Dental Group" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Texas", tone: "indigo" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Prospect" },
        { kind: CELL.TEXT, value: "Business" }
      ],
      [
        { kind: CELL.AVATAR, value: "Marsh & Doyle 401(k)" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Ohio", tone: "teal" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Client" },
        { kind: CELL.TEXT, value: "Retirement Plan" }
      ],
      [
        { kind: CELL.AVATAR, value: "Priya Raman" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Washington", tone: "indigo" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Prospect" },
        { kind: CELL.TEXT, value: "Individual" }
      ],
      [
        { kind: CELL.AVATAR, value: "Delgado Household" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Arizona", tone: "amber" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Client" },
        { kind: CELL.TEXT, value: "Household" }
      ],
      [
        { kind: CELL.AVATAR, value: "Northfield Bakery" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Minnesota", tone: "teal" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Prospect" },
        { kind: CELL.TEXT, value: "Business" }
      ],
      [
        { kind: CELL.AVATAR, value: "Owen Hartley" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Georgia", tone: "indigo" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Client" },
        { kind: CELL.TEXT, value: "Individual" }
      ]
    ]
  },

  cases: {
    kind: "list",
    crumbs: ["Work", "Cases"],
    title: "Cases",
    tabs: ["All Cases", "My Open Cases", "My Team's Open Cases"],
    columns: [
      "Case Number",
      "Contact Name",
      "Subject",
      "Status",
      "Priority",
      "Date/Time Opened"
    ],
    rows: [
      [
        { kind: CELL.LEAD, value: "00012418" },
        { kind: CELL.TEXT, value: "Whitfield Household" },
        { kind: CELL.TEXT, value: "Account maintenance" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.PILL, value: "Medium", tone: "blue" },
        { kind: CELL.TEXT, value: "1/8/2026" }
      ],
      [
        { kind: CELL.LEAD, value: "00012402" },
        { kind: CELL.TEXT, value: "Ana Reyes" },
        { kind: CELL.TEXT, value: "New account opening" },
        { kind: CELL.PILL, value: "New", tone: "amber" },
        { kind: CELL.PILL, value: "High", tone: "green" },
        { kind: CELL.TEXT, value: "1/6/2026" }
      ],
      [
        { kind: CELL.LEAD, value: "00012377" },
        { kind: CELL.TEXT, value: "Brennan Family Trust" },
        { kind: CELL.TEXT, value: "Trustee change" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.PILL, value: "Medium", tone: "blue" },
        { kind: CELL.TEXT, value: "12/29/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "00012351" },
        { kind: CELL.TEXT, value: "Kesler Dental Group" },
        { kind: CELL.TEXT, value: "401(k) onboarding" },
        { kind: CELL.PILL, value: "New", tone: "amber" },
        { kind: CELL.PILL, value: "Medium", tone: "blue" },
        { kind: CELL.TEXT, value: "12/22/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "00012340" },
        { kind: CELL.TEXT, value: "Marsh & Doyle 401(k)" },
        { kind: CELL.TEXT, value: "Plan amendment" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.PILL, value: "Low", tone: "grey" },
        { kind: CELL.TEXT, value: "12/18/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "00012322" },
        { kind: CELL.TEXT, value: "Priya Raman" },
        { kind: CELL.TEXT, value: "Beneficiary update" },
        { kind: CELL.PILL, value: "New", tone: "amber" },
        { kind: CELL.PILL, value: "Medium", tone: "blue" },
        { kind: CELL.TEXT, value: "12/15/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "00012318" },
        { kind: CELL.TEXT, value: "Delgado Household" },
        { kind: CELL.TEXT, value: "Address change" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.PILL, value: "Low", tone: "grey" },
        { kind: CELL.TEXT, value: "12/11/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "00012301" },
        { kind: CELL.TEXT, value: "Owen Hartley" },
        { kind: CELL.TEXT, value: "Transfer of assets" },
        { kind: CELL.PILL, value: "New", tone: "amber" },
        { kind: CELL.PILL, value: "High", tone: "green" },
        { kind: CELL.TEXT, value: "12/8/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "00012288" },
        { kind: CELL.TEXT, value: "Northfield Bakery" },
        { kind: CELL.TEXT, value: "New account opening" },
        { kind: CELL.PILL, value: "In Progress", tone: "indigo" },
        { kind: CELL.PILL, value: "Medium", tone: "blue" },
        { kind: CELL.TEXT, value: "12/3/2025" }
      ]
    ]
  },

  tasks: {
    kind: "list",
    crumbs: ["Work", "Tasks"],
    title: "Tasks",
    tabs: ["All Tasks", "My Open Tasks", "My Team's Open Tasks"],
    columns: [
      "Subject",
      "Name",
      "Related To",
      "Due Date",
      "Assigned Alias",
      "Advisor Team"
    ],
    rows: [
      [
        { kind: CELL.LEAD, value: "Collect updated ID" },
        { kind: CELL.TEXT, value: "Whitfield Household" },
        { kind: CELL.TEXT, value: "00012418" },
        { kind: CELL.TEXT, value: "1/14/2026" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Advisor review" },
        { kind: CELL.TEXT, value: "Whitfield Household" },
        { kind: CELL.TEXT, value: "00012418" },
        { kind: CELL.TEXT, value: "1/16/2026" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Confirm beneficiary" },
        { kind: CELL.TEXT, value: "Ana Reyes" },
        { kind: CELL.TEXT, value: "00012402" },
        { kind: CELL.TEXT, value: "1/15/2026" },
        { kind: CELL.MUTED, value: "Unassigned" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Send welcome pack" },
        { kind: CELL.TEXT, value: "Kesler Dental Group" },
        { kind: CELL.TEXT, value: "00012351" },
        { kind: CELL.TEXT, value: "1/18/2026" },
        { kind: CELL.MUTED, value: "Unassigned" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Upload signed forms" },
        { kind: CELL.TEXT, value: "Marsh & Doyle 401(k)" },
        { kind: CELL.TEXT, value: "00012340" },
        { kind: CELL.TEXT, value: "1/20/2026" },
        { kind: CELL.TEXT, value: "dwhitlock" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Plan amendment review" },
        { kind: CELL.TEXT, value: "Marsh & Doyle 401(k)" },
        { kind: CELL.TEXT, value: "00012340" },
        { kind: CELL.TEXT, value: "1/22/2026" },
        { kind: CELL.TEXT, value: "dwhitlock" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Confirm address change" },
        { kind: CELL.TEXT, value: "Delgado Household" },
        { kind: CELL.TEXT, value: "00012318" },
        { kind: CELL.TEXT, value: "1/23/2026" },
        { kind: CELL.TEXT, value: "amorgan" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Request transfer paperwork" },
        { kind: CELL.TEXT, value: "Owen Hartley" },
        { kind: CELL.TEXT, value: "00012301" },
        { kind: CELL.TEXT, value: "1/26/2026" },
        { kind: CELL.MUTED, value: "Unassigned" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ],
      [
        { kind: CELL.LEAD, value: "Verify business documents" },
        { kind: CELL.TEXT, value: "Northfield Bakery" },
        { kind: CELL.TEXT, value: "00012288" },
        { kind: CELL.TEXT, value: "1/28/2026" },
        { kind: CELL.TEXT, value: "dwhitlock" },
        { kind: CELL.TEXT, value: "Morgan Advisors" }
      ]
    ]
  },

  isas: {
    kind: "list",
    crumbs: ["Investments & Services", "Accounts"],
    title: "Accounts",
    subtitle: "Financial accounts across your book",
    columns: [
      "Contact Name",
      "Account Status",
      "Account Number",
      "Primary Owner",
      "Created Date"
    ],
    rows: [
      [
        { kind: CELL.LEAD, value: "Joint Brokerage" },
        { kind: CELL.TEXT, value: "Open" },
        { kind: CELL.TEXT, value: "••••4182" },
        { kind: CELL.TEXT, value: "Whitfield Household" },
        { kind: CELL.TEXT, value: "6/23/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Roth IRA" },
        { kind: CELL.TEXT, value: "Open" },
        { kind: CELL.TEXT, value: "••••3067" },
        { kind: CELL.TEXT, value: "Ana Reyes" },
        { kind: CELL.TEXT, value: "7/16/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Trust Account" },
        { kind: CELL.MUTED, value: "Pending" },
        { kind: CELL.TEXT, value: "••••2915" },
        { kind: CELL.TEXT, value: "Brennan Family Trust" },
        { kind: CELL.TEXT, value: "8/11/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "401(k) Plan" },
        { kind: CELL.TEXT, value: "Open" },
        { kind: CELL.TEXT, value: "••••7734" },
        { kind: CELL.TEXT, value: "Kesler Dental Group" },
        { kind: CELL.TEXT, value: "9/2/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Traditional IRA" },
        { kind: CELL.TEXT, value: "Open" },
        { kind: CELL.TEXT, value: "••••5520" },
        { kind: CELL.TEXT, value: "Priya Raman" },
        { kind: CELL.TEXT, value: "9/18/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Advisory Agreement" },
        { kind: CELL.TEXT, value: "Active" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.TEXT, value: "Whitfield Household" },
        { kind: CELL.TEXT, value: "10/2/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Joint Brokerage" },
        { kind: CELL.TEXT, value: "Open" },
        { kind: CELL.TEXT, value: "••••8841" },
        { kind: CELL.TEXT, value: "Delgado Household" },
        { kind: CELL.TEXT, value: "10/14/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "SEP IRA" },
        { kind: CELL.TEXT, value: "Open" },
        { kind: CELL.TEXT, value: "••••6203" },
        { kind: CELL.TEXT, value: "Northfield Bakery" },
        { kind: CELL.TEXT, value: "11/1/2025" }
      ],
      [
        { kind: CELL.LEAD, value: "Rollover IRA" },
        { kind: CELL.MUTED, value: "Pending" },
        { kind: CELL.TEXT, value: "••••4417" },
        { kind: CELL.TEXT, value: "Owen Hartley" },
        { kind: CELL.TEXT, value: "11/19/2025" }
      ]
    ]
  },

  compliance: {
    kind: "list",
    crumbs: ["Compliance", "Advertising Reviews"],
    title: "Advertising Reviews",
    subtitle: "Advertising items submitted for compliance review",
    primaryAction: "New Advertising Item",
    tabs: ["My Team's Requests", "All Items"],
    columns: ["Contact Name", "Advertising Type", "Review Case", "Status"],
    rows: [
      [
        { kind: CELL.LEAD, value: "Q1 client newsletter" },
        { kind: CELL.TEXT, value: "Newsletter" },
        { kind: CELL.TEXT, value: "00012455" },
        { kind: CELL.PILL, value: "Approved", tone: "green" }
      ],
      [
        { kind: CELL.LEAD, value: "Seminar invitation" },
        { kind: CELL.TEXT, value: "Event material" },
        { kind: CELL.TEXT, value: "00012461" },
        { kind: CELL.PILL, value: "In Review", tone: "indigo" }
      ],
      [
        { kind: CELL.LEAD, value: "Website bio update" },
        { kind: CELL.TEXT, value: "Website" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Draft", tone: "amber" }
      ],
      [
        { kind: CELL.LEAD, value: "Client review deck" },
        { kind: CELL.TEXT, value: "Presentation" },
        { kind: CELL.TEXT, value: "00012470" },
        { kind: CELL.PILL, value: "Approved", tone: "green" }
      ],
      [
        { kind: CELL.LEAD, value: "Social media post" },
        { kind: CELL.TEXT, value: "Social" },
        { kind: CELL.TEXT, value: "00012472" },
        { kind: CELL.PILL, value: "In Review", tone: "indigo" }
      ],
      [
        { kind: CELL.LEAD, value: "Quarterly market update" },
        { kind: CELL.TEXT, value: "Newsletter" },
        { kind: CELL.TEXT, value: "00012481" },
        { kind: CELL.PILL, value: "Approved", tone: "green" }
      ],
      [
        { kind: CELL.LEAD, value: "Referral one-pager" },
        { kind: CELL.TEXT, value: "Print" },
        { kind: CELL.MUTED, value: "–" },
        { kind: CELL.PILL, value: "Draft", tone: "amber" }
      ],
      [
        { kind: CELL.LEAD, value: "Retirement webinar deck" },
        { kind: CELL.TEXT, value: "Presentation" },
        { kind: CELL.TEXT, value: "00012488" },
        { kind: CELL.PILL, value: "In Review", tone: "indigo" }
      ]
    ]
  },

  case: {
    kind: "record",
    crumbs: ["Work", "Cases", "Account maintenance"],
    eyebrow: "Case",
    title: "Account maintenance",
    priorityPill: "Medium Priority",
    actions: [
      "Create Branch Pit Stop Task",
      "Create Home Office Pit Stop Task"
    ],
    facts: [
      { key: "f1", label: "Case Number", value: "00012418" },
      { key: "f2", label: "Priority", value: "Medium" },
      { key: "f3", label: "Status", value: "Working" },
      {
        key: "f4",
        label: "Account Name",
        value: "Whitfield Household",
        link: true
      },
      { key: "f5", label: "Case Owner", value: "Alex Morgan" },
      { key: "f6", label: "Advisor Team", value: "Morgan Advisors" }
    ],
    path: [
      { key: "p1", label: "Working", state: "current" },
      { key: "p2", label: "New", state: "todo" },
      { key: "p3", label: "Returned To Advisor", state: "todo" },
      { key: "p4", label: "Conditionally Approved", state: "todo" },
      { key: "p5", label: "Ready for Review", state: "todo" }
    ],
    overview: {
      badge: "ON TRACK",
      title: "Account maintenance",
      assignee: "Alex Morgan | Collect updated ID",
      ratio: "2/5",
      ratioLabel: "MAIN TRACK TASKS",
      startLabel: "HO Submission",
      endLabel: "Branch Goal"
    },
    pitStopTitle: "Branch Pit Stop Tasks",
    pitStops: [
      {
        key: "ps1",
        subject: "Missing signature page",
        status: "Waiting",
        owner: "Branch"
      }
    ],
    mainTrackTitle: "Main Track Tasks",
    mainTrack: [
      {
        key: "mt1",
        subject: "Confirm account registration",
        status: "Completed",
        owner: "Alex Morgan"
      },
      {
        key: "mt2",
        subject: "Collect updated ID",
        status: "In Progress",
        owner: "Alex Morgan"
      },
      {
        key: "mt3",
        subject: "Advisor review",
        status: "Not Started",
        owner: "Finance"
      }
    ],
    currentTask: {
      eyebrow: "CURRENT TASK",
      title: "Collect updated ID",
      assignedLabel: "Assigned To",
      assigned: "Alex Morgan",
      dueLabel: "Due Date",
      due: "2026-01-14",
      action: "Mark Complete"
    }
  },

  resources: {
    kind: "resources",
    eyebrow: "Resource Center",
    title: "Find the resources you need",
    searchPlaceholder: "Search resources…",
    helpLink: "Not sure where to start? Get Help →",
    featuredLabel: "Featured",
    featured: {
      pill: "Video",
      title: "Getting started in ARC",
      body: "A short walk through submitting your first envelope.",
      action: "Watch"
    },
    categoryLabel: "Browse by category",
    categories: [
      { key: "cat1", label: "Getting started", meta: "6 guides" },
      { key: "cat2", label: "Client onboarding", meta: "11 articles" },
      { key: "cat3", label: "Forms library", meta: "42 forms" },
      { key: "cat4", label: "Compliance", meta: "9 articles" },
      { key: "cat5", label: "Accounts", meta: "14 guides" },
      { key: "cat6", label: "Billing", meta: "5 articles" }
    ]
  },

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
        key: "s5",
        label: "Your photo",
        photo: true,
        hint: "SVG, PNG, JPG or GIF"
      },
      { key: "s3", label: "Role", value: "Advisor" },
      { key: "s4", label: "Country", value: "United States" }
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
   * "tabs", "path", "tracks", "current-task", "hero" or "header". Anything
   * else lights nothing, which is a valid step.
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

  get columns() {
    return (this.config.columns || []).map((label, index) => ({
      key: `col-${index}`,
      label
    }));
  }

  get rows() {
    return (this.config.rows || []).map((cells, rowIndex) => ({
      key: `row-${rowIndex}`,
      cells: cells.map((cell, cellIndex) => {
        const kind = cell.kind || CELL.TEXT;
        return {
          key: `cell-${rowIndex}-${cellIndex}`,
          value: cell.value,
          isPill: kind === CELL.PILL,
          isAvatar: kind === CELL.AVATAR,
          isPlain: kind !== CELL.PILL && kind !== CELL.AVATAR,
          cellClass: `tp-td tp-td--${kind}`,
          pillClass: `tp-pill tp-pill--${cell.tone || "grey"}`
        };
      })
    }));
  }

  /** The dashboard's Work table, reusing the list cell model. */
  get workColumns() {
    return (this.config.workColumns || []).map((label, index) => ({
      key: `wcol-${index}`,
      label
    }));
  }

  get workRows() {
    return (this.config.workRows || []).map((cells, rowIndex) => ({
      key: `wrow-${rowIndex}`,
      cells: cells.map((value, cellIndex) => ({
        key: `wcell-${rowIndex}-${cellIndex}`,
        value,
        cellClass: cellIndex === 0 ? "tp-td tp-td--lead" : "tp-td"
      }))
    }));
  }

  // ---- record screen -----------------------------------------------------

  get pathSteps() {
    return (this.config.path || []).map((step) => ({
      ...step,
      className: `tp-path__step tp-path__step--${step.state}`
    }));
  }

  get facts() {
    return (this.config.facts || []).map((fact) => ({
      ...fact,
      valueClass: fact.link
        ? "tp-fact__value tp-fact__value--link"
        : "tp-fact__value"
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

  get pathClass() {
    return this.regionClass("tp-path", "path");
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

  get catsClass() {
    return this.regionClass("tp-cats", "list");
  }

  get formClass() {
    return this.regionClass("tp-form", "list");
  }

  get headerActionsClass() {
    return this.regionClass("tp-chrome__actions", "header");
  }
}