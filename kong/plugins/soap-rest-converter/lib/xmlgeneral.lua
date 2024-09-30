local xmlgeneral = {}

local cjson             = require("cjson")
local xmlua             = require("xmlua")
local ffi               = require("ffi")
local libxml2           = require("xmlua.libxml2")
local libsaxon4kong     = require("kong.plugins.soap-rest-converter.lib.libsaxon4kong")
local base64     = require "kong.openid-connect.codec".base64

xmlgeneral.HTTPCodeSOAPFault = 500

xmlgeneral.RequestTextError   = "Request"
xmlgeneral.ResponseTextError  = "Response"
xmlgeneral.GeneralError       = "General process failed"
xmlgeneral.SepTextError       = " - "
xmlgeneral.XSLTError          = "XSLT transformation failed"
xmlgeneral.XMLContentType     = "text/xml; charset=utf-8"
xmlgeneral.JSONContentType    = "application/json"

local HTTP_ERROR_MESSAGES = {
    [400] = "Bad request",
    [401] = "Unauthorized",
    [402] = "Payment required",
    [403] = "Forbidden",
    [404] = "Not found",
    [405] = "Method not allowed",
    [406] = "Not acceptable",
    [407] = "Proxy authentication required",
    [408] = "Request timeout",
    [409] = "Conflict",
    [410] = "Gone",
    [411] = "Length required",
    [412] = "Precondition failed",
    [413] = "Payload too large",
    [414] = "URI too long",
    [415] = "Unsupported media type",
    [416] = "Range not satisfiable",
    [417] = "Expectation failed",
    [418] = "I'm a teapot",
    [421] = "Misdirected request",
    [422] = "Unprocessable entity",
    [423] = "Locked",
    [424] = "Failed dependency",
    [425] = "Too early",
    [426] = "Upgrade required",
    [428] = "Precondition required",
    [429] = "Too many requests",
    [431] = "Request header fields too large",
    [451] = "Unavailable for legal reasons",
    [494] = "Request header or cookie too large",
    [500] = "An unexpected error occurred",
    [501] = "Not implemented",
    [502] = "An invalid response was received from the upstream server",
    [503] = "The upstream server is currently unavailable",
    [504] = "The upstream server is timing out",
    [505] = "HTTP version not supported",
    [506] = "Variant also negotiates",
    [507] = "Insufficient storage",
    [508] = "Loop detected",
    [510] = "Not extended",
    [511] = "Network authentication required",
}

---------------------------------
-- Format the SOAP Fault message
---------------------------------
function xmlgeneral.formatSoapFault(VerboseResponse, ErrMsg, ErrEx, contentTypeJSON)
  local soapErrMsg
  local detailErrMsg
  
  detailErrMsg = ErrEx

  -- if the last character is '\n' => we remove it
  if detailErrMsg:sub(-1) == '\n' then
    detailErrMsg = string.sub(detailErrMsg, 1, -2)
  end

  -- Add the Http status code of the SOAP/XML Web Service only during 'Response' phases (response, header_filter, body_filter)
  local ngx_get_phase = ngx.get_phase
  if  ngx_get_phase() == "response"      or 
      ngx_get_phase() == "header_filter" or 
      ngx_get_phase() == "body_filter"   then
    local status = kong.service.response.get_status()
    if status ~= nil then
      -- if the last character is not '.' => we add it
      if detailErrMsg:sub(-1) ~= '.' then
        detailErrMsg = detailErrMsg .. '.'
      end
      local additionalErrMsg = "Server - HTTP code: " .. tostring(status)      
      detailErrMsg = detailErrMsg .. " " .. additionalErrMsg
    end
  end
  
  -- If it's a SOAP/XML Request then the Fault Message is SOAP/XML text
  if contentTypeJSON == false then
    kong.log.err ("<faultstring>" .. ErrMsg .. "</faultstring><detail>".. detailErrMsg .. "</detail>")
    if VerboseResponse then
      detailErrMsg = "\n      <detail>" .. detailErrMsg .. "</detail>"
    else
      detailErrMsg = ''
    end
    soapErrMsg = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\
<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\
  <soap:Body>\
    <soap:Fault>\
      <faultcode>soap:Client</faultcode>\
      <faultstring>" .. ErrMsg .. "</faultstring>" .. detailErrMsg .. "\
    </soap:Fault>\
  </soap:Body>\
</soap:Envelope>\
"
  -- Else the Fault Message is a JSON text
  else
    -- Replace " by '
    detailErrMsg = string.gsub(detailErrMsg, "\"", "'")
    kong.log.err ("message: '" .. ErrMsg .. "' message_verbose: '".. detailErrMsg .. "'")
    soapErrMsg = "{\n    \"message\": \"" .. ErrMsg .. "\""
    if VerboseResponse then
      soapErrMsg = soapErrMsg .. ",\n    \"message_verbose\": \"" .. detailErrMsg .. "\""
    else
      soapErrMsg = soapErrMsg .. "\n"
    end
    soapErrMsg = soapErrMsg .. "\n}"
  end

  return soapErrMsg
end

-----------------------------------------------------
-- Add the HTTP Error code to the SOAP Fault message
-----------------------------------------------------
function xmlgeneral.addHttpErrorCodeToSoapFault(VerboseResponse, contentTypeJSON)
  local soapFaultBody
  
  local msg = HTTP_ERROR_MESSAGES[kong.response.get_status()]
  if not msg then
    msg = "Error"
  end
  soapFaultBody = xmlgeneral.formatSoapFault(VerboseResponse, msg, "HTTP Error code is " .. tostring(kong.response.get_status()), contentTypeJSON)
  
  return soapFaultBody
end

---------------------------------------
-- Return a SOAP Fault to the Consumer
---------------------------------------
function xmlgeneral.returnSoapFault(plugin_conf, HTTPcode, soapErrMsg, contentTypeJSON) 
  local contentType
  if contentTypeJSON == false then
    contentType = xmlgeneral.XMLContentType
  else
    contentType = xmlgeneral.JSONContentType
  end
  -- Send a Fault code to client
  return kong.response.exit(HTTPcode, soapErrMsg, {["Content-Type"] = contentType})
end

--------------------------------------------------------------------------------------
-- Initialize the ContentTypeJSON table for keeping the 'Content-Type' of the Request
--------------------------------------------------------------------------------------
function xmlgeneral.initializeContentTypeJSON ()
  -- If the 'kong.ctx.shared.contentTypeJSON' is not already created (by the Request plugin)
  if not kong.ctx.shared.contentTypeJSON then
    kong.ctx.shared.contentTypeJSON = {}
    -- Get the 'Content-Type' to define the type of a potential Error message (sent by the plugin): SOAP/XML or JSON
    local contentType = kong.request.get_header("Content-Type")
    kong.ctx.shared.contentTypeJSON.request = xmlgeneral.compareToJSONType(contentType)
  end
end

----------------------------------------------------------------
-- Return true if the contentType is JSON type, false otherwise
----------------------------------------------------------------
function xmlgeneral.compareToJSONType (contentType)
  return contentType == 'application/json' or contentType == 'application/vnd.api+json'
end

----------------------------------------------------------------
-- Return true if the string is an URL format, false otherwise
----------------------------------------------------------------
function xmlgeneral.isUrl(str)
  -- Simple pattern to check if the string is a URL
  local pattern = "^https?://[%w-_%.%?%.:/%+=&]+"
  return str:match(pattern) ~= nil
end

----------------------------------------------------------------
-- Return the credentials extracted from the request
----------------------------------------------------------------
function xmlgeneral.extractAuthData(plugin_conf, request_body)
  local errMessage
  local authData
  local authToExtract = plugin_conf.RequestAuthorizationLocation
  local auth_types_extract = { header = true, xPath = true }

  if auth_types_extract[authToExtract] then
    if authToExtract == "xPath" then
      authData = xmlgeneral.retrieveAuthDataFromXPath (kong, request_body, 
                                            plugin_conf.RequestAuthorizationXPath, plugin_conf.XPathRegisterNs)
      if #authData ~= #plugin_conf.RequestAuthorizationXPath then
        errMessage = "Some Xpath not Found"
      end
    else 
      authData = kong.request.get_header(plugin_conf.RequestAuthorizationHeader)
      if authData == nil then
        errMessage = "no data found in header " .. plugin_conf.RequestAuthorizationHeader
      end

      -- Check if authData starts with "Basic"
      if authData and authData:sub(1, 6) == "Basic " then
        -- Remove the "Basic " prefix
        local encoded_credentials = authData:sub(7)
        
        -- Decode the Base64-encoded string
        local decoded_credentials = base64.decode(encoded_credentials)
        
        -- Split the credentials into login and password
        local login, password = decoded_credentials:match("([^:]+):(.+)")
        authData = {
          [1] = login,
          [2] = password
        }
      end
    end

    if errMessage ~= nil and plugin_conf.FailIfAuthError then
      errMessage = "The authentication is not present and mandatory! Error: " .. errMessage
      -- Format a Fault code to Client
      return nil, xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.RequestTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  errMessage,
                                                  contentTypeJSON)
    end
  end

  return authData
end

----------------------------------------------------------------
-- Send the credentials extracted from the request
----------------------------------------------------------------
function xmlgeneral.sendAuthData(plugin_conf, authData, request_body_transformed)
  local errMessage
  local authToUpstream = plugin_conf.ResponseAuthorizationLocation
  local auth_types_upstream = { header = true, xPath = true }

  if auth_types_upstream[authToUpstream] and authData ~= nil then
    if authToUpstream == "xPath" then
      if type(authData) == "table" and #authData == 2  then
        local new_xml
        new_xml, errMessage = xmlgeneral.XPathContent(kong, request_body_transformed, plugin_conf.ResponseAuthorizationXPath[1], plugin_conf.XPathRegisterNs, authData[1])
        if new_xml then
          new_xml, errMessage= xmlgeneral.XPathContent(kong, request_body_transformed, plugin_conf.ResponseAuthorizationXPath[2], plugin_conf.XPathRegisterNs, authData[2])
        end

        if errMessage then
          errMessage = "error when replacing placeholders, err: " .. errMessage
        else
          request_body_transformed = new_xml
        end
      else
        request_body_transformed, errMessage = xmlgeneral.XPathContent(kong, request_body_transformed, plugin_conf.ResponseAuthorizationXPath[1], plugin_conf.XPathRegisterNs, authData[1])
      end
    end

    if authToUpstream == "header" then
      if #authData == 2 then
        authData = "Basic " .. base64.encode(authData[1] .. ":" .. authData[2])
      end

      kong.service.request.set_header(plugin_conf.ResponseAuthorizationHeader, authData)
    end
  end

  if errMessage ~= nil and plugin_conf.FailIfAuthError then
    errMessage = "The authentication was not replaced and is mandatory! Error: " .. errMessage 
    -- Format a Fault code to Client
    return nil, xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                xmlgeneral.RequestTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                errMessage,
                                                contentTypeJSON)
  end

  return request_body_transformed
end

----------------------------------------------------------------
-- Return the content downloaded from the url
----------------------------------------------------------------
function xmlgeneral.downLoadDataFromUrl (url, timeout)
  kong.log.debug("Downloading the xsd data from ", url)
  local http = require "resty.http"
  local httpc = http.new()  
  
  httpc:set_timeout(timeout * 1000)
  local res, err = httpc:request_uri(url, {
    method = 'GET',
    ssl_verify = false,
  })
  if err or res.status ~= 200 then
    -- We don't update the 'body' and 'httpStatus' and give the user a chance to have the cached value
    local errMsg = "Error when downloading data from " .. url .. " with status: " .. res.status
    if err then
      errMsg = errMsg .. " and error: " .. err
    end
    return nil, errMsg
  end
  
  return res.body
end

----------------------------------------------------------------
-- Check Response content, return error message if contentType is wrong
----------------------------------------------------------------
function xmlgeneral.checkResponseContent(responseBody, contentTypeJSON)
  local errMessage
  if contentTypeJSON then
    if not pcall(function() return xmlua.XML.parse(responseBody) end) then
      errMessage = "Response is not a valid XML"
    end
  else
    if not pcall(function() return cjson.decode(responseBody) end) then
      errMessage = "Response is not a valid JSON"
    end
  end

  return errMessage
end

----------------------------
-- libsaxon: Initialization
----------------------------
function xmlgeneral.initializeSaxon()
  local errMessage

  if not kong.xmlSoapSaxon then
    kong.log.debug ("initializeSaxon: it's the 1st time the function is called => initialize the 'saxon' library")
    kong.xmlSoapSaxon = {}
    kong.xmlSoapSaxon.saxonProcessor    = ffi.NULL
    kong.xmlSoapSaxon.xslt30Processor   = ffi.NULL
    
    -- Load the Saxon for kong Shared Object
    kong.log.debug ("initializeSaxon: loadSaxonforKongLibrary")
    errMessage = libsaxon4kong.loadSaxonforKongLibrary ()

    if not errMessage then
      -- Create Saxon Processor
      kong.log.debug ("initializeSaxon: createSaxonProcessorKong")
      kong.xmlSoapSaxon.saxonProcessor, errMessage = libsaxon4kong.createSaxonProcessorKong ()
      
      if not errMessage then
        -- Create XSLT 3.0 processor
        kong.log.debug ("initializeSaxon: createXslt30ProcessorKong")
        kong.xmlSoapSaxon.xslt30Processor, errMessage = libsaxon4kong.createXslt30ProcessorKong (kong.xmlSoapSaxon.saxonProcessor)
        if not errMessage then
          kong.log.debug ("initializeSaxon: the 'saxon' library is successfully initialized")
        end
      end

      if errMessage then
        kong.log.err ("initializeSaxon: errMessage: " .. errMessage)
      end

    else
      kong.log.debug ("initializeSaxon: errMessage: " .. errMessage)
    end
  else
    kong.log.debug ("initializeSaxon: 'saxon' is already initialized => nothing to do")
  end
end

---------------------------------------------------
-- libsaxon: Transform XML with XSLT Transformation
---------------------------------------------------
function xmlgeneral.XSLTransform_libsaxon(plugin_conf, XMLtoTransform, XSLT, verbose, useTemplate)
  local errMessage
  local xml_transformed_dump
  local context
  
  kong.log.debug ("XSLT transformation, BEGIN: " .. XMLtoTransform)

  -- Check if Saxon for Kong library is correctly loaded
  errMessage = libsaxon4kong.isSaxonforKongLoaded()
  
  if not errMessage then
    -- Compile the XSLT document
    context, errMessage = libsaxon4kong.compileStylesheet (kong.xmlSoapSaxon.saxonProcessor, 
                                                          kong.xmlSoapSaxon.xslt30Processor, 
                                                          XSLT)
  end

  if not errMessage then
    -- If the XSLT Transformation is configured with a Template (example: <xsl:template name="main">)
    if useTemplate then
      -- Transform the XML doc with XSLT transformation by invoking a template
      xml_transformed_dump, errMessage = libsaxon4kong.stylesheetInvokeTemplate ( 
                                            kong.xmlSoapSaxon.saxonProcessor,
                                            context,
                                            "main",
                                            "request-body",
                                            XMLtoTransform
                                          )
    else
      -- Transform the XML doc with XSLT transformation
      xml_transformed_dump, errMessage = libsaxon4kong.stylesheetTransformXml ( 
                                            kong.xmlSoapSaxon.saxonProcessor,
                                            context,
                                            XMLtoTransform
                                          )
    end
  end
  
  -- Free memory
  if context then
    -- Delete the Saxon Context and the compiled XSLT
    libsaxon4kong.deleteContext(context)
  end

  if errMessage == nil then
    kong.log.debug ("XSLT transformation, END: " .. xml_transformed_dump)
  else
    kong.log.debug ("XSLT transformation, END with error: " .. errMessage)
  end
  
  return xml_transformed_dump, errMessage
end

---------------------------------------------
-- Search a XPath and return its value
---------------------------------------------
function xmlgeneral.XPathContent (kong, XMLtoSearch, XPath, XPathRegisterNs, newValue)
  local XpathContent
  
  kong.log.debug("XPathContent, XMLtoSearch: " .. XMLtoSearch)
  kong.log.debug("XPath for the search IS: " .. XPath)

  local context = libxml2.xmlNewParserCtxt()
  local document = libxml2.xmlCtxtReadMemory(context, XMLtoSearch)
  
  if not document then
    kong.log.debug ("RouteByXPath, xmlCtxtReadMemory error, no document")
    return nil, "no document"
  end
  
  local context = libxml2.xmlXPathNewContext(document)

  -- Register NameSpace(s)
  kong.log.debug("XPathRegisterNs length: " .. #XPathRegisterNs)

  -- Go on each NameSpace definition
  for i = 1, #XPathRegisterNs do
    local prefix, uri
    local j = XPathRegisterNs[i]:find(',', 1)
    if j then
      prefix  = string.sub(XPathRegisterNs[i], 1, j - 1)
      uri     = string.sub(XPathRegisterNs[i], j + 1, #XPathRegisterNs[i])
    end
    local rc = false
    if prefix and uri then
      -- Register NameSpace
      rc = libxml2.xmlXPathRegisterNs(context, prefix, uri)
    end
    if rc then
      kong.log.debug("RouteByXPath, successful registering NameSpace for '" .. XPathRegisterNs[i] .. "'")
    else
      kong.log.err("RouteByXPath, failure registering NameSpace for '" .. XPathRegisterNs[i] .. "'")
    end
  end

  local object = libxml2.xmlXPathEvalExpression(XPath, context)
  
  if object ~= ffi.NULL then  
    -- If we found the XPath element
    if object.nodesetval ~= ffi.NULL and object.nodesetval.nodeNr ~= 0 then
        local node = object.nodesetval.nodeTab[0]
        local nodeContent = libxml2.xmlNodeGetContent(node)
        kong.log.debug("libxml2.xmlNodeGetContent: " .. nodeContent)
        if nodeContent then
          kong.log.debug ("XPathContent found: " .. nodeContent)
          XpathContent = nodeContent
        else
          kong.log.debug ("No XPathContent found") 
          return nil, "No XPathContent found for " .. XPath 
        end

        if newValue then
          libxml2.xmlNodeSetContent(node, newValue, #newValue)
          local newXML = xmlgeneral.to_xml(document)
          kong.log.debug("Replaced content at XPath: " .. XPath .. " with value: " .. newValue)
          XpathContent = newXML
        end
    else
      kong.log.debug ("XPathContent, object.nodesetval is null")  
      return nil, "XPathContent, object.nodesetval is null for " .. XPath 
    end
  else
    kong.log.debug ("XPathContent, object is null")
    return nil, "XPathContent, object is null for " .. XPath
  end

  -- Clean up
  ffi.gc(object, libxml2.xmlXPathFreeObject)
  ffi.gc(context, libxml2.xmlXPathFreeContext)
  ffi.gc(document, libxml2.xmlFreeDoc)

  return XpathContent
end


--------------------------
-- Dump a document to XML
--------------------------
function xmlgeneral.to_xml(document)
  local buffer = libxml2.xmlBufferCreate()
  local context = libxml2.xmlSaveToBuffer(buffer,
                                          "UTF-8",
                                          bit.bor(ffi.C.XML_SAVE_FORMAT,
                                                  ffi.C.XML_SAVE_NO_DECL,
                                                  ffi.C.XML_SAVE_AS_XML))
  libxml2.xmlSaveDoc(context, document)
  libxml2.xmlSaveClose(context)
  return libxml2.xmlBufferGetContent(buffer)
end

---------------------------------------------
-- Retrieve Element using a XPath
---------------------------------------------
function xmlgeneral.retrieveAuthDataFromXPath(kong, XMLtoSearch, XPath, XPathRegisterNs)
  local authData

  -- Check if there's only one XPath
  if #XPath == 1 then
    -- Retrieve authentication data from the single XPath
    authData = xmlgeneral.XPathContent(kong, XMLtoSearch, XPath[1], XPathRegisterNs)
  else
    -- Retrieve authentication data from multiple XPaths and store them in a table
    authData = {
      [1] = xmlgeneral.XPathContent(kong, XMLtoSearch, XPath[1], XPathRegisterNs),
      [2] = xmlgeneral.XPathContent(kong, XMLtoSearch, XPath[2], XPathRegisterNs)
    }
  end

  return authData
end

return xmlgeneral