public with sharing class KS_GetStateByPostalCode {

    public class Request {
        @InvocableVariable(label='Country Code' required=true)
        public String countryCode;

        @InvocableVariable(label='Postal Code' required=true)
        public String postalCode;
    }

    public class Response {
        @InvocableVariable(label='State Code')
        public String stateCode;

        @InvocableVariable(label='Region')
        public String region;
    }

    @InvocableMethod(
        label='Get State Code by Postal Code Range'
        description='Returns the State Code for a given Country and Postal Code based on KS_PostalCodeStateMap__mdt ranges. Returns null if no match is found.'
        category='Custom'
    )
    public static List<Response> getStateCode(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();
            KS_PostalCodeStateMap__mdt record = resolveRecord(req.countryCode, req.postalCode);
            if (record != null) {
                res.stateCode = record.KS_StateCode__c;
                res.region = record.KS_Region__c;
            }
            responses.add(res);
        }

        return responses;
    }

    private static KS_PostalCodeStateMap__mdt resolveRecord(String countryCode, String postalCode) {
        if (String.isBlank(countryCode) || String.isBlank(postalCode)) {
            return null;
        }

        List<KS_PostalCodeStateMap__mdt> records = [
            SELECT KS_StateCode__c, KS_Region__c
            FROM KS_PostalCodeStateMap__mdt
            WHERE KS_CountryCode__c = :countryCode
                AND KS_PostalCodeStart__c <= :postalCode
                AND KS_PostalCodeEnd__c >= :postalCode
            LIMIT 1
        ];

        return records.isEmpty() ? null : records[0];
    }
}