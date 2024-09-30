local KongGzip        = require("kong.tools.gzip")
local sha256_hex      = require("kong.tools.sha256").sha256_hex
local xmlgeneral      = require("kong.plugins.soap-rest-converter.lib.xmlgeneral")
local cjson           = require "cjson"

-- handler.lua
local plugin = {
    PRIORITY = 75,
    VERSION = "1.1.0",
  }

------------------------------------------------------------------------------------------------------------------------------------
-- XSLT TRANSFORMATION - BEFORE XSD: Transform the XML request with XSLT (XSLTransformation) before XSD Validation
-- WSDL/XSD VALIDATION             : Validate XML request with its WSDL or XSD schema
-- XSLT TRANSFORMATION - AFTER XSD : Transform the XML request with XSLT (XSLTransformation) after XSD Validation
-- ROUTING BY XPATH                : change the Route of the request to a different hostname and path depending of XPath condition
------------------------------------------------------------------------------------------------------------------------------------
function plugin:requestTransformHandling(plugin_conf, requestBody, contentTypeJSON)
  local request_body_transformed
  local errMessage
  local soapFaultBody
  local useTemplate

  local templateTransformBefore = plugin_conf.xsltTransformRequest

  if xmlgeneral.isUrl(templateTransformBefore) then
    -- Calculate a cache key based on the URL using the hash_key function.
    local url_cache_key = sha256_hex("templateTransformBefore")
    local timeout = plugin_conf.ExternalDataTimeout

    -- Retrieve the response_body from cache, with a TTL (in seconds), using the 'syncDownloadEntities' function.
    templateTransformBefore, errMessage = kong.cache:get(url_cache_key, { ttl = plugin_conf.ExternalDataCacheTTL }, xmlgeneral.downLoadDataFromUrl, templateTransformBefore, timeout)
    
    if errMessage ~= nil then
      errMessage = "Error when retrieving the xslt template: " .. errMessage
      -- Format a Fault code to Client
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.RequestTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  errMessage,
                                                  contentTypeJSON)
    end
  end

  -- we need to download in the access phase
  kong.ctx.shared.xsltTransformResponse = plugin_conf.xsltTransformResponse
  if xmlgeneral.isUrl(plugin_conf.xsltTransformResponse) then
    -- Calculate a cache key based on the URL using the hash_key function.
    local url_cache_key = sha256_hex(plugin_conf.xsltTransformResponse)
    local timeout = plugin_conf.ExternalDataTimeout

    -- Retrieve the response_body from cache, with a TTL (in seconds), using the 'syncDownloadEntities' function.
    kong.ctx.shared.xsltTransformResponse, errMessage = kong.cache:get(url_cache_key, { ttl = plugin_conf.ExternalDataCacheTTL }, xmlgeneral.downLoadDataFromUrl, plugin_conf.xsltTransformResponse, timeout)
    
    if errMessage ~= nil then
      errMessage = "Error when retrieving the xslt template: " .. errMessage
      -- Format a Fault code to Client
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  errMessage,
                                                  contentTypeJSON)
    end
  end

  -- check if json2soap or soap2json transformation
  if kong.ctx.shared.contentTypeJSON.request == true then
    useTemplate = true
  else
    useTemplate = false
  end

  -- If there is 'XSLT Transformation Before XSD' configuration then:
  -- => we apply XSL Transformation (XSLT) Before XSD
  if soapFaultBody == nil and templateTransformBefore then
    request_body_transformed, errMessage = xmlgeneral.XSLTransform_libsaxon(plugin_conf, requestBody, templateTransformBefore, plugin_conf.VerboseRequest, useTemplate)
    
    if errMessage ~= nil then
      -- Format a Fault code to Client
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.RequestTextError .. xmlgeneral.SepTextError .. xmlgeneral.XSLTError,
                                                  errMessage,
                                                  contentTypeJSON)
    end
  end
  
  return request_body_transformed, soapFaultBody

end

-----------------------------------------------------------------------------------------
-- XSLT TRANSFORMATION - BEFORE XSD: Transform the XML response Before (XSD VALIDATION)
-- WSDL/XSD VALIDATION             : Validate XML request with its WSDL or XSD schema
-- XSLT TRANSFORMATION - AFTER XSD : Transform the XML response After (XSD VALIDATION)
-----------------------------------------------------------------------------------------
function plugin:responseSOAPXMLhandling(plugin_conf, responseBody, contentTypeJSON)
  local responseBodyTransformed
  local errMessage
  local soapFaultBody
  local useTemplate

  local templateTransformAfter = kong.ctx.shared.xsltTransformResponse

  -- check if json2soap or soap2json transformation
  if kong.ctx.shared.contentTypeJSON.request == true then
    useTemplate = false
  else
    useTemplate = true
  end

  -- Check if response body is not null
  if responseBody == nil then
    errMessage = "Response body is null"
    kong.log.debug("The response Body is 'nil': nothing to do")
      -- Format a Fault code to Client
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  errMessage,
                                                  contentTypeJSON)
  end

  -- If the plugin is defined with Routing ErrorXPath properties then:
  -- => we check if an error returned in response and add error is satisfied
  if soapFaultBody == nil and plugin_conf.ErrorXPath then
    -- Get Error By XPath and check if the condition is satisfied
    errMessage = xmlgeneral.XPathContent (kong, responseBody, 
                                            plugin_conf.ErrorXPath, plugin_conf.XPathRegisterNs)
    -- If the condition is statisfied we return an error
    if errMessage then
      kong.log.debug("ErrorXPath: Error return by the service upstream")
      -- Format a Fault code to Client
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  errMessage,
                                                  contentTypeJSON)
    end
  end

  -- Check response content is correct
  -- JSON if rest 
  -- XML is Soap
  errMessage = xmlgeneral.checkResponseContent(responseBody, contentTypeJSON)

  if errMessage ~= nil then
    -- Format a Fault code to Client
    soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                errMessage,
                                                contentTypeJSON)
  end

  -- If there is no error and
  -- If there is 'XSLT Transformation After XSD' configuration then:
  -- => we apply XSL Transformation (XSLT) After XSD
  if soapFaultBody == nil and templateTransformAfter then
    responseBodyTransformed, errMessage = xmlgeneral.XSLTransform_libsaxon(plugin_conf, responseBody, templateTransformAfter, plugin_conf.VerboseRequest, useTemplate)
    if errMessage ~= nil then
      -- Format a Fault code to Client
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.XSLTError,
                                                  errMessage,
                                                  contentTypeJSON)
    end
  end
    
  return responseBodyTransformed, soapFaultBody

end

------------------------------------------------------
-- Executed upon every Nginx worker process’s startup
------------------------------------------------------
function plugin:init_worker ()
  -- Initialize Saxon
  xmlgeneral.initializeSaxon()
end

---------------------------------------------------------------------------------------------------
-- Executed for every request from a client and before it is being proxied to the upstream service
---------------------------------------------------------------------------------------------------
function plugin:access(plugin_conf)
  local authData
  
  -- initialize the ContentTypeJSON table for storing the Content-Type of the Request
  xmlgeneral.initializeContentTypeJSON ()

  -- Get SOAP envelope from the request
  local request_body = kong.request.get_raw_body()

  -- Handle all SOAP/XML topics of the Request: XSLT before, XSD validation, XSLT After and Routing by XPath
  local request_body_transformed, soapFaultBody = plugin:requestTransformHandling (plugin_conf, request_body, kong.ctx.shared.contentTypeJSON.request)
  
  -- If there is no error Retrieve authentication data
  if soapFaultBody == nil then
    authData, soapFaultBody = xmlgeneral.extractAuthData(plugin_conf, request_body)
  end
  
  -- If there is no error Send authentication data
  if soapFaultBody == nil and authData ~= nil then
    request_body_transformed, soapFaultBody = xmlgeneral.sendAuthData(plugin_conf, authData, request_body_transformed)
  end

  -- If there is an error during SOAP/XML we change the HTTP status code and
  -- the Body content (with the detailed error message) will be changed by 'body_filter' phase
  if soapFaultBody ~= nil then
    -- Set the Global Fault Code to the "Request and Response SOAP/XML handling" plugins 
    -- It prevents to apply other XML/SOAP handling whereas there is already an error
    kong.ctx.shared.restSoapHandlingFault = {
      error = true,
      soapEnvelope = soapFaultBody
    }

    -- Return a Fault code to Client
    return xmlgeneral.returnSoapFault (plugin_conf,
                                      xmlgeneral.HTTPCodeSOAPFault,
                                      soapFaultBody,
                                      kong.ctx.shared.contentTypeJSON.request)
  end

  -- If the SOAP Body request has been changed (for instance, the XPath Routing alone doesn't change it)
  if request_body_transformed then
    -- We did a successful SOAP/XML handling, so we change the SOAP body request
    kong.service.request.set_raw_body(request_body_transformed)
  end

  -- If there is a XML -> JSON transformation on the Response: change the 'Content-Type' header of the Request
  if kong.ctx.shared.contentTypeJSON.request == true then
    kong.service.request.set_header("Content-Type", xmlgeneral.XMLContentType)
  else
    kong.service.request.set_header("Content-Type", xmlgeneral.JSONContentType)
  end

  -- If http version is 'HTTP/2' the enable_buffering doesn't work so the 'soap-xml-response-handling' 
  -- cannot work and we 'disable' it
  if ngx.req.http_version() < 2 then
    kong.service.request.enable_buffering()
  else
    local errMsg =  "Try calling 'kong.service.request.enable_buffering' with http/" .. ngx.req.http_version() .. 
                    " please use http/1.x instead. The plugin is disabled"

    kong.ctx.shared.restSoapHandlingFault = {
      error = true,
      soapEnvelope = errMsg
    }
  end

end

-----------------------------------------------------------------------------------------
-- Executed when all response headers bytes have been received from the upstream service
-----------------------------------------------------------------------------------------
function plugin:header_filter(plugin_conf)
  local responseBodyTransformed
  local responseBody
  local responseBodyDeflated
  local soapFaultBody
  local err

  -- In case of error set in previous phases, we don't do anything to avoid an issue.
  if kong.ctx.shared.restSoapHandlingFault and 
     kong.ctx.shared.restSoapHandlingFault.error then
    kong.log.debug("A pending error has been set in previous phases: we do nothing in this phase")
    return
  end
    
  --  In case of 'request-termination' plugin
  if (kong.response.get_source() == "exit" and kong.response.get_status() == 200) then
    return
  -- 
  -- If an error is set by other plugin (like Rate Limiting) or by the Service itself (timeout) 
  --   and
  -- If there is no XML to JSON transformation (i.e. we have to send a XML message)
  -- we reformat the JSON message to SOAP/XML Fault
  elseif  (kong.response.get_source() == "exit" or 
          kong.response.get_source()  == "error") then
    if kong.ctx.shared.contentTypeJSON.request == true then
      kong.log.debug("A pending error has been set by other plugin or by the Service itself")
      kong.response.set_header("Content-Type", xmlgeneral.JSONContentType)
      return
    else
      kong.log.debug("A pending error has been set by other plugin or by the Service itself: we format the error messsage in SOAP/XML Fault")
      soapFaultBody = xmlgeneral.addHttpErrorCodeToSoapFault(plugin_conf.VerboseResponse, kong.ctx.shared.contentTypeJSON.request)
      kong.response.clear_header("Content-Length")
      kong.response.set_header("Content-Type", xmlgeneral.XMLContentType)
    end
  else
    -- Get SOAP Envelope from the Body
    responseBody = kong.service.response.get_raw_body()

    -- There is no SOAP envelope (or Body content) so we don't do anything
    if not responseBody then
      kong.log.debug("The Body is 'nil': nothing to do")
      return
    end
  end
  
  -- If there is no error
  if soapFaultBody == nil then
    -- If the Body is deflated/zipped, we inflate/unzip it
    if kong.response.get_header("Content-Encoding") == "gzip" then
      local responseBodyDeflated, err = KongGzip.inflate_gzip(responseBody)
      if err then
        err = "Failed to inflate the gzipped SOAP/XML Body: " .. err
        soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                    xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                    err,
                                                    kong.ctx.shared.contentTypeJSON.request)
      else
        responseBody = responseBodyDeflated
      end
    -- If there is a 'Content-Encoding' type that is not supported (by 'KongGzip')
    elseif kong.response.get_header("Content-Encoding") then
      err = "Content-encoding of type '" .. kong.response.get_header("Content-Encoding") .. "' is not supported"
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  err,
                                                  kong.ctx.shared.contentTypeJSON.request)
    end
  end

  -- If there is no error and responseBody is not nil
  if soapFaultBody == nil and responseBody and kong.response.get_status() == 200 then
    -- Handle all SOAP/XML topics of the Response: XSLT before, XSD validation and XSLT After
    responseBodyTransformed, soapFaultBody = plugin:responseSOAPXMLhandling (plugin_conf, responseBody, kong.ctx.shared.contentTypeJSON.request)
  else
    err = "Error received from the upstream - "

    if plugin_conf.VerboseError and plugin_conf.ErrorXPath then
      -- Get Error By XPath and check if the condition is satisfied
      local ErrorXPath = xmlgeneral.XPathContent (kong, responseBody, 
                                              plugin_conf.ErrorXPath, plugin_conf.XPathRegisterNs)

      if ErrorXPath then
        err = err .. "Error from declared xPath is " .. cjson.encode(ErrorXPath) .. "-"
      end
  end

    soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  err,
                                                  kong.ctx.shared.contentTypeJSON.request)
  end

  -- If there is a XML -> JSON transformation on the Response: change the 'Content-Type' header of the Response
  if kong.ctx.shared.contentTypeJSON.request == true then
    kong.response.set_header("Content-Type", xmlgeneral.JSONContentType)
  else
    kong.response.set_header("Content-Type", xmlgeneral.XMLContentType)
  end
  
  -- If there is an error during SOAP/XML we change the HTTP staus code and
  -- the Body content (with the detailed error message) will be changed by 'body_filter' phase
  if soapFaultBody ~= nil then
    -- If the Body is zipped we removed it
    -- We don't have to deflate/zip it because there will have an error message with a few number of characters
    if kong.response.get_header("Content-Encoding") then
      kong.response.clear_header("Content-Encoding")
    end
    -- When the response was originated by successfully contacting the proxied Service
    if kong.response.get_source() == "service" then
      -- Change the HTTP Status and Return a Fault code to Client
      kong.response.set_status(xmlgeneral.HTTPCodeSOAPFault)
    else
      -- When another plugin (like Rate Limiting) or 
      -- the Service itself (timeout) has already raised an error: we don't change the HTTP Error code
    end
    kong.response.set_header("Content-Length", #soapFaultBody)

    -- Set the Global Fault Code to Request and Response XLM/SOAP plugins 
    -- It prevents to apply XML/SOAP handling whereas there is already an error
    kong.ctx.shared.restSoapHandlingFault = {
      error = true,
      soapEnvelope = soapFaultBody
    }
  -- If the SOAP envelope is transformed
  elseif responseBodyTransformed then
    -- If the Backend API Body is deflated/zipped, we deflate/zip the new transformed SOAP/XML Body
    if kong.response.get_header("Content-Encoding") == "gzip" then
      local soapInflated, err = KongGzip.deflate_gzip(responseBodyTransformed)
      
      if err then
        kong.log.err("Failed to deflate the gzipped SOAP/XML Body: " .. err)
        -- We are unable to deflate/zip new transformed SOAP/XML Body, so we remove the 'Content-Encoding' header
        -- and we return the non delated/zipped content
        kong.response.clear_header("Content-Encoding")
      else
        responseBodyTransformed = soapInflated
      end
    end
    -- We aren't able to call 'kong.response.set_raw_body()' at this stage to change the body content
    -- but it will be done by 'body_filter' phase
    kong.response.set_header("Content-Length", #responseBodyTransformed)

    -- We set the new SOAP Envelope for cascading Plugins because they are not able to retrieve it
    -- by calling 'kong.response.get_raw_body ()' in header_filter
    kong.ctx.shared.restSoapHandlingFault = {
      error = false,
      soapEnvelope = responseBodyTransformed
    }
  end

end

------------------------------------------------------------------------------------------------------------------
-- Executed for each chunk of the response body received from the upstream service.
-- Since the response is streamed back to the client, it can exceed the buffer size and be streamed chunk by chunk.
-- This function can be called multiple times
------------------------------------------------------------------------------------------------------------------
function plugin:body_filter(plugin_conf)
  -- Get modified SOAP envelope set by the plugin itself on 'header_filter'
  if kong.ctx.shared.restSoapHandlingFault and kong.ctx.shared.restSoapHandlingFault.soapEnvelope then
    -- Set the modified SOAP envelope
    kong.response.set_raw_body(kong.ctx.shared.restSoapHandlingFault.soapEnvelope)
  end
end

return plugin