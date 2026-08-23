({
	handleClick : function (component, event, helper) {
        
        var buttonText = component.get("v.ButtonText");
        console.log('button: ' + buttonText);
        component.set("v.ValueClicked", buttonText);
            var navigate = component.get('v.navigateFlow');
      		navigate("NEXT");

    },
    
    handlePauseClick : function (component, event, helper) {
        
        var buttonText = component.get("v.ButtonText");
        console.log('button: ' + buttonText);
        component.set("v.ValueClicked", buttonText);
            var navigate = component.get('v.navigateFlow');
      		navigate("PAUSE");

    },
    
    handleLinkClick : function (component, event, helper) {
        var buttonURL = component.get("v.ValueClicked");
        console.log('link: ' + buttonURL)
        window.open(buttonURL, '_blank');
    },
    
	doInit : function (component, event, helper) {
        var size = component.get("v.Size");
        var type = component.get("v.ButtonType");
        if(type != 'Link'){
            if(size == 'Large'){
                if(type == 'Blank Button'){
                    component.set("v.Class", "blankButton");
                } else if(type == 'Inactive Button'){
                    component.set("v.Class", "largeButtonInactive");
                }else {
                    component.set("v.Class", "largeButton");
                }
            } else if(size == 'Medium'){
                component.set("v.Class", "mediumButton");
            } else if(size == 'Small'){
                component.set("v.Class", "smallButton");
            }
        } else {
            component.set("v.Class", "linkButton");
        }
    }
})