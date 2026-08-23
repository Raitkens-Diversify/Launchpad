({
    doInit : function(component, event, helper) {
        component.set('v.spinner', true);
        component.set("v.existingRecords", []);
        helper.init(component, event, helper);
        if(component.get('v.totalAmountFieldName')){
            helper.handleTotalAmount(component, event, helper);
        }
    },
    
    handleDeleteForm: function(component, event, helper) {
        var index = event.getParam("indexToDelete");
        helper.deleteRecord(component, helper, index);
        if(component.get('v.totalAmountFieldName')){
            helper.handleTotalAmount(component, event, helper);
        }
    },
    
    handleFormChange: function(component, event, helper) {
        component.set("v.spinner", true);
        var index = event.getParam("indexChanged");
        var forms = component.get("v.dynamicFormList");  
        var records = component.get("v.existingRecords");
        var fieldsWithDataTypes = component.get("v.fieldsWithDataTypes");
        var fieldHeaders = component.get("v.tableHeaderRecords");
        
        var missingFields = [];
        var fetchedData = [];
        if(index < forms.length){
            
            var singleData = JSON.parse(JSON.stringify(forms[index].get("v.listvalue")));
            var obj = records[index];
            for(let key in singleData)
            {
                obj[key] = singleData[key];
            }
            
            var missingValue = false;
            for(let key in obj)
            {
                if(obj[key] == null || obj[key] == '')
                {
                    missingValue = true;
                    var fieldLabel = fieldsWithDataTypes.find(element => element.fieldName == key)
                    missingFields.push(fieldLabel.label);
                }
            }
            
            records.splice(index, 1, obj);
            component.set("v.existingRecords", records);
            
            if(!missingValue)
            {
                var pendingChanges = component.get("v.pendingChanges");
                pendingChanges[index] = obj;
                component.set("v.pendingChanges", pendingChanges);
            } else {
                console.log(missingFields);
                var message='Please complete all of the following fields before saving: ';
                for(var i = 0; i < missingFields.length; i++){
                    if(i < missingFields.length){
                        message += missingFields[i] + ', '
                    } else if(i == missingFields.length) {
                        message += missingFields[i] + '.'  
                    }
                }
                message = message.slice(0,-2);
                component.set('v.spinner', false);
                helper.showToastEvent('Warning', 'warning', message);
            }
        }
    },
    
    handleSaveAndAddRowBtn : function(component, event, helper){
        component.set("v.spinner", true);
        helper.saveAndAddRow(component, event, helper);
    },
    
    handleAddRow : function(component, event, helper){
        var index = event.getParam("indexChanged");
        var forms = component.get("v.dynamicFormList");  
        var records = component.get("v.existingRecords");
        var lstRequiredFields = component.get("v.lstRequiredFields");
        var fieldNames = component.get("v.tableHeaderRecords");
        
        if(index<forms.length){
            var singleData = JSON.parse(JSON.stringify(forms[index].get("v.listvalue")));
            var obj = records[index];
            for(let key in singleData)
            {
                obj[key] = singleData[key];
            }
            records.splice(index, 1, obj);
            console.log(records);
            component.set("v.existingRecords", records);
        }
    },
    
    handleTotalComparison : function(component, event, helper){
        helper.handleTotalComparison(component, event, helper);
    }
})