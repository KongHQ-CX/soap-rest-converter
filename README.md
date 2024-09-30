# Kong plugins: SOAP to Rest Converter Plugin

</br></br>
<img src="/images/Pipeline-Kong-soap-rest-converter.png?raw=true" alt="Kong - Manager">
</br></br>

This repository concerns Kong plugins developed in Lua and uses the GNOME C libraries [libxml2](https://gitlab.gnome.org/GNOME/libxml2#libxml2). Part of the functions are bound in the [XMLua/libxml2](https://clear-code.github.io/xmlua/) library.
Both GNOME C and XMLua/libxml2 libraries are already included in [kong/kong-gateway](https://hub.docker.com/r/kong/kong-gateway) Enterprise Edition Docker image, so you don't need to rebuild a Kong image.

The XSLT Transformation is managed with the [saxon](https://www.saxonica.com/html/welcome/welcome.html) library, which supports XSLT 2.0 and 3.0. With XSLT 2.0+ there is a way for applying JSON <-> XML transformation with [fn:json-to-xml](https://www.w3.org/TR/xslt-30/#func-json-to-xml) and [fn:xml-to-json](https://www.w3.org/TR/xslt-30/#func-xml-to-json). The saxon library is not included in the Kong Docker image, see [SAXON.md](SAXON.md) for how to integrate saxon with Kong.

This plugins doesn't apply to Kong OSS. It works for Kong EE and Konnect.

The plugin handle the **Soap to Rest**  and the **Rest to Soap** conversion:

**soap-2-rest**:

1) `XSLT TRANSFORMATION - BEFORE XSD`: Transform the XML request with XSLT (XSLTransformation) before step #2
2) `AUTH TRANSFER`: Retrieve and pass the authentication
3) `XSLT TRANSFORMATION - AFTER XSD`: Transform the XML request with XSLT (XSLTransformation) after step #2
4) `ERROR CHEKCING`: check the error depending of XPath

**rest-2-soap**:

1) `XSLT TRANSFORMATION - BEFORE XSD`: Transform the XML request with XSLT (XSLTransformation) before step #2
2) `AUTH TRANSFER`: Retrieve and pass the authentication
3) `XSLT TRANSFORMATION - AFTER XSD`: Transform the XML request with XSLT (XSLTransformation) after step #2
4) `ERROR CHEKCING`: check the error depending of XPath

Each handling is optional. In case of misconfiguration the Plugin sends to the consumer an HTTP 500 Internal Server Error `<soap:Fault>` (with the error detailed message).

</br></br>

## configuration reference
|FORM PARAMETER                 |REQUIRE          |DEFAULT          |DESCRIPTION                                                 |
|:------------------------------|:----------------|:----------------|:-----------------------------------------------------------|
|config.xsltTransformRequest|TRUE|N/A|`XSLT` template used by `Saxon` to tranform the request|
|config.xsltTransformResponse|TRUE|N/A|`XSLT` emplate used by `Saxon` to tranform the response|
|config.RequestAuthorizationLocation|FALSE|N/A|The location to extract the credentials, either xPath or Header|
|config.RequestAuthorizationHeader|FALSE|Authorization|The header location used to extract the credentials only when RequestAuthorizationLocation is Header|
|config.RequestAuthorizationXPath|FALSE|N/A|The xPath location used to extract the credentials only when RequestAuthorizationLocation is xPath|
|config.ResponseAuthorizationLocation|FALSE|N/A|The location to send the credentials, either xsltTemplate or Header|
|config.ResponseAuthorizationHeader|FALSE|Authorization|The header location used to send the credentials only when ResponseAuthorizationLocation is Header|
|config.FailIfAuthError|FALSE|N/A|Stop the request if an error occured during the authentication extraction and sending|
|config.ExternalDataCacheTTL|FALSE|300|The TTL in seconds to keep the xstl template in cache|
|config.ExternalDataTimeout|FALSE|300|The timeout in second for the request retrieving the xstl template|
|config.ErrorXPath|FALSE|N/A|The xPath to check if soap request is returning an error even with status code 200|
|config.RouteXPathRegisterNs|FALSE|N/A|Register Namespace to enable XPath request. The syntax is `name,namespace`. Mulitple entries are allowed (example: `name1,namespace1,name2,namespace2`)|
|config.VerboseError|FALSE|N/A|enable a detailed error message sent to the consumer. The syntax is `<detail>...</detail>` in the `<soap:Fault>` message|


## How to deploy SOAP/XML Handling plugins in Kong Gateway (standalone) | Docker
1) Do a Git Clone of this repo
```sh
git clone https://github.com/jeromeguillaume/kong-plugin-soap-xml-handling.git
```

2) Create and prepare a PostgreDB called `kong-gateway-soap-xml-handling`.
[See documentation](https://docs.konghq.com/gateway/latest/install/docker/#prepare-the-database)

3) Provision a license of Kong Enterprise Edition and put the content in `KONG_LICENSE_DATA` environment variable. The following license is only an example. You must use the following format, but provide your own content
```sh
 export KONG_LICENSE_DATA='{"license":{"payload":{"admin_seats":"1","customer":"Example Company, Inc","dataplanes":"1","license_creation_date":"2023-04-07","license_expiration_date":"2023-04-07","license_key":"00141000017ODj3AAG_a1V41000004wT0OEAU","product_subscription":"Konnect Enterprise","support_plan":"None"},"signature":"6985968131533a967fcc721244a979948b1066967f1e9cd65dbd8eeabe060fc32d894a2945f5e4a03c1cd2198c74e058ac63d28b045c2f1fcec95877bd790e1b","version":"1"}}'
```

4) Start the standalone Kong Gateway
```sh
./start-kong.sh
```

5) Check that the plugin is present
<img src="/images/Kong-Manager.png?raw=true" alt="Kong - Manager" width="400px">


## Other Deployements
Please [See documentation here](https://github.com/jeromeguillaume/kong-plugin-soap-xml-handling/tree/main?tab=readme-ov-file#how-to-deploy-soapxml-handling-plugins-schema-in-konnect-control-plane-for-kong-gateway)


## Example: REST TO SOAP | `XSLT 3.0 TRANSFORMATION` with the `saxon` library: JSON to SOAP/XML transformation

### Configure and test a `calculator` SOAP Web Service in Kong Gateway
1) Create a Kong Gateway Service named `calculator` with this URL: http://www.dneonline.com:80/calculator.asmx.
This simple backend Web Service adds or subtracts 2 numbers.

2) Create a Route on the Service `calculator` with the `path` value `/calculator`

3) Call the `calculator` through the Kong Gateway Route by using [httpie](https://httpie.io/) tool
```
http POST http://localhost:8000/calculator \
Content-Type:"text/xml; charset=utf-8" \
--raw '<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <Add xmlns="http://tempuri.org/">
      <intA>5</intA>
      <intB>7</intB>
    </Add>
  </soap:Body>
</soap:Envelope>'
```

The expected result is `12`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ...>
  <soap:Body>
    <AddResponse xmlns="http://tempuri.org/">
      <AddResult>12</AddResult>
    </AddResponse>
  </soap:Body>
</soap:Envelope>
```

### Configure the `SOAP REST Converter` plugin in Kong Gateway

Call the `calculator` web service by sending a `JSON` request.
The `soap-rest-converter` is in charge of transforming the JSON request to a SOAP/XML request by applying an XSLT 3.0 transformation. After the response is received, the plugin is in charge of doing the opposite, that's to say transforming the SOAP/XML response to JSON.

1) Add `soap-rest-converter` plugin to `calculator` and configure the plugin with:
- `VerboseRequest` enabled
- `XsltTransformRequest` property with the url `https://raw.githubusercontent.com/KongHQ-CX/soap-rest-converter/refs/heads/main/examples/calculator-json-to-xml` hosting the `XSLT 3.0` definition to convert the json to xml
- `XsltTransformResponse` property with the url `https://raw.githubusercontent.com/KongHQ-CX/soap-rest-converter/refs/heads/main/examples/calculator-xml-to-json` hosting the `XSLT 3.0` definition to convert the xml to json

5) Call the `calculator` through the Kong Gateway Route,  with a `JSON` request and by setting the operation to `Add`
```sh
http -v POST http://localhost:8000/calculator operation=Add intA:=50 intB:=10
```
```
Content-Type: application/json
...
```
```json
{
    "intA": 50,
    "intB": 10,
    "operation": "Add"
}
```
The expected `JSON` response is `60`:
```
HTTP/1.1 200 OK
Content-Type: application/json
...
```
```json
{
    "result": 60
}
```
You can change operation to the following values:
- `Subtract`
- `Divide`
- `Multiply`


## Example: SOAP TO REST | `XSLT 3.0 TRANSFORMATION` with the `saxon` library: SOAP/XML to JSON transformation

### Configure and test a `petstore` JSON Web Service in Kong Gateway
1) Create a Kong Gateway Service named `petstore` with this URL: https://petstore.swagger.io:443/v2/pet.
This simple Web Service mimicate a pet store.

2) Create a Route on the Service `petstore` with the `path` value `/petstore`

3) Call the `petstore` through the Kong Gateway Route by using [httpie](https://httpie.io/) tool
```
http POST http://localhost:8000/petstore \
Content-Type:"application/json; charset=utf-8" \
--raw '{
  "name": "doggie",
  "photoUrls": [
    "http://test.com/images"
  ],
  "status": "available"
}'
```

The expected result is:
```
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
...
```
```json
{
    "id": 9223372036854775807,
    "name": "doggie",
    "photoUrls": [
        "http://test.com/images"
    ],
    "status": "available",
    "tags": []
}
```

### Configure the `SOAP REST Converter` plugin in Kong Gateway

Call the `petstore` web service by sending a `XML` request.
The `soap-rest-converter` is in charge of transforming the SOAP/XML request to a JSON request by applying an XSLT 3.0 transformation. After the response is received, the plugin is in charge of doing the opposite, that's to say transforming the JSON to a SOAP/XML response.

1) Add `soap-rest-converter` plugin to `calculator` and configure the plugin with:
- `VerboseRequest` enabled
- `XsltTransformRequest` property with the url `https://raw.githubusercontent.com/KongHQ-CX/soap-rest-converter/refs/heads/main/examples/petstore-xml-to-json` hosting the `XSLT 3.0` definition to convert the json to xml
- `XsltTransformResponse` property with the url `https://raw.githubusercontent.com/KongHQ-CX/soap-rest-converter/refs/heads/main/examples/petstore-json-to-xml` hosting the `XSLT 3.0` definition to convert the xml to json

5) Call the `petstore` through the Kong Gateway Route,  with a `XML` request
```
http POST http://localhost:8000/petstore \
Content-Type:"text/xml; charset=utf-8" \
--raw '<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:pet="http://example.com/petstore">
   <soapenv:Header/>
   <soapenv:Body>
      <pet:AddPet>
         <pet:name>doggie</pet:name>
         <pet:photoUrls>
            <pet:url>http://test.com/images</pet:url>
         </pet:photoUrls>
         <pet:status>available</pet:status>
      </pet:AddPet>
   </soapenv:Body>
</soapenv:Envelope>'
```

The expected `XML` response is:

```
HTTP/1.1 200 OK
Content-Type: text/xml; charset=utf-8
...
```
```xml
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:pet="http://example.com/petstore">
   <soapenv:Header/>
   <soapenv:Body>
      <pet:AddPet>
         <pet:name>doggie</pet:name>
         <pet:photoUrls>
            <pet:url>http://test.com/images</pet:url>
         </pet:photoUrls>
         <pet:status>available</pet:status>
      </pet:AddPet>
   </soapenv:Body>
</soapenv:Envelope>
```

**More explanation on the xlst template and transformation could be found [here](/SAXON.md#behind-the-scenes-of-fnjson-to-xml-and-fnxml-to-json-functions)**

## Plugins Testing
The plugins testing is available through [pongo](https://github.com/Kong/kong-pongo)
1) Download pongo
2) Initialize pongo
3) Run tests with [pongo.sh](pongo.sh) and **adapt the `KONG_IMAGE` value** according to expectations

Note: If the Kong Docker image with `saxon` has been rebuilt, run a `pongo clean` for rebuilding the Pongo image

## Changelog
- v1.0.0:
  - Initial Release
