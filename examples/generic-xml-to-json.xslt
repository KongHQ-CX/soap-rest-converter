<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.w3.org/2005/xpath-functions" xmlns:fn="http://www.w3.org/2005/xpath-functions" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" version="3.0" exclude-result-prefixes="fn">
   <xsl:mode on-no-match="shallow-skip" />
   <xsl:output method="text" />
   <xsl:template match="*:Body//*:MUST_BE_REPLACED">
      <xsl:variable name="json-result">
         <map>
            <xsl:call-template name="convert-json" />
         </map>
      </xsl:variable>
      <xsl:value-of select="fn:xml-to-json($json-result)" />
   </xsl:template>
   <!-- Template for converting myInfo fields -->
	<xsl:template name="convert-json">
	    <xsl:for-each select="*">
	        <xsl:choose>
	        	<xsl:when test="local-name() = 'parametre'">
	        		<xsl:variable name="parametreName" select="./*[local-name() = 'nom']" />
                    <xsl:variable name="parametreValue" select="./*[local-name() = 'valeur']" />
                    <!-- Use position() to make the key unique -->
                    <string key="{$parametreName}">
                        <xsl:value-of select="$parametreValue" />
                    </string>
                </xsl:when>
	            <!-- Check if the element is a boolean -->
	            <xsl:when test=". = 'true' or . = 'false'">
	                <boolean key="{local-name()}">
	                    <xsl:value-of select="." />
	                </boolean>
	            </xsl:when>
	            <!-- Check if the element is a map (has child elements) -->
	            <xsl:when test="count(*) > 0">
	                <map key="{local-name()}">
	                    <xsl:call-template name="convert-json" />
	                </map>
	            </xsl:when>
	            <!-- Check if the element is a number -->
	            <xsl:when test="number(.)">
	                <number key="{local-name()}">
	                    <xsl:value-of select="." />
	                </number>
	            </xsl:when>
	            <!-- Default case for string -->
	            <xsl:otherwise>
	                <string key="{local-name()}">
	                    <xsl:value-of select="." />
	                </string>
	            </xsl:otherwise>
	        </xsl:choose>
	    </xsl:for-each>
	</xsl:template>
</xsl:stylesheet>