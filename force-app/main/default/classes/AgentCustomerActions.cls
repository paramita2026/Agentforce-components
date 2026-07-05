/**
 * AgentCustomerActions
 *
 * Returns a customer's (Contact) details as an Apex-defined DTO (and JSON) for reliable
 * serialization in Agentforce/Flow action contexts.
 *
 * Bulk model:
 * This is intentionally a "singleton" action: we only consider requests[0] and return
 * a single Response row.
 */
public with sharing class AgentCustomerActions {
    public class Request {
        @InvocableVariable(
            label='Verified Customer Id'
            description='The Contact Id for the verified customer whose details should be returned.'
            required=false
        )
        public String verifiedCustomerId;

        @InvocableVariable(
            label='Customer Email'
            description='The customer email address (Contact.Email). Provide this when you don’t have the record Id. Either verifiedCustomerId or customerEmail is required.'
            required=false
        )
        public String customerEmail;
    }

    public class CustomerDetails {
        @InvocableVariable(label='Customer Id' description='The Contact record Id.')
        public String id;

        @InvocableVariable(label='Account Id' description='The Account Id associated with this customer (Contact.AccountId).')
        public String accountId;

        @InvocableVariable(label='First Name' description='Customer first name (Contact.FirstName).')
        public String firstName;

        @InvocableVariable(label='Last Name' description='Customer last name (Contact.LastName).')
        public String lastName;

        @InvocableVariable(label='Email' description='Customer email address (Contact.Email).')
        public String email;

        @InvocableVariable(label='Phone Number' description='Customer phone number (Contact.Phone).')
        public String phoneNumber;

        @InvocableVariable(
            label='Contact Status'
            description='Customer status. If your org has a custom status field on Contact, this action will attempt to populate it from one of these fields (first match wins): Status__c, Contact_Status__c, Customer_Status__c. Otherwise this value is null.'
        )
        public String contactStatus;

        @InvocableVariable(
            label='Level'
            description='Customer level/tier (for example: Gold/Silver). This action will attempt to populate it from Level__c or Customer_Level__c if present; otherwise null.'
        )
        public String level;

        @InvocableVariable(
            label='Favourite Cuisine'
            description='Customer favourite cuisine preference. This action will attempt to populate it from Favourite_Cuisine__c, Favorite_Cuisine__c, FavouriteCuisine__c, or FavoriteCuisine__c if present; otherwise null.'
        )
        public String favouriteCuisine;
    }

    public class Response {
        @InvocableVariable(
            label='Success'
            description='True when the action executed successfully. False when inputs are missing/invalid or an unexpected error occurred.'
        )
        public Boolean success;

        @InvocableVariable(
            label='Found'
            description='True when a Contact record was found for the provided verifiedCustomerId.'
        )
        public Boolean found;

        @InvocableVariable(
            label='Message'
            description='User-readable status message. On errors, explains what was missing or what failed.'
        )
        public String message;

        @InvocableVariable(
            label='Account Id'
            description='The Account Id associated with this customer. Use this for subsequent actions that require account validation.'
        )
        public String accountId;

        @InvocableVariable(
            label='Verified Customer Id'
            description='The Contact Id for the verified customer. Use this for subsequent actions that require a Contact Id.'
        )
        public String verifiedCustomerId;

        @InvocableVariable(
            label='First Name'
            description='Customer first name (Contact.FirstName). Duplicated as a top-level string output for easy Flow mapping.'
        )
        public String firstName;

        @InvocableVariable(
            label='Last Name'
            description='Customer last name (Contact.LastName). Duplicated as a top-level string output for easy Flow mapping.'
        )
        public String lastName;

        @InvocableVariable(
            label='Customer'
            description='Customer (Contact) details. Null when found=false or on error.'
        )
        public CustomerDetails customer;

        @InvocableVariable(
            label='Customer JSON'
            description='JSON-serialized version of customer for clients that prefer JSON parsing. This is "null" when customer is null.'
        )
        public String customerJson;
    }

    @InvocableMethod(
        label='Get Customer Profile'
        description='Get a verified customer’s profile (Contact) by Id and return a DTO/JSON for reliable serialization.'
    )
    public static List<Response> invoke(List<Request> requests) {
        Response out = new Response();
        out.success = false;
        out.found = false;
        out.message = null;
        out.accountId = null;
        out.verifiedCustomerId = null;
        out.firstName = null;
        out.lastName = null;
        out.customer = null;
        out.customerJson = null;

        Request req = (requests != null && !requests.isEmpty()) ? requests[0] : null;

        try {
            if (req == null) {
                out.message = 'A request is required.';
                return new List<Response>{ out };
            }

            Boolean hasId = String.isNotBlank(req.verifiedCustomerId);
            Boolean hasEmail = !String.isBlank(req.customerEmail);
            if (!hasId && !hasEmail) {
                out.message = 'Either verifiedCustomerId or customerEmail is required.';
                return new List<Response>{ out };
            }

            Map<String, Schema.SObjectField> fieldMap = Contact.SObjectType.getDescribe().fields.getMap();
            List<String> fieldsToQuery = new List<String>{ 'Id', 'AccountId', 'FirstName', 'LastName', 'Email', 'Phone' };

            List<String> statusCandidates = new List<String>{ 'Status__c', 'Contact_Status__c', 'Customer_Status__c' };
            List<String> levelCandidates = new List<String>{ 'Level__c', 'Customer_Level__c' };
            List<String> cuisineCandidates = new List<String>{ 'Favourite_Cuisine__c', 'Favorite_Cuisine__c', 'FavouriteCuisine__c', 'FavoriteCuisine__c' };

            for (String f : statusCandidates) if (fieldMap.containsKey(f)) { fieldsToQuery.add(f); break; }
            for (String f : levelCandidates) if (fieldMap.containsKey(f)) { fieldsToQuery.add(f); break; }
            for (String f : cuisineCandidates) if (fieldMap.containsKey(f)) { fieldsToQuery.add(f); break; }

            Id custId = hasId ? Id.valueOf(req.verifiedCustomerId.trim()) : null;
            String email = hasEmail ? req.customerEmail.trim() : null;

            String whereClause;
            if (hasId && hasEmail) whereClause = 'Id = :custId AND Email = :email';
            else if (hasId) whereClause = 'Id = :custId';
            else whereClause = 'Email = :email';

            String soql = 'SELECT ' + String.join(fieldsToQuery, ',') + ' FROM Contact WHERE ' + whereClause + ' LIMIT 1';
            List<SObject> contacts = Database.query(soql);

            if (contacts.isEmpty()) {
                out.success = true;
                out.found = false;
                out.message = hasId
                    ? (hasEmail ? 'No customer found matching that verifiedCustomerId + customerEmail.' : 'No customer found for the provided verifiedCustomerId.')
                    : 'No customer found for the provided customerEmail.';
                return new List<Response>{ out };
            }

            SObject c = contacts[0];
            CustomerDetails d = new CustomerDetails();
            d.id = (Id) c.get('Id');
            d.accountId = (Id) c.get('AccountId');
            d.firstName = (String) c.get('FirstName');
            d.lastName = (String) c.get('LastName');
            d.email = (String) c.get('Email');
            d.phoneNumber = (String) c.get('Phone');

            d.contactStatus = null;
            for (String f : statusCandidates) {
                if (fieldMap.containsKey(f) && fieldsToQuery.contains(f)) {
                    Object v = c.get(f);
                    d.contactStatus = (v == null) ? null : String.valueOf(v);
                    break;
                }
            }

            d.level = null;
            for (String f : levelCandidates) {
                if (fieldMap.containsKey(f) && fieldsToQuery.contains(f)) {
                    Object v = c.get(f);
                    d.level = (v == null) ? null : String.valueOf(v);
                    break;
                }
            }

            d.favouriteCuisine = null;
            for (String f : cuisineCandidates) {
                if (fieldMap.containsKey(f) && fieldsToQuery.contains(f)) {
                    Object v = c.get(f);
                    d.favouriteCuisine = (v == null) ? null : String.valueOf(v);
                    break;
                }
            }

            out.customer = d;
            out.customerJson = JSON.serialize(d);
            out.accountId = d.accountId;
            out.verifiedCustomerId = d.id;
            out.firstName = d.firstName;
            out.lastName = d.lastName;
            out.success = true;
            out.found = true;
            out.message = 'OK';
        } catch (Exception e) {
            out.success = false;
            out.found = false;
            out.message = e.getMessage();
        }

        return new List<Response>{ out };
    }
}