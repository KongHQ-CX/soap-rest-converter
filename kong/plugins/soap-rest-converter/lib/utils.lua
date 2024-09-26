local cjson = require("cjson")
local xmlua = require("xmlua")
local _M = {}

local function checkIsJson(responseBody)
  -- Try to decode the response as JSON
  local success, result = pcall(function() return cjson.decode(responseBody) end)
  
  -- If decoding is successful, return true, else return false
  return success
end

local function checkIsXML(responseBody)
  -- Try to parse the response as XML
  local success, result = pcall(function() return xmlua.XML.parse(responseBody) end)

  -- If parsing is successful, return true, else return false
  return success
end


function _M.checkResponseContent(responseBody, contentTypeJSON)
  local errMessage
  if contentTypeJSON then
    if not checkIsXML(responseBody) then
      errMessage = "Response is not a valid XML"
    end
  else
    if not checkIsJson(responseBody) then
      errMessage = "Response is not a valid JSON"
    end
  end

  return errMessage
end

function _M.is_url(str)
  -- Simple pattern to check if the string is a URL
  local pattern = "^https?://[%w-_%.%?%.:/%+=&]+"
  return str:match(pattern) ~= nil
end

function _M.downLoadDataFromUrl (url, timeout)
  kong.log.debug("Downloading the xsd data from ", url)
  local http = require "resty.http"
  local httpc = http.new()  
  
  httpc:set_timeout(timeout * 1000)
  local res, err = httpc:request_uri(url, {
    method = 'GET',
    ssl_verify = false,
  })
  if not res or res.status ~= 200 then
    -- We don't update the 'body' and 'httpStatus' and give the user a chance to have the cached value
    local errMsg = "Error when downloading data from " .. url .. " with status: " .. res.status
    if err then
      errMsg = errMsg .. " and error: " .. err
    end
    return nil, errMsg
  end
  
  return res.body
end


return _M