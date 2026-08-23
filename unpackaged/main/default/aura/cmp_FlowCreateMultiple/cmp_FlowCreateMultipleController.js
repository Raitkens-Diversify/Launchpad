({
    doInit : function(component, event, helper) {
        component.set("v.existingRecords", []);
        helper.init(component, event, helper);
    },
    
    handleDeleteForm: function(component, event, helper) {
        var index = event.getParam("indexToDelete");
        helper.deleteRecord(component, helper, index);
    },
    handleFormChange: function(component, event, helper) {
        component.set("v.spinner",true);
        var index = event.getParam("indexChanged");
        var forms = component.get("v.dynamicFormList");  
        var records = component.get("v.existingRecords");
        var fieldsWithDataTypes=component.get("v.fieldsWithDataTypes");
        var fieldHeaders=component.get("v.tableHeaderRecords");
       
        var missingFields=[];
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
                if(obj[key] == null || obj[key]=='')
                {
                    missingValue=true;
                    var fieldLabel=fieldsWithDataTypes.find(element => element.fieldName==key)
                    
                    missingFields.push(fieldLabel.label);
                }
            }
            
            records.splice(index,1,obj);
            component.set("v.existingRecords", records);
            
            if(!missingValue)
            {
                var pendingChanges = component.get("v.pendingChanges");
                pendingChanges[index] = obj;
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
                  message=message.slice(0,-2);
                component.set('v.spinner',false);
                helper.showToastEvent('warning','warning',message);
            }
        }
    },
    
    addRow:function(component, event, helper) {
      component.set("v.spinner",true);
        helper.addRowNew(component, event, helper);
       // helper.addRow(component, event, helper);
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
    handleClick:function(component, event, helper){
        debugger;
       var existingRecords=  component.get("v.existingRecords");
        var forms=component.get("v.dynamicFormList");
        var singleData;
        var disabled;
        var IdMissed='false';
        var objvalues;
        var MissedIdList=[];
        for(var i=0;i<existingRecords.length;i++){
            if(!existingRecords[i].hasOwnProperty('Id')){
                 objvalues=Object.values(existingRecords[i]);
                 IdMissed= objvalues.every(element => element===null || element==='') == true ? 'false' :'true';
               MissedIdList.push(IdMissed);
				                
            } else if(existingRecords[i].hasOwnProperty('Id')){
                disabled=JSON.parse(JSON.stringify(forms[i].get("v.disabled")));
                if(!disabled){
                   MissedIdList.push('true'); 
                }
            } 
           
        }
         if(MissedIdList.includes('true')){
                helper.showToastEvent('warning','warning','Please save records');
            }else {
                var navigate = component.get('v.navigateFlow');
                navigate("NEXT");
            }
    },
    handleAddRow:function(component, event, helper){
     
            debugger;
            var index = event.getParam("indexChanged");
            var forms = component.get("v.dynamicFormList");  
            var records = component.get("v.existingRecords");
            var lstRequiredFields = component.get("v.lstRequiredFields");
            var fieldNames=component.get("v.tableHeaderRecords");
            
            if(index<forms.length){
                var singleData = JSON.parse(JSON.stringify(forms[index].get("v.listvalue")));
                var obj = records[index];
                for(let key in singleData)
                {
                    obj[key] = singleData[key];
                }
                records.splice(index,1,obj);
                console.log(records);
                component.set("v.existingRecords", records);
            }
        }
        })