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
        var comparisonInputField = component.find("comparisonInput");
        if(comparisonInputField){
            setTimeout(function(){
                comparisonInputField.blur();
            }, 0);
        }
        component.set("v.pendingChanges", {});
        var recordId = component.get("v.recordId");
        var parentRecordId = component.get("v.parentRecordId");
        if(recordId != null && recordId != "")
        {
            component.set("v.parentRecordId", recordId);
        }
        var objectFields = component.get("v.sObjectFields");
        var lstSObjectFields = objectFields.split(',');
        var readOnlyFields = component.get("v.readOnlyFields");
        var lstReadOnlyFields = readOnlyFields.split(',');
        component.set("v.tableHeaderRecords", lstSObjectFields);
        
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
                          sObjectFields :  component.get("v.tableHeaderRecords"),
                          readOnlyFields : lstReadOnlyFields
                         });
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                console.log(JSON.stringify(result));
                
                lstSObjectFields = [];
                
                for(var idx=0, len=result.length; idx<len; idx++)
                {
                    lstSObjectFields.push(result[idx].label);
                }
                
                component.set("v.tableHeaderRecords", lstSObjectFields);
                
                component.set("v.fieldsWithDataTypes", result);
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
        action.setParams({ objType : sObjectVal ,
                          recordValues : record,
                          recordTypeName : recordType});
        action.setCallback(this, function(actionResult) {
            var state = actionResult.getState();
            if (state === "SUCCESS") {
                let result = actionResult.getReturnValue();
                if(component.get('v.totalAmountFieldName')){
                    this.handleTotalAmount(component, event);
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
    
    addNewForm:function(component, event, count)
    {
        var action = component.get("c.getExistingRecords");
        var recordType = component.get("v.recordTypeName");
        var disable = false;
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
                
                var forms = component.get("v.dynamicFormList");
                var fieldData = component.get("v.fieldsWithDataTypes");
                var records = [];
                var record;
                if(result.length > count || !component.get('v.allowCreate'))
                {
                    count = result.length;
                    component.set("v.LinestoShow", count);
                }
                for(let i=0; i<count; i++)
                { 
                    record = i<result.length ? result[i] : null;
                    if(record != null)
                    {
                        for(var idx = 0, len = fieldData.length; idx < len; idx++)
                        {
                            fieldData[idx].fieldValue = record[fieldData[idx].fieldName]!=null ? record[fieldData[idx].fieldName] : null;
                        }
                        disable = record.hasOwnProperty('Id') && record.Id ? true : false;
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
                            "allowCreate": component.get("v.allowCreate")
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
            setTimeout(function(){
                component.set('v.spinner', false);
            }, 1000);
        });        
        $A.enqueueAction(action);
    },
    
    /*saveAndAddRow : function(component, event, helper){
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
            if(!records[i].hasOwnProperty('Id') || (records[i].hasOwnProperty('Id')&&(!component.get("v.allowCreate")||(!disable && component.get("v.allowCreate"))))){
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
        //Check to add a new blank row only when AllowCreate Permission is given.
        if(component.get('v.allowCreate')){
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
                        "allowCreate": component.get("v.allowCreate")
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
                        component.set('v.spinner',false);
                    }
                );
            }
        }
        component.set("v.existingRecords", records);
    },*/
    
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
        var missingValue = false;
        var pendingChanges = component.get("v.pendingChanges");
        const mapPendingChanges = new Map();
        for(var i=0;i<records.length;i++){
            var disable = JSON.parse(JSON.stringify(forms[i].get("v.disabled")));
            if(!records[i].hasOwnProperty('Id') || (records[i].hasOwnProperty('Id')&&(!component.get('v.allowCreate') || component.get('v.allowCreate') && !disable))){
                objValues=Object.values(records[i]);
                var Idmissed=objValues.every(element => element=== null ||element==='') == true ? false :true;
                if(Idmissed){
                    var singleData = JSON.parse(JSON.stringify(forms[i].get("v.listvalue")));
                    var obj = records[i];
                    for(let key in singleData)
                    {
                        obj[key] = singleData[key];
                    }
                    for(let key in obj)
                    {
                        if(obj[key] == null || obj[key]=='')
                        {
                            missingValue=true;
                            var fieldLabel=fieldsWithDataTypes.find(element => element.fieldName==key)
                            if (!missingFields.includes(fieldLabel.label)){
                                missingFields.push(fieldLabel.label);
                            }
                        }
                    }
                    
                    records.splice(i,1,obj);
                    component.set("v.existingRecords", records);
                    
                    mapPendingChanges.set(i, obj);
                } 
            }
        }
        
        //Conditions to upsert records or show error
        if(!missingValue)
        {
            mapPendingChanges.forEach(function(value, key){
                pendingChanges[key] = value;
            })
            component.set("v.pendingChanges", pendingChanges); 
        }
        else {
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
        
        //Adding a new blank record in case of creation
        if(component.get('v.allowCreate')){
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
                        "varhouseholdId": component.get("v.varhouseholdId")
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
        }
        component.set("v.existingRecords", records);
        component.set('v.spinner',false);
    },    
    
    handleTotalAmount : function(component, event, helper){
        var objectName = component.get("v.sObjectName");
        var parentFieldName = component.get("v.parentLookupFieldName");
        var parentRecordId = component.get("v.parentRecordId");
        var totalFieldName = component.get("v.totalAmountFieldName");
        var action = component.get("c.getTotalAmount");
        action.setParams({"sObjectName": objectName, "parentFieldName" : parentFieldName, "parentFieldId" : parentRecordId,
                          "fieldName" : totalFieldName});
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var result = response.getReturnValue();
                component.set("v.totalAmountObj", result);
                component.set("v.totalAmount", result.totalSum);
            }
            component.set('v.spinner', false);
        });
        $A.enqueueAction(action);
    },
    
    handleTotalComparison : function(component, event, helper){
        var totalAmount = component.get("v.totalAmount");
        var totalComparisonAmount = component.get("v.totalAmountComparisonValue");
        var totalMatched = (totalAmount == totalComparisonAmount) ? true : false;
        component.set("v.doesTotalMatch", totalMatched);
    }
})