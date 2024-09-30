<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.w3.org/2005/xpath-functions" xmlns:fn="http://www.w3.org/2005/xpath-functions" xmlns:pet="http://example.com/petstore" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" version="3.0" exclude-result-prefixes="fn soapenv pet">
   <xsl:output method="text" />
   <xsl:template match="/soapenv:Envelope/soapenv:Body">
      <xsl:variable name="json-result">
         <map>
            <string key="name">
               <xsl:value-of select="pet:AddPet/pet:name" />
            </string>
            <string key="status">
               <xsl:value-of select="pet:AddPet/pet:status" />
            </string>
            <array key="photoUrls">
               <string>
                  <xsl:value-of select="pet:AddPet/pet:photoUrls/pet:url" />
               </string>
            </array>
         </map>
      </xsl:variable>
      <xsl:value-of select="fn:xml-to-json($json-result)" />
   </xsl:template>
   <xsl:template match="/soapenv:Envelope/soapenv:Header" />
</xsl:stylesheet>