import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import communityBasePath from "@salesforce/community/basePath";
import NEXS_ICONS from "@salesforce/resourceUrl/arcicon";
import getHomeMetrics from "@salesforce/apex/ArcHomeMetricsController.getHomeMetrics";

const CARET_ICON = "caret-right.svg";

// The two "my teams'" tiles deep-link to the site's own Case/Task list pages,
// pre-switched to the team-scoped tab, instead of the object's generic home
// page (which always lands on the My-scoped default). Both list pages are
// nexSListView, which resolves a ?c__tabId= param against its configured
// tabs on load — this reuses that existing deep-link mechanism rather than
// adding a new one.
const TILE_ROUTES = {
  "cases-team": "/case/Case/Default?c__tabId=My_teams_open_cases",
  "tasks-team": "/task/Task/Default?c__tabId=My_Team_s_Open_Tasks"
};

/**
 * Home dashboard's 5-tile KPI row (Figma node 791:29291): Cases/Tasks
 * assigned to me, Cases/Tasks assigned to my teams', and My Pitstop Tasks
 * (the user's open Branch + Home Office pit stop tasks, matching the Task
 * donut's two pit stop slices). Each tile's chevron navigates to that record type's
 * object home page via standard__objectPage/actionName "home" — the same
 * PageReference arcNavigation's sidebar links already use for Case/Task,
 * confirmed working there, rather than guessing at a hardcoded route URL.
 * The two "my teams'" tiles instead deep-link to their team-scoped list
 * view (see TILE_ROUTES) so they land already switched to that scope.
 */
export default class ArcHomeMetrics extends NavigationMixin(LightningElement) {
  metrics = {
    casesAssignedToMe: 0,
    tasksAssignedToMe: 0,
    casesAssignedToMyTeams: 0,
    tasksAssignedToMyTeams: 0,
    pitStopTasksAssignedToMe: 0
  };

  get caretIconStyle() {
    return `--icon-url: url('${NEXS_ICONS}/${CARET_ICON}');`;
  }

  @wire(getHomeMetrics)
  wiredHomeMetrics({ data, error }) {
    if (data) {
      this.metrics = data;
      return;
    }
    if (error) {
      console.error("[arcHomeMetrics] Failed to load home metrics", error);
    }
  }

  get tiles() {
    return [
      {
        key: "cases-mine",
        label: "Cases",
        value: this.metrics.casesAssignedToMe,
        subtext: "Assigned to me",
        objectApiName: "Case"
      },
      {
        key: "tasks-mine",
        label: "Tasks",
        value: this.metrics.tasksAssignedToMe,
        subtext: "Assigned to me",
        objectApiName: "Task"
      },
      {
        key: "cases-team",
        label: "Cases",
        value: this.metrics.casesAssignedToMyTeams,
        subtext: "Assigned to my teams’",
        objectApiName: "Case"
      },
      {
        key: "tasks-team",
        label: "Tasks",
        value: this.metrics.tasksAssignedToMyTeams,
        subtext: "Assigned to my teams’",
        objectApiName: "Task"
      },
      {
        key: "pitstops-mine",
        label: "My Pitstop Tasks",
        value: this.metrics.pitStopTasksAssignedToMe,
        subtext: "Branch and home office",
        objectApiName: "Task"
      }
    ];
  }

  handleTileClick(event) {
    const { key, objectApiName } = event.currentTarget.dataset;
    if (!objectApiName) {
      return;
    }

    const route = TILE_ROUTES[key];
    if (route) {
      this[NavigationMixin.Navigate]({
        type: "standard__webPage",
        attributes: {
          url: `${communityBasePath}${route}`
        }
      });
      return;
    }

    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName,
        actionName: "home"
      }
    });
  }
}