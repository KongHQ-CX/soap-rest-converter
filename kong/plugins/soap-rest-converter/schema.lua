
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "soap-rest-converter",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { xsltTransformRequest = { type = "string", required = true }, },
          { xsltTransformResponse = { type = "string", required = true }, },
          { RequestAuthorizationLocation = {required = false, type = "string", default = "none",
            one_of = {
              "none",
              "header",
              "xPath",
            },
          }},
          { RequestAuthorizationHeader = { type = "string", required = false, default = "Authorization" }, },
          { RequestAuthorizationXPath = { type = "array", required = false, elements = { type = "string" }}, },
          { ResponseAuthorizationLocation = {required = false, type = "string", default = "none",
            one_of = {
              "none",
              "header",
              "xPath",
            },
          }},
          { ResponseAuthorizationHeader = { type = "string", required = false, default = "Authorization" }, },
          { ResponseAuthorizationXPath = { type = "array", required = false, elements = { type = "string" }}, },
          { FailIfAuthError = { type = "boolean", required = false, default = false }, },
          { ExternalDataCacheTTL = { type = "integer", default = 300, required = false }, },
          { ExternalDataTimeout = { type = "integer", default = 2, required = false }, },
          { ErrorXPath = { type = "string", required = false }, },
          { XPathRegisterNs = { type = "array",  required = false, elements = {type = "string"}, default = {
            "soap,http://schemas.xmlsoap.org/soap/envelope",
            "soapenv,http://schemas.xmlsoap.org/soap/envelope",
            "wsse,http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
          }},},
          { VerboseError = { type = "boolean", required = false }, },
        },
    }, },
  },
}
