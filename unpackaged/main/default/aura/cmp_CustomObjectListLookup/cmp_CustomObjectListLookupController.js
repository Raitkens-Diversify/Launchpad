({
    doInit : function(component, event, helper){
        console.log('CustomObjectListLookup controller.doInit');
        helper.doInit(component, event, helper);
    },
    
    searchField : function(component, event, helper) {
        console.log('CustomObjectListLookup controller.searchField');
        var currentText = event.getSource().get("v.value");
        var resultBox = component.find('resultBox');
        component.set("v.LoadingText", true);
        if(currentText.length > 0) {
            $A.util.addClass(resultBox, 'slds-is-open');
        }
        else {
            $A.util.removeClass(resultBox, 'slds-is-open');
        }
        var action = component.get("c.getResults");
        debugger;
        console.log('objectname: ' + component.get("v.objectName"));
        console.log('childobjectname: ' + component.get("v.childObjectName"));
        console.log('fieldName: ' + component.get('v.fieldName'));
        action.setParams({
            "objectName" : component.get("v.objectName"),
            "fieldName" : component.get("v.fieldName"),
            "value" : currentText,
            "conditionFieldName" : component.get('v.conditionFieldName'),
            "conditionFieldValue" : component.get('v.conditionFieldValue'),
            "filter" : component.get('v.filter')

        });
        
        action.setCallback(this, function(response){
            var STATE = response.getState();
            if(STATE === "SUCCESS") {
                component.set("v.searchRecords", response.getReturnValue());
                if(component.get("v.searchRecords").length == 0) {
                    console.log('000000');
                }
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
            component.set("v.LoadingText", false);
        });
        
        $A.enqueueAction(action);
    },
    
    setSelectedRecord : function(component, event, helper) {
        console.log('CustomObjectListLookup controller.setSelectedRecord');
        var currentText = event.currentTarget.id;
        var resultBox = component.find('resultBox');
        $A.util.removeClass(resultBox, 'slds-is-open');
        //component.set("v.selectRecordName", currentText);
        component.set("v.selectRecordName", event.currentTarget.dataset.name);
        component.set("v.selectRecordId", currentText);
        component.find('userinput').set("v.readonly", true);
        var compEvent = component.getEvent("customObjectLookupChange");
        compEvent.fire();
    }, 
    
    resetData : function(component, event, helper) {
        console.log('CustomObjectListLookup controller.resetData');
        component.set("v.selectRecordName", "");
        component.set("v.selectRecordId", "");
        component.find('userinput').set("v.readonly", false);
        var compEvent = component.getEvent("customObjectLookupChange");
        compEvent.fire();
    },
    
    disableRow:function(component,event,helper){
        console.log('CustomObjectListLookup controller.disableRow');
        var index=event.getParam("index");
        console.log(index);
        if(index==component.get("v.itemIndex")){
            var disabled=event.getParam("disabled");
            component.set("v.disabled",disabled);
        }
    },
   
})