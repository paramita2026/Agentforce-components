/**
 * AgentStorefrontActions
 *
 * Why this exists:
 * Some invocation surfaces (notably certain "agent"/tooling integrations) have trouble
 * serializing Flow output variables when they are SObject *collections* — often returning
 * only Ids or empty field values even when the Flow queried fields correctly.
 *
 * This Apex action returns storefronts as Apex-defined DTOs (and a JSON string) which
 * serializes reliably across those surfaces.
 *
 * Bulk model:
 * This is intentionally a "singleton" action: we only consider requests[0] and return
 * a single Response row. (This matches how Agent/Flow action steps are commonly used.)
 */
public without sharing class AgentStorefrontActions {
    public class Request {
        @InvocableVariable(
            label='Storefront Name'
            description='Full or partial storefront name to search for. Matches Storefront__c.Name using a contains search.'
            required=true
        )
        public String storefrontName;
    }

    public class StorefrontSummary {
        @InvocableVariable(label='Storefront Id' description='The Storefront__c record Id.')
        public Id id;

        @InvocableVariable(label='Name' description='The storefront name (Storefront__c.Name).')
        public String name;

        @InvocableVariable(label='Account Id' description='Optional related Account Id (Storefront__c.Account__c).')
        public Id accountId;

        @InvocableVariable(label='Description' description='Storefront description (Storefront__c.Description__c).')
        public String description;

        @InvocableVariable(label='Cuisine' description='Cuisine type (Storefront__c.Cuisine__c).')
        public String cuisine;

        @InvocableVariable(label='Average Review Score' description='Average review score (Storefront__c.Average_Review_Score__c).')
        public Decimal averageReviewScore;
    }

    public class Response {
        @InvocableVariable(
            label='Success'
            description='True when the action executed successfully. False when inputs are missing/invalid or an unexpected error occurred.'
        )
        public Boolean success;

        @InvocableVariable(
            label='Message'
            description='User-readable status message. On errors, explains what was missing or what failed.'
        )
        public String message;

        @InvocableVariable(
            label='Storefronts'
            description='A list of storefront summaries matching the provided storefrontName.'
        )
        public List<StorefrontSummary> storefronts;

        @InvocableVariable(
            label='Storefronts JSON'
            description='JSON-serialized version of storefronts for clients that prefer to parse JSON.'
        )
        public String storefrontsJson;
    }

    @InvocableMethod(
        label='Get Storefronts By Name'
        description='Query Storefront__c by Name (contains) and return results as Apex-defined DTOs for reliable serialization.'
    )
    public static List<Response> invoke(List<Request> requests) {
        Response out = new Response();
        out.storefronts = new List<StorefrontSummary>();
        out.success = false;
        out.message = null;

        Request req = (requests != null && !requests.isEmpty()) ? requests[0] : null;
        String nameQuery = (req == null) ? null : req.storefrontName;

        try {
            if (String.isBlank(nameQuery)) {
                out.message = 'storefrontName is required.';
                out.storefrontsJson = JSON.serialize(out.storefronts);
                return new List<Response>{ out };
            }

            // Mirror the Flow behavior: Name CONTAINS <storefrontName>, ordered by Name ASC.
            List<Storefront__c> storefronts = [
                SELECT Id, Name, Account__c, Description__c, Cuisine__c, Average_Review_Score__c
                FROM Storefront__c
                WHERE Name LIKE :('%' + nameQuery + '%')
                ORDER BY Name ASC
                LIMIT 200
            ];

            for (Storefront__c sf : storefronts) {
                StorefrontSummary s = new StorefrontSummary();
                s.id = sf.Id;
                s.name = sf.Name;
                s.accountId = sf.Account__c;
                s.description = sf.Description__c;
                s.cuisine = sf.Cuisine__c;
                s.averageReviewScore = sf.Average_Review_Score__c;
                out.storefronts.add(s);
            }

            out.success = true;
            out.message = 'OK';
        } catch (Exception e) {
            out.success = false;
            out.message = e.getMessage();
        }

        out.storefrontsJson = JSON.serialize(out.storefronts);
        return new List<Response>{ out };
    }
}