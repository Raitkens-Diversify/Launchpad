@isTest
public class EmailTemplateHelperTest {
    
    @testSetup
    private static void setup(){
        
        List<User> users  = [Select Id from User];
        
        Account finservHousehold = new Account(Name = 'Finserv Account', Classification__c = 'Unclassified');
        insert finservHousehold;
        
        Contact con = new Contact(FirstName = 'John' , LastName = 'Kovlan');
        insert con;
        //Advisor_Group__c testgroup = new Advisor_Group__c( Name = 'Test Advisor Group' );
		//Insert testgroup;
        Financial_Advisor_Team__c fat = new Financial_Advisor_Team__c(Name = 'Financial Advisor', /*Advisor_Group__c  = testGroup.Id, */Primary_Financial_Advisor__c = users[0].Id);
        
        Instruction__c instruction = new Instruction__c(Recurring_Amount__c = 4, Direction__c = 'In', Method__c = 'Wire');
        insert instruction;
        
        Outside_Manager__c outsideManager = new Outside_Manager__c(Name = 'John Kartis'); 
        insert outsideManager;
        
        Case c = new Case();
        c.Amount__c = 3;
        c.Reimbursement_Reason__c = 'xyz';
        c.Financial_Advisor_Team__c = faT.Id;
        c.ContactId = con.Id;
        c.Name_of_Charity__c = 'Test Charity';
        c.Recurring_Transfer_Frequency__c = 'Monthly';
        c.Money_Movement_Direction__c = 'In';
        c.Money_Type__c = 'Wire';
        c.TIN__c = 'Tin';
        c.Reason_for_the_Trade__c = 'Dummy Reason';
        c.Instruction__c = instruction.Id;
        c.Cancel_Effective_Date__c = date.Today();
        c.Federal_Withholding__c = 3;
        c.State_Withholding__c = 4;
        c.FinServ__Household__c = finservHousehold.Id;
        c.Previous_Management_Style__c = 'mstyle';
        c.Management_Style__c = 'DMS';
        c.Outside_Manager__c = outsideManager.Id;
        c.Custodian__c = 'custodian';
        
        insert c; 
    }
    
    @IsTest
    private static void test(){
        EmailTemplate et = new EmailTemplate();
        et.Body = 'Hello [!Case.Contact.FirstName] [!Case.Contact.LastName],I hope this email finds you well. I am reaching out with a confirmation that your donation of [!Case.Amount__c] has been initiated to [!Case.Name_of_Charity__c]. We expect the funds to arrive within **X** business days. Please do not hesitate to reach out with any follow up questions.Sincerely,';
        et.DeveloperName ='Test_Email';
        et.Subject = 'Test';
        et.Name = 'Test';
        et.templatetype = 'custom';
        et.FolderId = UserInfo.getUserId();
        insert et;
        
        List<User> primaryAdvisor  = [Select Id from User];
        Case newCase = [SELECT Id from case LIMIT 1];
        Test.Starttest();
        String emailTemplateText = EmailTemplateHelper.getEmailTemplateText('Test_Email',newCase.Id,primaryAdvisor[0].Id);
        Test.Stoptest();        
        Assert.areNotEqual('', emailTemplateText);
    }  
    
}