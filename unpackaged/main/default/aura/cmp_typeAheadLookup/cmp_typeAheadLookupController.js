({  
    doInit: function(component, event, helper) {
        helper.fetchPickListVal(component);
        component.set("v.isWorking", false);
    },
    
    scriptsLoaded : function(component, event, helper) {
        setTimeout(function() { waitJquery(); }, 2000);
        function waitJquery(){
            $(".select2Class").select2({
                placeholder: "Select multiple values"
            });
            
            $(".select2Class").on("select2:select", function (evt) {
                var element = evt.params.data.element;
                var $element = $(element);
                
                $element.detach();
                $(this).append($element);
                $(this).trigger("change");
            });
            
            var pkId = component.get("v.picklistId");
            var roleVal = component.get("v.roleValue");
            if(roleVal != "" && roleVal != null){
                $('#'+pkId).val(roleVal.split(";")).trigger('change');
            }
            $('#'+pkId).on("select2:select", function(event) { 
                var selectedSkills = $('[id$=' + pkId + ']').select2("val");
                if(selectedSkills != null){
                    var roleVal = selectedSkills.toString();
                    component.set("v.roleValue", roleVal);
                }
            }).trigger('change');
            
            $('#'+pkId).on("select2:unselect", function(e){
                var selectedSkills = $('[id$=' + pkId + ']').select2("val");
                if(selectedSkills != null){
                    var roleVal = selectedSkills.toString();
                    component.set("v.roleValue", roleVal);
                } else {
                    component.set("v.roleValue", "");
                }
            }).trigger('change');
        }
    },
    
    childSave : function(component,event,helper){
        var pkId = component.get("v.picklistId");
        var selectedSkills = $('[id$=' + pkId + ']').select2("val");
        if(selectedSkills != null){
            var roleVal = selectedSkills.toString();
            component.set("v.roleValue", roleVal);
        }
    } 
})