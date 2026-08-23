({
    doInit : function(component, event, helper) {
        component.set("v.existingRecords", []);debugger
        if(component.get('v.sObjectName') == 'Order__c'){
            helper.createOrderTicketRecord(component, event, helper);
            //helper.handleBondLadder(component,event,helper);
            //helper.handleSTCM(component,event,helper);
        }else{
            helper.init(component, event, helper);
            
        }
    },
    
    handleDeleteForm: function(component, event, helper) {
        //component.set("v.spinner", true);
        var index = event.getParam("indexToDelete");
        helper.deleteRecord(component, helper, index);
        if(component.get('v.sObjectName') == 'Order__c'){
            helper.handleTotalInitialFundingPercent(component, event, helper);
            //helper.handleBondLadder(component,event,helper);
            //helper.handleSTCM(component,event,helper);
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
        // helper.addRow(component, event, helper);
    },
    
    handleNextBtn : function(component, event, helper){
        var existingRecords = component.get("v.existingRecords");
        var forms = component.get("v.dynamicFormList");
        var singleData;
        var disabled;
        var idMissed = 'false';
        var objvalues;
        var missedIdList = [];
        for(var i = 0; i < existingRecords.length; i++){
            if(!existingRecords[i].hasOwnProperty('Id')){
                objvalues = Object.values(existingRecords[i]);
                idMissed = objvalues.every(element => element === null || element === '') == true ? 'false' : 'true';
                missedIdList.push(idMissed);
                
            } else if(existingRecords[i].hasOwnProperty('Id')){
                disabled = JSON.parse(JSON.stringify(forms[i].get("v.disabled")));
                if(!disabled){
                    missedIdList.push('true'); 
                }
            } 
        }
        if(missedIdList.includes('true')){
            helper.showToastEvent('Warning','warning','Please save records.');
        } 
        else if(component.get('v.totalFundingPercent') != 100){
            helper.showToastEvent('Error','error','Total Initial Funding Percentage must equal 100% before moving forward.');
        }
            else {
                var navigate = component.get('v.navigateFlow');
                navigate("NEXT");
            }
    },
    
    handleAddRow : function(component, event, helper){debugger
        var index = event.getParam("indexChanged");
        var forms = component.get("v.dynamicFormList");  
        var records = component.get("v.existingRecords");
        //var lstRequiredFields = component.get("v.lstRequiredFields");
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
            //component.set("v.existingRecords", records);
        }
    },
})