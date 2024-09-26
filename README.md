# Kong plugins: SOAP to Rest Converter Plugin
This repository concerns Kong plugins developed in Lua and uses the GNOME C libraries [libxml2](https://gitlab.gnome.org/GNOME/libxml2#libxml2). Part of the functions are bound in the [XMLua/libxml2](https://clear-code.github.io/xmlua/) library.
Both GNOME C and XMLua/libxml2 libraries are already included in [kong/kong-gateway](https://hub.docker.com/r/kong/kong-gateway) Enterprise Edition Docker image, so you don't need to rebuild a Kong image.

The XSLT Transformation is managed with the [saxon](https://www.saxonica.com/html/welcome/welcome.html) library, which supports XSLT 2.0 and 3.0. With XSLT 2.0+ there is a way for applying JSON <-> XML transformation with [fn:json-to-xml](https://www.w3.org/TR/xslt-30/#func-json-to-xml) and [fn:xml-to-json](https://www.w3.org/TR/xslt-30/#func-xml-to-json). The saxon library is not included in the Kong Docker image, see [SAXON.md](SAXON.md) for how to integrate saxon with Kong.

These plugins don't apply to Kong OSS. They work for Kong EE and Konnect.

The plugins handle the **Soap to Rest**  and the **Rest to Soap** conversion:

**soap-2-rest**:

1) `XSLT TRANSFORMATION - BEFORE XSD`: Transform the XML request with XSLT (XSLTransformation) before step #2
2) `AUTH TRANSFER`: Retrieve and pass the authentication
3) `XSLT TRANSFORMATION - AFTER XSD`: Transform the XML request with XSLT (XSLTransformation) after step #2
4) `ERROR CHEKCING`: check the error depending of XPath

**rest-2-soap**:

1) `XSLT TRANSFORMATION - BEFORE XSD`: Transform the XML request with XSLT (XSLTransformation) before step #2
2) `AUTH TRANSFER`: Retrieve and pass the authentication
3) `XSLT TRANSFORMATION - AFTER XSD`: Transform the XML request with XSLT (XSLTransformation) after step #2
4) `ERROR CHEKCING`: check the error depending of XPath

Each handling is optional. In case of misconfiguration the Plugin sends to the consumer an HTTP 500 Internal Server Error `<soap:Fault>` (with the error detailed message).

![Alt text](/images/Kong-Manager.png?raw=true "Kong - Manager")

