public class Case_TriggerHandler {
    
    private List<String> lstOfCaseTemplateField;
    private String caseTemplateFieldDefaultValue;
    private Map< String, String> mapCaseTempFldToCaseFld;
    private String caseTemplateMatchFields;
    private Map< String, String> caseFieldAndTypeMap = new Map< String, String>();
    
    public void isBeforeInsert(List<Case> newList){
        setProjectManager(newList);
        setRepCode(newList, null);
        setCustodian(newList, null);
        setOriginalOwner(newList);
        setAccountForVAAP(newList);
        setCaseTemplateForWizard(newList);
        //setCaseTemplateForAdvisorRequest(newList);
        populateBranchAndHomeNames(newList, null);
        populateTaskDetails(newList, null);
    }
    
    public void isBeforeUpdate(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        setCustodian(newMap.values(), oldMap);
        setRepCode(newMap.values(), oldMap);
        createTask(newMap, oldMap);
        //setOwnerAndStatusOnCase(newMap.values(), oldMap);
        cancelMoveMoney(newMap, oldMap);
        recalcTaskRecord(newMap);
        populateBranchAndHomeNames(newMap.values(), oldMap);
        populateTaskDetails(newMap.values(), oldMap);
        populateMilestoneOnCase(newMap.values(), oldMap);
    }
    
    public void isBeforeDelete(Map<Id, Case> oldMap){
        
    }
    
    public void isAfterInsert(Map<Id, Case> newMap){
        createShareRecord(newMap, null);
        createAdvisorRequestTask(newMap);
        createWizardTask(newMap);
        createCDLforCase(newMap, null);
        populateJointOwner(newMap, null);
    }
    
    public void isAfterUpdate(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        createShareRecord(newMap, oldMap);
        createCDLonAccount(newMap, oldMap);
        //createCDLforCase(newMap, oldMap);
        updateRelatedAccount(newMap, oldMap);
        setApprovedStatusOnAdItem(newMap, oldMap);
        setDateOfDeathOnAccount(newMap.values(), oldMap);
        populateJointOwner(newMap, oldMap);
        updateMainTrackCounts(newMap.values(), oldMap);
    }
    
    public void isAfterDelete(Map<Id, Case> oldMap){
        
    }
    
    public void isAfterUnDelete(Map<Id, Case> newMap){
        
    }
    
    private static void populateBranchAndHomeNames(List<Case> newList, Map<Id, Case> oldMap) {
    
        Set<Id> finAcctIds = new Set<Id>();
        Set<Id> advisorTeamIds = new Set<Id>();
    
        for (Case c : newList) {
            if (c.Wizard_Financial_Account__c != null)
                finAcctIds.add(c.Wizard_Financial_Account__c);
    
            if (c.Financial_Advisor_Team__c != null)
                advisorTeamIds.add(c.Financial_Advisor_Team__c);
        }
    
        Map<Id, Financial_Account__c> faMap =
            new Map<Id, Financial_Account__c>(
                [SELECT Id,
                        Registration_Type__c,
                        Custodian__c,
                        Managed_Account_Platform__c,
                        BD_or_RIA__c,
                        Primary_Owner__r.FirstName,
                        Primary_Owner__r.LastName
                 FROM Financial_Account__c
                 WHERE Id IN :finAcctIds]
            );
    
        Map<Id, Financial_Advisor_Team__c> teamMap =
            new Map<Id, Financial_Advisor_Team__c>(
                [SELECT Id,
                        Primary_Financial_Advisor__r.FirstName,
                        Primary_Financial_Advisor__r.LastName
                 FROM Financial_Advisor_Team__c
                 WHERE Id IN :advisorTeamIds]
            );
    
        for (Case c : newList) {
    
            Financial_Account__c fa = faMap.get(c.Wizard_Financial_Account__c);
            Financial_Advisor_Team__c team = teamMap.get(c.Financial_Advisor_Team__c);
    
            List<String> branchParts = new List<String>();
            List<String> homeParts = new List<String>();
    
            // -------- Branch Name -------- /
            branchParts.add(c.Type);
            if (fa != null) {
                branchParts.add(fa.Registration_Type__c);
                branchParts.add(fa.Custodian__c);
                branchParts.add(fa.Managed_Account_Platform__c);
                branchParts.add(fa.BD_or_RIA__c);
                branchParts.add('</br>');
                branchParts.add(fullName(fa.Primary_Owner__r));
            }
            if (team != null)
                branchParts.add(fullName(team.Primary_Financial_Advisor__r));
            if(c.Amount__c != null)
            branchParts.add('$ ' + String.valueOf(c.Amount__c.format()));
    
            c.Case_Branch_Name__c = joinNonNull(branchParts);
    
            // -------- Home Office Name -------- /
            homeParts.add(c.Type);
            if (fa != null) {
                homeParts.add(fa.Registration_Type__c);
                homeParts.add(fa.Custodian__c);
                homeParts.add(fa.Managed_Account_Platform__c);
                homeParts.add(fa.BD_or_RIA__c);
                homeParts.add('</br>');
            }
            if (team != null)
                homeParts.add(fullName(team.Primary_Financial_Advisor__r));
    
            if (fa != null)
                homeParts.add(fullName(fa.Primary_Owner__r));
            if(c.Amount__c != null)
            homeParts.add('$ ' + String.valueOf(c.Amount__c.format()));
    
            c.Case_Home_Office_Name__c = joinNonNull(homeParts);
        }
        populateNullNameFields(newList);
    }
    
    private static void populateNullNameFields(List<Case> newList) {
        for (Case record : newList) {
            record.Case_Branch_Name__c = record.Case_Branch_Name__c ?? record.Subject;
            record.Case_Home_Office_Name__c = record.Case_Home_Office_Name__c ?? record.Subject;
        }
    }
    
    private static void populateTaskDetails(List<Case> newCases, Map<Id, Case> oldMap) {
        Set<Id> currentTaskIds = new Set<Id>();
        Set<Id> caseIds = new Set<Id>();
    
        for (Case c : newCases) {
            if (c.Current_Task_Id__c != null) currentTaskIds.add(c.Current_Task_Id__c);
            if (c.Id != null) caseIds.add(c.Id);
        }
    
        if (caseIds.isEmpty()) return;
    
        Map<Id, Task> currentTaskMap = new Map<Id, Task>([
            SELECT Id, Owner.Name, Subject, Home_Office_Pit_Stop__c, Branch_Pit_Stop__c  
            FROM Task WHERE Id IN :currentTaskIds
        ]);
    
        Map<Id, List<Task>> openTasksPerCase = new Map<Id, List<Task>>();
        for (Task t : [SELECT Id, WhatId FROM Task WHERE WhatId IN :caseIds AND Status != 'Completed']) {
            if (!openTasksPerCase.containsKey(t.WhatId)) openTasksPerCase.put(t.WhatId, new List<Task>());
            openTasksPerCase.get(t.WhatId).add(t);
        }
    
        for (Case c : newCases) {
            if (c.Current_Task_Id__c != null && currentTaskMap.containsKey(c.Current_Task_Id__c)) {
                Task relatedTask = currentTaskMap.get(c.Current_Task_Id__c);
                c.Current_Task_Subject_Assignee__c = relatedTask.Owner.Name + ' | ' + relatedTask.Subject;
                
                if (!openTasksPerCase.containsKey(c.Id)) {
                    c.Current_Task_Status__c = 'Completed';
                } 
                else if (relatedTask.Branch_Pit_Stop__c) {
                    c.Current_Task_Status__c = 'Branch Pit Stop';
                } else if (relatedTask.Home_Office_Pit_Stop__c) {
                    c.Current_Task_Status__c = 'HO Pit Stop';               
                } else {
                    c.Current_Task_Status__c = 'On Track';
                }
            } else {
                c.Current_Task_Subject_Assignee__c = null;
                if (!openTasksPerCase.containsKey(c.Id) && c.Id != null) {
                    c.Current_Task_Status__c = 'Completed';
                }
            }
        }
    }

    public static void populateMilestoneOnCase(List<Case> newCases, Map<Id, Case> oldMap) {

        System.debug('Hello from populateMilestone');
    
        Set<Id> caseIds = new Set<Id>();
        for(Case c : newCases){
            caseIds.add(c.Id);
        }
    
        Map<Id, List<Task>> caseTaskMap = new Map<Id, List<Task>>();
    
        for(Task t : [
            SELECT Status, WhatId,
                   Task_Template_Item__r.Home_Office_Submission_Milestone__c,
                   Task_Template_Item__r.Home_Office_Approval_Milestone__c,
                   Task_Template_Item__r.Branch_Goal_Milestone__c,
                   Task_Template_Item__r.Home_Office_Goal_Milestone__c
            FROM Task
            WHERE WhatId IN :caseIds
        ]){
            if(!caseTaskMap.containsKey(t.WhatId)){
                caseTaskMap.put(t.WhatId, new List<Task>());
            }
            caseTaskMap.get(t.WhatId).add(t);
        }
    
        List<String> milestoneOrder = new List<String>{
            'Home_Office_Submission_Milestone__c',
            'Home_Office_Approval_Milestone__c',
            'Branch_Goal_Milestone__c',
            'Home_Office_Goal_Milestone__c'
        };
    
        Map<String,String> milestoneLabel = new Map<String,String>{
            'Home_Office_Submission_Milestone__c' => 'HO Submission',
            'Home_Office_Approval_Milestone__c' => 'HO Approval',
            'Branch_Goal_Milestone__c' => 'Branch Goal',
            'Home_Office_Goal_Milestone__c' => 'HO Goal'
        };
    
        for(Case c : newCases){
    
            if(!caseTaskMap.containsKey(c.Id)){
                continue;
            }
    
            String lastCompletedMilestone;
    
            for(String milestoneField : milestoneOrder){
    
                for(Task t : caseTaskMap.get(c.Id)){
    
                    Task_Template_Item__c tti = t.Task_Template_Item__r;
    
                    if(tti != null && (Boolean)tti.get(milestoneField) == true){
    
                        if(t.Status == 'Completed'){
                            lastCompletedMilestone = milestoneLabel.get(milestoneField);
                        }
                    }
                }
            }
    
            if(lastCompletedMilestone != null && c.Milestone__c != lastCompletedMilestone){
                c.Milestone__c = lastCompletedMilestone;
            }
        }
    }
    
    private static String joinNonNull(List<String> items) {
        List<String> cleaned = new List<String>();
        for (String s : items)
            if (s != null && s.trim() != '')
            cleaned.add(s.trim());
        
        return cleaned.size() > 0 ? String.join(cleaned, ' | ') : null;
    }

    private static String fullName(SObject person) {
        if (person == null) return null;

        String first = (String)person.get('FirstName');
        String last = (String)person.get('LastName');

        if ((first == null || first == '') && (last == null || last == ''))
            return null;

        return (first != null ? first : '') + ' ' + (last != null ? last : '');
    }
    
    public static void updateMainTrackCounts(List<Case> newList, Map<Id, Case> oldMap) {
        List<Case> caseList = new List<Case>();
        Set<Id> templateIds = new Set<Id>();

        for(Case triggeringRecord : newList) {
            if((triggeringRecord.Total_Main_Track_Tasks__c == NULL ) || (triggeringRecord.Total_Main_Track_Tasks__c != oldMap.get(triggeringRecord.Id).Total_Main_Track_Tasks__c)) {
                caseList.add(triggeringRecord);             
                if (triggeringRecord.Case_Template__c != null) {
                    templateIds.add(triggeringRecord.Case_Template__c);
                }
            }
        }
        System.debug('caseList :' + caseList);
        
        if (caseList.isEmpty()) return;
        Map<Id, Integer> templateItemCountMap = new Map<Id, Integer>();
        if (!templateIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Case_Template__c templateId, COUNT(Id) total 
                FROM Task_Template_Item__c 
                WHERE Case_Template__c IN :templateIds 
                GROUP BY Case_Template__c
            ]) {
                System.debug('ar :' + ar);
                templateItemCountMap.put((Id) ar.get('templateId'), (Integer) ar.get('total'));
            }
        }
    
        List<Case> casesToUpdate = new List<Case>();
        for (Case triggerRecord : caseList) {
            //if (newMap.keySet().contains(triggerRecord.Id)) {
                Case updatedCase = new Case(Id = triggerRecord.Id);
                Id tId = triggerRecord.Case_Template__c;
                updatedCase.Total_Main_Track_Tasks__c = (tId != null && templateItemCountMap.containsKey(tId)) 
                                                        ? templateItemCountMap.get(tId) 
                                                        : 0;
                
                casesToUpdate.add(updatedCase);
            //}
        }
    
        if (!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }

     }
    
    public static void setProjectManager(List<Case> newList){
        Map<Id,Id> caseToFinAdvTeam = new Map<Id,Id>();
        List<Case> casesToUpdate = new List<Case>();
        for(Case c : newList){
            if(c.Financial_Advisor_Team__c != null){
                caseToFinAdvTeam.put(c.Id, c.Financial_Advisor_Team__c);
                casesToUpdate.add(c);
            }
        }
        if(!caseToFinAdvTeam.isEmpty()){
            List<Financial_Advisor_Team_Member__c> fatms = [SELECT Id, Project_Manager__c, Financial_Advisor_Team__c, User__c FROM Financial_Advisor_Team_Member__c WHERE Project_Manager__c = true and Financial_Advisor_Team__c in: caseToFinAdvTeam.values()];
            Map<Id,Id> teamToPM = new Map<Id,Id>();
            for(Financial_Advisor_Team_Member__c fat : fatms){
                teamToPM.put(fat.Financial_Advisor_Team__c, fat.User__c);
            }
            for(Case c : casesToUpdate){
                if(teamToPM.get(caseToFinAdvTeam.get(c.Id)) != null){
                    c.OwnerId = teamToPM.get(caseToFinAdvTeam.get(c.Id));
                }else{
                    //Set the owner of the case to the submitter of the case
                    c.OwnerId  = UserInfo.getUserId();
                }
            }
        }
    }
    
    public static void setRepCode(List<Case> cases, Map<Id, Case> oldMap){
        Set<Id> finAcctIds = new Set<Id>();
        for(Case c : cases){
            if(c.Wizard_Financial_Account__c != null && shouldSetRepCodeFromFinancialAccount(c, oldMap)){
                finAcctIds.add(c.Wizard_Financial_Account__c);
            }
        }
        if(!finAcctIds.isEmpty()){
            Map<Id,Financial_Account__c> finAccts = new Map<Id,Financial_Account__c>([SELECT Id, Rep_Code__c FROM Financial_Account__c WHERE Id in: finAcctIds]);
            for(Case c : cases){
                if(c.Wizard_Financial_Account__c != null && shouldSetRepCodeFromFinancialAccount(c, oldMap)){
                    c.Rep_Code__c = finAccts.get(c.Wizard_Financial_Account__c).Rep_Code__c;
                }
            }
        }
    }
    
    private static Boolean shouldSetRepCodeFromFinancialAccount(Case c, Map<Id, Case> oldMap){
        if(oldMap == null){
            return c.Wizard_Financial_Account__c != null;
        }
        Case oldCase = oldMap.get(c.Id);
        return c.Wizard_Financial_Account__c != oldCase.Wizard_Financial_Account__c;
    }
    
    public static void setCustodian(List<Case> cases, Map<Id, Case> oldMap){
        Set<Id> finAcctIds = new Set<Id>();
        
        for(Case c : cases){
            if(String.isNotBlank(c.Custodian__c) || !shouldSetCustodianFromFinancialAccount(c, oldMap)){
                continue;
            }
            if(c.Wizard_Financial_Account__c != null){
                finAcctIds.add(c.Wizard_Financial_Account__c);
            } 
        }
        
        if(finAcctIds.isEmpty()){
            return;
        }
        
        Map<Id, Financial_Account__c> finAcctMap = finAcctIds.isEmpty()
            ? new Map<Id, Financial_Account__c>()
            : new Map<Id, Financial_Account__c>(
                [SELECT Id, Custodian__c FROM Financial_Account__c WHERE Id IN :finAcctIds]
            );
        
        for(Case c : cases){
            if(String.isNotBlank(c.Custodian__c) || !shouldSetCustodianFromFinancialAccount(c, oldMap)){
                continue;
            }
            if(c.Wizard_Financial_Account__c != null && finAcctMap.containsKey(c.Wizard_Financial_Account__c)){
                c.Custodian__c = finAcctMap.get(c.Wizard_Financial_Account__c).Custodian__c;
            }
        } 
    }
    
    private static Boolean shouldSetCustodianFromFinancialAccount(Case c, Map<Id, Case> oldMap){
        if(oldMap == null){
            return c.Wizard_Financial_Account__c != null;
        }
        Case oldCase = oldMap.get(c.Id);
        return c.Wizard_Financial_Account__c != oldCase.Wizard_Financial_Account__c;
    }
    
    public static void setOriginalOwner(List<Case> newList){
        for(Case c : newList){
            c.Original_Owner__c = c.OwnerId;
        }
    }
    
    public void setAccountForVAAP(List<Case> newList){
        List<Case> casesToUpdate = new List<Case>();
        Set<Id> finIds = new Set<Id>();
        Map<Id, Id> finAcctToHouseholdId = new Map<Id, Id>();
        for(Case c : newList){
            if(c.Type == 'Variable Annuity Additional Purchase'){
                casesToUpdate.add(c);
                finIds.add(c.Wizard_Financial_Account__c);
            }
        }
        if(!finIds.isEmpty()){
            List<Financial_Account__c> finAccts = [SELECT Id, Household__c FROM Financial_Account__c WHERE Id IN: finIds];
            for(Financial_Account__c f : finAccts){
                finAcctToHouseholdId.put(f.Id, f.Household__c);
            }
        }
        if(!casesToUpdate.isEmpty()){
            for(Case c : casesToUpdate){
                if(finAcctToHouseholdId.get(c.Wizard_Financial_Account__c) != null){
                    c.AccountId = finAcctToHouseholdId.get(c.Wizard_Financial_Account__c);
                }
            }
        }
    }
    
public  Map<Id,Case> setCaseTemplateForWizard(List<Case> newList){
        Set<String> setOfTypeToName = new Set<String>(); 
        Map<String, List<Case_Template__c>> mapOfNameTolstCaseTemp = new Map<String, List<Case_Template__c>>(); 
        Map<Id, Id> mapOfCaseIdToCaseTempId = new  Map<Id, Id>();
        List<Case_Template__c> lstCaseTemplate = new List<Case_Template__c>();
        Map<String, List<Case_Template__c>> templatesByType = new Map<String, List<Case_Template__c>>();
        String caseTemplateType;
        
        lstOfCaseTemplateField = new List<String>{'Type__c', 'Compliance_Needed__c', 'Check_in_Hand__c',
            'Management_Style__c' ,'Custodian__c', 'Previous_Management_Style__c', 'Charity_Sponsor__c',
            'Enough_Cash__c', 'Live_SLOA_on_File__c', 'Money_Movement_Direction__c' };
                
                caseTemplateFieldDefaultValue = 'EXCLUDED';
        
         mapCaseTempFldToCaseFld = new Map< String, String>{ 'Type__c' => 'Type','Compliance_Needed__c' => 'SOF_Compliance__c', 
            'Check_in_Hand__c' => 'Check_in_Hand__c', 'Management_Style__c' => 'Management_Style__c','Custodian__c' => 'Custodian__c', 'Previous_Management_Style__c' => 'Previous_Management_Style__c',
            'Charity_Sponsor__c' => 'Charity_Sponsor__c', 'Enough_Cash__c' => 'Enough_Cash__c', 'Live_SLOA_on_File__c' => 'No_SLOA_On_File__c', 'Money_Movement_Direction__c' => 'Money_Movement_Direction__c'}; 
                
        Id newAccountRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Opening').getRecordTypeId();
        Id servicingRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Servicing').getRecordTypeId();
        Id approvalRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Account Servicing - Approval Required').getRecordTypeId();
        //Id approvalTaskRecordTypeId = Schema.sObjectType.Task.getRecordTypeInfosByName().get('Approval Task').getRecordTypeId();
        
        setCaseTemplateFieldTypes();
        
        /*for(Case caseRecord : newList){
setOfTypeToName.add('Account Opening');
setOfTypeToName.add('Account Servicing');
setOfTypeToName.add('Account Servicing - Approval Required');
}*/
        
        //Get type of tmeplate by using current user 
        User currentUser = [SELECT Id,Profile.UserLicense.Name FROM User WHERE Id =: UserInfo.getUserId()];
        
        if (currentUser.Profile.UserLicense.Name == 'Customer Community Plus') {
            
            caseTemplateType = 'Fixed';
            
            lstCaseTemplate = [
                SELECT Id,
                Name,
                Check_in_hand__c,
                Compliance_Needed__c,
                Management_Style__c,
                Type__c,
                Custodian__c,
                Previous_Management_Style__c,
                Charity_Sponsor__c,
                Enough_Cash__c,
                Live_SLOA_on_file__c,
                money_movement_direction__c,
                Type_of_Template__c
                FROM Case_Template__c
                WHERE Type_of_Template__c = 'Fixed'
            ];
            
        } else if (currentUser.Profile.UserLicense.Name == 'Salesforce') {
            caseTemplateType = 'PrePostFixed';
            
            lstCaseTemplate = [
                SELECT Id,
                Name,
                Check_in_hand__c,
                Compliance_Needed__c,
                Management_Style__c,
                Type__c,
                Custodian__c,
                Previous_Management_Style__c,
                Charity_Sponsor__c,
                Enough_Cash__c,
                Live_SLOA_on_file__c,
                money_movement_direction__c,
                Type_of_Template__c
                FROM Case_Template__c
                WHERE Type_of_Template__c IN ('Pre', 'Post', 'Fixed')
            ];
            System.debug('templates: ' + lstCaseTemplate);
        }
        
        
        // Group templates by Type_of_Template__c
        for (Case_Template__c template : lstCaseTemplate) {
            if (!templatesByType.containsKey(template.Type_of_Template__c)) {
                templatesByType.put(
                    template.Type_of_Template__c,
                    new List<Case_Template__c>()
                );
            }
            templatesByType.get(template.Type_of_Template__c).add(template);
        }
        
        
        // Match templates for each Case
        for (Case caseRecord : newList) {
            
            if (caseRecord.Donotcalc__c != true) {
                
                caseTemplateMatchFields = '';
                
                // ---------------------------------
                // Customer Community Plus
                // Only Fixed template
                // ---------------------------------
                if (caseTemplateType == 'Fixed') {
                    
                    List<Case_Template__c> fixedTemplates = templatesByType.get('Fixed');
                    
                    if (fixedTemplates != null && !fixedTemplates.isEmpty()) {
                        
                        Id fixedTemplateId = getCaseTempId(fixedTemplates, caseRecord,0);
                        
                        if (!String.isEmpty(fixedTemplateId)) {
                            caseRecord.Case_Template__c = fixedTemplateId;
                            caseRecord.No_Template_Found__c = false;
                        }
                    }
                    
                }
                // ---------------------------------
                // Salesforce / Salesforce Platform
                // Pre + Post + Fixed
                // ---------------------------------
                else {
                    // PRE
                    List<Case_Template__c> preTemplates = templatesByType.get('Pre');
                    
                    if (preTemplates != null && !preTemplates.isEmpty()) {
                        
                        Id preTemplateId = getCaseTempId(preTemplates, caseRecord, 0);
                        if (!String.isEmpty(preTemplateId)) {
                            caseRecord.Pre_Case_Template__c = preTemplateId;
                            caseRecord.No_Template_Found__c = false;
                        }
                    }
                    
                    // POST
                    List<Case_Template__c> postTemplates = templatesByType.get('Post');
                    
                    if (postTemplates != null && !postTemplates.isEmpty()) {
                        
                        Id postTemplateId = getCaseTempId(postTemplates, caseRecord,0);
                        
                        if (!String.isEmpty(postTemplateId)) {
                            caseRecord.Post_Case_Template__c = postTemplateId;
                            caseRecord.No_Template_Found__c = false;
                        }
                    }
                    
                    // FIXED
                    List<Case_Template__c> fixedTemplates = templatesByType.get('Fixed');
                    
                    if (fixedTemplates != null && !fixedTemplates.isEmpty()) {
                        
                        Id fixedTemplateId = getCaseTempId(fixedTemplates, caseRecord, 0);
                        
                        if (!String.isEmpty(fixedTemplateId)) {
                            caseRecord.Case_Template__c = fixedTemplateId;
                            caseRecord.No_Template_Found__c = false;
                        }
                    }
                }
                
                // Set matching fields
                caseRecord.No_Template_Found_Completed_Fields__c =
                    caseTemplateMatchFields;
            }
        }
        
        
        
        Map<Id,Case> caseMap = new Map<Id,Case>(); 
        for(Case caseRecord : newList){
            if(caseRecord.Id != null){
                caseMap.put(caseRecord.Id,caseRecord);
            }
        }
        return caseMap;
    }
    
    /*public Map<Id,Case> setCaseTemplateForAdvisorRequest(List<Case> newList){
        Set<String> setOfTypeToName = new Set<String>(); 
        Map<String, List<Case_Template__c>> mapOfNameTolstCaseTemp = new Map<String, List<Case_Template__c>>(); 
        Map<Id, Id> mapOfCaseIdToCaseTempId = new  Map<Id, Id>();
        List<Case_Template__c> lstCaseTemplate = new List<Case_Template__c>();
        
        lstOfCaseTemplateField = new List<String>{'Previous_Management_Style__c', 'Management_Style__c', 'Charity_Sponsor__c',
            'Enough_Cash__c', 'Custodian__c' , 
            'Live_SLOA_on_File__c', 'Money_Movement_Direction__c', 'Compliance_Needed__c', 'Check_in_Hand__c' };
                
                caseTemplateFieldDefaultValue = 'EXCLUDED';
        
        mapCaseTempFldToCaseFld = new Map< String, String>{'Name' => 'Type', 'Previous_Management_Style__c' => 'Previous_Management_Style__c', 'Management_Style__c' => 'Management_Style__c',
            'Charity_Sponsor__c' => 'Charity_Sponsor__c', 'Enough_Cash__c' => 'Enough_Cash__c', 'Custodian__c' => 'Custodian__c',
            'Live_SLOA_on_File__c' => 'No_SLOA_On_File__c', 'Money_Movement_Direction__c' => 'Money_Movement_Direction__c', 'Compliance_Needed__c' => 'SOF_Compliance__c', 'Check_in_Hand__c' => 'Check_in_Hand__c'};
                
                setCaseTemplateFieldTypes(); 
        
        for(Case caseRecord : newList){
            if(!String.isEmpty(caseRecord.Type)){
                setOfTypeToName.add(caseRecord.Type);
            }
            
        }
        lstCaseTemplate = [SELECT Id, Name, Previous_Management_Style__c, Management_Style__c, Charity_Sponsor__c, Enough_Cash__c, Custodian__c,
                           Live_SLOA_on_File__c,
                           Money_Movement_Direction__c, Compliance_Needed__c, Check_in_Hand__c FROM Case_Template__c WHERE Name IN : setOfTypeToName];
        
        for(Case_Template__c caseTemplate : lstCaseTemplate){
            if(!mapOfNameTolstCaseTemp.containsKey(caseTemplate.Name)){
                mapOfNameTolstCaseTemp.put(caseTemplate.Name, new List<Case_Template__c>());
            }
            mapOfNameTolstCaseTemp.get(caseTemplate.Name).add(caseTemplate);
        }
        
        for(Case caseRecord : newList){
            if(caseRecord.Origin == 'Service Request' && mapOfNameTolstCaseTemp.containsKey(caseRecord.Type)){
                List<Case_Template__c> caseTemplateList = mapOfNameTolstCaseTemp.get(caseRecord.Type);
                if(!caseTemplateList.isEmpty() && caseTemplateList.size() > 0){
                    caseTemplateMatchFields ='';
                    Id caseTempId = getCaseTempId(caseTemplateList, caseRecord, 0);
                    if(!String.isEmpty(caseTempId)){
                        caseRecord.Case_Template__c = caseTempId;   
                        caseRecord.No_Template_Found__c = False;
                    } 
                    //set Matching Fields
                    caseRecord.No_Template_Found_Completed_Fields__c = caseTemplateMatchFields;
                }
            }
        }
        //For Recalculate Task
        Map<Id,Case> caseMap = new Map<Id,Case>(); 
        for(Case caseRecord : newList){
            if(caseRecord.Id != null){
                caseMap.put(caseRecord.Id,caseRecord);
            }
        }           
        return caseMap;
    }*/
    
    public void createShareRecord(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        Set<Id> fAccTeamIdSet = new Set<Id>();
        
        for(Case cs : newMap.values()){
            if(oldMap == null){
                if(cs.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(cs.Financial_Advisor_Team__c);
            } else if(oldMap.get(cs.Id).Financial_Advisor_Team__c != cs.Financial_Advisor_Team__c || oldMap.get(cs.Id).OwnerId != cs.OwnerId){
                if(cs.Financial_Advisor_Team__c != null)
                    fAccTeamIdSet.add(cs.Financial_Advisor_Team__c);
                if(oldMap.get(cs.Id).Financial_Advisor_Team__c != null){
                    fAccTeamIdSet.add(oldMap.get(cs.Id).Financial_Advisor_Team__c);
                }
            } 
        }
        
        if(!fAccTeamIdSet.isEmpty()){
            Map<Id, Financial_Advisor_Team__c> fATeamMap = new Map<Id, Financial_Advisor_Team__c>([SELECT Id, Public_Group_Id__c FROM Financial_Advisor_Team__c WHERE Id IN : fAccTeamIdSet]);
            if(!fATeamMap.isEmpty()){
                List<CaseShare> shareRecordList = new List<CaseShare>();
                //For revoke Share
                Set<Id> groupIdSet = new Set<Id>();
                Set<Id> parentIdSet = new Set<Id>();
                for(Case cs : newMap.values()){
                    CaseShare shareRec = new CaseShare();
                    if(fATeamMap.get(cs.Financial_Advisor_Team__c)!=null){
                        shareRec.CaseId = cs.Id;
                        if(cs.Financial_Advisor_Team__c != null){
                            shareRec.UserOrGroupId = fATeamMap.get(cs.Financial_Advisor_Team__c).Public_Group_Id__c;
                        }
                        
                        shareRec.CaseAccessLevel = 'Edit';
                        shareRec.RowCause = Schema.CaseShare.RowCause.Manual;
                        if(oldMap == null){
                            if(cs.Financial_Advisor_Team__c != null){
                                shareRecordList.add(shareRec);
                            }
                        } else if(oldMap != null && (oldMap.get(cs.Id).Financial_Advisor_Team__c != cs.Financial_Advisor_Team__c ||
                                                     oldMap.get(cs.Id).OwnerId != cs.OwnerId)){
                                                         if(oldMap.get(cs.Id).Financial_Advisor_Team__c != null 
                                                            && fATeamMap.get(oldMap.get(cs.Id).Financial_Advisor_Team__c) != null){
                                                                groupIdSet.add(fATeamMap.get(oldMap.get(cs.Id).Financial_Advisor_Team__c).Public_Group_Id__c);
                                                                parentIdSet.add(cs.Id);
                                                            }            
                                                         if(cs.Financial_Advisor_Team__c != null){
                                                             shareRecordList.add(shareRec);                                 
                                                         }
                                                     }
                    }
                }
                if(groupIdSet.size() > 0 && parentIdSet.size() > 0){
                    List<CaseShare> removeShareList = new List<CaseShare>();
                    for(CaseShare shareRec: [SELECT Id, CaseId, UserOrGroupId FROM CaseShare WHERE CaseId IN: parentIdSet and UserOrGroupId IN: groupIdSet]){
                        if(groupIdSet.Contains(shareRec.UserOrGroupId) && parentIdSet.contains(shareRec.CaseId) ){
                            removeShareList.add(shareRec);
                        }
                    }
                    if(removeShareList.size() > 0){
                        Database.delete(removeShareList,false);
                    } 
                }
                if(shareRecordList.size() > 0){
                    Database.insert(shareRecordList,false);
                }
            }
        }
    }
    
    private void createCDLonAccount(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        List<ContentDocumentLink> cdlsToInsert = new List<ContentDocumentLink>();
        Set<Id> caseIds = new Set<Id>();
        for(Case newCase : newMap.values()){
            Case oldCase = oldMap.get(newCase.Id);
            if(newCase.Type == 'AML Document Approval' && newCase.AccountId != null && newCase.Documents_Uploaded__c > 0 && newCase.Documents_Uploaded__c != oldCase.Documents_Uploaded__c){
                caseIds.add(newCase.Id);
            }
        }
        
        if(!caseIds.isEmpty()){
            Map<Id, Id> mapCaseIdToDocumentId = new Map<Id, Id>();
            List<ContentDocumentLink> caseCDL = [SELECT Id, LinkedEntityId, ContentDocumentId FROM ContentDocumentLink
                                                 WHERE LinkedEntityId IN :caseIds LIMIT 1];
            for(ContentDocumentLink cdl : caseCDL){
                mapCaseIdToDocumentId.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
            }
            
            for(Id caseId : mapCaseIdToDocumentId.keySet()){
                ContentDocumentLink accCDL = new ContentDocumentLink();
                accCDL.LinkedEntityId = newMap.get(caseId).AccountId;
                accCDL.ShareType = 'V';
                accCDL.ContentDocumentId = mapCaseIdToDocumentId.get(caseId);
                cdlsToInsert.add(accCDL);
            }
            
            if(!cdlsToInsert.isEmpty()){
                insert cdlsToInsert;
            }
        }
        
    }
    
    private void createAdvisorRequestTask(Map<Id, Case> newMap){
        Set<Id> setOfFATIds = new Set<Id>();
        Set<String> setOfQueueNames = new Set<String>();
        Set<Id> setAccounts = new Set<Id>();
        Set<Id> setOfFinAccountId = new Set<Id>();
        
        Map<Id, Id> mapOfCaseIdToCaseTempId = new  Map<Id, Id>();
        Map<String, List<Case_Template__c>> mapOfNameTolstCaseTemp = new Map<String, List<Case_Template__c>>(); 
        Map<Id, List<Task_Template_Item__c>> mapOfCaseTempIdToLstTemp = new Map<Id, List<Task_Template_Item__c>>();
        Map<Id, Financial_Advisor_Team__c> mapOfFATeam = new Map<Id, Financial_Advisor_Team__c>();
        Map<String, Id> mapOfQueueIdByName = new Map<String, Id>();
        Map<Id,Id> perToAccIds = new Map<Id,Id>();
        Map<Id,Financial_Account__c> mapOfFinAccount = new Map<Id,Financial_Account__c>();
        
        List<Task> lstTask = new List<Task>();
        List<Task_Template_Item__c> lstTaskTempItem = new List<Task_Template_Item__c>();
        List<Case_Template__c> lstCaseTemplate = new List<Case_Template__c>();
        List<Group> lstGroup = new List<Group>();
        List<Account> accts = new List<Account>();
        Map<Id,Id> mapOfFatTeamAndUserForPrimary = new Map<Id,Id>();
        Map<Id,Id> mapOfFatTeamAndUserForOperations = new Map<Id,Id>();
        for(Case caseRecord : newMap.Values()){
            if(!String.isEmpty(caseRecord.Case_template__c) && caseRecord.Origin == 'Service Request'){
                mapOfCaseIdToCaseTempId.put(caseRecord.Id,caseRecord.Case_template__c);
            }
            if(!String.isEmpty(caseRecord.ContactId)){
                setAccounts.add(caseRecord.ContactId);
            }
            if(!String.isEmpty(caseRecord.Financial_Advisor_Team__c)){
                setOfFATIds.add(caseRecord.Financial_Advisor_Team__c);
            }
            if(!String.isEmpty(caseRecord.Wizard_Financial_Account__c)){
                setOfFinAccountId.add(caseRecord.Wizard_Financial_Account__c);
            }
        }
        
        if(!setOfFATIds.isEmpty()){
            mapOfFATeam = new Map<Id, Financial_Advisor_Team__c>([SELECT Id, (SELECT ID, Associate_Advisor__c, CSA__c, Send_Notifications__c, 
                                                                              Review_Paperwork__c, Draft_Paperwork__c, Trading__c, User__c ,Operations__c,Primary__c
                                                                              FROM Financial_Advisor_Team_Members__r)
                                                                  FROM Financial_Advisor_Team__c WHERE Id IN :setOfFATIds ]);
        }
        //Get User from FAT Team Member thoese have Primary and Operations permission true
        
        for(Financial_Advisor_Team__c fat : mapOfFATeam.values()){
            for(Financial_Advisor_Team_Member__c fatm : fat.Financial_Advisor_Team_Members__r){
                if(fatm.Operations__c){
                    mapOfFatTeamAndUserForOperations.put(fat.Id,fatm.User__c);
                }
                if(fatm.Primary__c){
                    mapOfFatTeamAndUserForPrimary.put(fat.Id,fatm.User__c);
                }
            }
        }
        if(!setOfFinAccountId.isEmpty()){
            mapOfFinAccount = new Map<Id, Financial_Account__c>([SELECT Id, Name
                                                                         FROM Financial_Account__c WHERE Id IN :setOfFinAccountId ]);
        }
        
        if(!setAccounts.isEmpty()){
            accts = [SELECT Id, PersonContactId FROM Account WHERE PersonContactId in: setAccounts];
        }
        for(Account a : accts){
            perToAccIds.put(a.PersonContactId,a.Id);
        }
        
        if(!mapOfCaseIdToCaseTempId.isEmpty()){
            lstTaskTempItem = [SELECT Id, Task_Template__r.Priority__c, Case_Template__c,
                               Task_Template__r.Assigned_To__c,
                               Task_Template__r.FA_Team_Permission__c, Order__c,
                               Task_Template__r.Queue__c, Task_Template__r.Due_Date__c,
                               Task_Template__r.Number_of_Days__c,
                               Task_Template__r.Description__c, Task_Template__r.Referenced_Field__c, Task_Template__r.Needs_2nd_Ops_Review__c, 
                               Independent__c, Task_Template__r.Name
                               FROM Task_Template_Item__c 
                               WHERE Case_Template__c IN : mapOfCaseIdToCaseTempId.values()];
        } 
        
        setOfQueueNames.add('Unassigned'); 
        setOfQueueNames.add('Operations'); 
        for(Task_Template_Item__c taskTempItem : lstTaskTempItem){
            if(!String.isEmpty(taskTempItem.Task_Template__r.Queue__c)){
                setOfQueueNames.add(taskTempItem.Task_Template__r.Queue__c);
            }
            if(!mapOfCaseTempIdToLstTemp.containsKey(taskTempItem.Case_Template__c)){
                mapOfCaseTempIdToLstTemp.put(taskTempItem.Case_Template__c, new List<Task_Template_Item__c>());
            }
            mapOfCaseTempIdToLstTemp.get(taskTempItem.Case_Template__c).add(taskTempItem);
        }
        
        lstGroup = [Select Id, Name from Group where type='Queue' and Name= :setOfQueueNames];
        for(Group groupRecord : lstGroup){
            mapOfQueueIdByName.put(groupRecord.Name, groupRecord.Id);
        }
        
        Id approvalTaskRecordTypeId = Schema.sObjectType.Task.getRecordTypeInfosByName().get('Approval Task').getRecordTypeId();
        for(Id caseId : mapOfCaseIdToCaseTempId.keySet()){
            Case caseRecord = newMap.get(caseId);
            Date ActivityDate = System.Today();
            if(!mapOfCaseTempIdToLstTemp.isEmpty() && mapOfCaseTempIdToLstTemp.containsKey(mapOfCaseIdToCaseTempId.get(caseId))){
                List<Task_Template_Item__c> lstTaskTempItemRecord = mapOfCaseTempIdToLstTemp.get(mapOfCaseIdToCaseTempId.get(caseId));
                //Sort on the base of order.
                Map<Integer,Task_Template_Item__c> orderAndTaskTempItemsMap = new Map<Integer,Task_Template_Item__c>();
                for(Task_Template_Item__c taskTempItemRecord : lstTaskTempItemRecord){
                    orderAndTaskTempItemsMap.put((Integer)taskTempItemRecord.Order__c,taskTempItemRecord);
                }
                List<Integer> sortedOrders = new List<Integer>(orderAndTaskTempItemsMap.keySet());
                sortedOrders.sort(); // Sort the keys               
                for(Integer order :sortedOrders){
                    Task_Template_Item__c taskTempItemRecord = orderAndTaskTempItemsMap.get(order);
                    Task taskRec = new Task();
                    if(caseRecord.ContactId != null){
                        taskRec.WhoId = caseRecord.ContactId; 
                        taskRec.Person_Account_Id__c = perToAccIds.get(caseRecord.ContactId);
                    }
                    if(caseRecord.Household__c != null){
                        taskRec.FinServ__Household__c = caseRecord.Household__c;
                    }
                    if(caseRecord.Wizard_Financial_Account__c != null && mapOfFinAccount.containsKey(caseRecord.Wizard_Financial_Account__c)){
                        taskRec.DFPG_Financial_Account__c = mapOfFinAccount.get(caseRecord.Wizard_Financial_Account__c).Name;
                    }
                    taskRec.Status = 'Not Started';
                    taskRec.Needs_2nd_Ops_Review__c = taskTempItemRecord.Task_Template__r.Needs_2nd_Ops_Review__c;
                    taskRec.WhatId = caseRecord.Id;
                    taskRec.Task_Template_Item__c = taskTempItemRecord.Id;
                    taskRec.Task_Template__c = taskTempItemRecord.Task_Template__c;
                    if(String.isEmpty(taskTempItemRecord.Task_Template__r.Priority__c)){
                        taskRec.Priority = 'Normal';
                    } else {
                        taskRec.Priority = taskTempItemRecord.Task_Template__r.Priority__c;
                    }
                    taskRec.Subject = taskTempItemRecord.Task_Template__r.Name;
                    taskRec.Task_Instructions__c = taskTempItemRecord.Task_Template__r.Description__c;
                    taskRec.Financial_Advisor_Team__c = caseRecord.Financial_Advisor_Team__c;
                    if(taskTempItemRecord.Order__c == 1 || taskTempItemRecord.Independent__c || taskTempItemRecord.Order__c == null){
                        if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Immediate'){
                            taskRec.ActivityDate = ActivityDate;
                        } else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Case Creation' ||
                                  taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Previous Task Completion'){
                                      ActivityDate += (Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
                                      taskRec.ActivityDate = ActivityDate;
                                  } /*else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'After Referenced Field' && taskTempItemRecord.Task_Template__r.Referenced_Field__c == 'Review_Meeting_Scheduled_Date__c'){
ActivityDate = caseRecord.Review_Meeting_Scheduled_Date__c + (Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
taskRec.ActivityDate = ActivityDate;
} else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Before Referenced Field' && taskTempItemRecord.Task_Template__r.Referenced_Field__c == 'Review_Meeting_Scheduled_Date__c'){
ActivityDate = caseRecord.Review_Meeting_Scheduled_Date__c - (Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
taskRec.ActivityDate = ActivityDate;
}*/
                        if(taskTempItemRecord.Task_Template__r.Assigned_To__c == 'Queue'){
                            if(!String.isEmpty(taskTempItemRecord.Task_Template__r.Queue__c)){
                                if(!mapOfQueueIdByName.isEmpty() && mapOfQueueIdByName.containsKey(taskTempItemRecord.Task_Template__r.Queue__c)){
                                    taskRec.OwnerId =  mapOfQueueIdByName.get(taskTempItemRecord.Task_Template__r.Queue__c);
                                    if(taskTempItemRecord.Task_Template__r.Queue__c == 'Compliance'||taskTempItemRecord.Task_Template__r.Queue__c == 'Principal Review'){
                                        taskRec.RecordTypeId = approvalTaskRecordTypeId;  
                                    }
                                } else if(taskTempItemRecord.Task_Template__r.Queue__c == 'Back Office Operations'){
                                    taskRec.OwnerId =  mapOfQueueIdByName.get('Operations');
                                } else if(taskTempItemRecord.Task_Template__r.Queue__c == 'Financial Advisor Team Operations'){
                                    if(mapOfFatTeamAndUserForOperations.containsKey(caseRecord.Financial_Advisor_Team__c)){
                                        taskRec.OwnerId =  mapOfFatTeamAndUserForOperations.get(caseRecord.Financial_Advisor_Team__c);
                                    } else if(mapOfFatTeamAndUserForPrimary.containsKey(caseRecord.Financial_Advisor_Team__c)){
                                        taskRec.OwnerId =  mapOfFatTeamAndUserForPrimary.get(caseRecord.Financial_Advisor_Team__c);
                                    }
                                }
                            }
                        } else if(taskTempItemRecord.Task_Template__r.Assigned_To__c == 'FA Team Permission'){
                            if(!mapOfFATeam.isEmpty() && mapOfFATeam.containsKey(caseRecord.Financial_Advisor_Team__c)){
                                List<Financial_Advisor_Team_Member__c> lstFATM = mapOfFATeam.get(caseRecord.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
                                String fieldName = Null;
                                if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Trading'){
                                    fieldName = 'Trading__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Draft Paperwork'){
                                    fieldName = 'Draft_Paperwork__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Review Paperwork'){
                                    fieldName = 'Review_Paperwork__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Send Notifications'){
                                    fieldName = 'Send_Notifications__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'CSA'){
                                    fieldName = 'CSA__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Associate Advisor'){
                                    fieldName = 'Associate_Advisor__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Advisor'){
                                    fieldName = 'Primary_Financial_Advisor__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Operation'){
                                    fieldName = 'Operations__c';
                                }
                                if(fieldName != Null){
                                    for(Financial_Advisor_Team_Member__c fatm: lstFATM){
                                        if((Boolean)fatm.get(fieldName)){
                                            taskRec.OwnerId =  fatm.User__c;
                                            break;
                                        } else {
                                            taskRec.OwnerId = caseRecord.OwnerId;
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        if(!mapOfQueueIdByName.isEmpty() && mapOfQueueIdByName.containsKey('Unassigned')){
                            taskRec.OwnerId = mapOfQueueIdByName.get('Unassigned');
                        }
                        if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Immediate'){
                            taskRec.ActivityDate = ActivityDate;
                        } else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Case Creation' ||
                                  taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Previous Task Completion'){
                                      ActivityDate += (Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
                                      taskRec.ActivityDate = ActivityDate;
                                  } /*else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'After Referenced Field' && taskTempItemRecord.Task_Template__r.Referenced_Field__c == 'Review_Meeting_Scheduled_Date__c'){
ActivityDate = caseRecord.Review_Meeting_Scheduled_Date__c + (Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
taskRec.ActivityDate = ActivityDate;
} else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Before Referenced Field' && taskTempItemRecord.Task_Template__r.Referenced_Field__c == 'Review_Meeting_Scheduled_Date__c'){
ActivityDate = caseRecord.Review_Meeting_Scheduled_Date__c - (Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
taskRec.ActivityDate = ActivityDate;
}*/
                    }
                    lstTask.add(taskRec);
                }
            }
        }
        if(!lstTask.isEmpty()){
            insert lstTask;
        }
        //Set Current Task On Case
        if(!mapOfCaseIdToCaseTempId.isEmpty()){
            setCurrentTask(mapOfCaseIdToCaseTempId.keySet());
        }
    }
    
    private void createWizardTask(Map<Id, Case> newMap){
        
        Set<Id> setOfFATIds = new Set<Id>();
        Set<String> setOfQueueNames = new Set<String>();
        Set<Id> setAccounts = new Set<Id>();
        
        Set<Id> setOfFinAccountId = new Set<Id>();
        Map<Id, Id> mapOfCaseIdToCaseTempId = new  Map<Id, Id>();
        
        Map<Id, Financial_Advisor_Team__c> mapOfFATeam = new Map<Id, Financial_Advisor_Team__c>();
        Map<String, Id> mapOfQueueIdByName = new Map<String, Id>();
        Map<Id,Id> perToAccIds = new Map<Id,Id>();
        Map<Id,Financial_Account__c> mapOfFinAccount = new Map<Id,Financial_Account__c>();
        Map<Id, List<Task_Template_Item__c>> mapOfCaseTempIdToLstTemp = new Map<Id, List<Task_Template_Item__c>>();
        
        List<Task> lstTask = new List<Task>();
        List<Task_Template_Item__c> lstTaskTempItem = new List<Task_Template_Item__c>();
        List<Case_Template__c> lstCaseTemplate = new List<Case_Template__c>();
        List<Group> lstGroup = new List<Group>();
        List<Account> accts = new List<Account>();
        Map<Id,Id> mapOfFatTeamAndUserForPrimary = new Map<Id,Id>();
        Map<Id,Id> mapOfFatTeamAndUserForOperations = new Map<Id,Id>();
        
        
        for(Case caseRecord : newMap.Values()){
            if(!String.isEmpty(caseRecord.ContactId)){
                setAccounts.add(caseRecord.ContactId);
            }
            if(!String.isEmpty(caseRecord.Financial_Advisor_Team__c)){
                setOfFATIds.add(caseRecord.Financial_Advisor_Team__c);
            }
            if(!String.isEmpty(caseRecord.Wizard_Financial_Account__c)){
                setOfFinAccountId.add(caseRecord.Wizard_Financial_Account__c);
            }
            if(!String.isEmpty(caseRecord.Case_Template__c)){
                mapOfCaseIdToCaseTempId.put(caseRecord.Id,caseRecord.Case_Template__c);
            }
            
        }
        
        if(!setOfFATIds.isEmpty()){
            mapOfFATeam = new Map<Id, Financial_Advisor_Team__c>([SELECT Id, Primary_Financial_Advisor__c, (SELECT ID, Associate_Advisor__c, CSA__c, Send_Notifications__c, 
                                                                                                            Review_Paperwork__c, Draft_Paperwork__c, Trading__c, User__c, Primary__c,Operations__c  
                                                                                                            FROM Financial_Advisor_Team_Members__r)
                                                                  FROM Financial_Advisor_Team__c WHERE Id IN :setOfFATIds ]);
        }
        
        if(!setOfFinAccountId.isEmpty()){
            mapOfFinAccount = new Map<Id, Financial_Account__c>([SELECT Id, Name
                                                                         FROM Financial_Account__c WHERE Id IN :setOfFinAccountId ]);
        }
        //Get User from FAT Team Member thoese have Primary and Operations permission true
        
        for(Financial_Advisor_Team__c fat : mapOfFATeam.values()){
            for(Financial_Advisor_Team_Member__c fatm : fat.Financial_Advisor_Team_Members__r){
                if(fatm.Operations__c){
                    mapOfFatTeamAndUserForOperations.put(fat.Id,fatm.User__c);
                }
                if(fatm.Primary__c){
                    mapOfFatTeamAndUserForPrimary.put(fat.Id,fatm.User__c);
                }
            }
        }
        if(!setAccounts.isEmpty()){
            accts = [SELECT Id, PersonContactId FROM Account WHERE PersonContactId in: setAccounts];
        }
        for(Account a : accts){
            perToAccIds.put(a.PersonContactId,a.Id);
        }         
        
        if(!mapOfCaseIdToCaseTempId.isEmpty()){
            lstTaskTempItem = [SELECT Id, Task_Template__r.Priority__c, Case_Template__c,
                               Task_Template__r.Assigned_To__c,
                               Task_Template__r.FA_Team_Permission__c, Order__c,
                               Task_Template__r.Queue__c, Task_Template__r.Due_Date__c,
                               Task_Template__r.Number_of_Days__c,
                               Task_Template__r.Description__c, Independent__C, Task_Template__r.Name
                               FROM Task_Template_Item__c 
                               WHERE Case_Template__c IN : mapOfCaseIdToCaseTempId.values()];
        } 
        
        setOfQueueNames.add('Unassigned'); 
        setOfQueueNames.add('Operations'); 
        for(Task_Template_Item__c taskTempItem : lstTaskTempItem){
            if(!String.isEmpty(taskTempItem.Task_Template__r.Queue__c)){
                setOfQueueNames.add(taskTempItem.Task_Template__r.Queue__c);
            }
            if(!mapOfCaseTempIdToLstTemp.containsKey(taskTempItem.Case_Template__c)){
                mapOfCaseTempIdToLstTemp.put(taskTempItem.Case_Template__c, new List<Task_Template_Item__c>());
            }
            mapOfCaseTempIdToLstTemp.get(taskTempItem.Case_Template__c).add(taskTempItem);
        }
        
        lstGroup = [Select Id, Name from Group where type='Queue' and Name= :setOfQueueNames];
        for(Group groupRecord : lstGroup){
            mapOfQueueIdByName.put(groupRecord.Name, groupRecord.Id);
        }
        Id approvalTaskRecordTypeId = Schema.sObjectType.Task.getRecordTypeInfosByName().get('Approval Task').getRecordTypeId(); 
        for(Id caseId : mapOfCaseIdToCaseTempId.keySet()){
            Case caseRecord = newMap.get(caseId);
            if(!mapOfCaseTempIdToLstTemp.isEmpty() && mapOfCaseTempIdToLstTemp.containsKey(mapOfCaseIdToCaseTempId.get(caseId))){
                List<Task_Template_Item__c> lstTaskTempItemRecord = mapOfCaseTempIdToLstTemp.get(mapOfCaseIdToCaseTempId.get(caseId));
                for(Task_Template_Item__c taskTempItemRecord : lstTaskTempItemRecord){
                    Task taskRec = new Task();
                    if(caseRecord.ContactId != null){
                        taskRec.WhoId = caseRecord.ContactId; 
                        taskRec.Person_Account_Id__c = perToAccIds.get(caseRecord.ContactId);
                    }
                    if(caseRecord.Household__c != null){
                        taskRec.FinServ__Household__c = caseRecord.Household__c;
                    }
                    
                    
                    if(caseRecord.Wizard_Financial_Account__c != null && mapOfFinAccount.containsKey(caseRecord.Wizard_Financial_Account__c)){
                        taskRec.Financial_Account__c = mapOfFinAccount.get(caseRecord.Wizard_Financial_Account__c).Name;
                    }
                    taskRec.Status = 'Not Started';
                    taskRec.WhatId = caseRecord.Id;
                    taskRec.Task_Template_Item__c = taskTempItemRecord.Id;
                    taskRec.Task_Template__c = taskTempItemRecord.Task_Template__c;
                    if(String.isEmpty(taskTempItemRecord.Task_Template__r.Priority__c)){
                        taskRec.Priority = 'Normal';
                    } else {
                        taskRec.Priority = taskTempItemRecord.Task_Template__r.Priority__c;
                    }
                    taskRec.Subject = taskTempItemRecord.Task_Template__r.Name;
                    taskRec.Task_Instructions__c = taskTempItemRecord.Task_Template__r.Description__c;
                    taskRec.Financial_Advisor_Team__c = caseRecord.Financial_Advisor_Team__c;
                    if(taskTempItemRecord.Order__c == 1 || taskTempItemRecord.Independent__c || taskTempItemRecord.Order__c == null){
                        if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Immediate'){
                            taskRec.ActivityDate = System.Today();
                        } else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Case Creation' ||
                                  taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Previous Task Completion'){
                                      taskRec.ActivityDate = System.Today()+(Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
                                  }
                        if(taskTempItemRecord.Task_Template__r.Assigned_To__c == 'Queue'){
                            if(!String.isEmpty(taskTempItemRecord.Task_Template__r.Queue__c)){
                                if(!mapOfQueueIdByName.isEmpty() && mapOfQueueIdByName.containsKey(taskTempItemRecord.Task_Template__r.Queue__c)){
                                    taskRec.OwnerId =  mapOfQueueIdByName.get(taskTempItemRecord.Task_Template__r.Queue__c);
                                    if(taskTempItemRecord.Task_Template__r.Queue__c == 'Compliance'||taskTempItemRecord.Task_Template__r.Queue__c == 'Principal Review'){
                                        taskRec.RecordTypeId = approvalTaskRecordTypeId;  
                                    }
                                } else if(taskTempItemRecord.Task_Template__r.Queue__c == 'Back Office Operations'){
                                    taskRec.OwnerId =  mapOfQueueIdByName.get('Operations');
                                } else if(taskTempItemRecord.Task_Template__r.Queue__c == 'Financial Advisor Team Operations'){
                                    if(mapOfFatTeamAndUserForOperations.containsKey(caseRecord.Financial_Advisor_Team__c)){
                                        taskRec.OwnerId =  mapOfFatTeamAndUserForOperations.get(caseRecord.Financial_Advisor_Team__c);
                                    } else if(mapOfFatTeamAndUserForPrimary.containsKey(caseRecord.Financial_Advisor_Team__c)){
                                        taskRec.OwnerId =  mapOfFatTeamAndUserForPrimary.get(caseRecord.Financial_Advisor_Team__c);
                                    }
                                }
                            }
                        } else if(taskTempItemRecord.Task_Template__r.Assigned_To__c == 'FA Team Permission'){
                            if(!mapOfFATeam.isEmpty() && mapOfFATeam.containsKey(caseRecord.Financial_Advisor_Team__c)){
                                List<Financial_Advisor_Team_Member__c> lstFATM = mapOfFATeam.get(caseRecord.Financial_Advisor_Team__c).Financial_Advisor_Team_Members__r;
                                String fieldName = Null;
                                if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Trading'){
                                    fieldName = 'Trading__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Draft Paperwork'){
                                    fieldName = 'Draft_Paperwork__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Review Paperwork'){
                                    fieldName = 'Review_Paperwork__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Send Notifications'){
                                    fieldName = 'Send_Notifications__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'CSA'){
                                    fieldName = 'CSA__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Associate Advisor'){
                                    fieldName = 'Associate_Advisor__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Advisor'){
                                    fieldName = 'Primary__c';
                                } else if(taskTempItemRecord.Task_Template__r.FA_Team_Permission__c == 'Operation'){
                                    fieldName = 'Operations__c';
                                }
                                if(fieldName != Null){
                                    for(Financial_Advisor_Team_Member__c fatm: lstFATM){
                                        if((Boolean)fatm.get(fieldName)){
                                            taskRec.OwnerId =  fatm.User__c;
                                            break;
                                        } else {
                                            taskRec.OwnerId = caseRecord.OwnerId;
                                        }
                                    }
                                }
                            }
                        } 
                    } else {
                        if(!mapOfQueueIdByName.isEmpty() && mapOfQueueIdByName.containsKey('Unassigned')){
                            taskRec.OwnerId = mapOfQueueIdByName.get('Unassigned');
                        }
                        if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Immediate'){
                            taskRec.ActivityDate = System.Today();
                        } else if(taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Case Creation' ||
                                  taskTempItemRecord.Task_Template__r.Due_Date__c == 'Days from Previous Task Completion'){
                                      taskRec.ActivityDate = System.Today()+(Integer)taskTempItemRecord.Task_Template__r.Number_of_Days__c;
                                  } 
                    }
                    lstTask.add(taskRec);
                }
            }
        }
        if(!lstTask.isEmpty()){
            insert lstTask;
        }
        //Set Current Task On Case
        if(!mapOfCaseIdToCaseTempId.isEmpty()){
            setCurrentTask(mapOfCaseIdToCaseTempId.keySet());
        }    
    }
    
    private void createCDLforCase(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        List<ContentDocumentLink> cdlsToInsert = new List<ContentDocumentLink>();
        Map<String, Id> flowInterviewIdsToCaseIds = new Map<String,Id>();
        Set<String> caseTypes = new Set<String>();
        List<Case_Request_Type__mdt> caseTypesMdt = [SELECT Label FROM Case_Request_Type__mdt];
        for(Case_Request_Type__mdt c : caseTypesMdt){
            caseTypes.add(c.Label);
        }
        for(Case newCase : newMap.values()){
            if(caseTypes.contains(newCase.Type) && newCase.Flow_Interview_Id__c != null){
                flowInterviewIdsToCaseIds.put(newCase.Flow_Interview_Id__c, newCase.Id);
            }
        }
        
        
        if(!flowInterviewIdsToCaseIds.isEmpty()){
            for(String flowInterviewId : flowInterviewIdsToCaseIds.keyset()){
                List<ContentVersion> caseCVrecord = [SELECT Id, ContentDocumentId, Flow_Interview_Id__c FROM ContentVersion
                                                     WHERE Flow_Interview_Id__c =: flowInterviewId];
                for(ContentVersion c : caseCVrecord){
                    ContentDocumentLink caseCDL = new ContentDocumentLink();
                    caseCDL.LinkedEntityId = flowInterviewIdsToCaseIds.get(flowInterviewId);
                    caseCDL.ShareType = 'V';
                    caseCDL.ContentDocumentId = c.ContentDocumentId;
                    cdlsToInsert.add(caseCDL); 
                }
                
            }
            if(!cdlsToInsert.isEmpty()){
                insert cdlsToInsert;
            }
        }
        
    }
    
    private void createTask(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        Task t;
        List<Task> taskToBeInserted = new List<Task>();
        Id recTypeId = Schema.sObjectType.Case.getRecordTypeInfosByName().get('Advertising Review').getRecordTypeId();
        set<Id> adItemsIds = new set<Id>();
        for(Case ca : newMap.values()){
            if(ca.Advertising_Item__c != null){
                adItemsIds.add(ca.Advertising_Item__c);
            }
        }
        Map<Id, Advertising_Item__c> adItemMap = new Map<Id, Advertising_Item__c>([SELECT Id, OwnerId, Date_of_Intended_First_Use__c
                                                                                   FROM Advertising_Item__c WHERE Id IN:adItemsIds]);
        for(Case c : newMap.values()){
            if(c.RecordTypeId == recTypeId && c.Status == 'Conditionally Approved' && oldMap.get(c.Id).Status != 'Conditionally Approved'){
                c.Status = 'Waiting for Additional Documentation';
                c.isConditionallyApproved__c = true;
                Id recTypeTaskId = Schema.SObjectType.Task.getRecordTypeInfosByName().get('Advisor Task').getRecordTypeId();
                if(c.Advertising_Type__c == 'Radio/TV Ad'){
                    t = new Task();
                    t.Description = 'Upload final Radio/TV Ad Recording';
                    t.Subject = 'Upload final Radio/TV Ad Recording';
                    t.Priority = 'Normal';
                    t.OwnerId = adItemMap.get(c.Advertising_Item__c).OwnerId;
                    t.WhatId = c.Id;
                    t.Status = 'Not Started';
                    t.ActivityDate = adItemMap.get(c.Advertising_Item__c).Date_of_Intended_First_Use__c;
                    t.Financial_Advisor_Team__c = c.Financial_Advisor_Team__c;
                    t.RecordTypeId = recTypeTaskId;
                    t.Task_Type__c = 'Advertising Final Document';
                    taskToBeInserted.add(t);
                } else if(c.Advertising_Type__c == 'Public Appearance'){
                    t = new Task();
                    t.Description = 'Upload Talking Points';
                    t.Subject = 'Upload Talking Points';
                    t.Priority = 'Normal';
                    t.OwnerId = adItemMap.get(c.Advertising_Item__c).OwnerId;
                    t.WhatId = c.Id;
                    t.Status = 'Not Started';
                    t.ActivityDate = adItemMap.get(c.Advertising_Item__c).Date_of_Intended_First_Use__c;
                    t.Financial_Advisor_Team__c = c.Financial_Advisor_Team__c;
                    t.RecordTypeId = recTypeTaskId;
                    t.Task_Type__c = 'Advertising Final Document';
                    taskToBeInserted.add(t);
                }
            } 
        }
        if(!taskToBeInserted.isEmpty()){
            insert taskToBeInserted;
        }
    }
    
    /*private void setOwnerAndStatusOnCase(List<Case> newList,  Map<Id, Case> oldMap){

Id queuePRId = [SELECT Id, Type FROM Group WHERE Type = 'Queue' AND Name = 'Principal Review'].Id;
for(Case record : newList) {
if(record.Status == 'Ready for Principal Review' && oldMap.get(record.Id).Status != 'Ready for Principal Review'){
record.Status = 'Principal Review';
record.OwnerId = queuePRId;
}
}
}*/
    
    private void cancelMoveMoney(Map<Id,Case> newMap, Map<Id,Case> oldMap){
        Set<Id> instructionIds = new Set<Id>();
        List<Standing_Letter_of_Authorization__c> sloas = new List<Standing_Letter_of_Authorization__c>();
        Date today = Date.today();
        for(Case newCase : newMap.values()){
            Case oldCase = oldMap.get(newCase.Id);
            if(newCase.Status == 'Closed' && oldCase.Status != 'Closed' && newCase.Type == 'Cancel Move Money Recurring'){
                instructionIds.add(newCase.Instruction__c);
            }
        }
        if(!instructionIds.isEmpty()){
            List<Instruction__c> instrs = [SELECT Id, Active__c, End_Date__c, Standing_Letter_of_Authorization__c, Standing_Letter_of_Authorization__r.Active__c FROM Instruction__c WHERE Id in: instructionIds];
            for(Instruction__c i : instrs){
                //i.Active__c = false;
                i.End_Date__c = today;
                Standing_Letter_of_Authorization__c sloa = new Standing_Letter_of_Authorization__c(Id = i.Standing_Letter_of_Authorization__c, Active__c = false);
                sloas.add(sloa);
            }
            update instrs;
            update sloas;
        }
    }
    
    private void recalcTaskRecord(Map<Id, Case> newMap){
        Map<Id,Case> casesAdvisorToRecalc = new Map<Id,Case>();
        Map<Id,Case> casesWizardToRecalc = new Map<Id,Case>();
        for(Case c : newMap.values()){
            if(c.Recalculate_Case_Template__c){
                //if(c.Origin == 'Wizard'){
                    casesWizardToRecalc.put(c.Id, c);
                /*} else {
                    casesAdvisorToRecalc.put(c.Id, c);
                }*/
                
                c.Recalculate_Case_Template__c = false;
                c.DoNotCalc__c = false;
            }
        }
        /*if(!casesAdvisorToRecalc.isEmpty()){
            //casesAdvisorToRecalc = setCaseTemplateForAdvisorRequest(casesAdvisorToRecalc.values());
            createAdvisorRequestTask(casesAdvisorToRecalc);
        }*/
        if(!casesWizardToRecalc.isEmpty()){
            casesWizardToRecalc = setCaseTemplateForWizard(casesWizardToRecalc.values());
            createWizardTask(casesWizardToRecalc);
        }
    }
    
    private void updateRelatedAccount(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        Map<Id, Account> updateAccounts = new Map<Id, Account>();
        for(Case c : newMap.values()){
            if(c.Type == 'Client Terminated Services' && c.isClosed && c.isClosed != oldMap.get(c.Id).isClosed && !String.isEmpty(c.Household__c)){
                Account account;
                if(updateAccounts.containsKey(c.Household__c)){
                    account = updateAccounts.get(c.Household__c);
                } else {
                    Account = new Account(Id = c.Household__c);
                }
                account.Account_Funding_Client__c = false;
                account.Account_Funding_Next_Service_Date__c = null;
                account.Donation_in_Kind_Client__c = false; 
                account.Donation_in_Kind_Next_Service_Date__c = null; 
                account.QCD_Client__c = false;
                account.QCD_Next_Service_Date__c = null;
                account.Roth_Conversion_Client__c = false;
                account.Roth_Conversion_Next_Service_Date__c = null;
                updateAccounts.put(account.Id, account);
            }
            
            if(c.Type == 'AML Document Approval' && c.Status != oldMap.get(c.Id).Status && c.Status == 'Closed' && !String.isEmpty(c.AccountId)){
                Account account;
                if(updateAccounts.containsKey(c.AccountId)){
                    account = updateAccounts.get(c.AccountId);
                }else{
                    account = new Account(Id = c.AccountId);
                }
                account.AML_Valid__c = true;
                updateAccounts.put(account.Id, account);
            }
        }
        
        if(!updateAccounts.isEmpty()){
            update updateAccounts.values();
        }
    }
    
    public void setApprovedStatusOnAdItem(Map<Id, Case> newMap, Map<Id, Case> oldMap){
        List<Advertising_Item__c> adItemsToUpdate = new List<Advertising_Item__c>();
        for(Case newCase : newMap.values()){
            if(newCase.Advertising_Item__c != null && newCase.Status == 'Approved' && oldMap.get(newCase.Id).Status != 'Approved'){
                Advertising_Item__c adItem = new Advertising_Item__c();
                adItem.Id = newCase.Advertising_Item__c;
                adItem.Status__c = 'Approved';
                adItemsToUpdate.add(adItem);
            }
        }
        
        if(!adItemsToUpdate.isEmpty()){
            update adItemsToUpdate;
        }
    }
    
    private void setDateOfDeathOnAccount(List<Case> newList, Map<Id, Case> oldMap){
        List<Account> accountsToUpdate = new List<Account>();
        Map<Id, Date> mapOfContactToDOD = new Map<Id, Date>();
        for(Case cs : newList){
            if(cs.Type == 'Client Passed Away' && cs.isClosed && !oldMap.get(cs.Id).isClosed){
                if(!String.isEmpty(cs.ContactId)){
                    mapOfContactToDOD.put(cs.ContactId, cs.Date_of_Death__c);
                }
            }
        }
        if(!mapOfContactToDOD.isEmpty()){
            Id personRecTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Person Account').getRecordTypeId();
            List<Contact> contacts = [SELECT Id, AccountId, Account.LastName From Contact WHERE Id IN :mapOfContactToDOD.keySet()
                                      AND AccountId != null AND Account.RecordTypeId = :personRecTypeId];
            for(Contact contact : contacts){
                String lastName = contact.Account.LastName + ' (DECEASED)';
                accountsToUpdate.add(new Account(Id = contact.AccountId, 
                                                 Date_of_Death__c = mapOfContactToDOD.get(contact.Id), LastName = lastName));                
                
            }
            if(!accountsToUpdate.isEmpty()){
                update accountsToUpdate;
            }
        }
    }
    
    //HELPER METHODS
    private Id getCaseTempId (List<Case_Template__c> lstCaseTemplate, Case caseRecord, Integer indexNumber){
        System.debug('lstCaseTemplate line 1331: ' + lstCaseTemplate);
        System.debug('lstOfCaseTemplateField: ' + lstOfCaseTemplateField);
        System.debug('mapCaseTempFldToCaseFld: ' + mapCaseTempFldToCaseFld);
        System.debug('indexNumber: ' + indexNumber);
        System.debug('caseRecord: ' + caseRecord);
        
        if(!lstOfCaseTemplateField.isEmpty() && lstCaseTemplate.size() > 0 && indexNumber < lstOfCaseTemplateField.size() 
           && !mapCaseTempFldToCaseFld.isEmpty() && mapCaseTempFldToCaseFld.containsKey(lstOfCaseTemplateField[indexNumber])){
               List<Case_Template__c> lstCaseTemptValue = new List<Case_Template__c>();
               for(Case_Template__c caseTemplate : lstCaseTemplate){
                   System.debug('caseTemplate Id : ' + caseTemplate.Id);
                   System.debug('caseTemplate: ' + caseTemplate);
                   System.debug('lstOfCaseTemplateField[indexNumber]: ' + lstOfCaseTemplateField[indexNumber]);
                   //Commented out by Cale 8/11/2026 - caseTemplate.get('Type__c') threw System.SObjectException when
                   //getCaseTempId was called from setCaseTemplateForAdvisorRequest, whose SOQL does not select Type__c.
                   //This failed the Case insert in the BeforeInsert trigger for every Advisor Request submission.
                   //System.debug('caseTemplate.get(Type__c): ' + caseTemplate.get('Type__c'));
                   //System.debug(' caseTemplate.get(lstOfCaseTemplateField[indexNumber]) ' + caseTemplate.get(lstOfCaseTemplateField[indexNumber]));
                   System.debug(' String.valueOf(caseRecord.get(mapCaseTempFldToCaseFld.get(lstOfCaseTemplateField[indexNumber]))): ' + String.valueOf(caseRecord.get(mapCaseTempFldToCaseFld.get(lstOfCaseTemplateField[indexNumber]))));
                   if(caseFieldAndTypeMap.get(lstOfCaseTemplateField[indexNumber]) == String.valueOf(Schema.DisplayType.MultiPicklist)){
                       if(isMultiPicklistMatch(caseRecord.get(mapCaseTempFldToCaseFld.get(lstOfCaseTemplateField[indexNumber])),caseTemplate.get(lstOfCaseTemplateField[indexNumber]))){
                           system.debug('lstCaseTemptValue isMultiPicklistMatch'+lstCaseTemptValue);
                           lstCaseTemptValue.add(caseTemplate);
                       } 
                   }
                   String caseFieldValue = String.valueOf(caseRecord.get(mapCaseTempFldToCaseFld.get(lstOfCaseTemplateField[indexNumber])));
                   if(lstOfCaseTemplateField[indexNumber] == 'Live_SLOA_on_File__c'){
                       caseFieldValue = caseFieldValue == 'true' ? 'false' : 'true';
                   }
                   if(caseTemplate.get(lstOfCaseTemplateField[indexNumber]) == caseFieldValue
                      || caseTemplate.get(lstOfCaseTemplateField[indexNumber]) == caseTemplateFieldDefaultValue
                      || lstOfCaseTemplateField[indexNumber] == 'Management_Style__c'){
                          if(lstOfCaseTemplateField[indexNumber] == 'Management_Style__c'){
                              String templateValue = String.valueOf(caseTemplate.get('Management_Style__c'));
                              if(templateValue == caseTemplateFieldDefaultValue){
                                  lstCaseTemptValue.add(caseTemplate);
                              } else {
                                  String caseValue = String.valueOf(
                                      caseRecord.get(mapCaseTempFldToCaseFld.get(lstOfCaseTemplateField[indexNumber])));
                                  if(caseValue != null && templateValue != null){
                                      Set<String> templateValues = new Set<String>(templateValue.split(';'));
                                      Set<String> caseValues = new Set<String>(caseValue.split(';'));
                                      Boolean hasMatch = false;
                                      for(String cv : caseValues){
                                          if(templateValues.contains(cv)){
                                              hasMatch = true;
                                              break;
                                          }
                                      }
                                      if(hasMatch){
                                          lstCaseTemptValue.add(caseTemplate);
                                      }
                                  }
                              }
                          } else {
                              lstCaseTemptValue.add(caseTemplate);
                          }
                      }
               }
               if(lstCaseTemptValue.size() > 0 ){
                   caseTemplateMatchFields = caseTemplateMatchFields +  lstOfCaseTemplateField[indexNumber]+';';
                   return getCaseTempId( lstCaseTemptValue, caseRecord, ++indexNumber);
               }
           }else if(!lstOfCaseTemplateField.isEmpty() && indexNumber == lstOfCaseTemplateField.size() ){
               return returnCaseTempId(lstCaseTemplate, caseRecord);
           }
        return null;
    }
    
    private Id returnCaseTempId (List<Case_Template__c> lstCaseTemplate, Case caseRecord){
        if(lstCaseTemplate.size() == 1){
            return lstCaseTemplate[0].Id;
        }
        Integer matchCount = 0;
        Id caseTempId = lstCaseTemplate[0].Id;
        for(Case_Template__c caseTemp : lstCaseTemplate){
            Integer count = 0;
            for(String caseTemFld : mapCaseTempFldToCaseFld.keySet()){
                String caseVal = String.valueOf(caseRecord.get(mapCaseTempFldToCaseFld.get(caseTemFld)));
                if(caseTemFld == 'Live_SLOA_on_File__c'){
                    caseVal = caseVal == 'true' ? 'false' : 'true';
                }
                if(caseTemp.get(caseTemFld) == caseVal){
                    count++;
                }
            }
            if(count > matchCount){
                matchCount = count;
                caseTempId = caseTemp.Id;
            }
        }
        return caseTempId;
    }
    
    //FUTURE METHODS
    @future
    public static void setCurrentTask(set<Id> caseIds){
        List<Task> lstTask = [SELECT Id,WhatId,Owner.Name,Order__c FROM Task WHERE Order__c IN(1,2) AND WhatId IN : caseIds];
        
        Map<Id,Case> caseMap = new MAp<Id,Case>();
        for(Task tsk : lstTask){
            Case ca = new case(id = tsk.WhatId, Sub_Status__c ='New');
            if(caseMap.containsKey(tsk.WhatId)){
                ca =  caseMap.get(tsk.WhatId);
            }
            if(tsk.Order__c == 1){
                ca.Current_Task_Id__c = tsk.Id;
                ca.Owner_Group__c = tsk.Owner.Name;
            }else if(tsk.Order__c == 2){
                ca.Next_Task__c = tsk.Id;
            }
            caseMap.put(tsk.WhatId,ca);
        }
        
        if(!caseMap.isEmpty()){
            update caseMap.values();
        }
    }
    public static void populateJointOwner(Map<Id, Case> newMap, Map<Id, Case> oldMap) {
        Set<Id> finAccIds = new Set<Id>();
        List<Case> casesToUpdate = new List<Case>();
        for(Case c : newMap.values()) {
            if(c.Wizard_Financial_Account__c != null) {
                if(oldMap == null || 
                   (oldMap != null && c.Wizard_Financial_Account__c != oldMap.get(c.Id).Wizard_Financial_Account__c)) {
                       finAccIds.add(c.Wizard_Financial_Account__c);
                   }
            }
        }
        if(finAccIds.isEmpty()) {
            return;
        }
        
        // Query financial accounts
        Map<Id, Financial_Account__c> finAccMap = new Map<Id, Financial_Account__c>(
            [SELECT Id, Joint_Owner__c 
             FROM Financial_Account__c 
             WHERE Id IN :finAccIds
             AND Joint_Owner__c != NULL]
        );
        
        for(Case c : newMap.values()) {
            if(finAccMap.containsKey(c.FinServ__FinancialAccount__c)) {
                Id jointOwner = finAccMap.get(c.Wizard_Financial_Account__c).Joint_Owner__c;
                if(c.Joint_Account_Owner__c != jointOwner) {
                    casesToUpdate.add(new Case(
                        Id = c.Id,
                        Joint_Account_Owner__c = jointOwner
                    ));
                }
            }
        }
        
        if(!casesToUpdate.isEmpty()) {
            update casesToUpdate;
        }
    }
    private void setCaseTemplateFieldTypes() {
        Map<String, Schema.SObjectField> fieldMap =
            Case_Template__c.SObjectType.getDescribe().fields.getMap();
        
        for (String fieldName : lstOfCaseTemplateField) {
            if (fieldMap.containsKey(fieldName)) {
                caseFieldAndTypeMap.put(
                    fieldName,
                    String.valueOf(fieldMap.get(fieldName).getDescribe().getType())
                );
            }
        }
    }
    
    private Boolean isMultiPicklistMatch(Object caseTemplateValue,Object caseFieldValue) {
        if (caseTemplateValue == null && caseFieldValue == null) {
            return true;
        }
        
        if (caseTemplateValue == null || caseFieldValue == null) {
            return false;
        }
        
        List<String> templateValues = getSortedMultiPicklistValues(caseTemplateValue);
        List<String> caseValues = getSortedMultiPicklistValues(caseFieldValue);
        
        return templateValues == caseValues;
    }
    
    
    private List<String> getSortedMultiPicklistValues(Object fieldValue) {
        List<String> values = new List<String>();
        
        for (String value : String.valueOf(fieldValue).split(';')) {
            if (String.isNotBlank(value)) {
                values.add(value.trim());
            }
        }
        values.sort();
        return values;
    }
}