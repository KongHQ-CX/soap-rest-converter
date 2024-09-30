<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.w3.org/2005/xpath-functions" xmlns:fn="http://www.w3.org/2005/xpath-functions" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" version="3.0" xpath-default-namespace="http://tempuri.org/" exclude-result-prefixes="fn">
   <xsl:mode on-no-match="shallow-skip" />
   <xsl:output method="text" />
   <xsl:template match="/soap:Envelope/soap:Body/*[ends-with(name(), 'Response')]/*[ends-with(name(), 'Result')]">
      <xsl:variable name="json-result">
         <map>
            <number key="result">
               <xsl:value-of select="text()" />
            </number>
         </map>
      </xsl:variable>
      <xsl:value-of select="fn:xml-to-json($json-result)" />
   </xsl:template>
   <xsl:template match="/soapenv:Envelope/soapenv:Header" />
</xsl:stylesheet>