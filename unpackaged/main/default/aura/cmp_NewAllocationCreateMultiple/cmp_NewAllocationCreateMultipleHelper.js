({
    currentIndex : 0,
    intervalTimer: null,
    showToastEvent: function(title, type, message)
    {
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams(
            {
                "title": title,
                "type": type != null ? type.toLowerCase() : 'info',
                "message": message
            }
        );
        toastEvent.fire();
    },
    
    init : function(component, event, helper) {
        console.log('newAllocationCreateMultiple helper.init');
        component.set("v.pendingChanges", {});
        var recordId = component.get("v.recordId");
        var parentRecordId = component.get("v.parentRecordId");
        if(recordId != null && recordId != "" && component.get('v.sObjectName') != 'Allocation_Strategy__c'){
            component.set("v.parentRecordId", recordId);
        }
        var objectFields = component.get("v.sObjectFields");
        var lstSObjectFields = objectFields.split(',');
        component.set("v.tableHeaderRecords", lstSObjectFields);
        
        if(objectFields != null && component.get("v.allocationId") != null)
        {
            helper.intervalTimer = window.setInterval(
                $A.getCallback(function() {
                    helper.processPendingChanges(component, helper);
                })
                , 3000);
        }
        var linesToShow = component.get("v.LinestoShow");
        
        var action = component.get("c.getFieldAndDatatype");
        var sObjectVal = 'Order__c';
        action.setParams({ sObjectName : sObjectVal ,
                          sObjectFields :  component.get("v.tableHeaderRecords")});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            console.log('state: ' + state);
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                console.log(JSON.stringify(result));
                
                lstSObjectFields = [];
                
                for(var idx = 0, len = result.length; idx < len; idx++)
                {
                    lstSObjectFields.push(result[idx].label);
                }
                
                component.set("v.tableHeaderRecords", lstSObjectFields);
                
                component.set("v.fieldsWithDataTypes", result);
                console.log('result: ' +result);
                this.addNewForm(component, event, linesToShow);
            } else{
                this.showToastEvent('Error', 'Error', "Error" + actionResult.getError()[0].message);
            }      
        });        
        $A.enqueueAction(action); 
        window.addEventListener('beforeunload', helper.beforeUnloadHandler.bind(helper));
    },
    
    beforeUnloadHandler: function(event){
        console.log('newAllocationFromCurrent helper.beforeUnloadHandler');
        window.clearInterval(this.intervalTimer);
    },
    
    deleteRecord : function(component, helper, index){
        console.log('newAllocationCreateMultiple.helper.deleteRecord');
        var records = component.get("v.existingRecords");
        var record = records[index];
        var recordId = record.Id != null ? record.Id : null;
        if(!recordId)
        {
            records.splice(index,1);
            component.set("v.existingRecords", records);
            var forms = component.get("v.dynamicFormList");  
            forms.splice(index, 1);
            for(var idx = index, len = forms.length; idx < len; idx++)
            {
                forms[idx].set("v.index", forms[idx].get("v.index")-1);
            }
            component.set("v.dynamicFormList", forms);
            var linesToShow = component.get("v.LinestoShow");
            component.set("v.LinestoShow", linesToShow-1);
            return;
        }
        var action = component.get("c.deleteRecord");
        
        action.setParams({"recordId": recordId}
                        );
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            console.log('state of delete: ' + state);
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                console.log('result of delete: ' + state);
                if(result)
                {
                    records.splice(index,1);
                    component.set("v.existingRecords", records);
                    
                    var forms = component.get("v.dynamicFormList");  
                    forms.splice(index, 1);
                    
                    for(var idx = index,len = forms.length; idx < len; idx++)
                    {
                        forms[idx].set("v.index", forms[idx].get("v.index")-1);
                    }
                    component.set("v.dynamicFormList", forms);
                    var linesToShow = component.get("v.LinestoShow");
                    component.set("v.LinestoShow", linesToShow-1);
                    //this.handleTotalInitialFundingPercent(component,event);
                }
                else
                {
                    this.showToastEvent('Error', 'Error', "There was an error deleting please refresh and try again");
                }
            } else{
                this.showToastEvent('Error', 'Error', "Error" + actionResult.getError()[0].message);
            }      
        });        
        $A.enqueueAction(action); 
        
    },
    
    addNewForm:function(component, event, count){
        console.log('newAllocationFromCurrent helper.addNewForm');
        var action =component.get("c.getExistingRecordsToCreateNew");
        var disable=false;
        var allocationRecord = component.get("v.allocationId");
        var orderTicket = component.get("v.newOrderTicketId");
        var wizFin = component.get("v.wizFinId");
            action.setParams(
                { 
                    allocationRecordId: allocationRecord,
                    wizardFinId: wizFin,
                    objType:component.get("v.sObjectName"),
                    fieldNames:component.get("v.sObjectFields").split(','),
                    orderTicketId:orderTicket
                }
            );
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                console.log("state: " + state);
                    component.set("v.dynamicFormList", []);
                    let result = actionResult.getReturnValue();
                    console.log('result: ' + JSON.stringify(result));
                    
                    
                    var forms = component.get("v.dynamicFormList");
                    var fieldData = component.get("v.fieldsWithDataTypes");
                    var records = [];
                    var record;
                    if(result.length>count){
                        count = result.length;
                        component.set("v.LinestoShow", count);
                    }
                console.log('linestoshow: ' + component.get("v.LinestoShow"));
                    for(let i =0;i<count;i++){    
                        
                        record = i<result.length ? result[i] : null;
                        if(record!=null) {
                            component.set("v.newOrderTicketId", record.Order_Ticket__c);
                            for(var idx=0,len=fieldData.length;idx<len;idx++) {
                                fieldData[idx].fieldValue = record[fieldData[idx].fieldName]!=null ? record[fieldData[idx].fieldName] : null;
                            }
                            disable = record.hasOwnProperty('Id') && record.Id ? true : false;
                        } else {
                            record = {};
                            for(var idx=0,len=fieldData.length;idx<len;idx++){
                                record[fieldData[idx].fieldName] = null;
                                fieldData[idx].fieldValue = null;
                            }
                            disable=false;
                        }
                        records.push(record);
                        console.log('about to create component');
                        $A.createComponent(
                            "c:cmp_DynamicForm", 
                            {
                                "aura:id":"dynamicFormId", 
                                "sObjectName" : "Strategy__c" , 
                                "fieldsWithDataTypes" : fieldData,
                                "index" : i+1,
                                "disabled":disable,
                                "isCreated":disable,
                                "varhouseholdId": component.get("v.varhouseholdId"),
                                "totalInitialFundingAmount": component.get("v.totalInitialFundingAmount")
                                
                            }, 
                            function(content, status,error) {
                                console.log('status: ' + status);
                                if (status === "SUCCESS") { 
                                    component.set("v.dynamicFormList", component.get("v.dynamicFormList").concat(content));
                                } else {
                                    console.log(error); 
                                }
                            }
                        );
                    }
                    component.set("v.existingRecords", records);
                
            } else {
                this.showToastEvent('Error', 'Error', "Error" + actionResult.getError()[0].message);
            }      
        });        
        $A.enqueueAction(action);
    },
    
    processPendingChanges : function(component, helper){
        try
        {
            var pendingChanges = JSON.parse(JSON.stringify(component.get("v.pendingChanges")));
            var obj;
            var didUpdate;
            for(let index in pendingChanges)
            {
                component.set("v.autoSaving", true);
                didUpdate = true;
                obj = pendingChanges[index];
                helper.updateRecord(component, event, obj, index); 
            }
            
            if(didUpdate)
            {
                window.setTimeout(
                    $A.getCallback(function() {
                        component.set("v.autoSaving", false);
                    })
                    , 2000);
                component.set("v.pendingChanges", {});
            }
        }
        catch(e)
        {
            console.log(e);
        }
    },
    
    extend : function () {
        var extended = {};
        
        // Merge the object into the extended object
        var merge = function (obj) {
            for (var prop in obj) {
                if (obj.hasOwnProperty(prop)) {
                    // Push each value from `obj` into `extended`
                    extended[prop] = obj[prop];
                }
            }
        };
        
        // Loop through each object and conduct a merge
        for (var i = 0; i < arguments.length; i++) {
            merge(arguments[i]);
        }
        
        return extended;
        
    },
    
    updateRecord : function(component, event, record, index){
        console.log('flowcreatemultiplefromcurrent helper.updateRecord');
        var action = component.get("c.upsertRecordForCurrentAllocation");
        console.log('this is update record');
        var alloc = component.get("v.allocationId");
        var fieldNames = component.get("v.fieldsWithDataTypes");
        var wizFin = component.get("v.wizFinId");
        var uniquefieldName = fieldNames[0].fieldName;
        console.log('component.get("v.newOrderTicketId"): ' + component.get("v.newOrderTicketId"));
        record.Order_Ticket__c = component.get("v.newOrderTicketId");
        action.setParams({
            recordValues : record,
            allocationRecordId : alloc,
            wizId : wizFin});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            console.log('state: ' + state);
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                component.set("v.newOrderTicketId", result.Order_Ticket__c);
                    this.handleTotalInitialFundingPercent(component, event);
                //}
                component.set("v.spinner", false);
                this.showToastEvent('Success', 'success', 'Record saved successfully.');
                var appEvent = $A.get("e.c:DisableRow");
                appEvent.setParams(({"index":index,
                                     "saved":true,
                                     "field":uniquefieldName,
                                     "isCreated":true
                                    }));
                appEvent.fire();
                
                var records = component.get("v.existingRecords");
                records.splice(index, 1, result);
                component.set("v.existingRecords", records);
                
                var pendingChanges = JSON.parse(JSON.stringify(component.get("v.pendingChanges")));
                
                if(pendingChanges[index] != null)
                {
                    pendingChanges[index] = this.extend(result, pendingChanges[index]);
                    component.set("v.pendingChanges", pendingChanges);
                }
                
                console.log(JSON.stringify(result));
                component.set("v.fetchedResult", records);
                
            } else{
                component.set("v.spinner", false);
                this.showToastEvent('Error', 'error', "Error: " + actionResult.getError()[0].message);
            }
        });        
        $A.enqueueAction(action); 
    },
    
    handleTotalInitialFundingPercent : function(component, event, helper){
        var orderTicket = component.get("v.newOrderTicketId");
        var action = component.get("c.getTotalFieldSumBLSTCM");
        action.setParams({"orderTicketId" : orderTicket});
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var totalFundingPercent = response.getReturnValue().result;
                var bL = response.getReturnValue().bondLadder;
                var sT = response.getReturnValue().stcm;
                component.set("v.totalFundingPercent", totalFundingPercent);
                component.set("v.BondLadder", bL);
                component.set("v.ShortTermCashManagement", sT);
            }
        });
        $A.enqueueAction(action);
    },
    
    saveAndAddRow : function(component, event, helper){
        var linesToShow = component.get("v.LinestoShow");
        var max = component.get("v.MaximumNumberofRecords");
        if(linesToShow<max)
        {
            linesToShow++;
            component.set("v.LinestoShow" ,linesToShow);
        }  
        var fieldsWithDataTypes=component.get("v.fieldsWithDataTypes");
        var missingFields=[];
        var fetchedData = [];
        var forms=component.get("v.dynamicFormList");
        var index=forms.length;
        var recordsTobeUpsert;
        var objValues;
        var records=component.get("v.existingRecords");
        var fieldData = component.get("v.fieldsWithDataTypes");
        for(var i=0;i<records.length;i++){
            var disable=JSON.parse(JSON.stringify(forms[i].get("v.disabled")));
            if(!records[i].hasOwnProperty('Id') || (records[i].hasOwnProperty('Id')&&!disable)){
                objValues=Object.values(records[i]);
                var Idmissed=objValues.every(element => element=== null ||element==='') == true ? false :true;
                if(Idmissed){
                    var singleData = JSON.parse(JSON.stringify(forms[i].get("v.listvalue")));
                    var obj = records[i];
                    for(let key in singleData)
                    {
                        obj[key] = singleData[key];
                    }
                    var missingValue=false;
                    for(let key in obj)
                    {
                        if(obj[key] == null || obj[key]=='')
                        {
                            missingValue=true;
                            var fieldLabel=fieldsWithDataTypes.find(element => element.fieldName==key)
                            missingFields.push(fieldLabel.label);
                        }
                    }
                    
                    records.splice(i,1,obj);
                    component.set("v.existingRecords", records);
                    
                    if(!missingValue)
                    {
                        var pendingChanges = component.get("v.pendingChanges");
                        pendingChanges[i] = obj;
                        component.set("v.pendingChanges", pendingChanges); 
                    }else {
                        console.log(missingFields);
                        var message='Please complete all of the following fields before saving: ';
                        for(var i=0;i<missingFields.length;i++){
                            if(i<missingFields.length){
                                message+=missingFields[i]+', '
                            }else if(i==missingFields.length) {
                                message+=missingFields[i]+'.'  
                            }
                        }
                        component.set('v.spinner',false);
                        message=message.substring(0,message.length-2);
                        this.showToastEvent('Warning','warning',message);
                    }
                } 
            }
        }
        if(index<component.get("v.LinestoShow")){
            var record = {};
            for(var idx=0,len=fieldData.length;idx<len;idx++)
            {
                record[fieldData[idx].fieldName] = null;
                fieldData[idx].fieldValue = null;
                
            }
            disable=false;
            
            records.push(record); 
            console.log('record: ' + record);
            
            $A.createComponent(
                "c:cmp_DynamicForm", 
                {
                    "aura:id":"dynamicFormId", 
                    "sObjectName" : 'Allocation_Strategy__c' , 
                    "fieldsWithDataTypes" : fieldData,
                    "index" : index+1,
                    "disabled":disable,
                    "varhouseholdId": component.get("v.varhouseholdId")                }, 
                function(content, status,error) 
                {
                    if (status === "SUCCESS") 
                    { 
                        component.set("v.dynamicFormList", component.get("v.dynamicFormList").concat(content));
                    }
                    else
                    {
                        console.log(error); 
                    }
                }
            );
        }
        component.set("v.existingRecords", records);
        component.set('v.spinner',false);
    },
    
    //Insert Order Tickect first time
    createOrderTicketRecord : function(component, event, helper)
    {
        let record = {};
        record['Status__c'] = 'new';
        //record[] = component.get("v.parentRecordId");
        var action = component.get("c.upsertRecord");
        var allocationRecord = component.get("v.allocationId");
        action.setParams({recordValues : record,
                          recordTypeName : null});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();    
                console.log('result: ' + result);
                component.set("v.parentLookupFieldName",sObjectVal);
                component.set("v.parentRecordId",result.Id);
                helper.init(component, event, helper);
                helper.handleTotalInitialFundingPercent(component, event, helper);
            } else{
                component.set("v.spinner", false);
                this.showToastEvent('Error', 'error', "Error: " + actionResult.getError()[0].message);
            }
        });        
        $A.enqueueAction(action); 
    },
})