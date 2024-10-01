<xsl:stylesheet version="2.0" xmlns="MUST_BE_REPLACED" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:fn="http://www.w3.org/2005/xpath-functions" xpath-default-namespace="http://www.w3.org/2005/xpath-functions" exclude-result-prefixes="fn">
  <xsl:output method="xml" indent="yes"/>
  <xsl:template name="main">
    <xsl:param name="request-body" required="yes"/>
    <xsl:variable name="json" select="fn:json-to-xml($request-body)"/>    
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
       	<xsl:apply-templates select="$json"/>
      </soap:Body>
    </soap:Envelope>
  </xsl:template>
   <xsl:template
        match="*[@key]"
        xpath-default-namespace="http://www.w3.org/2005/xpath-functions">
      <xsl:element name="{@key}">
          <xsl:apply-templates/>
      </xsl:element>
  </xsl:template>
</xsl:stylesheet>