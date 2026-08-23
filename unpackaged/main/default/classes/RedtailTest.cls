@isTest
private class RedtailTest {

    @isTest
    static void testCreatingContactData() {

            Redtail.ContactWrapper contactWrapper = new Redtail.ContactWrapper();
            contactWrapper.contact = new Redtail.ContactData();

            contactWrapper.contact.id = '2';
            contactWrapper.contact.first_name = 'Margaret';
            contactWrapper.contact.middle_name = 'Anne';
            contactWrapper.contact.last_name = 'Smith';
            contactWrapper.contact.full_name = 'Margaret Smith';
            contactWrapper.contact.dob = '1983-04-12';
            contactWrapper.contact.employer = 'Investor & Investor';
            contactWrapper.contact.employer_id = 65340;
            contactWrapper.contact.designation = '';
            contactWrapper.contact.tax_id = '123-45-6789';
            contactWrapper.contact.job_title = 'Investor';

            contactWrapper.contact.important_information = new Redtail.ImportantInformation();
            contactWrapper.contact.important_information.id = 1;
            contactWrapper.contact.important_information.content = '<b>She prefers to be called Mary.</b><br><b><i>Do not call after 7:00PM</i></b><br><br>';
            contactWrapper.contact.important_information.created_at = '2015-01-07T01:33:43.000Z';
            contactWrapper.contact.important_information.updated_at = '2015-01-07T02:42:39.000Z';

            contactWrapper.contact.addresses = new List<Redtail.Address>();
            Redtail.Address address = new Redtail.Address();
            address.id = 2;
            address.addressable_id = 1;
            address.addressable_type = 'Crm::Contact';
            address.street_address = '1234 Main St.';
            address.secondary_address = '';
            address.city = 'Sacramento';
            address.state = 'CA';
            address.zip = '99320';
            address.country = 'US';
            address.address_type = 1;
            address.description = '';
            address.is_primary = true;
            address.is_preferred = false;
            address.deleted = false;
            address.created_at = '2015-01-07T03:44:59.000Z';
            address.updated_at = '2015-01-07T03:48:04.000Z';
            contactWrapper.contact.addresses.add(address);
            address = new Redtail.Address();
            address.id = 2;
            address.addressable_id = 1;
            address.addressable_type = 'Crm::Contact';
            address.street_address = '123 Main St.';
            address.secondary_address = '';
            address.city = 'Lafayette';
            address.state = 'LA';
            address.zip = '70508';
            address.country = 'US';
            address.address_type = 3;
            address.description = '';
            address.is_primary = true;
            address.is_preferred = false;
            address.deleted = false;
            address.created_at = '2015-01-07T03:44:59.000Z';
            address.updated_at = '2015-01-07T03:48:04.000Z';
            contactWrapper.contact.addresses.add(address);

            contactWrapper.contact.phones = new List<Redtail.Phone>();
            Redtail.Phone phone = new Redtail.Phone();
            phone.id = 5;
            phone.numberValue = '5559815634';
            phone.extension = '';
            phone.is_primary = true;
            phone.phone_type = 1;
            phone.phone_type_description = 'Home';
            phone.description = '';
            phone.deleted = false;
            phone.created_at = '2015-01-07T03:40:32.000Z';
            phone.updated_at = '2015-01-07T03:40:32.000Z';
            contactWrapper.contact.phones.add(phone);

            contactWrapper.contact.emails = new List<Redtail.Email>();
            Redtail.Email email = new Redtail.Email();
            email.id = 5;
            email.emailable_id = 1;
            email.emailable_type = 'Crm::Contact';
            email.address = 'minvestor21@yahoo.com';
            email.email_type = 3;
            email.email_type_description = 'Other';
            email.custom_type_title = 'Personal Email';
            email.description = '';
            email.is_primary = true;
            email.is_preferred = false;
            email.deleted = false;
            email.created_at = '2015-01-07T03:42:22.000Z';
            email.updated_at = '2015-01-07T03:42:22.000Z';
            contactWrapper.contact.emails.add(email);

        Test.startTest();

            contactWrapper = RedTail.parse(JSON.serialize(contactWrapper));

            Assert.areNotEqual(null, contactWrapper, 'There should be a Contact Wrapper');

        Test.stopTest();
    }
}