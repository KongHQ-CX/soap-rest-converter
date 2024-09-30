<xsl:stylesheet version="3.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:fn="http://www.w3.org/2005/xpath-functions"
    xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
	xpath-default-namespace="http://www.w3.org/2005/xpath-functions"
    exclude-result-prefixes="fn">
    <xsl:output method="xml" indent="yes"/>
    <xsl:template name="main">
        <xsl:param name="request-body" required="yes"/>
        <xsl:variable name="json" select="fn:json-to-xml($request-body)"/>
        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:pet="http://example.com/petstore">
            <soapenv:Body>
                <pet:identification>
                    <xsl:value-of select="$json/map/number[@key='id']" />
                </pet:identification>
                <pet:name>
                    <xsl:value-of select="$json/map/string[@key='name']" />
                </pet:name>
                <pet:photoUrls>
                    <xsl:for-each select="$json/map/array[@key='photoUrls']/string">
                        <pet:url>
                            <xsl:value-of select="."/>
                        </pet:url>
                    </xsl:for-each>
                </pet:photoUrls>
            </soapenv:Body>
        </soapenv:Envelope>
    </xsl:template>
</xsl:stylesheet>