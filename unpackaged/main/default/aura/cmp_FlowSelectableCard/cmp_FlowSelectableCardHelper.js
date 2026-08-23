({
	getRecord: function(component, event, helper) {  
        var objectName = component.get("v.sObjectType");
        var record = component.get("v.recordId");
        var records = component.get("v.recordIds");
        var fields = component.get("v.fields");
        var recordFilter = component.get("v.recordFilter");

        var action;
        //debugger;
        if(record == null){
            var action = component.get("c.getRecordsInfo");  
            //console.log(record);
            //debugger;
            action.setParams({'objectName':objectName, 'recordIds':records, 'fields':fields,'recordFilter':recordFilter});
        } else {
            var action = component.get("c.getRecordInfo");  
            //console.log(record);
            //debugger;
            action.setParams({'objectName':objectName, 'recordId':record, 'fields':fields,'recordFilter':recordFilter});
        }
        
        action.setCallback(this, function(response){
            var state = response.getState();
            if (state === "SUCCESS") {
                console.log('response: ' + JSON.stringify(response.getReturnValue()));
                console.log(response.getReturnValue());
                component.set("v.records", response.getReturnValue());
                component.set("v.isLoaded", true);
                var fields = component.get("v.fields");
        		console.log('fields: ' + component.get("v.fields"));
                console.log("here", JSON.stringify(component.get("v.records")));
        		var fieldsList = fields.split(", ");
        		component.set("v.fieldsList", fieldsList);
                //var reloadEvent = component.getEvent("reloadTimeLogData");
                //reloadEvent.fire();
            }else{   
                this.showToastEvent('Error', 'Error', response.getError()[0].message, 'sticky');   
            }
            //component.set("v.openTimeLogModal", false); 
            //component.set("v.showSpinner", false);
            //component.set("v.duration", 0);
        })
        $A.enqueueAction(action);
    },
    
    assignSelectedCard: function (component, recordId) {
        component.set("v.selectedValue", recordId);
        console.log(component.get("v.selectedValue"));
    },
    
    assignSelectedPersonCard: function (component, recordId) {
        debugger;
        component.set("v.selectedValue", recordId);
        var pcId = '';
        for(let i=0; i < component.get("v.records").length; i++){
            if(component.get("v.records")[i].Id == recordId){
                pcId = component.get("v.records")[i].PersonContactId;
            }
        }
        debugger;
        component.set("v.personContactId", pcId);
    }
})