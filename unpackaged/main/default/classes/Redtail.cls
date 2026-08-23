public without sharing class Redtail {

    public static final String CONTACT_ENDPOINT = '/contacts/';
    public static final String REDTAIL_NUMBER = 'number';
    public static final String SF_NUMBER = 'numberValue';

    public class ContactWrapper {
        public ContactData contact;
    }

    public class ContactData {
		public String id;		//2
		public String first_name;	//Margaret
		public String middle_name;	//
		public String last_name;	//Smith
		public String full_name; //65340
		public String dob;	//1983-04-12
		public String employer;	//Investor & Investor
        public Integer employer_id;
		public String designation;	//
        public String tax_id;
        public String job_title;
		public ImportantInformation important_information;
		public Address[] addresses;
		public Phone[] phones;
		public Email[] emails;
	}
	public class ImportantInformation {
		public Integer id;	//1
		public String content;	//<b>She prefers to be called Mary.</b><br><b><i>Do not call after 7:00PM</i></b><br><br>
		public String created_at;	//2015-01-07T01:33:43.000Z
		public String updated_at;	//2015-01-07T02:42:39.000Z
	}
	public class Address {
		public Integer id;	//2
		public Integer addressable_id;	//1
		public String addressable_type;	//Crm::Contact
		public String street_address;	//1234 Main St.
		public String secondary_address;	//
		public String city;	//Sacramento
		public String state;	//CA
		public String zip;	//99320
		public String country;	//US
		public Integer address_type;	//1
		public String description;	//
		public boolean is_primary;
		public boolean is_preferred;
		public boolean deleted;
		public String created_at;	//2015-01-07T03:44:59.000Z
		public String updated_at;	//2015-01-07T03:48:04.000Z
	}
	public class Phone {
		public Integer id;	//5
		public String numberValue;	//5559815634
		public String extension;	//
        public Boolean is_primary;
		public Integer phone_type;	//1
		public String phone_type_description;	//Home
		public String description;	//
		public boolean deleted;
		public String created_at;	//2015-01-07T03:40:32.000Z
		public String updated_at;	//2015-01-07T03:40:32.000Z
	}
	public class Email {
		public Integer id;	//5
		public Integer emailable_id;	//1
		public String emailable_type;	//Crm::Contact
		public String address;	//minvestor21@yahoo.com
		public Integer email_type;	//3
		public String email_type_description;	//Other
		public String custom_type_title;	//Personal Email
		public String description;	//
		public boolean is_primary;
		public boolean is_preferred;
		public boolean deleted;
		public String created_at;	//2015-01-07T03:42:22.000Z
		public String updated_at;	//2015-01-07T03:42:22.000Z
	}
	public static ContactWrapper parse(String json){

        json = json.replaceAll('number', 'numberValue');

		return (ContactWrapper) System.JSON.deserialize(json, ContactWrapper.class);
	}
}