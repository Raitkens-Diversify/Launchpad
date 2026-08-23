({
    doInit : function(component, event, helper) {
        var objData = {};
        var ObjDataList = [];
        
        var fieldsWithDatatypes = component.get("v.fieldsWithDataTypes"); 
        
        component.set("v.listvalue", objData);
        //component.set("v.objectList", ObjDataList); 
        
        if(component.get('v.varhouseholdId') && component.get('v.sObjectName') == 'Check_Deposit__c'){
            component.set('v.conditionFieldName', 'FinServ__Household__c');
            component.set('v.conditionFieldValue', component.get('v.varhouseholdId'));
        }
    },
    
    deleteForm : function(component, event, helper) {
        var fieldList=[];
        var fieldswithDataTypes=component.get("v.fieldsWithDataTypes");
        fieldswithDataTypes.forEach(field => {
            fieldList.push(field['fieldName']);
        });
            var field=fieldList[0];
            var appEvent = $A.get("e.c:dynamicFormEvent");
            appEvent.setParams({
            "indexToDelete" : component.get("v.index")-1
        });
        appEvent.fire();
        
    },
    
    handleChange : function(component, event, helper) {
        var objData = component.get("v.listvalue");
     
        if( event.getName()== 'change'){
            var index;
            var fieldType = event.target.getAttribute('data-fieldType');
            var value;
            if(fieldType === "REFERENCE"){
                index = event.target.getAttribute('name')
                value = component.get("v.temp");
            } else {
                index = event.getSource().get("v.name");
                value = event.getSource().get('v.value');
            }
            objData[index] = value;
        }
        if(event.getName() == 'customObjectLookupChange'){
            var index=event.getSource().get('v.parentFieldName');
            objData[index] = event.getSource().get('v.selectRecordId');
        }
        component.set("v.listvalue" ,objData);
        //Logic for Initial Funding Amount and Initial Funding Percentage 
         var fieldName = event.getSource().get("v.name");

         if(fieldName == 'Initial_Funding_Percentage__c' || fieldName == 'Initial_Funding_Amount__c'){
           var fieldsWithDataTypes= component.get("v.fieldsWithDataTypes");
           var initialFundingAmount;
           var initialFundingPercentage;
             for (let i = 0; i < fieldsWithDataTypes.length; i++) 
            	{
             		if(fieldsWithDataTypes[i].fieldName == 'Initial_Funding_Amount__c'){
                          initialFundingAmount = fieldsWithDataTypes[i].fieldValue
             		}
               		else if(fieldsWithDataTypes[i].fieldName == 'Initial_Funding_Percentage__c'){
                          initialFundingPercentage = fieldsWithDataTypes[i].fieldValue
             		}
                }    
             for (let i = 0; i < fieldsWithDataTypes.length; i++) 
            	{let totalInitialFundingAmount = component.get("v.totalInitialFundingAmount"); 
             		if(fieldsWithDataTypes[i].fieldName == 'Initial_Funding_Amount__c' && fieldName == 'Initial_Funding_Percentage__c'){
                       fieldsWithDataTypes[i].fieldValue =   totalInitialFundingAmount * initialFundingPercentage / 100;
             			objData[fieldsWithDataTypes[i].fieldName] = fieldsWithDataTypes[i].fieldValue;
                    }
               		else if(fieldsWithDataTypes[i].fieldName == 'Initial_Funding_Percentage__c' && fieldName == 'Initial_Funding_Amount__c'){
                        fieldsWithDataTypes[i].fieldValue =  initialFundingAmount/totalInitialFundingAmount * 100;
             	        objData[fieldsWithDataTypes[i].fieldName] = fieldsWithDataTypes[i].fieldValue;
                    }
                }
      		component.set("v.fieldsWithDataTypes",fieldsWithDataTypes);
        }   
        component.set("v.listvalue" ,objData);
        var appEvent=$A.get("e.c:dynamicFormAddRowEvent");
        appEvent.setParams({
            "indexChanged":component.get("v.index")-1
        });
        appEvent.fire();
    },
    
    saveForm : function(component,event,helper) {
        var listValue= JSON.parse(JSON.stringify(component.get("v.listvalue")));
        if(listValue.hasOwnProperty('Strategy__c')){
            listValue['Strategy__c']=component.find('referenceId').get('v.selectRecordId');
        }
        component.set("v.listvalue",listValue);
        
        var appEvent = $A.get("e.c:dynamicFormChangeEvent");
        appEvent.setParams({
            "indexChanged" : component.get("v.index")-1
        });
        appEvent.fire();
    },
    
    editForm:function (component,event,helper) {
        component.set("v.disabled",false);
        var saveIcon=component.find('saveIcon');
        $A.util.removeClass(saveIcon,'disablePointer');
        /*if(component.get('v.varhouseholdId') && component.get('v.sObjectName') == 'Check_Deposit__c'){
            var appEventLookupfield=$A.get("e.c:DisableRowForCustomObjectListLookup");
            appEventLookupfield.setParams(({"disabled":false,
                                            "index":component.get("v.index")}));
            appEventLookupfield.fire();
        }*/
    },
    
    enableRows : function(component, event, helper) {
        var fieldList = [];
        var fieldswithDataTypes = component.get("v.fieldsWithDataTypes");
        fieldswithDataTypes.forEach(field => {
            fieldList.push(field['fieldName']);
        });
        try{
            var currIndex = component.get("v.index");
            var index = parseInt(event.getParam("index"))+1;
            var saved = event.getParam("saved");
            var field = event.getParam("field");
            var fieldapi = field.apiname;
            if(component.get("v.index") == index && fieldList.includes(field)){
            component.set("v.disabled", saved);
            component.set("v.isCreated", event.getParam("isCreated"));
            if(saved){
            var saveIcon = component.find('saveIcon');
            $A.util.addClass(saveIcon, 'disablePointer');
        	}}	
        } catch(err) {
            console.log('disabled error');
        } 
	},
})