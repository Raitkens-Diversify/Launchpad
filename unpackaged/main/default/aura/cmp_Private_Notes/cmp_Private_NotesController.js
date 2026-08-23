({
	doInit : function(component, event, helper) {  
        
        component.set("v.isWorking", true);
        var userId = $A.get("$SObjectType.CurrentUser.Id");
        console.log(userId);
        component.set("v.currentUserId", userId);
        var today = $A.localizationService.formatDate(new Date(), "M/D/YYYY");
        component.set('v.today',today);
        
        var beforeDate = new Date();
        beforeDate.setDate(beforeDate.getDate() - 30);
        var aMonthBeforeDate = $A.localizationService.formatDate(beforeDate,  "M/D/YYYY");
        component.set('v.aMonthBeforeDate',aMonthBeforeDate);
        
        var dateToDo = new Date().toISOString();
        var yesterday = new Date(dateToDo);
        yesterday.setDate(yesterday.getDate() - 1);
        component.set('v.yesterday',yesterday.toISOString());
        
        helper.getNotesTemplates(component, event, helper);
        
        var action1  =  component.get("c.fetchNotesRecords");
        action1.setParams({ parentObjectId : component.get("v.recordId"), sObjectName : component.get("v.sObjectName")});
        action1.setCallback(this, function(actionResult) {
            var wrapper = actionResult.getReturnValue();
            console.log('Wrapper ::>> '+JSON.stringify(wrapper));
            //component.set("v.section",  wrapper.notesList[0].Name);
            component.set("v.allNotesList", wrapper.notesList);
            console.log('wrapper.notesList: ' + wrapper.notesList);
            component.set("v.filteredNoteList", wrapper.notesList);
            component.set("v.notesList", wrapper.notesList);
            component.set("v.parentLookupFieldName", wrapper.fieldName);
            component.set("v.toggleAllNoteList", wrapper.notesToggleList);
            component.set("v.toggleNoteList", wrapper.notesToggleList);
           
            
            setTimeout($A.getCallback(
                () => component.set("v.section",  (wrapper.notesList.length > 0 ? wrapper.notesList[0].Name : '')),
                component.set("v.toggleSection",  (wrapper.notesToggleList.length >0 ? wrapper.notesToggleList[0].Name : ''))
            ));
             component.set("v.isWorking", false);
        });  
        $A.enqueueAction(action1);
    },
    
    /*closeModel: function(component, event, helper) {
        component.set("v.isModalOpen", false);
    },
    
    editNote: function(component, event, helper) {
        helper.editNote(component,event, helper);
    },*/
    
    handleSubmit  : function(component, event, helper) {
        helper.handleSubmit(component, event, helper);
    },
    
    searchNotes : function(component, event, helper) {
       helper.searchingNotesRecords(component, event, helper);
    },
    
    clearFilter : function(component, event, helper) {
        component.set("v.searchString", '');
        helper.searchingNotesRecords(component, event, helper);
    },
    
    searchKey : function(component, event, helper) {
        var searchTextvalue = event.target.value;
        component.set("v.searchString", searchTextvalue);
		helper.searchingNotesRecords(component, event, helper);
	
    },
    
    typeSearchKey : function(component, event, helper) {
        console.log(component.get("v.typeaheadMultiselectValue"));
		helper.searchingNotesRecords(component, event, helper);
    },
    
    searchByDate  : function(component, event, helper) {
        helper.searchingNotesRecords(component, event, helper);
    },
    
    handlesuccess : function(component, event, helper) {
        component.find('field').forEach(function(f) {
            f.reset();
        });
        $A.get('e.force:refreshView').fire();
    },
    
    handleSave : function(component, event, helper) {
        helper.submitData(component, event, helper); 
    },
    
    handleDataChange : function(component, event, helper) {
        helper.dataChange(component, event, helper); 
    },
    
    changeNotesTemplate : function(component, event, helper){
        helper.changeNoteTemplate(component, event, helper);
    },

    getToggleButtonValue:function(component, event, helper){
        var checkCmp = component.find("tglbtn").get("v.checked");
        component.set("v.chkBoxValue",checkCmp);
    },
    
})