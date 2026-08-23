({
	/*editNote: function(component, event, helper) {
        component.set("v.isModalOpen", true);
        var idx = event.target.id;
        component.set("v.editRecordId", idx);
    },*/
    
    handleSubmit  : function(component, event, helper) {
        event.preventDefault();  
        var fields = event.getParam('fields');
        var fieldname = component.get("v.parentLookupFieldName");
        if(fieldname == 'Client__c'){
            fields.Client__c = component.get("v.recordId");
        }else if(fieldname == 'Household__c'){
            fields.Household__c = component.get("v.recordId");
        }else if(fieldname == 'Financial_Account__c'){
            fields.Financial_Account__c = component.get("v.recordId");
        }
        
        if(component.get("v.isModalOpen")){
            component.find('myRecordForm').submit(fields);
        	component.set("v.isModalOpen", false);
        }else{
            component.find('myNewRecordForm').submit(fields);
        }
    },
    
    searchingNotesRecords : function(component, event, helper) {
        var action1  =  component.get("c.searchNotesRecords");
        action1.setParams({ parentObjectId : component.get("v.recordId"),
                           searchStr : component.get("v.searchString"), 
                           typeStr : component.get("v.typeaheadMultiselectValue"),
                           startDate : component.get("v.startDate"), 
                           endDate : component.get("v.endDate"), 
                           toggleNoteList : component.get("v.toggleAllNoteList")});
        action1.setCallback(this, function(actionResult) {
            var wrapper = actionResult.getReturnValue();
            component.set("v.filteredNoteList", wrapper.notesList);
            component.set("v.toggleNoteList", wrapper.notesToggleList);
        });  
        
        $A.enqueueAction(action1);
    },
    submitData : function(component, event, helper) {
        var unSavedChange = component.find('unsaved');
        unSavedChange.setUnsavedChanges(false);
    },
    
    dataChange : function(component, event, helper) {
        var unSavedChange = component.find('unsaved');
        if(event.getParam("value") != '' && event.getParam("value") != null ){
            unSavedChange.setUnsavedChanges(true, { label: 'New Notes' });
        } 
    },
    
    getNotesTemplates : function(component, event, helper) {
        console.log('In Get Notes');
        var act = component.get("c.getNotesTemplates");
        act.setCallback(this, function(response){
            var state = response.getState();
            console.log('Returned FRom apex::?>>'+JSON.stringify(response.getReturnValue()));
            if(state === 'SUCCESS'){
                component.set('v.notesTemplatesMap',response.getReturnValue());
                var templateMap = response.getReturnValue();
                var templateKeys = [];
                for(let key in templateMap){
                   templateKeys.push(key); 
                }
                component.set("v.notesTemplatesList",templateKeys);
                /*var custs = [];
                
                for(var key in conts){
                    custs.push({value:conts[key], key:key}); //Here we are creating the list to show on UI.
                }
                component.set("v.notesTemplatesList",custs);*/
            }
            else if (state === "INCOMPLETE") {
                console.log('State Incomplete');
            }
            else if (state === "ERROR") {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                        console.log("Error message: " + 
                                 errors[0].message);
                    }
                } else {
                    console.log("Unknown error");
                }
            }
        });
        $A.enqueueAction(act);
    },
    
    changeNoteTemplate : function (component, event, helper){
        var selectedTemplate = component.find("selectTemp").get("v.value");
        console.log("In Change Template :: "+selectedTemplate);
        if(selectedTemplate){
            var noteTemplate = component.get('v.notesTemplatesMap')[selectedTemplate];
            component.set('v.noteTemplate', noteTemplate);
            console.log('Template :: >> '+noteTemplate);
        }
        else{
            component.set('v.noteTemplate', '');
        }
    },
})