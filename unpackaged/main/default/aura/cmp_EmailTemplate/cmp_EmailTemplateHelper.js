({
	helperMethod : function() {
		
	},
    
    copyTextHelper : function(component,event,text) {
        var hiddenInput = document.createElement("textarea");
        // hiddenInput.setAttribute("value", text);
        hiddenInput.innerHTML = text;
        document.body.appendChild(hiddenInput);
        hiddenInput.select();
        // Executing the copy command
        document.execCommand("copy");
        document.body.removeChild(hiddenInput); 
        var orignalLabel = event.getSource().get("v.label");
        //To change Button Icon and label after text is copied
        event.getSource().set("v.iconName" , 'utility:check');
        event.getSource().set("v.label" , 'copied');
        
        //reset icon and button label value after 'n' milliseconds 
        setTimeout(function(){ 
            event.getSource().set("v.iconName" , 'utility:copy_to_clipboard'); 
            event.getSource().set("v.label" , orignalLabel);
        }, 1000);
        
    }
})