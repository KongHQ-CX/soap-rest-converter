<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:fn="http://www.w3.org/2005/xpath-functions" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" version="3.0" xpath-default-namespace="http://www.w3.org/2005/xpath-functions" exclude-result-prefixes="fn">
   <xsl:output method="xml" indent="yes" />
   <xsl:template name="main">
      <xsl:param name="request-body" required="yes" />
      <xsl:variable name="json" select="fn:json-to-xml($request-body)" />
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Header>
            <wsse:Security>
                <wsse:UsernameToken>
                    <wsse:Username>xxx</wsse:Username>
                    <wsse:Password>xxx</wsse:Password>
                </wsse:UsernameToken>
            </wsse:Security>
        </soap:Header>
         <soap:Body>
            <xsl:variable name="operation" select="$json/map/string[@key='operation']" />
            <xsl:element xmlns="http://tempuri.org/" name="{$operation}">
               <intA>
                  <xsl:value-of select="$json/map/number[@key='intA']" />
               </intA>
               <intB>
                  <xsl:value-of select="$json/map/number[@key='intB']" />
               </intB>
            </xsl:element>
         </soap:Body>
      </soap:Envelope>
   </xsl:template>
</xsl:stylesheet>