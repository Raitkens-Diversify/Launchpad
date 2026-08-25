public with sharing class CaseStatusSummaryController {

    public class MilestoneWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isCompleted;
        public MilestoneWrapper(String label, Boolean isCompleted) {
            this.label = label;
            this.isCompleted = isCompleted;
        }
    }

    public class CaseStatusWrapper {
        @AuraEnabled public String statusMessage = '';
        @AuraEnabled public String waitingOn = '';
        @AuraEnabled public Integer submissionToHO = 0;
        @AuraEnabled public Integer hoApproval = 0;
        @AuraEnabled public Integer branchGoal = 0;
        @AuraEnabled public Integer totalTasks = 0;
        @AuraEnabled public Integer completedTasks = 0;
        @AuraEnabled public String nextAction = '';
        @AuraEnabled public String timeInStage = '';
        @AuraEnabled public Id currentTaskId;
        @AuraEnabled public String membership = '';
        @AuraEnabled public String formattedOwnerDetail = '';
        @AuraEnabled public List<MilestoneWrapper> wrappedMilestones = new List<MilestoneWrapper>();
    }

    @AuraEnabled
    public static CaseStatusWrapper getCaseStatusSummary(Id caseId, Id userId) {
        CaseStatusWrapper wrap = new CaseStatusWrapper();
        if (caseId == null) {
            return wrap;    
        }

            String membershipField = getMembershipField(userId);
            Case c = fetchCase(caseId, membershipField);

            wrap.currentTaskId = c.Current_Task_Id__c;
            wrap.membership = resolveMembership(c, membershipField);

            Task currentTask = fetchCurrentTask(c.Current_Task_Id__c);
            processCurrentTask(currentTask, wrap);
            wrap.wrappedMilestones = buildMilestones(caseId, wrap);

            applyMainTrackTaskCounts(caseId, wrap);
            return wrap;
    }

    /**
     * Main-track task counts, read from the tasks themselves.
     *
     * These were read from Case.Total_Main_Track_Tasks__c and
     * Completed_Main_Track_Tasks__c, which UpdateCaseTaskCountsBatch writes.
     * Those fields are null until the batch has run against a case and go stale
     * between runs, so the tile's ratio showed 0/0 on cases that did have
     * main-track tasks. Counting here means the figure is right on first load
     * and needs no batch to have run.
     *
     * The criteria are the batch's own -- tasks on the case with Order__c set --
     * which is also what MainTrackTasksController selects for the Main Track
     * Tasks list, so the ratio and that list cannot disagree. One query rather
     * than two COUNT() aggregates, since the statuses are needed anyway.
     */
    private static void applyMainTrackTaskCounts(Id caseId, CaseStatusWrapper wrap) {
        Integer total = 0;
        Integer completed = 0;

        for (Task t : [
            SELECT Id, Status
            FROM Task
            WHERE WhatId = :caseId AND Order__c != NULL
        ]) {
            total++;
            if (t.Status == 'Completed') {
                completed++;
            }
        }

        wrap.totalTasks = total;
        wrap.completedTasks = completed;
    }

    private static String getMembershipField(Id userId) {
        for (GroupMember gm : [
            SELECT Group.DeveloperName
            FROM GroupMember
            WHERE UserOrGroupId = :userId
        ]) { if (gm.Group.DeveloperName == 'Home_Office')return 'Case_Home_Office_Name__c';

        }
        return 'Case_Branch_Name__c';
    }

    /**
     * The tile's centre summary line: the case type, the account's registration
     * and custody details, then the client, the advisor and the amount.
     *
     * Case_Branch_Name__c / Case_Home_Office_Name__c hold this text on orgs whose
     * Case trigger writes it. Nothing writes it here -- every Case in this org has
     * both fields null -- so the line rendered blank while the rest of the tile
     * worked off live queries. It is assembled from the same fields, in the same
     * order, as Case_TriggerHandler.populateBranchAndHomeNames does elsewhere, so
     * both render identically. A stored value still wins, which keeps this correct
     * if that trigger is ever brought across.
     *
     * The literal '</br>' is a part, not markup: joinNonNull turns it into
     * ' | </br> | ', which caseOverviewTile rewrites into a line break.
     */
    private static String resolveMembership(Case c, String membershipField) {
        Boolean isHomeOffice = (membershipField == 'Case_Home_Office_Name__c');

        String stored = isHomeOffice ? c.Case_Home_Office_Name__c : c.Case_Branch_Name__c;
        if (String.isNotBlank(stored)) {
            return stored;
        }

        Financial_Account__c fa = c.Wizard_Financial_Account__r;
        Financial_Advisor_Team__c team = c.Financial_Advisor_Team__r;

        /*
         * The people on a case do not describe it. Without a type, an account or an
         * amount there is nothing to say about the work itself, and the line came
         * out as a bare advisor name sitting alone in the middle of the tile as
         * though it were the case's title. Fall back to the subject in that case --
         * the same intent as populateNullNameFields, applied before the names are
         * added rather than only when every part is null.
         */
        Boolean describesCase = String.isNotBlank(c.Type) || fa != null || c.Amount__c != null;
        if (!describesCase) {
            return c.Subject;
        }

        List<String> parts = new List<String>{ c.Type };
        if (fa != null) {
            parts.add(fa.Registration_Type__c);
            parts.add(fa.Custodian__c);
            parts.add(fa.Managed_Account_Platform__c);
            parts.add(fa.BD_or_RIA__c);
            parts.add('</br>');
        }

        // Branch reads owner then advisor; home office reads advisor then owner.
        String owner = (fa == null) ? null : fullName(fa.Primary_Owner__r);
        String advisor = (team == null) ? null : fullName(team.Primary_Financial_Advisor__r);
        if (isHomeOffice) {
            parts.add(advisor);
            parts.add(owner);
        } else {
            parts.add(owner);
            parts.add(advisor);
        }

        if (c.Amount__c != null) {
            parts.add('$ ' + c.Amount__c.format());
        }

        String built = joinNonNull(parts);
        return String.isNotBlank(built) ? built : c.Subject;
    }

    private static String joinNonNull(List<String> items) {
        List<String> cleaned = new List<String>();
        for (String s : items) {
            if (s != null && s.trim() != '') {
                cleaned.add(s.trim());
            }
        }
        return cleaned.isEmpty() ? null : String.join(cleaned, ' | ');
    }

    /** FirstName/LastName exist on User and on person accounts; null elsewhere. */
    private static String fullName(SObject person) {
        if (person == null) {
            return null;
        }
        String first = (String) person.get('FirstName');
        String last = (String) person.get('LastName');
        if (String.isBlank(first) && String.isBlank(last)) {
            return null;
        }
        return ((first == null ? '' : first) + ' ' + (last == null ? '' : last)).trim();
    }

    private static Case fetchCase(Id caseId, String membershipField) {
        String query =
            'SELECT Id, Current_Task_Id__c, Case_Template__c,' +
            ' Total_Main_Track_Tasks__c, Completed_Main_Track_Tasks__c,' +
            ' Type, Subject, Amount__c,' +
            ' Wizard_Financial_Account__r.Registration_Type__c,' +
            ' Wizard_Financial_Account__r.Custodian__c,' +
            ' Wizard_Financial_Account__r.Managed_Account_Platform__c,' +
            ' Wizard_Financial_Account__r.BD_or_RIA__c,' +
            ' Wizard_Financial_Account__r.Primary_Owner__r.FirstName,' +
            ' Wizard_Financial_Account__r.Primary_Owner__r.LastName,' +
            ' Financial_Advisor_Team__r.Primary_Financial_Advisor__r.FirstName,' +
            ' Financial_Advisor_Team__r.Primary_Financial_Advisor__r.LastName,' +
            ' ' + membershipField +
            ' FROM Case WHERE Id = :caseId LIMIT 1';
        return Database.query(query);
    }

    private static List<MilestoneWrapper> buildMilestones(
        Id caseId, CaseStatusWrapper wrap
    ) {
        List<Task> tasks = [
            SELECT Status,
                Task_Template_Item__r.Branch_Goal_Milestone__c,
                Task_Template_Item__r.Home_Office_Submission_Milestone__c,
                Task_Template_Item__r.Home_Office_Approval_Milestone__c,
                Task_Template_Item__r.Home_Office_Goal_Milestone__c
            FROM Task
            WHERE WhatId = :caseId
        ];
        
        Map<String, Boolean> milestoneCompleted = new Map<String, Boolean>();
        Set<String> includedMilestones = new Set<String>();
        Boolean allCompleted = true;
        
        for (Task t : tasks) {
            if (t.Status != 'Completed') {
                allCompleted = false;
                break; 
            }
        }
        System.debug('allCompleted :' + allCompleted);
        if(!tasks.isEmpty() && allCompleted == true) {
            wrap.statusMessage = 'All Tasks Completed';
        }

        for (Task t : tasks) {
            Boolean isCompleted = (t != null && t.Status == 'Completed');
            Task_Template_Item__c tti = (t != null) ? t.Task_Template_Item__r : null;
            if (tti != null) {
                if (tti.Home_Office_Submission_Milestone__c == true) {
                    includedMilestones.add('HO Submission');
                    if (isCompleted) milestoneCompleted.put('HO Submission', true);
                }
                if (tti.Home_Office_Approval_Milestone__c == true) {
                    includedMilestones.add('HO Approval');
                    if (isCompleted) milestoneCompleted.put('HO Approval', true);
                }
                if (tti.Branch_Goal_Milestone__c == true) {
                    includedMilestones.add('Branch Goal');
                    if (isCompleted) milestoneCompleted.put('Branch Goal', true);
                }
                if (tti.Home_Office_Goal_Milestone__c == true) {
                    includedMilestones.add('HO Goal');
                    if (isCompleted) milestoneCompleted.put('HO Goal', true);
                }
            }
        }

        List<MilestoneWrapper> result = new List<MilestoneWrapper>();

        if (includedMilestones.contains('HO Submission')) {
            result.add(new MilestoneWrapper(
                'HO Submission',
                milestoneCompleted.containsKey('HO Submission')
            ));
        }

        if (includedMilestones.contains('HO Approval')) {
            result.add(new MilestoneWrapper(
                'HO Approval',
                milestoneCompleted.containsKey('HO Approval')
            ));
        }

        if (includedMilestones.contains('Branch Goal')) {
            result.add(new MilestoneWrapper(
                'Branch Goal',
                milestoneCompleted.containsKey('Branch Goal')
            ));
        }

        if (includedMilestones.contains('HO Goal')) {
            result.add(new MilestoneWrapper(
                'HO Goal',
                milestoneCompleted.containsKey('HO Goal')
            ));
        }
        System.debug('Hello from milestone Wrapper ' + result);
        return result;
    }

    private static Boolean hasCompletedActivity(List<SObject> acts) {
        if (acts == null) return false;
        for (SObject a : acts) {
            if (String.valueOf(a.get('Status')) == 'Completed') return true;
        }
        return false;
    }

    private static Task fetchCurrentTask(Id taskId) {
        if (taskId == null) return null;
        return [
            SELECT Id, Branch_Pit_Stop__c, Home_Office_Pit_Stop__c,
                   Task_Template__c, Subject, CreatedDate,
                   TYPEOF Owner
                        WHEN User THEN Name, Department_Picklist__c
                        WHEN Group THEN Name
                   END
            FROM Task
            WHERE Id = :taskId LIMIT 1
        ];
    }

    private static void processCurrentTask(Task t, CaseStatusWrapper wrap) {
        if (t == null) {
            wrap.statusMessage = 'No current Task set.';
            return;
        }

        wrap.statusMessage =
            t.Branch_Pit_Stop__c ? 'Branch Pit Stop Task' :
            t.Home_Office_Pit_Stop__c ? 'HO Pit Stop Task' :
            t.Task_Template__c != null ? 'This Case is On Track.' :
            'This Case status is Unspecified.';

        wrap.formattedOwnerDetail = formatOwner(t);
        wrap.nextAction = t.Subject != null ? t.Subject : 'N/A';
        wrap.timeInStage = computeStageTime(t.CreatedDate);
    }

    private static String formatOwner(Task t) {
        SObject owner = t.getSObject('Owner');
        if (owner == null) return 'No Owner found';

        if (owner.getSObjectType() == Group.SObjectType) {
            Group g = (Group)t.Owner;
            return g.Name + ' | ' + t.Subject;
        }

        if (owner.getSObjectType() == User.SObjectType) {
            User u = (User)t.Owner;
            String dept;
            if(u.Department_Picklist__c != null){
                dept = u.Department_Picklist__c + ' | ';
            } else {
                dept = '';
            }
            //String dept = u.Department_Picklist__c != null ? u.Department_Picklist__c : 'No Department';
            //dept = dept + ' | ';
            return u.Name + ' | ' + dept + t.Subject;
        }

        return 'No Owner found';
    }

    private static String computeStageTime(Datetime createdDt) {
        if (createdDt == null) return '';
        Integer days = Date.today().daysBetween(createdDt.date());
        return days <= 0 ? 'Today' : days == 1 ? '1 day' : days + ' days';
    }

    private static CaseStatusWrapper errorResponse(CaseStatusWrapper wrap) {
        wrap.statusMessage = 'Error retrieving status';
        wrap.totalTasks = 0;
        wrap.completedTasks = 0;
        wrap.nextAction = '';
        wrap.timeInStage = '';
        return wrap;
    }
}