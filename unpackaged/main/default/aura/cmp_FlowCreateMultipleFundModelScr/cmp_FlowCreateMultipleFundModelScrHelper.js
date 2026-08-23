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
        component.set("v.pendingChanges", {});
        var recordId = component.get("v.recordId");
        var parentRecordId = component.get("v.parentRecordId");
        if(recordId != null && recordId != "" && component.get('v.sObjectName') != 'Order__c')
        {
            component.set("v.parentRecordId", recordId);
        }
        var objectFields = component.get("v.sObjectFields");
        var lstSObjectFields = objectFields.split(',');
        console.log('lstObjectFields: ' + lstSObjectFields);
        component.set("v.tableHeaderRecords", lstSObjectFields);
        console.log('lstObjectFields: ' + lstSObjectFields);
        component.set("v.numberOfRecords", null);

        if(objectFields != null && component.get("v.parentRecordId") != null)
        {
            helper.intervalTimer = window.setInterval(
                $A.getCallback(function() {
                    helper.processPendingChanges(component, helper);
                })
                , 3000);
        }
        var linesToShow = component.get("v.LinestoShow");
        
        var action = component.get("c.getFieldAndDatatype");
        var sObjectVal = component.get("v.sObjectName");
        action.setParams({ sObjectName : component.get("v.sObjectName") ,
                          sObjectFields :  component.get("v.tableHeaderRecords")});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
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
    
    beforeUnloadHandler: function(event) 
    {
        window.clearInterval(this.intervalTimer);
    },
    
    deleteRecord : function(component, helper, index){
        var parentFieldName = component.get("v.parentLookupFieldName");
        var parentRecordId = component.get("v.parentRecordId");
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
        var sObjectVal = component.get("v.sObjectName");
        
        action.setParams(
            { 
                "objType" : sObjectVal,
                "parentRecordId" :  parentRecordId,
                "parentLookup" : parentFieldName,
                "recordId": recordId
            }
        );
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
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
                }
                else
                {
                    this.showToastEvent('Error', 'Error', "There was an error deleting please refresh and try again");
                }
            } else{
                this.showToastEvent('Error', 'Error', "Error" + actionResult.getError()[0].message);
            }      
            //component.set("v.spinner", false);
        });        
        $A.enqueueAction(action); 
        
        /*  var rowIndex = event.target.getAttribute("id"); 
        var rows = component.get("v.tableHeaderRows");
        var linesToShow = component.get("v.LinestoShow");
        rows.splice(rowIndex, 1);
        linesToShow=linesToShow-1;
        component.set("v.tableHeaderRows" ,rows);
        component.set("v.LinestoShow" ,linesToShow); */
    },
    
    /*addRow : function(component, event, helper)
    {
        var linesToShow = component.get("v.LinestoShow");
        var max = component.get("v.MaximumNumberofRecords");
        if(linesToShow < max)
        {
            linesToShow++;
            component.set("v.LinestoShow", linesToShow);
            helper.addNewForm(component, event, linesToShow);
        }  
    },*/
    
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
    
    updateRecord : function(component, event, record, index)
    {
        var action = component.get("c.upsertRecord");
        var sObjectVal = component.get("v.sObjectName");
        var parentFieldName = component.get("v.parentLookupFieldName");
        var parentRecordId = component.get("v.parentRecordId");
        var recordType = component.get("v.recordTypeName");
        var fieldNames = component.get("v.fieldsWithDataTypes");
        var uniquefieldName = fieldNames[0].fieldName;
        recordType = recordType != null && recordType.length > 0 ? recordType : null; 
        
        if(parentFieldName != null && parentRecordId != null){
            record[parentFieldName] = parentRecordId;
        }
        if(component.get("v.totalInitialFundingAmount") != null){
            record['Total_Initial_Funding_Amount__c'] = component.get("v.totalInitialFundingAmount");
        }
        action.setParams({ objType : sObjectVal ,
                          recordValues : record,
                          recordTypeName : recordType});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                if(component.get('v.sObjectName') == 'Order__c'){
                    this.handleTotalInitialFundingPercent(component, event);
                    //this.handleBondLadder(component,event,helper);
                    //this.handleSTCM(component,event,helper);
                }
                component.set("v.spinner", false);
                this.showToastEvent('Success', 'success', 'Record saved successfully.');
                var appEvent = $A.get("e.c:DisableRow");
                appEvent.setParams(({"index":index,
                                     "saved":true,
                                     "field":uniquefieldName,
                                     "isCreated":true
                                    }));
                appEvent.fire();
                /*var appEventLookupfield = $A.get("e.c:DisableRowForCustomObjectListLookup");
                appEventLookupfield.setParams({"disabled":true,
                                               "index":parseInt(index)+1,
                                              });
                appEventLookupfield.fire();*/
                
                var records = component.get("v.existingRecords");
                records.splice(index, 1, result);
                component.set("v.existingRecords", records);
                //Set number of records
                debugger
                if(records !=null){
                    component.set("v.numberOfRecords", records.length);
                    
                }else{
                    component.set("v.numberOfRecords", null);
                }
                
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
    
    /*addNewForm : function(component, event, count)
    {
        var action = component.get("c.getExistingRecords");
        var recordType = component.get("v.recordTypeName");
        var disable = false;
        recordType = recordType != null && recordType.length > 0 ? recordType : null; 
        action.setParams(
            { 
                parentRecordId: component.get("v.parentRecordId"), 
                objType: component.get("v.sObjectName"),
                parentLookup: component.get("v.parentLookupFieldName"),
                fieldNames: component.get("v.sObjectFields").split(','),
                recordTypeName: recordType
            }
        );
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                component.set("v.dynamicFormList", []);
                let result = actionResult.getReturnValue();
                console.log(JSON.stringify(result));
                var forms = component.get("v.dynamicFormList");
                var fieldData = component.get("v.fieldsWithDataTypes");
                var records = [];
                var record;
                if(result.length>count)
                {
                    count = result.length;
                    component.set("v.LinestoShow", count);
                }
                for(let i =0;i<count;i++)
                {    
                    record = i<result.length ? result[i] : null;
                    if(record!=null)
                    {
                        for(var idx=0,len=fieldData.length;idx<len;idx++)
                        {
                            fieldData[idx].fieldValue = record[fieldData[idx].fieldName] != null ? record[fieldData[idx].fieldName] : null;
                        }
                        disable = record.hasOwnProperty('Id') && record.Id ? true : false;
                        var appEventLookupfield=$A.get("e.c:DisableRowForCustomObjectListLookup");
                        appEventLookupfield.setParams({"disabled":true,
                                                       "index":parseInt(i)+1,
                                                      });
                        appEventLookupfield.fire();
                    }
                    else
                    {
                        record = {};
                        for(var idx=0,len=fieldData.length;idx<len;idx++)
                        {
                            record[fieldData[idx].fieldName] = null;
                            fieldData[idx].fieldValue = null;
                            
                        }
                        disable = false;
                    }
                    records.push(record);
                    $A.createComponent(
                        "c:cmp_DynamicForm", 
                        {
                            "aura:id":"dynamicFormId", 
                            "sObjectName" : component.get("v.sObjectName") , 
                            "fieldsWithDataTypes" : fieldData,
                            "index" : i+1,
                            "disabled":disable
                        }, 
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
            } else{
                this.showToastEvent('Error', 'Error', "Error: " + actionResult.getError()[0].message);
            }      
        });        
        $A.enqueueAction(action);
        
    },*/
    
    addNewForm:function(component, event, count)
    {
        var action = component.get("c.getExistingRecords");
        var recordType = component.get("v.recordTypeName");
        var disable=false;
        recordType = recordType!=null && recordType.length>0 ? recordType : null; 
        action.setParams(
            { 
                parentRecordId: component.get("v.parentRecordId"), 
                objType:component.get("v.sObjectName"),
                parentLookup:component.get("v.parentLookupFieldName"),
                fieldNames:component.get("v.sObjectFields").split(','),
                recordTypeName: recordType
            }
        );
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                component.set("v.dynamicFormList", []);
                let result = actionResult.getReturnValue();
                console.log(JSON.stringify(result));
                
                
                var forms = component.get("v.dynamicFormList");
                var fieldData = component.get("v.fieldsWithDataTypes");
                var records = [];
                var record;
                if(result.length>count)
                {
                    count = result.length;
                    component.set("v.LinestoShow", count);
                }
                for(let i =0;i<count;i++)
                {    
                    
                    record = i<result.length ? result[i] : null;
                    if(record!=null)
                    {
                        for(var idx=0,len=fieldData.length;idx<len;idx++)
                        {
                            
                            fieldData[idx].fieldValue = record[fieldData[idx].fieldName]!=null ? record[fieldData[idx].fieldName] : null;
                            
                        }
                        disable = record.hasOwnProperty('Id') && record.Id ? true : false;
                        /*var appEventLookupfield=$A.get("e.c:DisableRowForCustomObjectListLookup");
                        appEventLookupfield.setParams({"disabled":true,
                                                       "index":parseInt(i)+1,
                                                      });
                        appEventLookupfield.fire(); */
                        
                    }
                    else
                    {
                        record = {};
                        for(var idx=0,len=fieldData.length;idx<len;idx++)
                        {
                            record[fieldData[idx].fieldName] = null;
                            fieldData[idx].fieldValue = null;
                        }
                        disable=false;
                    }
                    records.push(record);
                    $A.createComponent(
                        "c:cmp_DynamicForm", 
                        {
                            "aura:id":"dynamicFormId", 
                            "sObjectName" : component.get("v.sObjectName") , 
                            "fieldsWithDataTypes" : fieldData,
                            "index" : i+1,
                            "disabled":disable,
                            "isCreated":disable,
                            "varhouseholdId": component.get("v.varhouseholdId"),
                            "totalInitialFundingAmount": component.get("v.totalInitialFundingAmount")
                            
                        }, 
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
            } else{
                this.showToastEvent('Error', 'Error', "Error" + actionResult.getError()[0].message);
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
            
            $A.createComponent(
                "c:cmp_DynamicForm", 
                {
                    "aura:id":"dynamicFormId", 
                    "sObjectName" : component.get("v.sObjectName") , 
                    "fieldsWithDataTypes" : fieldData,
                    "index" : index+1,
                    "disabled":disable,
                    "varhouseholdId": component.get("v.varhouseholdId"),
                    "totalInitialFundingAmount": component.get("v.totalInitialFundingAmount")
                }, 
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
    
    handleTotalInitialFundingPercent : function(component, event, helper){
        var parentFieldName = component.get("v.parentLookupFieldName");
        var parentRecordId = component.get("v.parentRecordId");
        var action = component.get("c.getTotalFieldSumBLSTCM");
        action.setParams({"parentFieldName" : parentFieldName, "parentFieldId" : parentRecordId});
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
    
    //Insert Order Tickect first time
    createOrderTicketRecord : function(component, event, helper)
    {
        let record = {};
        record['Status__c'] = 'new';
        record[component.get("v.parentLookupFieldName")] = component.get("v.parentRecordId");
        record['Leave_in_Kind__c'] = component.get("v.leaveInKind") ? 'true' : 'false';
        var action = component.get("c.upsertRecord");
        var sObjectVal = 'Order_Ticket__c';
        action.setParams({ objType : sObjectVal ,
                          recordValues : record,
                          recordTypeName : null});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                component.set("v.orderTicketId", result.Id);
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

    updateLeaveInKind : function(component, callback)
    {
        var orderTicketId = component.get("v.orderTicketId");
        if(!orderTicketId) {
            if(callback) {
                callback(true);
            }
            return;
        }
        var record = {
            'Id': orderTicketId,
            'Leave_in_Kind__c': component.get("v.leaveInKind") ? 'true' : 'false'
        };
        var action = component.get("c.upsertRecord");
        action.setParams({
            objType: 'Order_Ticket__c',
            recordValues: record,
            recordTypeName: null
        });
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if(state !== "SUCCESS" && callback) {
                this.showToastEvent('Error', 'error', "Error: " + actionResult.getError()[0].message);
            }
            if(callback) {
                callback(state === "SUCCESS");
            }
        });
        $A.enqueueAction(action);
    },
    /*handleSTCM : function(component, event, helper){
        var parentFieldName = component.get("v.parentLookupFieldName");
        var parentRecordId = component.get("v.parentRecordId");
        var action = component.get("c.getSTCM");
        action.setParams({"parentFieldName" : parentFieldName, "parentFieldId" : parentRecordId});
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var stcmVAR = response.getReturnValue();
                component.set("v.ShortTermCashManagement", stcmVAR);
            }
        });
        $A.enqueueAction(action);
    },*/
    
    /*handleBondLadder : function(component, event, helper){
        var parentFieldName = component.get("v.parentLookupFieldName");
        var parentRecordId = component.get("v.parentRecordId");
        var action = component.get("c.getBondLadder");
        action.setParams({"parentFieldName" : parentFieldName, "parentFieldId" : parentRecordId});
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var bondLadderVar = response.getReturnValue();
                component.set("v.BondLadder", bondLadderVar);
            }
        });
        $A.enqueueAction(action);
    },*/
})