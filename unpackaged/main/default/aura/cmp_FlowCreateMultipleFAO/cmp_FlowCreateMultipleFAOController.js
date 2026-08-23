({
    doInit : function(component, event, helper) {
        helper.createfinAccOpp(component,event,helper);
        component.set("v.existingRecords", []);
        helper.init(component, event, helper);
        
    },
    
    handleDeleteForm: function(component, event, helper) {
        var index = event.getParam("indexToDelete");
        helper.deleteRecord(component, helper, index);
    },
    handleFormChange: function(component, event, helper) {
        var index = event.getParam("indexChanged");
        var forms = component.get("v.dynamicFormList");  
		var records = component.get("v.existingRecords");
        
        var fetchedData = [];
        if(index<forms.length){
            
            var singleData = JSON.parse(JSON.stringify(forms[index].get("v.listvalue")));
           var obj = records[index];
            for(let key in singleData)
            {
                obj[key] = singleData[key];
            }
            
            var missingValue=false;
            for(let key in obj)
            {
                if(obj[key] == null)
                {
                    missingValue=true;
                }
            }
            
            records.splice(index,1,obj);
            component.set("v.existingRecords", records);
            
            if(!missingValue)
            {
                var pendingChanges = component.get("v.pendingChanges");
                pendingChanges[index] = obj;
                component.set("v.pendingChanges", pendingChanges);
            }
        }
    },
    
    addRow:function(component, event, helper) {
        helper.addRow(component, event, helper);
    },
    
    saveRecords : function(component, event, helper) {
        helper.saveRecords(component, event, helper);    
    },
    
    fetchFormValue : function(component, event, helper)
    {
        var fieldsWithDataTypes = component.get("v.fieldsWithDataTypes");
        var fetchedData = [];
        var forms = component.get("v.dynamicFormList");
        for(let i=0; i<forms.length; i++){
            var singleData = JSON.parse(JSON.stringify(forms[i].get("v.listvalue")));
            var idx=0;
            var obj = {};
            for(let key in singleData)
            {
                obj[fieldsWithDataTypes[idx].fieldName] = singleData[key];
                idx++
            }
            if(idx>0)
            {
            	fetchedData.push(obj);
            }
        }
        component.set("v.fetchedResult",fetchedData);
    },
})