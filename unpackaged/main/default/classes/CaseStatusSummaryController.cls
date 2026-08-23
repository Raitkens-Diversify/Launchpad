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
            wrap.membership = (membershipField == 'Case_Branch_Name__c') ?
                                c.Case_Branch_Name__c : c.Case_Home_Office_Name__c;

            Task currentTask = fetchCurrentTask(c.Current_Task_Id__c);
            processCurrentTask(currentTask, wrap);
            wrap.wrappedMilestones = buildMilestones(caseId, wrap);

            wrap.totalTasks = c.Total_Main_Track_Tasks__c != null ? Integer.valueOf(c.Total_Main_Track_Tasks__c) : 0;
            wrap.completedTasks = c.Completed_Main_Track_Tasks__c != null ? Integer.valueOf(c.Completed_Main_Track_Tasks__c) : 0;
            return wrap;
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

    private static Case fetchCase(Id caseId, String membershipField) {
        String query = 
            'SELECT Id, Current_Task_Id__c, Case_Template__c,' +
            ' Total_Main_Track_Tasks__c, Completed_Main_Track_Tasks__c,' +
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