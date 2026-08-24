@IsTest
private class KS_GetStateByPostalCodeTest {

    @IsTest
    static void returnsMatchingStateCode() {
        Test.startTest();
        List<KS_GetStateByPostalCode.Response> responses = KS_GetStateByPostalCode.getStateCode(
            new List<KS_GetStateByPostalCode.Request>{
                buildRequest('FR', '01000')
            }
        );
        Test.stopTest();

        System.assert(responses.size() == 1, 'Expected one response for a matching postal code.');
        System.assert(responses[0].stateCode == '01', 'Expected the matching state code to be returned.');
        System.assert(responses[0].region != null, 'Expected a region to be returned alongside the state code.');
    }

    @IsTest
    static void returnsNullWhenNoMatchExists() {
        Test.startTest();
        List<KS_GetStateByPostalCode.Response> responses = KS_GetStateByPostalCode.getStateCode(
            new List<KS_GetStateByPostalCode.Request>{
                buildRequest('FR', '00000')
            }
        );
        Test.stopTest();

        System.assert(responses.size() == 1, 'Expected one response when no match exists.');
        System.assert(responses[0].stateCode == null, 'Expected null when no matching range exists.');
        System.assert(responses[0].region == null, 'Expected null region when no matching range exists.');
    }

    @IsTest
    static void returnsNullForBlankInput() {
        Test.startTest();
        List<KS_GetStateByPostalCode.Response> responses = KS_GetStateByPostalCode.getStateCode(
            new List<KS_GetStateByPostalCode.Request>{
                buildRequest(null, '10001'),
                buildRequest('US', null)
            }
        );
        Test.stopTest();

        System.assert(responses.size() == 2, 'Expected both blank-input requests to return a response.');
        System.assert(responses[0].stateCode == null, 'Expected null for a blank country code.');
        System.assert(responses[1].stateCode == null, 'Expected null for a blank postal code.');
    }

    private static KS_GetStateByPostalCode.Request buildRequest(String countryCode, String postalCode) {
        KS_GetStateByPostalCode.Request request = new KS_GetStateByPostalCode.Request();
        request.countryCode = countryCode;
        request.postalCode = postalCode;
        return request;
    }
}