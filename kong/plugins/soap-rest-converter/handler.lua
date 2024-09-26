local KongGzip        = require("kong.tools.gzip")
local sha256_hex      = require("kong.tools.sha256").sha256_hex
local base64_encode   = require "kong.openid-connect.codec".base64.encode
local utils           = require "kong.plugins.soap-rest-converter.lib.utils"
local xmlgeneral      = require("kong.plugins.soap-rest-converter.lib.xmlgeneral")

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

  if utils.is_url(templateTransformBefore) then
    -- Calculate a cache key based on the URL using the hash_key function.
    local url_cache_key = sha256_hex("templateTransformBefore")
    local timeout = plugin_conf.ExternalDataTimeout

    -- Retrieve the response_body from cache, with a TTL (in seconds), using the 'syncDownloadEntities' function.
    templateTransformBefore, errMessage = kong.cache:get(url_cache_key, { ttl = plugin_conf.ExternalDataCacheTTL }, utils.downLoadDataFromUrl, templateTransformBefore, timeout)
    
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
  if utils.is_url(plugin_conf.xsltTransformResponse) then
    -- Calculate a cache key based on the URL using the hash_key function.
    local url_cache_key = sha256_hex(plugin_conf.xsltTransformResponse)
    local timeout = plugin_conf.ExternalDataTimeout

    -- Retrieve the response_body from cache, with a TTL (in seconds), using the 'syncDownloadEntities' function.
    kong.ctx.shared.xsltTransformResponse, errMessage = kong.cache:get(url_cache_key, { ttl = plugin_conf.ExternalDataCacheTTL }, utils.downLoadDataFromUrl, plugin_conf.xsltTransformResponse, timeout)
    
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
                                            plugin_conf.ErrorXPath, plugin_conf.RouteXPathRegisterNs)
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
  errMessage = utils.checkResponseContent(responseBody, contentTypeJSON)

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
    local errMessage
    local authToExtract = plugin_conf.RequestAuthorizationLocation
    local auth_types_extract = { header = true, xPath = true }

    if auth_types_extract[authToExtract] then
      if authToExtract == "xPath" then
        authData = xmlgeneral.retrieveAuthDataFromXPath (kong, request_body, 
                                              plugin_conf.RequestAuthorizationXPath, plugin_conf.RouteXPathRegisterNs)
        if #authData ~= #plugin_conf.RequestAuthorizationXPath then
          errMessage = "Some Xpath not Found"
        end
      else 
        authData = kong.request.get_header(plugin_conf.RequestAuthorizationHeader)
        if authData == nil then
          errMessage = "no data found in header " .. plugin_conf.RequestAuthorizationHeader
        end
      end

      if errMessage ~= nil and plugin_conf.FailIfAuthError then
        errMessage = "The authentication is not present and mandatory! Error: " .. errMessage
        -- Format a Fault code to Client
        soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                    xmlgeneral.RequestTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                    errMessage,
                                                    contentTypeJSON)
      end
    end
  end
  
  -- If there is no error Send authentication data
  if soapFaultBody == nil and authData ~= nil then
    local errMessage
    local authToUpstream = plugin_conf.ResponseAuthorizationLocation
    local auth_types_upstream = { header = true, xsltTemplate = true }

    if auth_types_upstream[authToUpstream] and authData ~= nil then
      if authToUpstream == "xsltTemplate" then
        if type(authData) == "table" then
          local check1
          local check2
          request_body_transformed, check1 = request_body_transformed:gsub("$AUTH1", authData[1])
          request_body_transformed, check2 = request_body_transformed:gsub("$AUTH2", authData[2])
          if check1 + check2 ~= 2 then
            errMessage = "$AUTH1 or $AUTH2 placeholders not found in the xslt template, please check!"
          end
        else
          local check
          request_body_transformed, check = request_body_transformed:gsub("$AUTH1", authData)
          if check == 0 then
            errMessage = "$AUTH1 placeholder not found in the xslt template, please check!"
          end
        end

      end

      if authToUpstream == "header" then
        if #authData == 2 then
          authData = "Basic " .. base64_encode(authData[1] .. ":" .. authData[2])
        end

        kong.service.request.set_header(plugin_conf.ResponseAuthorizationHeader, authData)
      end
    end

    if errMessage ~= nil and plugin_conf.FailIfAuthError then
      errMessage = "The authentication was not replaced and is mandatory! Error: " .. errMessage 
      -- Format a Fault code to Client
      soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.RequestTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  errMessage,
                                                  contentTypeJSON)
    end
  end

  -- If there is an error during SOAP/XML we change the HTTP status code and
  -- the Body content (with the detailed error message) will be changed by 'body_filter' phase
  if soapFaultBody ~= nil then
    -- Set the Global Fault Code to the "Request and Response SOAP/XML handling" plugins 
    -- It prevents to apply other XML/SOAP handling whereas there is already an error
    kong.ctx.shared.xmlSoapHandlingFault = {
      error = true,
      otherPlugin = false,
      priority = plugin.PRIORITY,
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
    kong.service.request.set_header("Content-Type", xmlgeneral.JsonContentType)
  end

  -- If http version is 'HTTP/2' the enable_buffering doesn't work so the 'soap-xml-response-handling' 
  -- cannot work and we 'disable' it
  if ngx.req.http_version() < 2 then
    kong.service.request.enable_buffering()
  else
    local errMsg =  "Try calling 'kong.service.request.enable_buffering' with http/" .. ngx.req.http_version() .. 
                    " please use http/1.x instead. The plugin is disabled"

    kong.ctx.shared.xmlSoapHandlingFault = {
      error = true,
      priority = -1,
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
  
  -- In case of error set by SOAP/XML plugin, we don't do anything to avoid an issue.
  -- If we call get_raw_body (), without calling request.enable_buffering(), it will raise an error and 
  -- it happens when a previous plugin called kong.response.exit(): in this case all 'header_filter' and 'body_filter'
  -- are called (and the 'access' is not called which enables the enable_buffering())
  if kong.ctx.shared.xmlSoapHandlingFault and 
     kong.ctx.shared.xmlSoapHandlingFault.error then
    kong.log.debug("A pending error has been set by SOAP/XML plugin: we do nothing in this plugin")
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
      kong.response.set_header("Content-Type", xmlgeneral.JsonContentType)
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
    err = "Error received from the upstream: "
    soapFaultBody = xmlgeneral.formatSoapFault (plugin_conf.VerboseError,
                                                  xmlgeneral.ResponseTextError .. xmlgeneral.SepTextError .. xmlgeneral.GeneralError,
                                                  err,
                                                  kong.ctx.shared.contentTypeJSON.request)
  end

  -- If there is a XML -> JSON transformation on the Response: change the 'Content-Type' header of the Response
  if kong.ctx.shared.contentTypeJSON.request == true then
    kong.response.set_header("Content-Type", xmlgeneral.JsonContentType)
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
    kong.ctx.shared.xmlSoapHandlingFault = {
      error = true,
      priority = plugin.PRIORITY,
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
    kong.ctx.shared.xmlSoapHandlingFault = {
      error = false,
      priority = plugin.PRIORITY,
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
  -- If there is a pending error set by SOAP/XML plugin we do nothing except for the Plugin itself
  if  kong.ctx.shared.xmlSoapHandlingFault      and
    kong.ctx.shared.xmlSoapHandlingFault.error  and 
    kong.ctx.shared.xmlSoapHandlingFault.priority ~= plugin.PRIORITY then
    kong.log.debug("A pending error has been set by SOAP/XML plugin: we do nothing in this plugin")
    return
  end

  -- Get modified SOAP envelope set by the plugin itself on 'header_filter'
  if  kong.ctx.shared.xmlSoapHandlingFault  and
      kong.ctx.shared.xmlSoapHandlingFault.priority == plugin.PRIORITY then
    
    if kong.ctx.shared.xmlSoapHandlingFault.soapEnvelope then
      -- Set the modified SOAP envelope
      kong.response.set_raw_body(kong.ctx.shared.xmlSoapHandlingFault.soapEnvelope)
    end
  end
end

return plugin