<!-- This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/. -->

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:xd="http://www.oxygenxml.com/ns/doc/xsl"
    xmlns:math="http://www.w3.org/2005/xpath-functions/math"
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xmlns:xforms="http://www.w3.org/2002/xforms" 
    xmlns:xhtml="http://www.w3.org/1999/xhtml"
    xmlns:js="http://saxonica.com/ns/globalJS" 
    xmlns:ixsl="http://saxonica.com/ns/interactiveXSLT"
    xmlns:sfl="http://saxonica.com/ns/forms-local"
    xmlns:sfp="http://saxon.sf.net/ns/packages" 
    
    xmlns:in="http://www.w3.org/2002/xforms-instance"
    xmlns:fn="http://www.w3.org/2005/xpath-functions"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns:array="http://www.w3.org/2005/xpath-functions/array"
    xmlns:saxon="http://saxon.sf.net/"
    xmlns:ev="http://www.w3.org/2001/xml-events"
        
    exclude-result-prefixes="xs math xforms sfl sfp"
    extension-element-prefixes="ixsl saxon" version="3.0">
    
    <!-- 
        
        General TO DO list:
    
    
    A proper test suite/demo
    
    Error detection and messaging
    
    Improve messaging around missing/invalid fields
    
    Handlers for more events
        
    Proper handling of @if, @while (I haven't used this before, so need to generate an example to develop against)
    
    Handle more xforms:submission options
    
    Is @targetref handled properly in HTTPsubmit?
    
    Apply improved performance to action-setvalue (i.e. remove use of form-check)
    
    Various other XForms elements and attributes still to be handled
    
    Improve performance (I think some of the simplifications may have slowed down performance, e.g. triggering xforms-rebuild after an insert or delete action rather than granular handling of the HTML)
    
    Improved xforms-value-changed handling, e.g. an <xforms:output> bound to a node and with @ev:event="value-changed" is not handled
    -   when instance value is changed (by setvalue or recalculate), update actions tagged with this event?

    -->
    
    <xsl:include href="xforms-function-library.xsl"/>
    <xsl:include href="xforms-javascript-library.xsl"/>
    
    <xsl:output method="html" encoding="utf-8" omit-xml-declaration="no" indent="no"
        doctype-public="-//W3C//DTD XHTML 1.0 Transitional//EN"
        doctype-system="http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"/>
    
    
    <xd:doc scope="component">
        <xd:desc>Shallow copy by default, e.g. for passing through HTML elements within the XForm.</xd:desc>
    </xd:doc>
    <xsl:mode on-no-match="shallow-copy"/>
    
    <!-- use case where saxon-forms.xsl is imported means we can't yet use a package -->
    <!--<xsl:use-package name="http://saxon.sf.net/packages/logger.xsl" package-version="1.0">
        <xsl:override>
            <xsl:variable name="sfp:LOGLEVEL" select="$LOGLEVEL_INT" as="xs:integer"/>
        </xsl:override>
    </xsl:use-package>-->
    
    <xsl:param name="LOGLEVEL" as="xs:string" select="'40'" required="no"/>
    <xsl:variable name="LOGLEVEL_INT" as="xs:integer" select="if ($LOGLEVEL castable as xs:integer) then xs:integer($LOGLEVEL) else 100"/>

    <xsl:param name="xforms-instance-id" select="'xforms-jinstance'" as="xs:string" required="no"/>
    <xsl:param name="xforms-cache-id" select="'xforms-cache'" as="xs:string" required="no"/>
    
    <!-- @id attribute of HTML div element into which the XForm is to be rendered on the page -->
    <xsl:param name="xform-html-id" as="xs:string" select="'xForm'" required="no"/>
    
    <xsl:param name="xforms-file-global" as="xs:string?"/>
    
    <xsl:param name="xforms-doc-global" as="document-node()?" required="no" select="if (exists($xforms-file-global) and fn:doc-available($xforms-file-global)) then fn:doc($xforms-file-global) else (if (exists(/) and namespace-uri(/*) = ('http://www.w3.org/2002/xforms','http://www.w3.org/1999/xhtml')) then (/) else ())"/>

    <xsl:variable static="yes" name="debugMode" select="true()"/>
    <xsl:variable static="yes" name="debugTiming" select="false()"/>
    <xsl:variable static="yes" name="global-default-model-id" select="'saxon-forms-default-model'" as="xs:string"/>
    <xsl:variable static="yes" name="global-default-instance-id" select="'saxon-forms-default-instance'" as="xs:string"/>
    <xsl:variable static="yes" name="global-default-submission-id" select="'saxon-forms-default-submission'" as="xs:string"/>
    
    <!-- https://www.w3.org/TR/xforms11/#action -->
    <xsl:variable static="yes" name="xforms-actions" select="(
        'setvalue', 
        'insert', 
        'delete',
        'setindex',
        'toggle',
        'setfocus',
        'dispatch',
        'rebuild',
        'recalculate',
        'revalidate',
        'refresh',
        'reset',
        'load',
        'send',
        'message'
        )" as="xs:string+"/>
    
    <!-- 
        https://www.w3.org/TR/xforms11/#controls 
        exclude 'submit' - its handler is different to the rest
    -->
    <xsl:variable static="yes" name="xforms-controls" as="xs:string+" select="(
        'input',
        'secret',
        'textarea',
        'output',
        'upload',
        'range',
        'trigger',
        'select',
        'select1'
        )"/>
    
    <xsl:variable name="models-global" as="element(xforms:model)*" select="//xforms:model"/>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Main initial template.</xd:p>
            <xd:p>Writes Javascript code into HTML page.</xd:p>
            <xd:p>Sets instances in Javascript variables and as a map.</xd:p>
            <xd:p>Registers bindings and submissions as maps.</xd:p>
        </xd:desc>
        <xd:param name="xforms-doc">Complete XForms document.</xd:param>
        <xd:param name="xforms-file">File path to XForms document.</xd:param>
        <xd:param name="instance-docs">All instances in the XForms document. (When completely refreshing the form from JS set parameters, bypassing the need to go back to an original XForm.)</xd:param>
        <xd:param name="xFormsId">The @id of an HTML div on the page into which the XForm will be rendered.</xd:param>
    </xd:doc>
    <xsl:template name="xformsjs-main">
        <xsl:param name="xforms-doc" as="document-node()?" required="no" select="()"/>
        <xsl:param name="xforms-file" as="xs:string?" required="no"/>
        <xsl:param name="instance-docs" as="map(*)?" required="no"/>   
        <xsl:param name="xFormsId" select="$xform-html-id" as="xs:string" required="no"/>
        
        <xsl:message use-when="$debugMode">[xformsjs-main] START</xsl:message>

        <!-- $xforms-doc-local helps to support XForms in an iframe -->
        <xsl:variable name="xforms-doc-local" as="document-node()" select="ixsl:page()"/>

        <xsl:apply-templates select="$xforms-doc-local/*:html/*:head" mode="set-js"/>
        
       
        <!-- 
            Populate $xforms-doci (local to this template) 
            using explicit parameter values if present
            (since this template can be called from an importing stylesheet),
            then falling back to global parameters
        -->
        <xsl:variable name="xforms-doci" as="document-node()?">
            <xsl:choose>
                <xsl:when test="$xforms-doc">
                    <xsl:sequence select="$xforms-doc"/>
                </xsl:when>
                <xsl:when test="fn:doc-available($xforms-file)">
                    <xsl:sequence select="fn:doc($xforms-file)"/>
                </xsl:when>
                <!-- if the "global" xforms doc is HTML we take this (iframe) HTML  -->
                <xsl:when test="exists($xforms-doc-global/xhtml:html)">
                    <xsl:sequence select="$xforms-doc-local"/>
                </xsl:when>
                <xsl:when test="$xforms-doc-global">
                    <xsl:sequence select="$xforms-doc-global"/>
                </xsl:when>
                <xsl:when test="exists($xforms-file)">
                    <xsl:message terminate="yes">[xformsjs-main] Unable to locate XForm file at <xsl:sequence select="$xforms-file"/></xsl:message>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:message terminate="yes">[xformsjs-main] Unable to locate XForm!</xsl:message>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        
        <xsl:variable name="xform-doc-ns" as="document-node()" select="xforms:addNamespaceDeclarationsToDocument($xforms-doci)"/>  
        <xsl:variable name="xform" as="element()" select="$xform-doc-ns/*"/>  
        
        <xsl:message use-when="$debugMode">[xformsjs-main] doc with ns added: <xsl:sequence select="fn:serialize($xform)"/></xsl:message>
        
        <xsl:variable name="models" as="element(xforms:model)*" select="$xform-doc-ns/(xforms:xform|xhtml:html/xhtml:head)/xforms:model"/>
        <xsl:variable name="first-model" as="element(xforms:model)?" select="$models[1]"/>
        <xsl:variable name="first-model-id" as="attribute()?" select="$first-model/@id"/>
        <xsl:variable name="first-instance" as="element(xforms:instance)" select="$first-model/xforms:instance[1]"/>
        <xsl:variable name="first-instance-id" as="attribute()?" select="$first-instance/@id"/>
        <xsl:variable name="default-model-id" as="xs:string" select="if (exists($first-model-id)) then $first-model-id else $global-default-model-id"/>
        <xsl:variable name="default-instance-id" as="xs:string" select="if (exists($first-instance-id)) then $first-instance-id else $global-default-instance-id"/>
        
        
        
        <xsl:if test="count($models[not(@id)]) gt 1">
            <xsl:variable name="message" as="xs:string" select="'[xformsjs-main] FATAL ERROR: The XForm contains more than one model with no ID. At most one model may have no ID.'"/>
            <xsl:message terminate="yes" select="$message"/>
        </xsl:if>
        <xsl:for-each select="$models">
            <xsl:message use-when="$debugMode">[xformsjs-main] Construct model ...</xsl:message>
            <!-- bindings are set here -->
            <xsl:call-template name="xforms-model-construct">
                <xsl:with-param name="model" select="." tunnel="yes"/>
                <xsl:with-param name="all-models" select="$models" tunnel="yes"/>
                <xsl:with-param name="default-model-id" select="$default-model-id" tunnel="yes"/>
                <xsl:with-param name="default-instance-id" select="$default-instance-id" tunnel="yes"/>
                <xsl:with-param name="default-namespace-context" select="$xform-doc-ns/*" tunnel="yes"/>
            </xsl:call-template>                       
        </xsl:for-each>    
        
        
        <!-- populate Javascript variables -->
        <xsl:sequence select="js:setXFormsDoc($xform-doc-ns)"/>
        
        <xsl:sequence select="js:setXForm($xform)"/>
        <!-- clear deferred update flags only if we're building from scratch -->
        <xsl:if test="empty($instance-docs)">
            <xsl:sequence select="js:clearDeferredUpdateFlags()" />    
        </xsl:if>
        
        <!-- register submissions in a map -->
        <xsl:variable name="submissions" as="map(xs:string, map(*))">
            <xsl:map>
                <xsl:for-each select="$models/xforms:submission">
                    <xsl:variable name="map-key" as="xs:string" select="
                        if (@id) then xs:string(@id)
                        else if (@ref) then xs:string(@ref) 
                        else $global-default-submission-id
                        "/>
                    <xsl:variable name="map-value" as="map(*)">
                        <xsl:call-template name="setSubmission">
                            <xsl:with-param name="this" select="."/>
                            <xsl:with-param name="submission-id" select="$map-key"/>
                            <xsl:with-param name="default-instance-id" select="$default-instance-id" tunnel="yes"/>
                            <xsl:with-param name="default-namespace-context" select="$xform-doc-ns/*" tunnel="yes"/>
                        </xsl:call-template>
                    </xsl:variable>
                    <xsl:map-entry key="$map-key" select="$map-value"/>
                </xsl:for-each>
            </xsl:map>
        </xsl:variable>
        
        
        <!-- add each submission to the Javascript variable -->
        <xsl:variable name="submissionKeys" select="map:keys($submissions)" as="xs:string*"/>
        
        <xsl:for-each select="$submissionKeys">
            <xsl:variable name="submission" select="map:get($submissions, .)" as="map(*)" />  
            <xsl:sequence select="js:addSubmission(.,$submission)"/>
        </xsl:for-each>
        

        <xsl:variable name="log-label" as="xs:string" select="'XForms Main Build'"/>
        <xsl:variable name="time-id" select="concat($log-label, ' ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id)" />
                
        <xsl:choose>
            <xsl:when test="exists($xform-doc-ns/xhtml:html)">
                <xsl:message use-when="$debugMode">[xformsjs-main] Replacing HTML body</xsl:message>
                <xsl:apply-templates select="$models,ixsl:page()/xhtml:html/xhtml:body">
                    <xsl:with-param name="bindings-js" select="js:getBindings()" as="element(xforms:bind)*" tunnel="yes"/>
                    <xsl:with-param name="submissions" select="$submissions" as="map(xs:string, map(*))" tunnel="yes"/>
                    <xsl:with-param name="model-key" select="$default-model-id" tunnel="yes"/>
                    <xsl:with-param name="default-instance-id" select="$default-instance-id" tunnel="yes"/>
                    <xsl:with-param name="default-namespace-context" select="$xform-doc-ns/*" tunnel="yes"/>
                </xsl:apply-templates>
            </xsl:when>
            <xsl:otherwise>
                <!-- 
                    Write HTML to placeholder <div id="xForm"> 
                    
                    For XForms embedded in HTML:
                    "If the href supplied does not match an existing element in the HTML page, the xsl:result-document instruction is ignored and the transform will continue to completion."
                    https://www.saxonica.com/saxon-js/documentation2/index.html#!browser/result-documents
                -->
                <xsl:result-document href="#{$xFormsId}" method="ixsl:replace-content">
                    <xsl:apply-templates select="$xform-doc-ns/xforms:xform">
                    <!--<xsl:apply-templates select="$xform-doc-ns/xforms:xform, $xform-doc-ns/xhtml:html/xhtml:head/xforms:model, $xform-doc-ns/xhtml:html/xhtml:body/*">-->
                        <xsl:with-param name="bindings-js" select="js:getBindings()" as="element(xforms:bind)*" tunnel="yes"/>
                        <xsl:with-param name="submissions" select="$submissions" as="map(xs:string, map(*))" tunnel="yes"/>
                        <xsl:with-param name="model-key" select="$default-model-id" tunnel="yes"/>
                        <xsl:with-param name="default-instance-id" select="$default-instance-id" tunnel="yes"/>
                        <xsl:with-param name="default-namespace-context" select="$xform-doc-ns/*" tunnel="yes"/>
                    </xsl:apply-templates>
                </xsl:result-document>
            </xsl:otherwise>
        </xsl:choose>
        
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id)" />
        
        <xsl:call-template name="xforms-ready"/>
        
    </xsl:template>


    <xd:doc scope="component">
        <xd:desc>Add Javascript to HTML head element</xd:desc>
    </xd:doc>
    <xsl:template match="*:head" mode="set-js">
        <!-- 
            for ixsl:page() 
            see http://www.saxonica.com/saxon-js/documentation/index.html#!ixsl-extension/functions/page
                    
            "the document node of the HTML DOM document"
            
            for href="?." 
            see http://www.saxonica.com/saxon-js/documentation/index.html#!development/result-documents
                        
            "the current context item as the target for inserting a generated fragment of HTML"
        -->
        
        <xsl:if test="not(ixsl:page()//script/@id = $xforms-cache-id)">
            <xsl:result-document href="?.">
                <script type="text/javascript" id="{$xforms-cache-id}">
                    <xsl:sequence select="$saxon-forms-javascript"/>
                    <!-- 
                        error "Cross origin requests are only supported for HTTP." when trying to load .js file
                    -->
                    <!--<xsl:sequence select="unparsed-text('xforms-javascript-library.js')"/>-->
                </script>
            </xsl:result-document>   
        </xsl:if>
        
     </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>Replace content of HTML body element, when XForm is embedded within XHTML.</xd:desc>
        <xd:param name="default-namespace-context">The HTML element that contains the XForm.</xd:param>
    </xd:doc>
    <xsl:template match="*:body">
        <xsl:param name="default-namespace-context" as="element()" tunnel="yes"/>
        <xsl:result-document href="?." method="ixsl:replace-content">
            <xsl:comment>Replacing HTML body with processed XForm</xsl:comment>
            <xsl:apply-templates select="$default-namespace-context/xhtml:head/xhtml:model, $default-namespace-context/xhtml:body/*"/>
        </xsl:result-document>   
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>If an attribute value is wrapper for evaluation in {}, register it as an output.</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="@*[starts-with(normalize-space(.),'{')]">
        <xsl:variable name="myid" as="xs:string" select="if (exists(../@id)) then ../@id else generate-id()"/>
        <xsl:variable name="nodeset" as="xs:string" select="
            substring-before(
                substring-after(
                    normalize-space(.), '{'
                ), '}'    
            )"/>
        
        <xsl:call-template name="registerOutput">
            <xsl:with-param name="id" select="$myid" tunnel="yes"/>
            <xsl:with-param name="nodeset" select="$nodeset" tunnel="yes"/>
        </xsl:call-template>
    </xsl:template>
    
    
    
    <xd:doc scope="component">
        <xd:desc>Handle incremental change to HTML input</xd:desc>
    </xd:doc>
    <xsl:template match="*:input[xforms:hasClass(.,'incremental')]" mode="ixsl:onkeyup">
        <xsl:call-template name="action-setvalue-form-control">
            <xsl:with-param name="form-control" select="."/>
        </xsl:call-template>
        <xsl:call-template name="outermost-action-handler"/>
    </xsl:template>


    <xd:doc scope="component">
        <xd:desc>Handle change to HTML form control value (except when control has "incremental" set)</xd:desc>
    </xd:doc>
    <xsl:template match="*:input[not(xforms:hasClass(.,'incremental'))] | *:select | *:textarea" mode="ixsl:onchange">
        <xsl:message use-when="$debugMode">[isxl:onchange mode] HTML form control '<xsl:sequence select="name()"/>' value changed</xsl:message>
        <xsl:call-template name="action-setvalue-form-control">
            <xsl:with-param name="form-control" select="."/>
        </xsl:call-template>
        <xsl:call-template name="outermost-action-handler"/>
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Highlight repeat item when selected</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="*:div[@data-repeat-item = 'true']//*[self::*:span or self::*:input]" mode="ixsl:onclick">
        <xsl:if test="exists(@id) and not(@id = '')">
            <xsl:sequence select="js:highlightClicked( string(@id) )"/>
        </xsl:if>
        
                
        <!-- update repeat index of ancestors (we may have clicked on a repeat item within a repeat item) -->
        <xsl:for-each select="./ancestor::*:div[@data-repeat-item = 'true']">
            <xsl:variable name="repeat-id" as="xs:string" select="./ancestor::*:div[exists(@data-repeatable-context)][1]/@id"/>
            <xsl:variable name="item-position" as="xs:integer" select="count(./preceding-sibling::*:div[@data-repeat-item = 'true']) + 1"/>
            
            <xsl:message use-when="$debugMode">[div onclick] Setting repeat index '<xsl:value-of select="$repeat-id"/>' to value '<xsl:value-of select="$item-position"/>'</xsl:message>
            <xsl:sequence select="js:setRepeatIndex($repeat-id,$item-position)"/>                        
        </xsl:for-each>
        
        <xsl:if test="self::*:span">
            <xsl:call-template name="refreshElementsUsingIndexFunction-JS"/>     
        </xsl:if>
       
        
       <!-- <xsl:if test="self::input">
            <xsl:sequence select="js:setFocus( xs:string(@id) )"/>    
        </xsl:if>-->
        

    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>get-context-instance-id mode: return ID of instance that is the context of an XForms element.</xd:p>
            <xd:p>Called from xforms:bind match template (add-context mode)</xd:p>
        </xd:desc>
        <xd:param name="model-key">ID of context model (xforms:model/@id value or default value).</xd:param>
        <xd:param name="default-instance-id">ID of default instance in XForm.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
    </xd:doc>
    <xsl:template match="xforms:*" mode="get-context-instance-id" as="xs:string">
        <xsl:param name="model-key" as="xs:string" required="no" select="$global-default-model-id" tunnel="yes"/>        
        <xsl:param name="default-instance-id" as="xs:string" required="no" select="$global-default-instance-id" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" required="no" select="''"/>
        
        <xsl:variable name="log-label" as="xs:string" select="concat('[get-context-instance-id mode for ', name(), ']')"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        <xsl:variable name="time-id" select="concat($log-label, ' ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id)" />    

        <xsl:variable name="model-ref" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists(@model)">
                    <xsl:sequence select="string(@model)"/>
                </xsl:when>
                <xsl:when test="self::xforms:bind">
                    <xsl:variable name="bind-model-id" select="./ancestor::xforms:model/@id"/>
                    <xsl:sequence select="if (exists($bind-model-id)) then string($bind-model-id) else $model-key"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="$model-key"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <!-- use $nodeset if present -->
        <xsl:variable name="referenced-instance-id" as="xs:string?" select="if ($nodeset ne '') then xforms:getInstanceId($nodeset) else ()"/>
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $referenced-instance-id = <xsl:sequence select="$referenced-instance-id"/></xsl:message>
          
        <xsl:choose>
            <!-- take non-default instance ID if it is made explicit -->
            <xsl:when test="exists($referenced-instance-id) and not($referenced-instance-id = $global-default-instance-id)">
                <xsl:sequence select="$referenced-instance-id"/>
            </xsl:when>
            <xsl:otherwise>
                <!-- take first available of: model explicitly referenced with @model, ancestor model, default model -->
                <xsl:variable name="context-model" as="element(xforms:model)" select="
                    ($models-global[@id = $model-ref], ./ancestor::xforms:model, $models-global[1])[1]"/>
                
                <xsl:variable name="local-default-instance" as="element(xforms:instance)?" select="$context-model/xforms:instance[1]"/>
                <xsl:choose>
                    <xsl:when test="exists($local-default-instance)">
                        <xsl:sequence select="if (exists($local-default-instance/@id)) then xs:string($local-default-instance/@id) else $global-default-instance-id"/>
                    </xsl:when>
                    <!-- use default instance of XForm if there is nothing else to go on -->
                    <xsl:otherwise>
                        <xsl:sequence select="$default-instance-id"/>
                    </xsl:otherwise>
                </xsl:choose>
                
            </xsl:otherwise>
        </xsl:choose>
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id)" />
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>get-properties mode: return map containing the properties associated with an XForms element (taken from its binding if present)</xd:desc>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="model-key">ID of context model (xforms:model/@id value or default value).</xd:param>
        <xd:param name="bindings-js">Node set of xforms:bind elements</xd:param>   
        <xd:param name="default-instance-id">Context instance ID</xd:param>
        <xd:param name="default-namespace-context">Root element containing all namespace declarations</xd:param>
    </xd:doc>
    <xsl:template match="xforms:*" mode="get-properties">
        <xsl:param name="nodeset" as="xs:string" select="''" tunnel="yes"/>
        <xsl:param name="model-key" as="xs:string" required="no" select="$global-default-model-id" tunnel="yes"/>        
        <xsl:param name="bindings-js" as="element(xforms:bind)*" required="no" select="()" tunnel="yes"/>
        <xsl:param name="default-instance-id" as="xs:string" required="no" select="$global-default-instance-id" tunnel="yes"/>
        <xsl:param name="default-namespace-context" as="element()" required="yes" tunnel="yes"/>
        
        <xsl:variable name="log-label" as="xs:string" select="concat('[get-properties mode for ', name(), ']')"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        
        <xsl:variable name="time-id" select="concat($log-label, ' ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id)" />   
        
        <xsl:variable name="binding-referenced-by-id" as="element(xforms:bind)?">
            <xsl:choose>
                <xsl:when test="exists(@bind)">
                    <xsl:variable name="bind" as="xs:string" select="xs:string(@bind)"/>
                    <xsl:sequence select="$bindings-js[@id = $bind]"/>
                </xsl:when>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="model-ref" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists(@model)">
                    <xsl:sequence select="string(@model)"/>
                </xsl:when>
                <xsl:when test="exists($binding-referenced-by-id)">
                    <xsl:sequence select="string($binding-referenced-by-id/@model-context)"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="$model-key"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="context-model" as="element(xforms:model)" select="
            ($models-global[@id = $model-ref], ./ancestor::xforms:model, $models-global[1])[1]"/>
        
        <xsl:variable name="context-nodeset" as="xs:string" select="if (exists(@context)) then xforms:resolveXPathStrings($nodeset,@context) else (if ($nodeset ne '') then $nodeset else ('instance(''' || $default-instance-id || ''')'))"/>
        
        <!-- empty if @iterate not set (so we only set the 'iterate' property when there is iteration) -->
        <xsl:variable name="context-nodeset-iterate" as="xs:string?" select="if (exists(@iterate)) then xforms:resolveXPathStrings($context-nodeset,@iterate) else ()"/>
        
        <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $context-nodeset = <xsl:sequence select="$context-nodeset"/></xsl:message>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $context-nodeset-iterate = <xsl:sequence select="$context-nodeset-iterate"/></xsl:message>-->
        
        <xsl:variable name="this-ref" as="xs:string?" select="
            if ( exists(@ref) ) 
            then normalize-space( xs:string(@ref) ) 
            else if ( exists(@nodeset) )
            then  normalize-space( xs:string(@nodeset) )
            else ()"/>
        
        <xsl:variable name="refi" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists($binding-referenced-by-id)">
                    <xsl:sequence select="string($binding-referenced-by-id/@nodeset)"/>
                </xsl:when>
                <xsl:when test="exists($this-ref)">
                    <!-- context is iterate context if set, fall back to context-nodeset -->
                    <xsl:sequence select="xforms:resolveXPathStrings(($context-nodeset-iterate,$context-nodeset)[1],$this-ref)"/>
                </xsl:when>
                <xsl:when test="$nodeset != ''">
                    <xsl:sequence select="$nodeset"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="concat('instance(''',$default-instance-id,''')')"/>
                </xsl:otherwise>
            </xsl:choose>           
        </xsl:variable>
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $refi = <xsl:sequence select="$refi"/></xsl:message>
        
        <xsl:variable name="instance-context" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists($binding-referenced-by-id)">
                    <xsl:sequence select="string($binding-referenced-by-id/@instance-context)"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="xforms:getInstanceId($refi)"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="bindings-this-instance" as="element(xforms:bind)*" select="$bindings-js[@instance-context = $instance-context]"/>
                
         
        <xsl:variable name="binding-matching-nodeset" as="element(xforms:bind)?">
            <xsl:choose>
                <xsl:when test="exists($binding-referenced-by-id)"/>
                <xsl:when test="$refi != '' and exists($bindings-this-instance)">
                    <xsl:variable name="nodeset-mod" as="xs:string" select="xforms:impose($refi)"/>
                    <xsl:variable name="instanceXML" as="element()">
                        <xsl:variable name="intanceXMLWithID" as="element()?" select="$context-model/xforms:instance[@id = $instance-context]"/>
                        <xsl:choose>
                            <xsl:when test="exists($intanceXMLWithID)">
                                <xsl:sequence select="$intanceXMLWithID"/>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:sequence select="$context-model/xforms:instance[1]"/>
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:variable>
                    
                    <xsl:for-each select="$bindings-this-instance">
                        <xsl:variable name="binding-nodeset-mod" as="xs:string" select="xforms:impose(xs:string(@nodeset))"/>
                        
                        <xsl:variable name="context-node" as="node()*" select="xforms:evaluate-xpath-with-context-node($nodeset-mod,$instanceXML,$default-namespace-context)"/>
                        
                        <xsl:choose>
                            <!-- do a string check here of $nodeset-mod = $binding-nodeset-mod (as a shortcut before performing XPath evaluation) -->
                            <xsl:when test="$nodeset-mod = $binding-nodeset-mod">
                                <xsl:sequence select="."/>
                                <xsl:message use-when="$debugMode">[get-properties mode] Binding found by matching nodeset path '<xsl:sequence select="$nodeset-mod"/>'</xsl:message>
                            </xsl:when>
                            <!-- 
                                ignore when context is a nodeset
                            -->
                            <xsl:when test="count($context-node) > 1"/>
                            <xsl:otherwise>
                                <xsl:variable name="binding-context-node" as="node()*" select="xforms:evaluate-xpath-with-context-node($binding-nodeset-mod,$instanceXML,$default-namespace-context)"/>
                                
                                <xsl:if test="some $n in $binding-context-node satisfies $n is $context-node">
                                    <xsl:message use-when="$debugMode">[get-properties mode for <xsl:value-of select="name(.)"/>] Binding found by matching nodeset: <xsl:value-of select="serialize(.)"/></xsl:message>
                                    <xsl:sequence select="."/>
                                </xsl:if>        
                            </xsl:otherwise>
                        </xsl:choose>
                    </xsl:for-each>
                </xsl:when>
                <xsl:otherwise>
                    <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> No binding found matching nodeset</xsl:message>-->
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        
        <xsl:variable name="binding" as="element(xforms:bind)?" select="($binding-referenced-by-id,$binding-matching-nodeset)[1]"/>
        
        <xsl:variable name="context-nodeset" as="xs:string" select="if (exists($binding)) then string($binding/@nodeset) else $nodeset"/>
                
                 
        <xsl:map>
            <xsl:map-entry key="'nodeset'" select="$refi"/>
            <xsl:map-entry key="'context-nodeset'" select="$context-nodeset"/>
            <xsl:map-entry key="'instance-context'" select="$instance-context"/>
            <xsl:map-entry key="'model-id'" select="$model-ref"/>
            <xsl:if test="exists($binding)">
                <xsl:map-entry key="'binding'" select="$binding"/>
            </xsl:if>
            <xsl:if test="exists($context-nodeset-iterate)">
                <xsl:map-entry key="'iterate'" select="$context-nodeset-iterate"/>
            </xsl:if>
        </xsl:map>
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id)" />
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
        
    </xsl:template>
    

    <xd:doc scope="component">
        <xd:desc>set-actions mode: create map of actions relevant to XForm control element</xd:desc>
    </xd:doc>
    <xsl:template match="xforms:*" mode="set-actions">
        <xsl:apply-templates select=" xforms:action | xforms:*[local-name() = $xforms-actions] | xforms:show | xforms:hide | xforms:script | xforms:unload"/>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>set-action mode: create map of an action relevant to XForm action element</xd:desc>
        <xd:param name="default-instance-id">ID of context instance.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="handler-status">String value 'outermost' (default) or 'inner' to determine whether the action produces <xd:a href="https://www.w3.org/TR/xforms11/#action-deferred-update-behavior">deferred updates</xd:a></xd:param>
    </xd:doc>
    <xsl:template match="xforms:*" mode="set-action">
        <xsl:param name="default-instance-id" as="xs:string" required="no" select="$global-default-instance-id" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" select="''" tunnel="yes"/>
        <xsl:param name="handler-status" select="'outermost'" required="no" tunnel="yes"/>
        
        <xsl:variable name="log-label" as="xs:string" select="concat('[set-action mode for ', name(), ']')"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        <xsl:variable name="time-id" select="concat($log-label, ' ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id)" />    
        
        <xsl:variable name="this-properties" as="map(*)">
            <xsl:apply-templates select="." mode="get-properties"/>  
        </xsl:variable>
        
        <xsl:variable name="refi" as="xs:string" select="map:get($this-properties,'nodeset')"/>
        <xsl:variable name="context-nodeset" as="xs:string" select="map:get($this-properties,'context-nodeset')"/>
        <xsl:variable name="this-instance-id" as="xs:string" select="map:get($this-properties,'instance-context')"/>
        
<!--        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $refi = <xsl:sequence select="$refi"/></xsl:message>-->
        
        <xsl:variable name="action-map" as="map(*)">
            <xsl:map>
                <xsl:map-entry key="'name'" select="local-name()"/>            
                <xsl:map-entry key="'handler-status'" select="$handler-status"/>            
                <xsl:map-entry key="'instance-context'" select="$this-instance-id"/>
                
                <xsl:if test="exists(@value)">
                    <xsl:map-entry key="'@value'" select="xforms:resolveContext(string(@value),$nodeset)" />                          
                </xsl:if>
                
                <xsl:if test="empty(@value) and exists(./text()) and not(self::xforms:message)">
                    <xsl:map-entry key="'value'" select="string(.)" />                         
                </xsl:if>
                
                <xsl:map-entry key="'@ref'" select="$refi"/>
                
                <!-- local ref used in conjunction with node set returned by @iterate -->
                <xsl:if test="exists(@ref) or exists(@nodeset)">
                    <xsl:map-entry key="'@ref-local'" select="normalize-space( xs:string((@ref,@nodeset)[1]) )"/>
                </xsl:if>
                
                <!-- 
                for @at and @position,
                see https://www.w3.org/TR/xforms11/#action-insert
            -->
                <xsl:if test="exists(@position)">
                    <xsl:map-entry key="'@position'" select="string(@position)" />
                </xsl:if>
                <xsl:if test="exists(@at)">
                    <xsl:map-entry key="'@at'" select="string(@at)" />
                </xsl:if>
                
                <!-- https://www.w3.org/TR/xforms11/#action-conditional -->
                <xsl:if test="exists(@if)">
                    <xsl:map-entry key="'@if'" select="string(@if)" />
                </xsl:if>
                
                <!-- https://www.w3.org/TR/xforms11/#action-iterated -->
                <xsl:if test="exists(@while)">
                    <xsl:map-entry key="'@while'" select="string(@while)" />
                </xsl:if>
                
                <!-- https://www.w3.org/community/xformsusers/wiki/XForms_2.0#The_iterate_attribute -->
                <xsl:if test="exists(@iterate)">
                    <xsl:map-entry key="'@iterate'" select="map:get($this-properties,'iterate')" />
                </xsl:if>
                
                <xsl:if test="exists(@*:event)">
                    <xsl:map-entry key="'@event'" select="string(@*:event)" />
                </xsl:if>
                <xsl:if test="exists(@submission)">
                    <xsl:map-entry key="'@submission'" select="string(@submission)" />
                </xsl:if>
                
                <xsl:if test="exists(@model)">
                    <xsl:map-entry key="'@model'" select="string(@model)" />
                </xsl:if>
                
                <xsl:if test="exists(@control)">
                    <xsl:map-entry key="'@control'" select="string(@control)" />
                </xsl:if>
                
                <xsl:if test="exists(@repeat)">
                    <xsl:map-entry key="'@repeat'" select="string(@repeat)" />
                </xsl:if>
                
                <xsl:if test="exists(@index)">
                    <xsl:map-entry key="'@index'" select="string(@index)" />
                </xsl:if>
                
                <xsl:if test="exists(@level)">
                    <xsl:map-entry key="'@level'" select="string(@level)" />
                </xsl:if>
                
                <xsl:if test="exists(@origin)">
                    <xsl:variable name="origin-context" as="xs:string" select="
                        if (exists(@context)) 
                        then xforms:resolveXPathStrings($nodeset,@context)
                        else $nodeset"/>
                    
                    <xsl:variable name="origin-ref" as="xs:string" select="xforms:resolveXPathStrings($origin-context,@origin)"/>
                    
                    <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> @origin = <xsl:sequence select="$origin-ref"/></xsl:message>-->
                    
                    <xsl:map-entry key="'@origin'" select="$origin-ref" />    
                </xsl:if>
                
                <xsl:map-entry key="'@context'" select="if (exists(@context)) then xforms:resolveXPathStrings($nodeset,@context) else $nodeset" />   
                
                <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> @context = <xsl:sequence select="xforms:resolveXPathStrings($nodeset,@context)"/></xsl:message>-->
                
                <!-- https://www.w3.org/TR/xforms11/#action-toggle -->
                <xsl:if test="exists(@case)">
                    <xsl:map-entry key="'@case'" select="string(@case)"/>
                </xsl:if>
                <xsl:if test="exists(child::xforms:case)">
                    <xsl:map-entry key="'case'" select="if (xforms:case/text()[normalize-space() ne '']) then xforms:case/text() else string(xforms:case/@value)"/>
                </xsl:if>
                
                <!-- need to apply nested actions in order! -->            
                <xsl:if test="(child::* and not(self::xforms:toggle)) or (self::xforms:message and child::text())">
                    <xsl:map-entry key="'nested-actions'">
                        <xsl:variable name="array" as="map(*)*">
                            <xsl:for-each select="child::node()[self::* or self::text()[parent::xforms:message]]">
                                <xsl:apply-templates select="." mode="set-action">
                                    <xsl:with-param name="default-instance-id" select="$this-instance-id" tunnel="yes"/>
                                    <xsl:with-param name="nodeset" select="$refi" tunnel="yes"/>
                                    <xsl:with-param name="handler-status" select="'inner'" tunnel="yes"/>
                                </xsl:apply-templates>
                            </xsl:for-each>
                        </xsl:variable>
                        <xsl:sequence select="array{$array}" />
                    </xsl:map-entry>
                </xsl:if>
                
            </xsl:map>
        </xsl:variable>
        
       
        
        
        <xsl:sequence select="$action-map"/>
        <xsl:if test="exists(@*:event)">
            <xsl:sequence select="js:addEventAction( string(@*:event), $action-map )"/>    
        </xsl:if>

        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id)" />
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
        
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Turn a text node (inside xforms:message) into an action.</xd:p>
            <xd:p>Enables handling of mixed text() and xforms:output children of xforms:message.</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="text()" mode="set-action">
        <xsl:map>
            <xsl:map-entry key="'name'" select="'text'"/>    
            <xsl:map-entry key="'instance-context'" select="$global-default-instance-id"/>    
            <xsl:map-entry key="'handler-status'" select="'inner'"/>    
            <xsl:map-entry key="'@value'" select="string(.)" />
        </xsl:map>
    </xsl:template>
    
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Function to get the ID of a repeat from a string containing an XForms index() function</xd:p>
        </xd:desc>
        <xd:param name="string-to-parse">A String</xd:param>
        <xd:return>Value of repeat ID (if present)</xd:return>
    </xd:doc>
    <xsl:function name="xforms:getRepeatID" as="xs:string?">
        <xsl:param name="string-to-parse" as="xs:string"/>
        
        <xsl:analyze-string select="$string-to-parse" regex="^.*index\s*\(\s*&apos;([^&apos;]+)&apos;\s*\).*$">
            <xsl:matching-substring>
                <xsl:sequence select="regex-group(1)"/>
            </xsl:matching-substring>
            <xsl:non-matching-substring>
                <xsl:message>[xforms:getRepeatID] No repeat identifiable from value '<xsl:value-of select="$string-to-parse"/>'</xsl:message>
            </xsl:non-matching-substring>
        </xsl:analyze-string>
        
        

    </xsl:function>
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Function to get 'if' statement from an action map</xd:p>
        </xd:desc>
        <xd:return>Value of map entry for @if (XPath expression)</xd:return>
        <xd:param name="map">Action map</xd:param>
    </xd:doc>
    <xsl:function name="xforms:getIfStatement" as="xs:string?">
        <xsl:param name="map" as="map(*)"/>
        <xsl:sequence select="map:get($map, '@if')"/>
    </xsl:function>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Function to get 'while' statemenmt from an action map</xd:p>
        </xd:desc>
        <xd:return>Value of map entry for @while (XPath expression)</xd:return>
        <xd:param name="map">Action map</xd:param>
    </xd:doc>
    <xsl:function name="xforms:getWhileStatement" as="xs:string?">
        <xsl:param name="map" as="map(*)"/>
        <xsl:sequence select="map:get($map, '@while')"/>
    </xsl:function>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Function to get 'iterate' statemenmt from an action map</xd:p>
        </xd:desc>
        <xd:return>Value of map entry for @iterate (XPath expression)</xd:return>
        <xd:param name="map">Action map</xd:param>
    </xd:doc>
    <xsl:function name="xforms:getIterateStatement" as="xs:string?">
        <xsl:param name="map" as="map(*)"/>
        <xsl:sequence select="map:get($map, '@iterate')"/>
    </xsl:function>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Function to resolve @ref relative to a context XPath</xd:p>
            <xd:p>Handles parent '..' steps in relative XPath</xd:p>
            <xd:p>OND comment: "Only to use this function on simple path cases"</xd:p>
        </xd:desc>
        <xd:return>Resolved XPath statement combining base and relative</xd:return>
        <xd:param name="base">Context XPath.</xd:param>
        <xd:param name="relative">XPath relative to base.</xd:param>
    </xd:doc>
    <xsl:function name="xforms:resolveXPathStrings" as="xs:string">
        <xsl:param name="base" as="xs:string"/>
        <xsl:param name="relative" as="xs:string"/>
        
        <!-- first get full path -->
        <xsl:variable name="full-path" as="xs:string">
            <xsl:choose>
                <xsl:when test="starts-with($relative,'/')">
<!--                    <xsl:sequence select="$relative"/>-->
                    <!-- remove root element from XPath -->
                    <xsl:analyze-string select="$relative" regex="^/[^/]+/(.*)$">
                        <xsl:matching-substring>
                            <xsl:sequence select="$base || '/' || regex-group(1)"/>
                        </xsl:matching-substring>
                        <xsl:non-matching-substring>
                            <xsl:message>[xforms:resolveXPathStrings] Invalid XPath: '<xsl:value-of select="$relative"/>'</xsl:message>
                        </xsl:non-matching-substring>
                    </xsl:analyze-string>
                </xsl:when>
                <xsl:when test="starts-with($relative,'instance(')">
                    <xsl:sequence select="$relative"/>
                </xsl:when>
                <xsl:when test="$base = ''">
                    <xsl:sequence select="$relative"/>
                </xsl:when>
                <xsl:when test="$relative = '' or $relative = '.'">
                    <xsl:sequence select="$base"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="concat($base,'/',$relative)"/>                    
                </xsl:otherwise>
            </xsl:choose>            
        </xsl:variable>
                
        <xsl:sequence select="$full-path"/>

    </xsl:function>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Function to resolve XForms 'context()' function in an XPath expression</xd:p>
            <xd:p>See <xd:a href="https://www.w3.org/TR/xforms11/#fn-context">7.10.4 The context() Function</xd:a></xd:p>
        </xd:desc>
        <xd:return>Resolved XPath statement</xd:return>
        <xd:param name="xpath">Context XPath.</xd:param>
        <xd:param name="context">XPath expression for context node set.</xd:param>
    </xd:doc>
    <xsl:function name="xforms:resolveContext" as="xs:string">
        <xsl:param name="xpath" as="xs:string"/>
        <xsl:param name="context" as="xs:string"/>
        
        <xsl:sequence select="replace($xpath,'context\(\)',$context)"/>
        
    </xsl:function>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Evaluate XPath relative to a context node</xd:p>
        </xd:desc>
        <xd:param name="xpath">XPath expression</xd:param>
        <xd:param name="context-node">XML node to use as context for the XPath expression.</xd:param>
        <xd:param name="namespace-context">Element containing all namespace declarations</xd:param>  
    </xd:doc>
    <xsl:function name="xforms:evaluate-xpath-with-context-node">
        <xsl:param name="xpath" as="xs:string"/>
        <xsl:param name="context-node" as="node()"/>
        <xsl:param name="namespace-context" as="element()?"/>
        
        <xsl:variable name="namespace-context-item" as="element()" select="
            if (exists($namespace-context))
            then $namespace-context
            else (
                if ($context-node[not(self::*)])
                then $context-node/parent::*
                else $context-node
            )"/>
        
        <xsl:choose>
            <xsl:when test="$xpath ne ''">
                <xsl:evaluate xpath="xforms:impose($xpath)" context-item="$context-node" namespace-context="$namespace-context-item"/>
            </xsl:when>
            <xsl:otherwise/>
        </xsl:choose>
        
             
        
    </xsl:function>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Evaluate XPath relative to an instance.</xd:p>
        </xd:desc>
        <xd:param name="xpath">XPath expression</xd:param>
        <xd:param name="instance-id">ID of instance to use as context node.</xd:param>    
        <xd:param name="namespace-context">Element containing all namespace declarations</xd:param>  
    </xd:doc>
    <xsl:function name="xforms:evaluate-xpath-with-instance-id">
        <xsl:param name="xpath" as="xs:string"/>
        <xsl:param name="instance-id" as="xs:string"/>
        <xsl:param name="namespace-context" as="element()?"/>
        
        <xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-id)"/>
        
        <xsl:variable name="namespace-context-item" as="element()" select="
            if (exists($namespace-context))
            then $namespace-context
            else $instanceXML"/>
        
        <xsl:evaluate xpath="xforms:impose($xpath)" context-item="$instanceXML" namespace-context="$namespace-context-item"/>     
        
    </xsl:function>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Return string or evaluate as XPath.</xd:p>
        </xd:desc>
        <xd:param name="string">String to check</xd:param>
        <xd:param name="context">XPath expression for context node set.</xd:param>
        <xd:param name="instance-id">ID of instance to use as context node.</xd:param>    
    </xd:doc>
    <xsl:function name="xforms:evaluate-string" as="xs:string?">
        <xsl:param name="string" as="xs:string"/>
        <xsl:param name="context" as="xs:string"/>
        <xsl:param name="instance-id" as="xs:string"/>
        
        <xsl:message use-when="$debugMode">[xforms:evaluate-string] Evaluating '<xsl:sequence select="$string"/>' in context '<xsl:sequence select="$context"/>'</xsl:message>
        
        
        <!-- 
            components needed in case of complex values, e.g. class="dc-{@pass}"
        -->
        <xsl:variable name="components" as="xs:string*">
            <xsl:analyze-string select="$string" regex="\{{([^\}}]+)\}}">
                <xsl:matching-substring>
                    <xsl:message use-when="$debugMode">[xforms:evaluate-string] Evaluating XPath '<xsl:sequence select="regex-group(1)"/>' in context <xsl:sequence select="$context"/></xsl:message>
                    <xsl:variable name="xpath" select="normalize-space(regex-group(1))" />
                    
                    <xsl:variable name="instanceField" as="node()?" select="xforms:evaluate-xpath-with-instance-id($context,$instance-id,())"/>
                    
                    <xsl:value-of select="xforms:evaluate-xpath-with-context-node($xpath,$instanceField,())"/>
                </xsl:matching-substring>
                <xsl:non-matching-substring>
                    <xsl:sequence select="$string"/>
                </xsl:non-matching-substring>
            </xsl:analyze-string>
        </xsl:variable>
        <xsl:sequence select="fn:string-join($components,'')"/>
        
    </xsl:function>
   
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Check whether each required field is populated.</xd:p>
        </xd:desc>
        <xd:return>Sequence of each HTML field that is required</xd:return>
        <xd:param name="instanceXML">Instance to check</xd:param>
    </xd:doc>
    <xsl:function name="xforms:check-required-fields" as="item()*">
        <xsl:param name="instanceXML" as="element()"/>

        <xsl:variable name="required-fieldsi" select="ixsl:page()//*[@data-required]" as="item()*"/>

        <xsl:for-each select="$required-fieldsi">
            <xsl:variable name="resulti" as="xs:boolean">
                <xsl:evaluate
                    xpath="'child::node() or string-length() gt 0'"
                    context-item="." namespace-context="$instanceXML"/>

            </xsl:variable>
            <xsl:message use-when="$debugMode">[xforms:check-required-fields] Evaluating XPath: <xsl:sequence select="'child::node() or string-length() gt 0'"/></xsl:message>
            <xsl:message use-when="$debugMode">[xforms:check-required-fields] XPath result: <xsl:sequence select="$resulti"/></xsl:message>
            <xsl:sequence select="if (not($resulti)) then . else ()"/>
        </xsl:for-each>

    </xsl:function>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Check whether each field satisfies any constraints.</xd:p>
            <xd:p>TODO: check logic here</xd:p>
        </xd:desc>
        <xd:return>Sequence of each HTML field that is not valid wrt its constraints</xd:return>
        <xd:param name="instanceXML">Instance to check</xd:param>
    </xd:doc>
    <xsl:function name="xforms:check-constraints-on-fields" as="item()*">
        <xsl:param name="instanceXML" as="element()"/>
        <xsl:variable name="instanceDoc" as="document-node()">
            <xsl:document>
                <xsl:sequence select="$instanceXML"/>
            </xsl:document>
        </xsl:variable>
        <xsl:variable name="constraint-fieldsi" select="ixsl:page()//*[@data-constraint]" as="item()*"/>
        
        <xsl:for-each select="$constraint-fieldsi">
            <xsl:variable name="contexti" as="node()" select="if (exists(@data-ref)) then xforms:evaluate-xpath-with-context-node(string(@data-ref),$instanceXML,()) else ()"/>
            <xsl:message use-when="$debugMode">[xforms:check-constraints-on-fields] Evaluating XPath: <xsl:value-of select="@data-ref"/></xsl:message>
            
            <xsl:variable name="resulti" as="xs:boolean" select="if (exists(@data-constraint)) then xforms:evaluate-xpath-with-context-node(string(@data-constraint),$contexti,()) else ()"/>
            <xsl:sequence select="if (not($resulti)) then . else ()"/>
        </xsl:for-each>
    </xsl:function>



    <xd:doc scope="component">
        <xd:desc>Handle HTML submission</xd:desc>
    </xd:doc>
    <xsl:template match="*:button[exists(@data-submit)]" mode="ixsl:onclick">
        
        <xsl:call-template name="xforms-submit">
            <xsl:with-param name="submission" select="string(./@data-submit)"/>
        </xsl:call-template>

    </xsl:template>

    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template called by ixsl:schedule-action in template for xforms-submit event</xd:p>
            <xd:p>The context item should be an <xd:a href="https://www.saxonica.com/saxon-js/documentation/index.html#!development/http">HTTP response map</xd:a>, i.e. Saxon-JS representation of an HTTP response as an XDM map. </xd:p>
        </xd:desc>
        <xd:param name="instance-id">Identifier of instance affected by submission</xd:param>
        <xd:param name="targetref">XPath to identify node within target instance</xd:param>
        <xd:param name="replace">String to identify whether to replace the node or just the text content</xd:param>
    </xd:doc>
    <xsl:template name="HTTPsubmit">
         
        <xsl:context-item as="map(*)" use="required"/>
                
        <xsl:param name="instance-id" as="xs:string" required="no" select="$global-default-instance-id"/>
        <xsl:param name="targetref" as="xs:string?" required="no"/>
        <xsl:param name="replace" as="xs:string?" required="no"/>
        
        <xsl:variable name="refi" as="xs:string" select="concat('instance(''', $instance-id, ''')/')"/>
        
        <!-- 
            https://www.saxonica.com/saxon-js/documentation2/index.html#!development/http
        -->
        <xsl:variable name="response-headers" select="?headers" as="map(*)"/>
        <xsl:message use-when="$debugMode">[HTTPsubmit] response content type: <xsl:sequence select="map:get($response-headers,'content-type')"/></xsl:message>
        
        <!-- 
            Type of response may vary, so using generic item() type
            
            '?' is the lookup operator: https://www.w3.org/TR/xpath-31/#id-lookup
            Here it acts on the context item, i.e. the HTTP response map
        -->
        <xsl:variable name="response" select="?body" as="item()?"/>  
         
        <xsl:choose>
              <xsl:when test="empty($response)">
                  <xsl:call-template name="serverError">
                      <xsl:with-param name="responseMap" select="."/>
                  </xsl:call-template>
              </xsl:when>


              <xsl:otherwise>
                  <!-- MD 2018: comment out replaceDocument for testing
                  The action here depends on the type of submission...
                  -->
<!--                  <xsl:sequence select="js:replaceDocument(serialize($responseXML))" />-->
                  
                  <xsl:choose>
                      <xsl:when test="$replace = 'instance' and $response[self::document-node()]">
                          <xsl:sequence select="js:setInstance($instance-id,$response/*)"/>
                          
<!--                         <xsl:message use-when="$debugMode">[HTTPsubmit] response body: <xsl:value-of select="serialize($response)"/></xsl:message>-->
                      </xsl:when>
                      <xsl:when test="$replace = 'text' and exists($targetref) and $response castable as xs:string">
                          <xsl:message use-when="$debugMode">[HTTPsubmit] response text: <xsl:sequence select="$response"/></xsl:message>
                          <xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-id)"/>
                          <xsl:variable name="instanceDoc" as="document-node()">
                              <xsl:document>
                                  <xsl:sequence select="$instanceXML"/>
                              </xsl:document>
                          </xsl:variable>
                          <xsl:variable name="updatedNode" as="node()" select="xforms:evaluate-xpath-with-context-node($targetref,$instanceXML,())"/>
                          <xsl:variable name="updatedInstanceXML" as="element()">
                              <xsl:choose>
                                  <xsl:when test="$instanceDoc//node()[. is $updatedNode]">
                                      <xsl:apply-templates select="$instanceDoc" mode="recalculate">
                                          <xsl:with-param name="updated-nodes" select="$updatedNode" tunnel="yes"/>
                                          <xsl:with-param name="updated-value" select="string($response)" tunnel="yes"/>
                                      </xsl:apply-templates>
                                  </xsl:when>
                                  <xsl:otherwise>
                                      <xsl:apply-templates select="$instanceXML" mode="recalculate">
                                          <xsl:with-param name="updated-nodes" select="$updatedNode" tunnel="yes"/>
                                          <xsl:with-param name="updated-value" select="string($response)" tunnel="yes"/>
                                      </xsl:apply-templates>
                                  </xsl:otherwise>
                              </xsl:choose>
                          </xsl:variable>
                          
                          <!--        <xsl:message use-when="$debugMode">[xforms-value-changed] Updated XML: <xsl:sequence select="serialize($updatedInstanceXML)"/></xsl:message>-->
                          
                          <xsl:sequence select="js:setInstance($instance-id,$updatedInstanceXML)"/>

                      </xsl:when>
                      <!-- TO DO: replace node or text within instance; replace entire page -->
                      <xsl:otherwise>
                          <xsl:message use-when="$debugMode">[HTTPsubmit] response = <xsl:sequence select="serialize($response)"/></xsl:message>
                       </xsl:otherwise>
                  </xsl:choose>
 
                  <xsl:call-template name="xforms-submit-done"/>
                  
              </xsl:otherwise>
          </xsl:choose>
      </xsl:template>


    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Send server error message to console log</xd:p>
        </xd:desc>
        <xd:param name="responseMap">HTTP response map, per <a href="http://www.saxonica.com/saxon-js/documentation/index.html#!development/http">Saxon HTTP client</a></xd:param>
    </xd:doc>
    <xsl:template name="serverError">
        <xsl:param name="responseMap" as="map(*)"/>
        <xsl:message>Server side error HTTP response - <xsl:value-of select="concat($responseMap?status, ' ', $responseMap?message)"/></xsl:message>
    </xsl:template>


    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Pass through xforms:form when rendering.</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="xforms:xform">
        <xsl:apply-templates select="node()"/>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Ignore xforms:model when rendering, except for setting actions defined there.</xd:p>
            <xd:p>Its instances, bindings, submissions are registered separately in the "xformsjs-main" template.</xd:p>
        </xd:desc>
        <xd:param name="model-key">ID of context model (xforms:model/@id value or default value).</xd:param>
    </xd:doc>
    <xsl:template match="xforms:model">
        <xsl:param name="model-key" as="xs:string" required="no" select="$global-default-model-id" tunnel="yes"/>

        <xsl:message use-when="$debugMode">[xforms:model] START</xsl:message>
        
        <xsl:variable name="model-ref" as="xs:string" select="if (exists(@id)) then string(@id) else $model-key"/>
        
        <xsl:variable name="actions" as="map(*)*">
            <xsl:apply-templates select="xforms:action" mode="set-action">
                <xsl:with-param name="model-key" select="$model-ref" tunnel="yes"/>
            </xsl:apply-templates>
        </xsl:variable>
        
        <xsl:if test="exists($actions)">
            <xsl:sequence select="js:addAction($model-ref, $actions)" />
            <xsl:message use-when="$debugMode">[xforms:model] actions within model have been set</xsl:message>
        </xsl:if>
        
        <xsl:message use-when="$debugMode">[xforms:model] END</xsl:message>
        
    </xsl:template>

    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for XForms root element (xforms:xform).</xd:p>
            <xd:p>Passes XForm to xformsjs-main template</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="/">
        <xsl:message use-when="$debugMode">[document node] Root element of <xsl:sequence select="base-uri()"/> is <xsl:sequence select="name(*)"/></xsl:message>
        <xsl:call-template name="xformsjs-main" >
            <xsl:with-param name="xFormsId" select="$xform-html-id" />
        </xsl:call-template>
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Identify context instance, nodeset, and bindings for <xd:a href="https://www.w3.org/TR/xforms11/#controls">XForm controls</xd:a>.</xd:p>
        </xd:desc>
        <xd:param name="model-key">ID of context model (xforms:model/@id value or default value).</xd:param>
        <xd:param name="nodeset">An XPath binding expression. Stored in Javascript variable to support recalculation of repeats.</xd:param>
        <xd:param name="position">Integer representing position of item (in a repeat list for example).</xd:param>
        <xd:param name="context-position">String representing position of item in a hierarchy (e.g. in nested repeat)</xd:param>
    </xd:doc>
    <xsl:template match="xforms:*[local-name() = $xforms-controls] | xforms:group | xforms:case ">
        <xsl:param name="model-key" as="xs:string" required="no" select="$global-default-model-id" tunnel="yes"/>        
        <xsl:param name="nodeset" as="xs:string" required="no" select="''" tunnel="yes"/>
        <xsl:param name="position" as="xs:integer" required="no" select="0"/>
        <xsl:param name="context-position" as="xs:string" required="no" select="''"/>
        
        <xsl:variable name="log-label" as="xs:string" select="concat('[',name(),' match template]')"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        
        <xsl:variable name="time-id" as="xs:string" select="concat('XForms ', local-name(), ' ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id)" />
        
        <xsl:variable name="string-position" as="xs:string" select="if ($context-position != '') then $context-position else string($position)"/>
        <xsl:variable name="myid" as="xs:string" select="
            if (exists(@id)) 
            then concat(@id, '-', $string-position)
            else concat( generate-id(), '-', $string-position )"/>
        
       
        
        <xsl:variable name="properties" as="map(*)">
            <xsl:apply-templates select="." mode="get-properties"/>
        </xsl:variable>
        
        <xsl:variable name="refi" as="xs:string" select="map:get($properties,'nodeset')"/>
        <xsl:variable name="this-instance-id" as="xs:string" select="map:get($properties,'instance-context')"/>
        <xsl:variable name="model-ref" as="xs:string" select="map:get($properties,'model-id')"/>
        <xsl:variable name="bindingi" as="element(xforms:bind)?" select="map:get($properties,'binding')"/>
        
        <xsl:if test="xforms:usesIndexFunction(.) and not(ancestor::*[xforms:usesIndexFunction(.)])">
            <xsl:sequence select="js:setElementUsingIndexFunction($myid,.)"/>
            <xsl:sequence select="js:setElementContextUsingIndexFunction($myid,$refi)"/>
        </xsl:if>
        
        
        <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $refi = <xsl:sequence select="$refi"/></xsl:message>-->
        
        <!-- set actions relevant to this -->
        <xsl:variable name="time-id-set-actions" as="xs:string" select="concat('XForms ', local-name(), ' set actions ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-set-actions)" />
        
        <xsl:variable name="actions" as="map(*)*">
            <xsl:apply-templates select="." mode="set-actions">
                <xsl:with-param name="model-key" select="$model-ref" tunnel="yes"/>
                <xsl:with-param name="instance-key" select="$this-instance-id" tunnel="yes"/>
                <xsl:with-param name="nodeset" select="$refi" tunnel="yes"/>
                <xsl:with-param name="properties" select="$properties" tunnel="yes"/>
            </xsl:apply-templates>
        </xsl:variable>
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-set-actions)" />
        
        <xsl:if test="exists($actions)">
            <xsl:sequence select="js:addAction($myid, $actions)" />
        </xsl:if>
        
        <xsl:apply-templates select="." mode="get-html">
            <xsl:with-param name="id" as="xs:string" select="$myid" tunnel="yes"/>
            <xsl:with-param name="model-key" select="$model-ref" tunnel="yes"/>
            <xsl:with-param name="nodeset" as="xs:string" select="$refi" tunnel="yes"/>
            <xsl:with-param name="context-nodeset" as="xs:string" select="$nodeset" tunnel="yes"/>
            <xsl:with-param name="instance-context" as="xs:string" select="$this-instance-id" tunnel="yes"/>
            <xsl:with-param name="binding" as="element(xforms:bind)*" select="$bindingi" tunnel="yes"/>
            <xsl:with-param name="actions" as="map(*)*" select="$actions"/>
        </xsl:apply-templates>
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id)" />
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
    </xsl:template>
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-output">output element</a>  </xd:p>          
            <xd:p>Generates HTML output field and registers actions.</xd:p>
        </xd:desc>
        <xd:param name="id">ID of HTML element.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="context-nodeset">XPath binding expression for context node (used if @value contains context() function)</xd:param>
        <xd:param name="instance-context">ID of XForms instance relevant to this control</xd:param>
        <xd:param name="binding">xforms:bind elements relevant to this control</xd:param>
    </xd:doc>
    <xsl:template match="xforms:output" mode="get-html">
        <xsl:param name="id" as="xs:string" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" tunnel="yes"/>
        <xsl:param name="context-nodeset" as="xs:string" tunnel="yes"/>
        <xsl:param name="instance-context" as="xs:string" tunnel="yes"/>
        <xsl:param name="binding" as="element(xforms:bind)*" tunnel="yes"/>
        
        <xsl:variable name="log-label" as="xs:string" select="concat('[',name(),' get-html mode]')"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        
        <!--<xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-context)"/>   
        <xsl:variable name="instanceDoc" as="document-node()">
            <xsl:document>
                <xsl:sequence select="$instanceXML"/>
            </xsl:document>
        </xsl:variable>-->
        
        
        <xsl:variable name="time-id-instance-field" as="xs:string" select="concat('XForms ', local-name(), ' get instance field ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-instance-field)" />
        <xsl:variable name="instanceField" as="node()?">
            <xsl:choose>
                <!-- 
                    Override default instance if @value specifies an instance
                -->
                <xsl:when test="starts-with(@value,'instance(')">
                    <xsl:sequence select="xforms:evaluate-xpath-with-instance-id(@value,xforms:getInstanceId(string(@value)),())"/>
                </xsl:when>
                <xsl:when test="$nodeset != ''">
                    <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> Identifying context instance field using $nodeset = <xsl:sequence select="$nodeset"/></xsl:message>-->
                    <xsl:sequence select="xforms:evaluate-xpath-with-instance-id($nodeset,$instance-context,())"/>
                </xsl:when>
                 <xsl:otherwise/>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-instance-field)" />
        
        
        <xsl:variable name="time-id-get-value" as="xs:string" select="concat('XForms ', local-name(), ' get value ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-get-value)" />
        
        <xsl:variable name="valueExecuted" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists($binding/@calculate)">
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node('string(' || $binding/@calculate || ')',$instanceField,())"/>
                </xsl:when>
                <xsl:when test="exists(@value)">
                    <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> Evaluating @value = <xsl:value-of select="@value"/> in context <xsl:sequence select="fn:serialize($instanceField)"/></xsl:message>-->
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node('string(' || xforms:resolveContext(@value,$context-nodeset) || ')',$instanceField,())"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$instanceField"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-get-value)" />
        
        <xsl:variable name="time-id-get-relevant" as="xs:string" select="concat('XForms ', local-name(), ' get relevant status ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-get-relevant)" />
        
        <xsl:variable name="relevantStatus" as="xs:boolean">
            <xsl:call-template name="getRelevantStatus">
                <xsl:with-param name="xformsControl" as="element()" select="."/>
                <xsl:with-param name="instanceField" as="node()?" select="$instanceField"/>
            </xsl:call-template>
        </xsl:variable>
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-get-relevant)" />
        
        <xsl:variable name="additional-class-values" as="xs:string+" select="('xforms-output')"/>
       
        <xsl:variable name="htmlClass" as="xs:string">
            <xsl:call-template name="getHtmlClass">
                <xsl:with-param name="source-class" as="xs:string?" select="@class"/>
                <xsl:with-param name="additional-values" as="xs:string*" select="$additional-class-values"/>
            </xsl:call-template>
        </xsl:variable>
        
       
        <!-- GENERATE HTML -->
        <xsl:variable name="time-id-get-html" as="xs:string" select="concat('XForms ', local-name(), ' get HTML ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-get-html)" />
        <span>    
            <xsl:attribute name="style" select="if($relevantStatus) then 'display:inline' else 'display:none'" />
            <xsl:apply-templates select="xforms:label"/>            
            <span>
                <xsl:attribute name="id" select="$id"/>
                <xsl:attribute name="class" select="$htmlClass"/>
                <xsl:attribute name="instance-context" select="$instance-context"/>
                <xsl:attribute name="data-ref" select="$nodeset"/>
                <xsl:if test="exists($binding) and exists($binding/@relevant)">
                    <xsl:attribute name="data-relevant" select="$binding/@relevant"/>
                </xsl:if>
               
                <xsl:sequence select="$valueExecuted" />
            </span>
        </span>
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-get-html)" />
        
        <!-- register outputs (except those inside a repeat) -->
        <xsl:variable name="time-id-register-outputs" as="xs:string" select="concat('XForms ', local-name(), ' get relevant status ', generate-id())"/>
        
        <xsl:call-template name="registerOutput">
            <xsl:with-param name="additional-class-values" select="$additional-class-values"/>
        </xsl:call-template>
               
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-input">input element</a></xd:p>
            <xd:p>Generates HTML input field and registers actions.</xd:p>
        </xd:desc>
        <xd:param name="id">ID of HTML element.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="instance-context">ID of XForms instance relevant to this control</xd:param>
        <xd:param name="binding">xforms:bind elements relevant to this control</xd:param>
        <xd:param name="actions">Map(s) of actions relevant to this control</xd:param>
    </xd:doc>
    <xsl:template match="xforms:input" mode="get-html">
        <xsl:param name="id" as="xs:string" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" tunnel="yes"/>
        <xsl:param name="instance-context" as="xs:string" tunnel="yes"/>
        <xsl:param name="binding" as="element(xforms:bind)*" tunnel="yes"/>
        <xsl:param name="actions" as="map(*)*"/>
               
        <xsl:message use-when="$debugMode">[xforms:input in get-html mode] nodeset: <xsl:sequence select="$nodeset"/></xsl:message>
        
        <xsl:variable name="instanceField" as="node()?" select="xforms:evaluate-xpath-with-instance-id($nodeset,$instance-context,())"/>                   
        <xsl:variable name="relevantStatus" as="xs:boolean">
            <xsl:call-template name="getRelevantStatus">
                <xsl:with-param name="xformsControl" as="element()" select="."/>
                <xsl:with-param name="instanceField" as="node()?" select="$instanceField"/>
            </xsl:call-template>
        </xsl:variable>
        
        <xsl:variable name="additional-class-values" as="xs:string+" select="('xforms-input')"/>
        
        <xsl:variable name="htmlClass" as="xs:string">
            <xsl:call-template name="getHtmlClass">
                <xsl:with-param name="source-class" as="xs:string?" select="@class"/>
                <xsl:with-param name="additional-values" as="xs:string*" select="$additional-class-values"/>
                <xsl:with-param name="incremental" as="xs:string?" select="@incremental"/>
            </xsl:call-template>
        </xsl:variable>
        
             
        <div>
            <xsl:attribute name="class" select="$htmlClass"/>
            <xsl:if test="not($relevantStatus)">
                <xsl:attribute name="style" select="'display:none'"/>
            </xsl:if>
            <xsl:apply-templates select="xforms:label"/>
            
            <xsl:variable name="hints" select="xforms:hint/text()"/>
            
            <input>
                <xsl:attribute name="id" select="$id"/>
                <xsl:attribute name="class" select="$htmlClass"/>
                <xsl:attribute name="instance-context" select="$instance-context"/>
                <xsl:attribute name="data-ref" select="$nodeset"/>
               
                <xsl:if test="exists($binding) and exists($binding/@constraint)">
                    <xsl:attribute name="data-constraint" select="$binding/@constraint"/>
                </xsl:if>
                <xsl:if test="exists($binding) and exists($binding/@relevant)">
                    <xsl:attribute name="data-relevant" select="$binding/@relevant"/>
                </xsl:if>
                <xsl:if test="exists($binding) and exists($binding/@required)">
                    <xsl:attribute name="data-required" select="$binding/@required"/>
                </xsl:if>
                
                <xsl:if test="exists($actions)">
                    <xsl:attribute name="data-action" select="$id"/>
                </xsl:if>
                
                <xsl:if test="exists($hints)">
                    <xsl:attribute name="title" select="$hints"/>
                </xsl:if>
                
                <xsl:attribute name="size" select="if (exists(@size)) then @size else '50'"/>
                                
                <xsl:variable name="input-value" as="xs:string">
                    <xsl:choose>
                        <xsl:when test="exists($instanceField)">
                            <xsl:value-of select="$instanceField"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:sequence select="''"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                
                <xsl:variable name="input-type" as="xs:string">
                    <xsl:choose>
                        <xsl:when
                            test="
                            if (exists($binding)) then
                            xs:QName($binding/@type) eq xs:QName('xs:date')
                            else
                            false()">
                            <xsl:sequence select="'date'"/>
                        </xsl:when>
                        <xsl:when
                            test="
                            if (exists($binding)) then
                            xs:QName($binding/@type) eq xs:QName('xs:time')
                            else
                            false()">
                            <xsl:sequence select="'time'"/>
                        </xsl:when>
                        <xsl:when
                            test="
                            if (exists($binding)) then
                            xs:QName($binding/@type) eq xs:QName('xs:boolean')
                            else
                            false()">
                            <xsl:sequence select="'checkbox'"/>
                        </xsl:when>
                        
                        <xsl:otherwise>
                            <xsl:sequence select="'text'"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                
                <xsl:attribute name="data-type" select="$input-type"/>
                <xsl:attribute name="type" select="$input-type"/>
                
                <xsl:choose>
                    <xsl:when test="$input-type eq 'date'">
                        <xsl:attribute name="value" select="$input-value"/>
                    </xsl:when>
                    <xsl:when test="$input-type eq 'time'">
                        <xsl:attribute name="value" select="$input-value"/>
                    </xsl:when>
                    <xsl:when test="$input-type eq 'checkbox'">
                        <xsl:if test="exists($instanceField)">
                            <xsl:if test="string-length($input-value) > 0 and xs:boolean($input-value)">
                                <xsl:attribute name="checked" select="$input-value"/>
                            </xsl:if>
                        </xsl:if>
                    </xsl:when>
                    
                    <xsl:otherwise>
                        <xsl:attribute name="value" select="$input-value"/>
                    </xsl:otherwise>
                </xsl:choose>
                
                
                <xsl:call-template name="registerOutput">
                    <xsl:with-param name="additional-class-values" select="$additional-class-values"/>
                    <xsl:with-param name="data-type" as="xs:string" select="$input-type"/>
                </xsl:call-template>
                
            </input>
        </div> 
        
        
        
    </xsl:template>
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-textarea">textarea element</a>  </xd:p>          
            <xd:p>Generates HTML output field and registers actions.</xd:p>
        </xd:desc>
        <xd:param name="id">ID of HTML element.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="instance-context">ID of XForms instance relevant to this control</xd:param>
        <xd:param name="binding">xforms:bind elements relevant to this control</xd:param>
        <xd:param name="actions">Map(s) of actions relevant to this control</xd:param>
    </xd:doc>
    <xsl:template match="xforms:textarea" mode="get-html">
        <xsl:param name="id" as="xs:string" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" tunnel="yes"/>
        <xsl:param name="instance-context" as="xs:string" tunnel="yes"/>
        <xsl:param name="binding" as="element(xforms:bind)*" tunnel="yes"/>
        <xsl:param name="actions" as="map(*)*"/>

        <xsl:variable name="instanceField" as="node()?" select="xforms:evaluate-xpath-with-instance-id($nodeset,$instance-context,())"/>
        
        <xsl:variable name="relevantStatus" as="xs:boolean">
            <xsl:call-template name="getRelevantStatus">
                <xsl:with-param name="xformsControl" as="element()" select="."/>
                <xsl:with-param name="instanceField" as="node()?" select="$instanceField"/>
            </xsl:call-template>
        </xsl:variable>
        
        <xsl:variable name="additional-class-values" as="xs:string+" select="('xforms-textarea')"/>
        <xsl:variable name="htmlClass" as="xs:string">
            <xsl:call-template name="getHtmlClass">
                <xsl:with-param name="source-class" as="xs:string?" select="@class"/>
                <xsl:with-param name="additional-values" as="xs:string*" select="$additional-class-values"/>
                <xsl:with-param name="incremental" as="xs:string?" select="@incremental"/>
            </xsl:call-template>
        </xsl:variable>
        
        <xsl:variable name="hints" select="xforms:hint/text()"/>
        
        <div>
            <xsl:attribute name="class" select="$htmlClass"/>
            <xsl:if test="not($relevantStatus)">
                <xsl:attribute name="style" select="'display:none'"/>
            </xsl:if>
            <xsl:apply-templates select="xforms:label"/>
            <textarea>
                <xsl:attribute name="id" select="$id"/>
                <xsl:attribute name="class" select="$htmlClass"/>
                <xsl:attribute name="instance-context" select="$instance-context" />
                <xsl:attribute name="data-ref" select="$nodeset"/>
                
                <xsl:if test="exists($binding) and exists($binding/@constraint)">
                    <xsl:attribute name="data-constraint" select="$binding/@constraint"/>
                </xsl:if>
                <xsl:if test="exists($binding) and exists($binding/@relevant)">
                    <xsl:attribute name="data-relevant" select="$binding/@relevant"/>
                </xsl:if>
                <xsl:if test="exists($binding) and exists($binding/@required)">
                    <xsl:attribute name="data-required" select="$binding/@required"/>
                </xsl:if>
                
                <xsl:if test="exists($actions)">
                    <xsl:attribute name="data-action" select="$id"/>
                </xsl:if>
                
                <xsl:if test="exists($hints)">
                    <xsl:attribute name="title" select="$hints"/>
                </xsl:if>
                
                <xsl:if test="exists(@size)">
                    <xsl:attribute name="size" select="@size"/>
                </xsl:if>
                
                <xsl:choose>
                    <xsl:when test="exists($instanceField)">
                        <xsl:value-of select="$instanceField"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:sequence select="'&#xA0;'"/>
                    </xsl:otherwise>
                </xsl:choose>
            </textarea>       
        </div>
    </xsl:template>


    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Ignore xforms:hint when rendering the XForm into HTML.</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="xforms:hint"/>

    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-selectMany">select</a> and <a href="https://www.w3.org/TR/xforms11/#ui-selectOne">select1</a> elements</xd:p>          
            <xd:p>Generates HTML select field and registers actions.</xd:p>
        </xd:desc>
        <xd:param name="id">ID of HTML element.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="instance-context">ID of XForms instance relevant to this control</xd:param>
        <xd:param name="binding">xforms:bind elements relevant to this control</xd:param>
        <xd:param name="actions">Map(s) of actions relevant to this control</xd:param>
    </xd:doc>
    <xsl:template match="xforms:select1 | xforms:select" mode="get-html">
        <xsl:param name="id" as="xs:string" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" tunnel="yes"/>
        <xsl:param name="instance-context" as="xs:string" tunnel="yes"/>
        <xsl:param name="binding" as="element(xforms:bind)*" tunnel="yes"/>
        <xsl:param name="actions" as="map(*)*"/>
        
        <xsl:variable name="instanceField" as="node()?" select="xforms:evaluate-xpath-with-instance-id($nodeset,$instance-context,())"/>                
        
        <xsl:variable name="selectedValue" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists($instanceField)">
                    <xsl:value-of select="$instanceField"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="''"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="relevantStatus" as="xs:boolean">
            <xsl:call-template name="getRelevantStatus">
                <xsl:with-param name="xformsControl" as="element()" select="."/>
                <xsl:with-param name="instanceField" as="node()?" select="$instanceField"/>
            </xsl:call-template>
        </xsl:variable>
        
        <xsl:variable name="additional-class-values" as="xs:string+" select="('xforms-select')"/>
        
        <xsl:variable name="htmlClass" as="xs:string">
            <xsl:call-template name="getHtmlClass">
                <xsl:with-param name="source-class" as="xs:string?" select="@class"/>
                <xsl:with-param name="additional-values" as="xs:string*" select="$additional-class-values"/>
            </xsl:call-template>
        </xsl:variable>
                         
        <div>
            <xsl:attribute name="class" select="$htmlClass"/>
            <xsl:if test="not($relevantStatus)">
                <xsl:attribute name="style" select="'display:none'"/>
            </xsl:if>
            <xsl:apply-templates select="xforms:label"/>
            <xsl:variable name="hints" select="xforms:hint/text()"/>
            
            <select>
                <xsl:attribute name="id" select="$id"/>
                <xsl:attribute name="class" select="$htmlClass"/>
                <xsl:attribute name="instance-context" select="$instance-context"/>
                <xsl:attribute name="data-ref" select="$nodeset"/>
                
                <xsl:if test="exists($binding) and exists($binding/@constraint)">
                    <xsl:attribute name="data-constraint" select="$binding/@constraint"/>
                </xsl:if>
                <xsl:if test="exists($binding) and exists($binding/@relevant)">
                    <xsl:attribute name="data-relevant" select="$binding/@relevant"/>
                </xsl:if>
                <xsl:if test="exists($binding) and exists($binding/@required)">
                    <xsl:attribute name="data-required" select="$binding/@required"/>
                </xsl:if>
                
                <xsl:if test="exists($actions)">
                    <xsl:attribute name="data-action" select="$id"/>
                </xsl:if>
                
                <xsl:if test="exists($hints)">
                    <xsl:attribute name="title" select="$hints"/>
                </xsl:if>
                
                
                <xsl:if test="local-name() = 'select'">
                    <xsl:attribute name="multiple">true</xsl:attribute>
                    <xsl:attribute name="size">
                        <xsl:value-of select="count(descendant::xforms:item)"/>
                    </xsl:attribute>
                </xsl:if>
                 
                <xsl:apply-templates select="xforms:item" mode="#current">
                    <xsl:with-param name="selectedValue" select="$selectedValue"/>
                </xsl:apply-templates>
                <xsl:apply-templates select="xforms:itemset" mode="#current"/>
                
            </select>
            
        </div>
        
        <xsl:call-template name="registerOutput">
            <xsl:with-param name="additional-class-values" select="$additional-class-values"/>
        </xsl:call-template>

    </xsl:template>





    <xd:doc scope="component">
        <xd:desc>Ignore text in model (REDUNDANT?)</xd:desc>
    </xd:doc>
    <xsl:template match="text()[((ancestor::xforms:model))]"/>



    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Render xforms:label as HTML label</xd:p>
            <xd:p>TODO: implement @for</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="xforms:label">
         
        <xsl:variable name="properties" as="map(*)">
            <xsl:apply-templates select="." mode="get-properties"/>
        </xsl:variable>
        
        <xsl:variable name="refi" as="xs:string" select="map:get($properties,'nodeset')"/>
        <xsl:variable name="this-instance-id" as="xs:string" select="map:get($properties,'instance-context')"/>
        <xsl:variable name="bindingi" as="element(xforms:bind)?" select="map:get($properties,'binding')"/>
                
        <xsl:variable name="instanceField" as="node()?" select="xforms:evaluate-xpath-with-instance-id($refi,$this-instance-id,())"/>
        
        <xsl:variable name="label" as="item()*">
            <xsl:choose>
                <xsl:when test="exists(@bind) and exists($bindingi/@calculate)">
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node('string(' || $bindingi/@calculate || ')',$instanceField,())"/>
                </xsl:when>
                <xsl:when test="exists(@ref)">
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node($refi,$instanceField,())"/>
                </xsl:when>
                <xsl:when test="count(./node()) &gt; 0">
                    <xsl:apply-templates select="node()"/>
                </xsl:when>
                <xsl:otherwise>
                    <!-- no-break space &#x00a0; -->
                    <xsl:text>&#xA0;</xsl:text>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:choose>
            <xsl:when test="parent::xforms:itemset">
                <xsl:value-of select="$label"/>
            </xsl:when>
            <xsl:otherwise>
                <label>
                    <xsl:copy-of select="@class"/>
                    <xsl:sequence select="$label"/>
                </label>
            </xsl:otherwise>
        </xsl:choose>
        
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Render xforms:value as HTML option/@value attribute</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="xforms:value">
        
        <xsl:variable name="properties" as="map(*)">
            <xsl:apply-templates select="." mode="get-properties"/>
        </xsl:variable>
        
        <xsl:variable name="refi" as="xs:string" select="map:get($properties,'nodeset')"/>
        <xsl:variable name="this-instance-id" as="xs:string" select="map:get($properties,'instance-context')"/>
        <xsl:variable name="bindingi" as="element(xforms:bind)?" select="map:get($properties,'binding')"/>
        
        <xsl:variable name="instanceField" as="node()?">
            <xsl:choose>
                <!-- 
                    Override default instance if @value specifies an instance
                -->
                <xsl:when test="starts-with(@value,'instance(')">
                    <xsl:sequence select="xforms:evaluate-xpath-with-instance-id(@value,xforms:getInstanceId(string(@value)),())"/>
                </xsl:when>
                <xsl:when test="$refi != ''">
                    <xsl:sequence select="xforms:evaluate-xpath-with-instance-id($refi,$this-instance-id,())"/>
                </xsl:when>
                <xsl:otherwise/>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="value" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists(@bind) and exists($bindingi/@calculate)">
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node('string(' || $bindingi/@calculate || ')',$instanceField,())"/>
                </xsl:when>
                <xsl:when test="exists(@value)">
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node('string(' || @value || ')',$instanceField,())"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="."/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:attribute name="value" select="$value"/>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for xforms:item element.</xd:p>
            <xd:p>Generates HTML option element.</xd:p>
        </xd:desc>
        <xd:param name="selectedValue">String consisting of the current selection in the list. (If it matches the value of the xforms:item, the HTML option will be marked as selected.)</xd:param>
    </xd:doc>
    <xsl:template match="xforms:item" mode="get-html">
        <xsl:param name="selectedValue" as="xs:string" select="''"/>
        
        <option>
            <xsl:apply-templates select="xforms:value"/>
            <xsl:if test="$selectedValue = xs:string(xforms:value/text())">
                <xsl:attribute name="selected" select="$selectedValue"/>
            </xsl:if>

            <xsl:apply-templates select="xforms:label"/>
        </option>

    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for xforms:itemset element.</xd:p>
            <xd:p>Generates HTML option elements according to evaluation of @ref.</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="xforms:itemset" mode="get-html">
        <xsl:message use-when="$debugMode">[xforms:itemset] Generate HTML for itemset</xsl:message>
        
        <xsl:variable name="properties" as="map(*)">
            <xsl:apply-templates select="." mode="get-properties"/>
        </xsl:variable>
        
        <xsl:variable name="refi" as="xs:string" select="map:get($properties,'nodeset')"/>
        <xsl:variable name="this-instance-id" as="xs:string" select="map:get($properties,'instance-context')"/>
        <xsl:variable name="model-ref" as="xs:string" select="map:get($properties,'model-id')"/>
        
        
        <xsl:variable name="options" as="item()*" select="xforms:evaluate-xpath-with-instance-id($refi,$this-instance-id,())"/>
        
        <xsl:variable name="xforms-value" as="element(xforms:value)" select="child::xforms:value"/>
        <xsl:variable name="xforms-label" as="element(xforms:label)" select="child::xforms:label"/>
        
        <xsl:for-each select="$options">
            <option>
                <xsl:apply-templates select="$xforms-value,$xforms-label">
                    <xsl:with-param name="nodeset" select="concat($refi, '[', position(), ']')" tunnel="yes"/>
                    
                    <xsl:with-param name="instance-context" select="$this-instance-id" tunnel="yes"/>
                </xsl:apply-templates>
            </option>
        </xsl:for-each>
        
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Handle XForms switch element. Register cases as a group for toggling.</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="xforms:switch">
        <xsl:variable name="myid" as="xs:string" select="if (exists(@id)) then @id else generate-id()"/>
        <xsl:variable name="cases" as="xs:string*" select="child::xforms:case/@id"/>
        <xsl:sequence select="js:addSwitch($myid,$cases)"/>
        
        <xsl:apply-templates>
            <xsl:with-param name="switch-id" as="xs:string" select="$myid" tunnel="yes"/>
        </xsl:apply-templates>
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-case">case element</a></xd:p>
            <xd:p>Generates an HTML div and is set to display or not according to its selected status.</xd:p>
        </xd:desc>
        <xd:param name="switch-id">ID of parent switch of a case element, used to support toggle behaviour.</xd:param>
    </xd:doc>
    <xsl:template match="xforms:case" mode="get-html">
        <xsl:param name="switch-id" as="xs:string?" required="no" tunnel="yes"/>
        
        <xsl:variable name="id" as="xs:string" select="@id"/>
        <xsl:variable name="isRelevant" as="xs:boolean">
            <xsl:call-template name="getCaseRelevantStatus"/>
        </xsl:variable>
        <xsl:choose>
            <xsl:when test="$isRelevant">
                <xsl:sequence select="js:setCaseStatus($id,'true')"/>
                <xsl:sequence select="js:setSwitchSelection($switch-id,$id)"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="js:setCaseStatus($id,'false')"/>
            </xsl:otherwise>
        </xsl:choose>
        <xsl:sequence select="js:setCaseSwitch($id,$switch-id)"/>
        
        <div>
            <xsl:attribute name="id" select="$id"/>
            <xsl:if test="not($isRelevant)">
                <xsl:attribute name="style" select="'display:none'"/>
            </xsl:if>
            <xsl:apply-templates select="child::node()"/>
        </div>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-group">group element</a></xd:p>
            <xd:p>Generates an HTML div and passes @ref or @nodeset to descendants.</xd:p>
        </xd:desc>
        <xd:param name="id">ID of HTML element.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
    </xd:doc>
    <xsl:template match="xforms:group" mode="get-html">
        <xsl:param name="id" as="xs:string" required="yes" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" required="yes" tunnel="yes"/>
        
        <div>
            <xsl:attribute name="id" select="$id"/>
            <xsl:if test="$nodeset != ''">
                <xsl:attribute name="data-group-ref" select="$nodeset" />
            </xsl:if>
            <xsl:apply-templates select="child::node()"/>
        </div>
    </xsl:template>
    
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-repeat">repeat element</a></xd:p>
            <xd:p>Generates HTML div and iterates over items within.</xd:p>
        </xd:desc>
        <xd:param name="model-key">ID of context model (xforms:model/@id value or default value).</xd:param>
        <xd:param name="nodeset">An XPath binding expression. Stored in Javascript variable to support recalculation of repeats.</xd:param>
        <xd:param name="position">Integer representing position of item (in a repeat list for example).</xd:param>
        <xd:param name="context-position">String representing position of item in a hierarchy (e.g. in nested repeat)</xd:param>
        <xd:param name="recalculate">Boolean parameter. A true value means we are recalculating and do not output the top-level div</xd:param>
        <xd:param name="refreshRepeats">Boolean parameter. A true value means we are calling it from the refreshRepeats-JS template - we are replacing the content of the div wrapper and don't need to recreate it (otherwise there will be duplicate IDs)</xd:param>
    </xd:doc>
    <xsl:template match="xforms:repeat">
        <xsl:param name="model-key" as="xs:string" required="no" select="$global-default-model-id" tunnel="yes"/>        
        <xsl:param name="nodeset" as="xs:string" required="no" select="''" tunnel="yes"/>
        <xsl:param name="position" as="xs:integer" required="no" select="0"/>
        <xsl:param name="context-position" as="xs:string" required="no" select="''"/>
        <xsl:param name="recalculate" as="xs:boolean" required="no" select="fn:false()" tunnel="yes"/>
        <xsl:param name="refreshRepeats" as="xs:boolean" required="no" select="fn:false()" tunnel="yes"/>
        
<!--        <xsl:message>[xforms:repeat] Handling: <xsl:sequence select="fn:serialize(.)"/></xsl:message>-->
        
        <xsl:variable name="model-ref" as="xs:string" select="if (exists(@model)) then string(@model) else $model-key"/>
        
        <xsl:variable name="string-position" as="xs:string" select="if ($context-position != '') then $context-position else string($position)"/>
        <xsl:variable name="myid" as="xs:string" select="
            if (exists(@id)) 
            then @id
            else concat( generate-id(), '-', $string-position )"/>
                
        <xsl:variable name="properties" as="map(*)">
            <xsl:apply-templates select="." mode="get-properties"/>
        </xsl:variable>
        
        <xsl:variable name="refi" as="xs:string" select="map:get($properties,'nodeset')"/>
        <xsl:variable name="this-instance-id" as="xs:string" select="map:get($properties,'instance-context')"/>
        
        <!-- set the starting index value -->        
        <xsl:choose>
            <xsl:when test="$recalculate">
<!--                <xsl:message use-when="$debugMode">[xforms:repeat] Index of item '<xsl:sequence select="$myid"/>' is <xsl:value-of select="js:getRepeatIndex($myid)"/></xsl:message>-->
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="this-index" as="xs:double">
                    <xsl:choose>
                        <xsl:when test="not(exists(@startindex))">
                            <xsl:sequence select="1"/>
                        </xsl:when>
                        <xsl:when test="@startindex castable as xs:double">
                            <xsl:value-of select="number(@startindex)"/>
                        </xsl:when>
                        <xsl:otherwise>
<!--                            <xsl:message>[xforms:repeat] value of @startindex ('<xsl:value-of select="@startindex"/>') is not a number. Setting the index to '1'</xsl:message>-->
                            <xsl:value-of select="1"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
<!--                <xsl:message>[xforms:repeat] Setting index of <xsl:sequence select="$myid"/> to '<xsl:sequence select="$this-index"/>'</xsl:message>-->
                <xsl:sequence select="js:setRepeatIndex($myid, $this-index)"/>
            </xsl:otherwise>
        </xsl:choose>
        

        <!-- identify instance fields corresponding to this -->
        <xsl:variable name="selectedRepeatVar" as="element()*" select="xforms:evaluate-xpath-with-instance-id($refi,$this-instance-id,())"/>
        
        <!--<xsl:message use-when="$debugMode">
            <xsl:choose>
                <xsl:when test="exists($selectedRepeatVar)">
                    [xforms:repeat] ref = <xsl:sequence select="$refi" />
                    count = <xsl:sequence select="count($selectedRepeatVar)" />
                </xsl:when>
                <xsl:otherwise>[xforms:repeat] No repeat found for ref <xsl:sequence select="$refi" /></xsl:otherwise>
            </xsl:choose>
        </xsl:message>-->
        
        <xsl:variable name="repeat-items" as="element()*">
            <xsl:variable name="this" as="element(xforms:repeat)" select="."/>
            <xsl:for-each select="$selectedRepeatVar">
                <xsl:variable name="string-position" as="xs:string" select="string(position())"/>
                <xsl:variable name="new-context-position" as="xs:string" select="if ($context-position != '') then concat($context-position, '.', $string-position) else $string-position"/>
                <div data-repeat-item="true">
                    <xsl:apply-templates select="$this/child::node()">
                        <xsl:with-param name="nodeset" select="concat($refi, '[', position(), ']')" tunnel="yes"/>
                        <xsl:with-param name="context-nodeset" select="concat($refi, '[', position(), ']')" tunnel="yes"/>
                        <xsl:with-param name="position" select="position()"/>
                        <xsl:with-param name="context-position" select="$new-context-position"/>
                    </xsl:apply-templates>
                </div>
            </xsl:for-each>
        </xsl:variable>
           
        <!-- Write HTML -->   
        <xsl:choose>
            <xsl:when test="$refreshRepeats and not(ancestor::xforms:repeat)">
                <xsl:sequence select="$repeat-items"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="additional-class-values" as="xs:string+" select="('xforms-repeat')"/>
                
                <xsl:variable name="htmlClass" as="xs:string">
                    <xsl:call-template name="getHtmlClass">
                        <xsl:with-param name="source-class" as="xs:string?" select="@class"/>
                        <xsl:with-param name="context-nodeset" select="$nodeset" tunnel="yes"/>
                        <xsl:with-param name="instance-context" select="$this-instance-id" tunnel="yes"/>
                        <xsl:with-param name="additional-values" as="xs:string*" select="$additional-class-values"/>
                    </xsl:call-template>
                </xsl:variable>
                <div>
                    <xsl:attribute name="id" select="$myid"/>
                    <xsl:attribute name="class" select="$htmlClass"/>
                    
                    <xsl:attribute name="data-repeatable-context" select="$refi" />
                    <xsl:attribute name="data-count" select="count($selectedRepeatVar)" />
                    
                    <xsl:sequence select="$repeat-items"/>
                </div>
            </xsl:otherwise>
        </xsl:choose>
        
        
        <!-- register repeats (top-level only and not when recalculating) -->
        <xsl:if test="not($recalculate) and not(ancestor::xforms:repeat)">
            <!--<xsl:message use-when="$debugMode">
                <xsl:sequence select="concat('[xforms:repeat] Registering repeat with ID ', $myid, ' and parsed nodeset ', $refi)"/>
            </xsl:message>-->
            <xsl:sequence select="js:addRepeat($myid , .)" />    
            
<!--            <xsl:message use-when="$debugMode">[xforms:repeat] setting context nodeset '<xsl:sequence select="$nodeset"/>'</xsl:message>-->
            <xsl:sequence select="js:addRepeatContext($myid , $nodeset)" /> 
            <xsl:sequence select="js:addRepeatModelContext($myid , $model-ref)" /> 
        </xsl:if>
        
        <!-- register size of repeat -->
        <xsl:sequence select="js:setRepeatSize($myid,count($selectedRepeatVar))"/>
        
        
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for xforms:submit element.</xd:p>
        </xd:desc>
        <xd:param name="submissions">Map of submissions.</xd:param>
    </xd:doc>
    <xsl:template match="xforms:submit">
        <xsl:param name="submissions" select="map{}" as="map(xs:string, map(*))" tunnel="yes"/>
        
        <!-- same logic as in xformsjs-main for setting submission map based on xforms:submission elements -->
        <xsl:variable name="submission-id" as="xs:string" select="
            if (@submission) then xs:string(@submission)
            else if (@id) then xs:string(@id)
            else $global-default-submission-id
            "/>
        
<!--        <xsl:message use-when="$debugMode">[xforms:submit] Generating form control for submission ID '<xsl:sequence select="string(@submission)"/>'</xsl:message>-->
        
<!--        <xsl:message use-when="$debugMode">[xforms:submit] Comparing ID with submissions map '<xsl:sequence select="serialize($submissions)"/>'</xsl:message>-->
        
        <xsl:variable name="innerbody">
            <xsl:apply-templates select="xforms:label"/>
        </xsl:variable>

        <xsl:choose>
            <xsl:when test="@appearance = 'minimal'">
                <a>
                    <xsl:copy-of select="$innerbody"/>
                </a>
            </xsl:when>
            <xsl:otherwise>
                <button type="button">
                    <xsl:copy-of select="@*[local-name() != 'submission']"/>
                    
                    <xsl:if test="map:contains($submissions, $submission-id)">
<!--                        <xsl:message use-when="$debugMode">[xforms:submit] Submission found</xsl:message>-->
                        <xsl:attribute name="data-submit" select="$submission-id"/>
                    </xsl:if>
                    <xsl:copy-of select="$innerbody"/>
                </button>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>


    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for updating instance XML based on node added with xforms:insert control</xd:p>
        </xd:desc>
        <xd:param name="insert-node-location">Node where insert is to take place</xd:param>
        <xd:param name="nodes-to-insert">Node set to be inserted</xd:param>
        <xd:param name="position-relative">"before" or "after"</xd:param>
    </xd:doc>
    <xsl:template match="*" mode="insert-node">
        <xsl:param name="insert-node-location" as="node()" tunnel="yes"/>
        <xsl:param name="nodes-to-insert" as="node()*" tunnel="yes"/>
        <xsl:param name="position-relative" as="xs:string?" select="'after'" required="no" tunnel="yes"/>
        
<!--        <xsl:message use-when="$debugMode">[insert-node mode] Checking whether <xsl:sequence select="name()"/> is the insert location</xsl:message>-->
        
        <xsl:if test=". is $insert-node-location and $position-relative = 'before'">
<!--            <xsl:message>[insert-node mode] Found! (inserting before) <xsl:value-of select="serialize($insert-node-location)"/></xsl:message>-->
            <xsl:copy-of select="$nodes-to-insert"/>
        </xsl:if>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <!-- 
            From XForms 1.1 spec:
            If the Node Set Binding node-set is not specified or empty, then the insert location node provided by the context attribute is intended to be the parent of the cloned node.
            -->
            <xsl:if test=". is $insert-node-location and $position-relative = 'child'">
<!--                <xsl:message>[insert-node mode] Found! (inserting as child) <xsl:value-of select="serialize($insert-node-location)"/></xsl:message>-->
                <xsl:copy-of select="$nodes-to-insert"/>
            </xsl:if>
            <xsl:apply-templates select="node()" mode="insert-node"/>
        </xsl:copy>
        <xsl:if test=". is $insert-node-location and $position-relative = 'after'">
<!--            <xsl:message>[insert-node mode] Found! (inserting after) <xsl:value-of select="serialize($insert-node-location)"/></xsl:message>-->
            <xsl:copy-of select="$nodes-to-insert"/>
        </xsl:if>
        
    </xsl:template>


    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for updating instance XML based on node deleted with xforms:delete control</xd:p>
        </xd:desc>
        <xd:param name="delete-node">Node(s) to be deleted</xd:param>
     </xd:doc>
    <xsl:template match="*" mode="delete-node">
        <xsl:param name="delete-node" as="node()*" tunnel="yes"/>
        
        <xsl:choose>
            <xsl:when test="some $n in $delete-node satisfies $n is .">

            </xsl:when>
            <xsl:otherwise>
                <xsl:copy>
                    <xsl:copy-of select="@*"/>
                    <xsl:apply-templates select="node()" mode="delete-node"/>
                </xsl:copy>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    
 
    <xd:doc scope="component">
        <xd:desc>Handle HTML button click</xd:desc>
    </xd:doc>
    <xsl:template match="(*:a|*:button)[exists(@data-action)]" mode="ixsl:onclick">      
        <xsl:call-template name="DOMActivate">
            <xsl:with-param name="form-control" select="."/>
        </xsl:call-template>       
    </xsl:template>



    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of XForms <a href="https://www.w3.org/TR/xforms11/#ui-trigger">trigger element</a></xd:p>
            <xd:p>Generates HTML link or button and registers actions.</xd:p>
        </xd:desc>
        <xd:param name="id">ID of HTML element.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
    </xd:doc>
    <xsl:template match="xforms:trigger" mode="get-html">
        <xsl:param name="id" as="xs:string" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" tunnel="yes"/>
        
        <xsl:variable name="innerbody">
            <xsl:choose>
                <xsl:when test="child::xforms:label">
                    <xsl:apply-templates select="xforms:label"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="'&#x00a0;'"/>
                </xsl:otherwise>
            </xsl:choose>
            
        </xsl:variable>
        
        <!--<span class="xforms-trigger">-->
            <xsl:variable name="html-element" as="xs:string">
                <xsl:choose>
                    <xsl:when test="@appearance = 'minimal'">
                        <xsl:sequence select="'a'"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:sequence select="'button'"/>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>
        <xsl:element name="{$html-element}">
                <xsl:if test="@appearance = 'minimal'">
                    <xsl:attribute name="type" select="'button'"/>
                </xsl:if>
            <xsl:attribute name="class" select="'xforms-trigger'"/>
                
                <xsl:attribute name="data-ref" select="$nodeset"/>
                <xsl:attribute name="data-action" select="$id"/>
                <xsl:copy-of select="$innerbody"/>            
            </xsl:element>
        <!--</span>-->        
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for XForms Action elements (xforms:action, xforms:setvalue, etc.)</xd:p>
            <xd:p>Generates map of this and descendant actions.</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="xforms:*[local-name() = $xforms-actions] | xforms:action | xforms:show | xforms:hide | xforms:script | xforms:unload">
        <xsl:variable name="myid" as="xs:string" select="if (exists(@id)) then @id else generate-id()"/>
        <xsl:variable name="log-label" as="xs:string" select="concat('[',name(),' match template]')"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        <xsl:variable name="time-id" select="concat($log-label, ' ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id)" />        
        
        
  
        <xsl:variable name="action-map" as="map(*)">
            <xsl:apply-templates select="." mode="set-action"/>
        </xsl:variable>
        
        <!--<xsl:message use-when="$debugMode">
            [XForms Action] found action!
            node       = <xsl:value-of select="serialize(.)"/>, 
            id         = <xsl:value-of select="@id"/>,
            myid       = <xsl:value-of select="$myid"/>, 
            event      = <xsl:value-of select="map:get($action-map,'@event')"/>
        </xsl:message>-->

        <xsl:if test="exists($action-map)">
            <xsl:sequence select="$action-map" />
        </xsl:if>

        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id)" />
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
    </xsl:template>
    

   
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for updating element within instance XML based on new value in binding calculation (xforms:bind/@calculate)</xd:p>
        </xd:desc>
        <xd:param name="updated-nodes">Nodes within instance that are affected by binding calculations</xd:param>
        <xd:param name="updated-value">Value of those nodes</xd:param>
    </xd:doc>

    <xsl:template match="*" mode="recalculate">
        <xsl:param name="updated-nodes" as="node()*" tunnel="yes"/>
        <xsl:param name="updated-value" as="item()?" tunnel="yes"/>
        
        <xsl:variable name="updated-node" as="element()?" select="$updated-nodes[. is fn:current()]"/>
        
<!--        <xsl:message use-when="$debugMode">[recalculate mode] comparing instance node <xsl:sequence select="fn:serialize(.)"/> with updated node <xsl:sequence select="fn:serialize($updated-nodes)"/></xsl:message> -->
        <xsl:copy>
            <xsl:apply-templates select="@*" mode="recalculate"/>
            
            <xsl:choose>
                <xsl:when test="exists($updated-node)">
                    <!--<xsl:message use-when="$debugMode">[recalculate mode] MATCHED <xsl:value-of select="name()"/></xsl:message> -->
                    <xsl:sequence select="$updated-value"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:apply-templates select="child::node()" mode="recalculate"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:copy>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for updating attribute within instance XML based on new value in binding calculation (xforms:bind/@calculate)</xd:p>
        </xd:desc>
        <xd:param name="updated-nodes">Nodes within instance that are affected by binding calculations</xd:param>
        <xd:param name="updated-value">Value of those nodes</xd:param>
    </xd:doc>
    <xsl:template match="@*" mode="recalculate">
        <xsl:param name="updated-nodes" as="node()*" tunnel="yes"/>
        <xsl:param name="updated-value" as="xs:string?" tunnel="yes"/>
        
        <xsl:variable name="updated-node" as="attribute()?" select="$updated-nodes[. is fn:current()]"/>
        
        <xsl:choose>
            <xsl:when test="exists($updated-node)">
                <xsl:attribute name="{name(.)}" select="$updated-value"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:copy-of select="."/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    
           
    
    <xd:doc scope="component">
        <xd:desc>Ensures namespaces are declared at instance level</xd:desc>
    </xd:doc>
    <xsl:template match="*" mode="namespace-fix">
        <xsl:variable name="current-namespace" as="xs:anyURI" select="namespace-uri()"/>
        <xsl:variable name="new-name" as="xs:QName" select="QName($current-namespace, name())"/>
        <xsl:element name="{$new-name}" namespace="{$current-namespace}">
            <xsl:namespace name="xforms" select="'http://www.w3.org/2002/xforms'"/>
            <xsl:copy-of select="namespace::*"/>
            <xsl:apply-templates select="@*,node()" mode="namespace-fix"/>
        </xsl:element>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>Copy attributes in namespace-fix mode</xd:desc>
    </xd:doc>
    <xsl:template match="@*" mode="namespace-fix">
        <xsl:copy-of select="."/>
    </xsl:template>



    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Return value of HTML form field</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="*:input" mode="get-field">

        <xsl:choose>
            <xsl:when test="exists(@type) and @type = 'checkbox'">
                <xsl:sequence select="if (ixsl:get(., 'checked') = true()) then 'true' else ''"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="ixsl:get(., 'value')"/>
            </xsl:otherwise>
        </xsl:choose>

    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Return value of HTML form field</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="*:select" mode="get-field">

        <xsl:sequence select="ixsl:get(./option[ixsl:get(., 'selected') = true()], 'value')"/>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Return value of HTML form field</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template match="*:textarea" mode="get-field">

        <xsl:sequence select="ixsl:get(., 'value')"/>
    </xsl:template>


    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Set value of HTML form field</xd:p>
        </xd:desc>
        <xd:param name="value">Value to set</xd:param>
    </xd:doc>
    <xsl:template match="*:input" mode="set-field">
        <xsl:param name="value" select="''" tunnel="yes"/>

        <xsl:choose>
            <xsl:when test="exists(@type) and @type = 'checkbox'">                
                <ixsl:set-property name="checked" select="if($value='true') then $value else ''" object="."/>
            </xsl:when>
            <xsl:otherwise>
                <ixsl:set-property name="value" select="$value" object="."/>
            </xsl:otherwise>
        </xsl:choose>

    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Set value of HTML form field</xd:p>
        </xd:desc>
        <xd:param name="value">Value to set</xd:param>
    </xd:doc>
    <xsl:template match="*:select" mode="set-field">
        <xsl:param name="value" select="''" tunnel="yes"/>

        <xsl:for-each select="./option[@value = $value]">
            <ixsl:set-property name="selected" select="true()" object="."/>
        </xsl:for-each>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Set value of HTML form field</xd:p>
        </xd:desc>
        <xd:param name="value">Value to set</xd:param>
    </xd:doc>
    <xsl:template match="*:textarea" mode="set-field">
        <xsl:param name="value" select="''" tunnel="yes" />
        <ixsl:set-property name="value" select="$value" object="."/>
    </xsl:template>
    
   
    <!-- 
    MD 2018
    
    Helper functions and templates
    
    -->
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Determine if an XForms element has a reference to the index() function.</xd:p>
            <xd:p>(If so, it will be added to a Javascript variable to support the xforms-recalculate event)</xd:p>
        </xd:desc>
        <xd:param name="this">Element to be checked</xd:param>
    </xd:doc>
    <xsl:function name="xforms:usesIndexFunction" as="xs:boolean">
        <xsl:param name="this" as="element()"/>
        <xsl:variable name="index-function-match" as="xs:string*" >
            <!-- 
            \i = "initial name character"
            \c = "name character"
            
            https://www.w3.org/TR/xmlschema11-2/#Name
            https://www.mulberrytech.com/quickref/regex.pdf
            
            -->
            <xsl:analyze-string select="$this/@ref" regex="\i\c*\(">
                <xsl:matching-substring>
                    <xsl:choose>
                        <xsl:when test="substring-before(.,'(')= 'index'">
                            <xsl:sequence select="'i'" />
                        </xsl:when>
                        <xsl:otherwise/>
                    </xsl:choose>
                </xsl:matching-substring>
                <xsl:non-matching-substring/>
            </xsl:analyze-string>
            
            <xsl:analyze-string select="$this/@nodeset" regex="\i\c*\(">
                <xsl:matching-substring>
                    <xsl:choose>
                        <xsl:when test="substring-before(.,'(')= 'index'">
                            <xsl:sequence select="'i'" />
                        </xsl:when>
                        <xsl:otherwise/>
                    </xsl:choose>
                </xsl:matching-substring>
                <xsl:non-matching-substring/>
            </xsl:analyze-string>
        </xsl:variable>
        
        <xsl:sequence select="if (exists($index-function-match)) then true() else false()"/>
        
    </xsl:function>
    
    <xd:doc scope="component">
        <xd:desc>Add all relevant namespace declarations to the xform element, to help with xsl:evaluation</xd:desc>
        <xd:param name="this">Document for which namespaces are needed</xd:param>
    </xd:doc>
    <xsl:function name="xforms:addNamespaceDeclarationsToDocument" as="document-node()">
        <xsl:param name="this" as="document-node()"/>
        <xsl:message use-when="$debugMode">[xforms:addNamespaceDeclarationsToDocument] URI: <xsl:value-of select="base-uri($this)"/></xsl:message>
        <xsl:document>
            <xsl:variable name="default-namespace" as="xs:anyURI" select="$this/*/namespace-uri()"/>
            <xsl:message use-when="$debugMode">[xforms:addNamespaceDeclarationsToDocument] <xsl:sequence select="if (name($this/*) eq 'html') then '&quot;' || string($this/*/*:head/*:title) || '&quot; ' else ()"/>Default namespace of root <xsl:sequence select="name($this/*)"/>: <xsl:sequence select="$default-namespace"/></xsl:message>
            <xsl:copy select="$this/*" copy-namespaces="yes">
                <xsl:namespace name="xforms" select="'http://www.w3.org/2002/xforms'"/>
                <xsl:for-each select="$this//*[not(namespace-uri() = ('','http://www.w3.org/2002/xforms',$default-namespace))][not(namespace-uri() = (ancestor::*/namespace-uri(),preceding::*/namespace-uri()))]">
                    <xsl:variable name="new-namespace" select="namespace-uri(.)"/>
                    <xsl:variable name="new-prefix-1" as="xs:string" select="substring-before(name(),':')"/>
                    <xsl:variable name="new-prefix" as="xs:string" select="if ($new-prefix-1 ne '') then $new-prefix-1 else ('ns' || fn:position())"/><xsl:namespace name="{$new-prefix}" select="$new-namespace"/>
                </xsl:for-each>
                <xsl:sequence select="$this/*/@*,$this/*/node()"/>
            </xsl:copy>
            
        </xsl:document>    
    </xsl:function>
    
    
    <xd:doc scope="component">
        <xd:desc>Write message to HTML page for the user. (Tried this as a function but got an error message relating to a "temporary output state")</xd:desc>
        <xd:param name="message">String message.</xd:param>
        <xd:param name="level">Optional string indicating level of severity, e.g. "error". Default value is "info".</xd:param>
    </xd:doc>
    <xsl:template name="logToPage">
        <xsl:param name="message" as="xs:string"/>
        <xsl:param name="level" as="xs:string" required="no" select="'info'"/>
        
        <xsl:result-document href="#{$xform-html-id}" method="ixsl:append-content">
            <div class="message-{$level}">
                <p>
                    <b>
                        <xsl:sequence select="concat(upper-case($level),': ')"/>
                    </b>
                    <xsl:sequence select="$message"/>
                </p>
            </div>
        </xsl:result-document>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>Find string in HTML @class attribute.</xd:desc>
        <xd:return>True if $string is one of the values of $class</xd:return>
        <xd:param name="element">HTML element that may have a @class attribute (e.g. class="block incremental")</xd:param>
        <xd:param name="string">String to match in class (e.g. "incremental")</xd:param>
    </xd:doc>
    <xsl:function name="xforms:hasClass" as="xs:boolean">
        <xsl:param name="element" as="element()"/>
        <xsl:param name="string" as="xs:string"/>
        
        <xsl:variable name="class" as="xs:string?" select="$element/@class"/>
        <xsl:variable name="classes" as="xs:string*" select="tokenize($class)"/>
        <xsl:choose>
            <xsl:when test="$string = $classes">
                <xsl:value-of select="true()"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="false()"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>From an XPath binding expression, return the ID of the referenced instance.</xd:p>
            <xd:p>If the expression starts instance('xxxx') the value is 'xxxx'.</xd:p>
            <xd:p>Otherwise, the value is the $default-instance-id</xd:p>
        </xd:desc>
        <xd:param name="nodeset">XPath binding expression</xd:param>
    </xd:doc>
    <xsl:function name="xforms:getInstanceId" as="xs:string">
        <xsl:param name="nodeset" as="xs:string"/>
        
        <xsl:choose>
            <xsl:when test="$nodeset = ''">
                <xsl:sequence select="$global-default-instance-id"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:analyze-string select="normalize-space($nodeset)"
                    regex="^instance\s*\(\s*&apos;([^&apos;]+)&apos;\s*\)\s*(/\s*(.*)|)$"
                    >
                    <xsl:matching-substring>
                        <xsl:sequence select="regex-group(1)"/>
                    </xsl:matching-substring>
                    <xsl:non-matching-substring>
                        <xsl:sequence select="$global-default-instance-id"/>
                    </xsl:non-matching-substring>
                </xsl:analyze-string>
            </xsl:otherwise>
        </xsl:choose>
       
    </xsl:function>
    
    <xd:doc scope="component">
        <xd:desc>Get HTML @class for rendering by combining @class set on XForms control and values determined by relevant status etc.  
            This template may be called during initial evaluation of the form or when refreshing outputs. In the latter case the original form control is lostd, so we need to use parameters for some fields. These are supplied either from the original form control, or from its registered properties when refreshing outputs.
        </xd:desc>
        <xd:param name="context-nodeset">XPath for context of class, in case class contains relative XPath</xd:param>
        <xd:param name="instance-context">Context instance ID, for XPath evaluation</xd:param>
        <xd:param name="source-class">Initial @class value from form control. If present, we will override an existing @class. This happens when refreshing outputs, where this template is applied to an HTML element instead of a form control.</xd:param>
        <xd:param name="additional-values">Optional sequence of strings to be included in the output as class values</xd:param>
        <xd:param name="incremental">Value of form control's @incremental attribute</xd:param>
    </xd:doc>
    <xsl:template name="getHtmlClass" as="xs:string">
        <xsl:param name="context-nodeset" as="xs:string?" tunnel="yes"/>
        <xsl:param name="instance-context" as="xs:string?" tunnel="yes"/>
        <xsl:param name="source-class" as="xs:string?"/>
        <xsl:param name="additional-values" as="xs:string*"/>
        <xsl:param name="incremental" as="xs:string?"/>
        
        <xsl:message use-when="$debugMode">[getHtmlClass] START</xsl:message>
        
        
        
        <xsl:message use-when="$debugMode">[getHtmlClass] Evaluating @class attribute: '<xsl:value-of select="$source-class"/>'</xsl:message>
        
        <xsl:variable name="class" as="xs:string?" select="if (exists($source-class)) then xforms:evaluate-string($source-class,$context-nodeset,$instance-context) else ()"/>
        
        
        <xsl:message use-when="$debugMode">[getHtmlClass] @class = '<xsl:sequence select="$class"/>'</xsl:message>
        
        <xsl:variable name="class-mod" as="xs:string*">
            <xsl:sequence select="fn:tokenize($class,'\s+')"/>
            <!-- include any additional "seed" values -->
            <xsl:sequence select="$additional-values"/>
            <xsl:if test="$incremental eq 'true'">
                <xsl:sequence select="'incremental'"/>
            </xsl:if>
         </xsl:variable>
        
        <xsl:sequence select="string-join($class-mod,' ')"/>
        
        <xsl:message use-when="$debugMode">[getHtmlClass] END</xsl:message>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>Identify when an XForms case (the context node) is "relevant". Supports the XForms <xd:a href="https://www.w3.org/TR/xforms11/#ui-switch-module">Switch module</xd:a>: "If multiple cases within a switch are marked as selected="true", the first selected case remains and all others are deselected. If none are selected, the first becomes selected."</xd:desc>
    </xd:doc>
    <xsl:template name="getCaseRelevantStatus" as="xs:boolean">
        <xsl:choose>
            <!-- If none are selected, the first becomes selected -->
            <xsl:when test="empty(../xforms:case[@selected eq 'true']) and empty(./preceding-sibling::xforms:case)">
                <xsl:sequence select="true()"/>
            </xsl:when>
            <!-- If multiple cases within a switch are marked as selected="true", the first selected case remain -->
            <xsl:when test=".[@selected eq 'true'] and empty(./preceding-sibling::xforms:case[@selected eq 'true'])">
                <xsl:sequence select="true()"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="false()"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>Identify when an XForms control is "relevant".</xd:desc>
        <xd:param name="xformsControl">XForms control element, e.g. input, output. NOTE: could be an HTML rendering of such an element.</xd:param>
        <xd:param name="instanceField">XForms instance or instance field relevant to the control</xd:param>
        <xd:param name="binding">xforms:bind elements relevant to this control</xd:param>
    </xd:doc>
    <xsl:template name="getRelevantStatus" as="xs:boolean">
        <xsl:param name="xformsControl" as="element()" required="yes"/>
        <xsl:param name="instanceField" as="node()?"/>
        <xsl:param name="binding" as="element(xforms:bind)*" tunnel="yes"/>
        
        <xsl:variable name="time-id-ns-context" as="xs:string" select="concat('getRelevantStatus (get namespace context)) ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-ns-context)" />
        
        <xsl:variable name="namespace-context-item" as="node()" select="
            if (exists($instanceField))
            then (
            if ($instanceField[self::text()])
            then $instanceField/parent::*
            else $instanceField
            )
            else /*"/>
        <!-- fallback was xforms:addNamespaceDeclarations(/*) which is SLOW -->
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-ns-context)" />
        
        <xsl:variable name="time-id-evaluate" as="xs:string" select="concat('getRelevantStatus (evaluate)) ', generate-id())"/>
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-evaluate)" />
        <!--<xsl:message use-when="$debugMode">[getRelevantStatus] Binding: <xsl:sequence select="serialize($binding)"/></xsl:message>-->
        <xsl:choose>
            <xsl:when test="exists($binding) and exists($binding/@relevant)">
                <!--<xsl:message use-when="$debugMode">[getRelevantStatus] context = <xsl:sequence select="fn:serialize($instanceField)"/></xsl:message>-->
                <xsl:evaluate xpath="xforms:impose($binding/@relevant)" context-item="$instanceField" namespace-context="$namespace-context-item"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="true()"/>
            </xsl:otherwise>
        </xsl:choose>
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-evaluate)" />
        
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>Update HTML display elements corresponding to xforms:output elements</xd:desc>
    </xd:doc>
    <xsl:template name="refreshOutputs-JS">
        <xsl:message use-when="$debugMode">[refreshOutputs-JS] START</xsl:message>
        
        <xsl:variable name="namespace-context-item" as="element()" select="js:getXForm()"/>
        
        <!-- get all registered outputs -->
        <!-- MD 2018-06-30 : want to use as="xs:string*" but get a cardinality error!? 
        JS data typing thing?
        -->
        <xsl:variable name="output-keys" select="js:getOutputKeys()" as="item()*"/>
        
        <xsl:for-each select="$output-keys">
            <xsl:variable name="this-key" as="xs:string" select="."/>
            <xsl:variable name="this-output" as="map(*)" select="js:getOutput($this-key)"/>
            
            <xsl:variable name="log-label" as="xs:string" select="'[refreshOutputs-JS]'"/>
            <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> Refreshing output ID = '<xsl:sequence select="$this-key"/>' (@value = <xsl:sequence select="map:get($this-output,'@value')"/>; @ref = <xsl:sequence select="map:get($this-output,'@ref')"/>; @data-type =  <xsl:sequence select="map:get($this-output,'@data-type')"/>; @instance-context =  <xsl:sequence select="map:get($this-output,'@instance-context')"/>)</xsl:message>
            
            
            <xsl:variable name="xpath" as="xs:string">
                <xsl:choose>
                    <xsl:when test="map:get($this-output,'@value')">
                        <xsl:sequence select="map:get($this-output,'@value')"/>
                    </xsl:when>
                    <xsl:when test="map:get($this-output,'@ref')">
                        <xsl:sequence select="map:get($this-output,'@ref')"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:sequence select="''"/>
                        <!-- TO DO: error condition -->
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>
            
            <xsl:variable name="xpath-mod" as="xs:string" select="xforms:impose('string(' || $xpath || ')')"/>
            
            <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $xpath-mod = '<xsl:sequence select="$xpath-mod"/>'</xsl:message>
                                    
            <xsl:variable name="this-instance-id" as="xs:string" select="map:get($this-output,'@instance-context')"/>
            
            <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $this-instance-id = '<xsl:sequence select="$this-instance-id"/>'</xsl:message>            
            
            <!-- 
                If value returned from unmodified XPath is a boolean
                the string value is '' for false() or 'true' for true()
            -->
            <xsl:variable name="value" as="xs:string?" select="xforms:evaluate-xpath-with-instance-id($xpath-mod,$this-instance-id,())"/>
            
            <xsl:variable name="data-type" as="xs:string?" select="map:get($this-output,'@data-type')"/>
            
            <xsl:variable name="itemset" as="element(xforms:itemset)?" select="map:get($this-output,'itemset')"/>
                        
            <xsl:variable name="associated-form-control" select="ixsl:page()//*[@id = $this-key]" as="node()?"/>
                        
            <xsl:choose>
                <xsl:when test="exists($associated-form-control) and local-name($associated-form-control) = ('input') and $data-type eq 'checkbox'">
                    <xsl:sequence select="js:setCheckboxValue($this-key,$value)"/>
                </xsl:when>
                
                <xsl:when test="exists($associated-form-control) and local-name($associated-form-control) = ('input','select','select1')">
                    <!-- update itemset before calling js:setValue -->
                    <xsl:if test="exists($itemset)">
                        <xsl:result-document href="#{$this-key}" method="ixsl:replace-content">
                            <xsl:apply-templates select="$itemset" mode="get-html">
                                <xsl:with-param name="default-namespace-context" select="$namespace-context-item" tunnel="yes"/>
                            </xsl:apply-templates>
                        </xsl:result-document>
                    </xsl:if>
                    
                    <xsl:sequence select="js:setValue($this-key,$value)"/>
                    
                    
                    
                </xsl:when>
                <xsl:when test="exists($associated-form-control) and local-name($associated-form-control) = ('iframe')">
                    <xsl:sequence select="js:setSrc($this-key,$value)"/>
                </xsl:when>
                <xsl:when test="exists($associated-form-control)">
                    <xsl:result-document href="#{$this-key}" method="ixsl:replace-content">
                        <xsl:value-of select="$value"/>
                    </xsl:result-document>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:message>[refreshOutputs-JS] Can't find form control with ID '<xsl:sequence select="$this-key"/>'</xsl:message>
                </xsl:otherwise>
            </xsl:choose>
            
            <!-- update class (value may include XPath) -->
            
            <xsl:variable name="xforms-class" as="xs:string?" select="map:get($this-output,'@class')"/>
            <xsl:variable name="context-nodeset" as="xs:string?" select="map:get($this-output,'@context-nodeset')"/>
            <xsl:variable name="additional-class-values" as="xs:string*" select="map:get($this-output,'@additional-class-values')"/>
            <xsl:variable name="incremental" as="xs:string?" select="map:get($this-output,'@incremental')"/>  
            
            <xsl:variable name="htmlClass" as="xs:string?">
                <xsl:call-template name="getHtmlClass">
                    <xsl:with-param name="context-nodeset" select="$context-nodeset" tunnel="yes"/>
                    <xsl:with-param name="instance-context" select="$this-instance-id" tunnel="yes"/>
                    <xsl:with-param name="source-class" select="$xforms-class"/>
                    <xsl:with-param name="additional-values" select="$additional-class-values"/>
                    <xsl:with-param name="incremental" select="$incremental"/>
                </xsl:call-template>
            </xsl:variable>
            
            <ixsl:set-attribute name="class" select="$htmlClass" object="$associated-form-control"/>
            
        </xsl:for-each>
        
        <xsl:message use-when="$debugMode">[refreshOutputs-JS] END</xsl:message>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>Update HTML display elements corresponding to xforms:repeat elements</xd:desc>
    </xd:doc>
    <xsl:template name="refreshRepeats-JS">      
        <xsl:variable name="log-label" as="xs:string" select="'[refreshRepeats-JS]'"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
              
        <xsl:variable name="repeat-keys" select="js:getRepeatKeys()" as="item()*"/>
        
        <xsl:variable name="namespace-context-item" as="element()" select="js:getXForm()"/>
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $namespace-context-item: <xsl:sequence select="name($namespace-context-item)"/></xsl:message>
        
        <xsl:for-each select="$repeat-keys">
            <xsl:variable name="this-key" as="xs:string" select="."/>
            <xsl:variable name="this-repeat" as="element()" select="js:getRepeat($this-key)"/>
            <xsl:variable name="this-repeat-nodeset" as="xs:string" select="js:getRepeatContext($this-key)"/>
            <xsl:variable name="this-repeat-model" as="xs:string" select="js:getRepeatModelContext($this-key)"/>
            
            <xsl:variable name="page-element" select="ixsl:page()//*[@id = $this-key]" as="node()?"/>
            
            <xsl:choose>
                <xsl:when test="exists($page-element)">
                    <xsl:result-document href="#{$this-key}" method="ixsl:replace-content">
                        <xsl:apply-templates select="$this-repeat">
                            <xsl:with-param name="model-key" select="$this-repeat-model" tunnel="yes"/>
                            <xsl:with-param name="nodeset" select="$this-repeat-nodeset" tunnel="yes"/>
                            <xsl:with-param name="recalculate" select="true()" tunnel="yes"/>
                            <xsl:with-param name="refreshRepeats" select="fn:true()" tunnel="yes"/>
                            <xsl:with-param name="default-namespace-context" select="$namespace-context-item" tunnel="yes"/>
                        </xsl:apply-templates>
                    </xsl:result-document>
                </xsl:when>
                <xsl:otherwise/>
            </xsl:choose>
        </xsl:for-each>
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
    </xsl:template>
 
 
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Check fields with @relevant binding (part of a xforms-refresh event.)</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="refreshRelevantFields-JS">
        <xsl:message use-when="$debugMode">[refreshRelevantFields-JS] START</xsl:message>
        
        <!-- go through all form controls where @data-relevant has been set -->
        <xsl:for-each select="ixsl:page()//*[@data-relevant]">
            <xsl:variable name="context-node" as="node()?" select="xforms:evaluate-xpath-with-instance-id(string(@data-ref),string(@instance-context),())"/>
            <xsl:variable name="relevantStatus" as="xs:boolean" select="if (exists($context-node)) then xforms:evaluate-xpath-with-context-node(string(@data-relevant),$context-node,()) else false()"/>
            <!-- 
                div containing span, input, etc. with its label (HTML <label> generated from <xforms:label>)
            -->
            <xsl:variable name="htmlWrapper" as="element()?" select="./parent::*"/>
            
            <!--<xsl:variable name="htmlClass" as="xs:string?">
                <xsl:call-template name="getHtmlClass">
                    
                </xsl:call-template>
            </xsl:variable>-->
            
           <!-- <ixsl:set-attribute name="class" select="$htmlClass" object="."/>
            <xsl:if test="exists($htmlWrapper)">
                <ixsl:set-attribute name="class" select="$htmlClass" object="$htmlWrapper"/>
            </xsl:if>-->
            
            <xsl:choose>
                <xsl:when test="$relevantStatus">
                    <xsl:if test="ixsl:style(.)?display = 'none'">
                        <xsl:message use-when="$debugMode">[refreshRelevantFields-JS] removing display="none"</xsl:message>
                        <ixsl:remove-property name="style.display" object="."/>
                        <ixsl:remove-attribute name="style" object="."/>
                    </xsl:if>
                    <!-- 
                        Change setting on parent as well
                        HTML for <xf:output> includes parent <span> containing rendering of label
                    -->
                    <xsl:if test="exists($htmlWrapper) and ixsl:style($htmlWrapper)?display = 'none'">
                        <xsl:message use-when="$debugMode">[refreshRelevantFields-JS] removing display="none" from parent</xsl:message>
                        <ixsl:remove-property name="style.display" object="$htmlWrapper"/>
                        <ixsl:remove-attribute name="style" object="$htmlWrapper"/>
                    </xsl:if>
                </xsl:when>
                <xsl:otherwise>
                    <ixsl:set-style name="display" select="'none'" object="."/>
                    <xsl:if test="exists($htmlWrapper)">
                        <ixsl:set-style name="display" select="'none'" object="$htmlWrapper"/>
                    </xsl:if>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:for-each>
        
        <xsl:message use-when="$debugMode">[refreshRelevantFields-JS] END</xsl:message>
        
     </xsl:template>
    
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Update HTML display elements corresponding to XForms elements that use the index() function</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="refreshElementsUsingIndexFunction-JS">
        <xsl:message use-when="$debugMode">[refreshElementsUsingIndexFunction-JS] START</xsl:message>
        
        <xsl:variable name="ElementsUsingIndexFunction-keys" select="js:getElementsUsingIndexFunctionKeys()" as="item()*"/>    
        
        <xsl:variable name="namespace-context-item" as="element()" select="js:getXForm()"/>
        
                
        <xsl:for-each select="$ElementsUsingIndexFunction-keys">
            <xsl:variable name="this-key" as="xs:string" select="."/>
            
            <xsl:message use-when="$debugMode">[refreshElementsUsingIndexFunction-JS] Refreshing item with key '<xsl:sequence select="$this-key"/>'</xsl:message>
            
            <xsl:variable name="this-element" as="element()" select="js:getElementUsingIndexFunction($this-key)"/>
            
            <xsl:variable name="this-element-refi" as="xs:string" select="js:getElementContextUsingIndexFunction($this-key)"/>
            
            <xsl:message use-when="$debugMode">[refreshElementsUsingIndexFunction-JS] $this-element-refi = '<xsl:sequence select="$this-element-refi"/>'</xsl:message>
            <xsl:result-document href="#{$this-key}" method="ixsl:replace-content">
                <xsl:apply-templates select="$this-element/*">
                    <xsl:with-param name="nodeset" select="$this-element-refi" tunnel="yes"/>
                    <xsl:with-param name="recalculate" select="true()" tunnel="yes"/>
                    <xsl:with-param name="default-namespace-context" select="$namespace-context-item" tunnel="yes"/>
                </xsl:apply-templates>
            </xsl:result-document>
            
        </xsl:for-each>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Apply actions by calling the template appropriate to each action.</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="applyActions">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <xsl:variable name="log-label" select="'[applyActions]'"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START <xsl:sequence select="if(exists(map:get($action-map, '@event'))) then '(event ' || map:get($action-map, '@event') || ')' else ''"/><xsl:sequence select="'(action name ' || map:get($action-map, 'name') || ')'"/></xsl:message>
        
        <xsl:variable name="instance-context" select="map:get($action-map, 'instance-context')" as="xs:string"/>
        <xsl:variable name="handler-status" select="map:get($action-map, 'handler-status')" as="xs:string"/>
        <xsl:variable name="ref" select="map:get($action-map, '@ref')" as="xs:string?"/>
        <xsl:variable name="at" select="map:get($action-map, '@at')" as="xs:string?"/>
        <xsl:variable name="position" select="(map:get($action-map, '@position'),'after')[1]" as="xs:string"/>
        <xsl:variable name="context" select="map:get($action-map, '@context')" as="xs:string?"/>
        
 
        <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $action-map @ref = <xsl:sequence select="$ref"/></xsl:message>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $action-map @at = <xsl:sequence select="$at"/></xsl:message>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $action-map @position = <xsl:sequence select="$position"/></xsl:message>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $action-map @context = <xsl:sequence select="$context"/></xsl:message>-->
        
        
        <xsl:variable name="ref-qualified" as="xs:string?" select="
            if (exists($ref) and $ref != '')
            then (
                if (exists($at))
                then concat($ref, '[', $at, ']')
                else $ref
            )
            else ()
            "/>
        
        <xsl:variable name="instanceXML" as="element()?" select="xforms:instance($instance-context)"/>        
       
        <xsl:variable name="context-nodeset" as="node()*">
            <xsl:choose>
                <!-- try evaluating @context first -->
                <xsl:when test="exists($context) and not($context = '')">
                    <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> context node: <xsl:sequence select="fn:serialize($context)"/></xsl:message>-->
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node($context,$instanceXML,())"/>
                </xsl:when>
                <!-- then try evaluating @ref (qualified with @at) -->
                <xsl:when test="exists($ref-qualified) and not($ref-qualified = '')">
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node($ref-qualified,$instanceXML,())"/>
                </xsl:when>
                <!-- fall back to instance XML -->
                <xsl:otherwise>
                    <xsl:sequence select="$instanceXML"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="context-node" as="element()?">
            <xsl:variable name="context-first-item" as="node()?" select="$context-nodeset[1]"/>
            <xsl:sequence select="if ($context-first-item[not(self::*)]) then $context-first-item/parent::* else $context-first-item"/>
        </xsl:variable>
        
        <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> context node: <xsl:sequence select="fn:serialize($context)"/></xsl:message>-->
        
        <!-- TODO error testing of incorrect ref given in the xform (i.e. context would be empty in this case) -->

        <xsl:variable name="ifVar" as="xs:string?" select="xforms:getIfStatement($action-map)"/>      
        <xsl:variable name="whileVar" as="xs:string?" select="xforms:getWhileStatement($action-map)"/>
        <xsl:variable name="iterate-ref" as="xs:string?" select="xforms:getIterateStatement($action-map)"/>
        
        <!-- TODO if the action does not contain an if or while it should execute action -->
        <xsl:variable name="ifExecuted" as="xs:boolean">
            <xsl:choose>
                <xsl:when test="exists($ifVar) and exists($context-node) and empty($iterate-ref)">
                    <!-- don't evaluate 'if' statement if there's an iterate -->
                    <xsl:message use-when="$debugMode">[applyActions] applying @if = <xsl:sequence select="$ifVar"/> in context <xsl:sequence select="fn:serialize($context-node)"/></xsl:message>
                    <xsl:variable name="evaluation-result" select="xforms:evaluate-xpath-with-context-node($ifVar,$context-node,())"/>
                    <xsl:sequence select="boolean($evaluation-result)"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="true()" />
                </xsl:otherwise>
            </xsl:choose>                    
        </xsl:variable>
        
        <!--<xsl:message use-when="$debugMode">[applyActions] $ifExecuted = <xsl:sequence select="$ifExecuted"/></xsl:message>-->
                
        <xsl:variable name="isWhileTrue" as="xs:boolean">
            <xsl:choose>
                <xsl:when test="exists($whileVar) and exists($context-node)">
                    <xsl:variable name="evaluation-result" select="xforms:evaluate-xpath-with-context-node($whileVar,$context-node,())"/>
                    <xsl:sequence select="boolean($evaluation-result)"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="true()" />
                </xsl:otherwise>
            </xsl:choose>                    
        </xsl:variable>
        
        <!-- https://www.w3.org/TR/xforms11/#action -->
        <xsl:if test="$ifExecuted and $isWhileTrue">
            <xsl:variable name="action-name" as="xs:string" select="map:get($action-map,'name')"/>
            
            <xsl:choose>
                <xsl:when test="$action-name = 'action'">
                    <!-- xforms:action is just a wrapper -->
                </xsl:when>
                <xsl:when test="$action-name = 'setvalue'">
                    <xsl:call-template name="action-setvalue"/>
                </xsl:when>
                <xsl:when test="$action-name = 'insert'">
                     
                    <xsl:call-template name="action-insert"/>
                </xsl:when>
                <xsl:when test="$action-name = 'delete'">
                    <xsl:call-template name="action-delete"/>
                </xsl:when>
                <xsl:when test="$action-name = 'setindex'">
                    <xsl:call-template name="action-setindex"/>
                </xsl:when>
                <xsl:when test="$action-name = 'toggle'">
                    <xsl:call-template name="action-toggle"/>
                </xsl:when>
                <xsl:when test="$action-name = 'setfocus'">
                    <xsl:call-template name="action-setfocus"/>
                </xsl:when>
                <!--<xsl:when test="$action-name = 'dispatch'">
                    <xsl:call-template name="action-dispatch"/>
                </xsl:when>-->
                <xsl:when test="$action-name = 'rebuild'">
                    <xsl:call-template name="xforms-rebuild"/>
                </xsl:when>
                <xsl:when test="$action-name = 'recalculate'">
                    <xsl:call-template name="xforms-recalculate"/>
                </xsl:when>
                <!--<xsl:when test="$action-name = 'revalidate'">
                    <xsl:call-template name="xforms-revalidate"/>
                </xsl:when>-->
                <xsl:when test="$action-name = 'refresh'">
                    <xsl:call-template name="action-refresh"/>
                </xsl:when>
                <xsl:when test="$action-name = 'reset'">
                    <xsl:call-template name="action-reset"/>
                </xsl:when>
                <!--<xsl:when test="$action-name = 'load'">
                    <xsl:call-template name="action-load"/>
                </xsl:when>-->
                <xsl:when test="$action-name = 'send'">
                    <xsl:call-template name="action-send"/>
                </xsl:when>
                <xsl:when test="$action-name = 'message'">
                    <xsl:call-template name="action-message"/>
                </xsl:when>
                <xsl:when test="$action-name = 'output'">
                    <xsl:call-template name="action-output">
                        <xsl:with-param name="context-node" select="$context-node"/>
                    </xsl:call-template>
                </xsl:when>
                <!-- special action for text content of xforms:message -->
                <xsl:when test="$action-name = 'text'">
                    <xsl:call-template name="action-text"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:message use-when="$debugMode">[applyActions] action '<xsl:value-of select="$action-name"/>' not yet handled!</xsl:message>
                </xsl:otherwise>
            </xsl:choose>
             
            
            <xsl:variable name="nested-actions-array" select="map:get($action-map, 'nested-actions')" as="array(map(*))?"/>
            <xsl:variable name="nested-actions" as="item()*">
                <xsl:sequence select="array:flatten($nested-actions-array)"/>
            </xsl:variable>
            
            <xsl:choose>
                <xsl:when test="$action-name = 'message'">
                    <!-- 
                        ignoring nested actions of xforms:message here - they are dealt with under action-message
                    -->
                </xsl:when>
                <xsl:otherwise>
                    <xsl:for-each select="$nested-actions">
                        <xsl:call-template name="applyActions">
                            <xsl:with-param name="action-map" select="." tunnel="yes"/>
                        </xsl:call-template>
                    </xsl:for-each>
                </xsl:otherwise>
            </xsl:choose>
            
            
            <xsl:variable name="isWhileStillTrue" as="xs:boolean">
                <xsl:choose>
                    <xsl:when test="exists($whileVar) and exists($context-node)">
                        <xsl:variable name="evaluation-result" select="xforms:evaluate-xpath-with-context-node($whileVar,$context-node,())"/>
                        <xsl:sequence select="boolean($evaluation-result)"/>
                     </xsl:when>
                    <xsl:otherwise>
                        <!-- 
                            don't go back round the loop unless there is a @while
                            and it is still true
                        -->
                        <xsl:sequence select="false()" />
                    </xsl:otherwise>
                </xsl:choose>                    
            </xsl:variable>
            
            <!-- TO DO: mitigate risk of recursion if possible -->
            <xsl:if test="$isWhileStillTrue">
                <xsl:call-template name="applyActions"/>
            </xsl:if>
            
            <xsl:if test="$handler-status = 'outermost'">
                <xsl:call-template name="outermost-action-handler"/>
            </xsl:if>
            
            
        </xsl:if>
       
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END <xsl:sequence select="if(exists(map:get($action-map, '@event'))) then '(event ' || map:get($action-map, '@event') || ')' else ''"/><xsl:sequence select="'(action name ' || map:get($action-map, 'name') || ')'"/></xsl:message>
        
    </xsl:template>
    
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>registerOutput: create map of an xforms:output (or xforms:input) whose value may be updated e.g. during an xforms-refresh. This element is the context node.</xd:p>
        </xd:desc>
        <xd:param name="id">ID of HTML element.</xd:param>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="context-nodeset">XPath binding expression for context node (used if @value contains context() function)</xd:param>
        <xd:param name="instance-context">ID of XForms instance relevant to this control</xd:param>
        <xd:param name="data-type">String identifying data type of an input. Required to support setting its value in the appropriate way</xd:param>
        <xd:param name="additional-class-values">Any additional class values we want to set. Need to register them here so they can be applied again when refreshing outputs.</xd:param>
    </xd:doc>
    <xsl:template name="registerOutput">
        <xsl:param name="id" as="xs:string" tunnel="yes"/>
        <xsl:param name="nodeset" as="xs:string" tunnel="yes"/>
        <xsl:param name="context-nodeset" as="xs:string" tunnel="yes"/>
        <xsl:param name="instance-context" as="xs:string" tunnel="yes"/>
        <xsl:param name="data-type" as="xs:string" required="no" select="''"/>
        <xsl:param name="additional-class-values" as="xs:string*"/>
        
        <xsl:sequence use-when="$debugTiming" select="js:startTime($time-id-register-outputs)" />
        
        <xsl:if test="not(ancestor::xforms:repeat)">
            <xsl:variable name="output-map" as="map(*)">
                <xsl:map>
                    <xsl:map-entry key="'@instance-context'" select="$instance-context"/>
                    <xsl:map-entry key="'@context-nodeset'" select="$context-nodeset"/>
                    
                    <xsl:if test="$nodeset != ''">
                        <xsl:map-entry key="'@ref'" select="xs:string($nodeset)" />
                    </xsl:if>
                    
                    <xsl:if test="exists(@value)">
                        <xsl:map-entry key="'@value'" select="xforms:resolveContext(xs:string(@value),$context-nodeset)" />
                    </xsl:if>
                    
                    <xsl:if test="$data-type ne ''">
                        <xsl:map-entry key="'@data-type'" select="$data-type"/>
                    </xsl:if>
                    
                    <xsl:if test="exists(@incremental)">
                        <xsl:map-entry key="'@incremental'" select="string(@incremental)"/>
                    </xsl:if>
                    
                    <xsl:if test="exists(@class)">
                        <xsl:map-entry key="'@class'" select="string(@class)"/>
                    </xsl:if>
                    <xsl:if test="exists($additional-class-values)">
                        <xsl:map-entry key="'@additional-class-values'" select="$additional-class-values"/>
                    </xsl:if>
                    
                    <xsl:if test="exists(child::xforms:itemset)">
                        <xsl:map-entry key="'itemset'" select="child::xforms:itemset"/>
                    </xsl:if>
                </xsl:map>
            </xsl:variable>
            
            <xsl:message use-when="$debugMode">
                <xsl:sequence select="concat('[registerOutput] Registering output with ID ', $id)"/>
            </xsl:message>
            <xsl:sequence select="js:addOutput($id , $output-map)" />
        </xsl:if>
        
        <xsl:sequence use-when="$debugTiming" select="js:endTime($time-id-register-outputs)" />
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>setSubmission: create map of an  xforms:submission</xd:p>
            <xd:p>See <a href="https://www.w3.org/TR/xforms11/#submit-submission-element">XForms spec 11.1 The submission Element</a></xd:p>
        </xd:desc>
        <xd:param name="this">An XForms Submission element (i.e. xforms:submission).</xd:param>
        <xd:param name="submission-id">Identifier for the xforms:submission element (or the default ID).</xd:param>
    </xd:doc>
    <xsl:template name="setSubmission">
        <xsl:param name="this" as="element()"/>
        <xsl:param name="submission-id" as="xs:string"/>
        
        <xsl:message use-when="$debugMode">[setSubmission] START (submission ID '<xsl:sequence select="$submission-id"/>')</xsl:message>
                
        <xsl:variable name="properties" as="map(*)">
            <xsl:apply-templates select="." mode="get-properties"/>
        </xsl:variable>
        
        <xsl:variable name="refi" as="xs:string" select="map:get($properties,'nodeset')"/>
        <xsl:variable name="this-instance-id" as="xs:string" select="map:get($properties,'instance-context')"/>
        
        <!-- set actions relevant to this -->
        <xsl:variable name="actions"  as="map(*)*">
            <xsl:apply-templates select="." mode="set-actions">
                <xsl:with-param name="instance-key" select="$this-instance-id" tunnel="yes"/>
                <xsl:with-param name="nodeset" select="$refi" tunnel="yes"/>
                <xsl:with-param name="properties" select="$properties" tunnel="yes"/>
            </xsl:apply-templates>
        </xsl:variable>
        
        <xsl:if test="exists($actions)">
            <xsl:sequence select="js:addAction($submission-id, $actions)" />
        </xsl:if>
        
        <!-- default values bases on XForms spec section 11: https://www.w3.org/TR/xforms11/#submit -->
        <xsl:map>
            <xsl:if test="exists($this/@resource)">
                <xsl:map-entry key="'@resource'" select="xs:string($this/@resource)" />
            </xsl:if>
            
            <xsl:map-entry key="'@id'" select="if (exists($this/@id)) then $this/@id else $submission-id"/>
            
            <xsl:map-entry key="'@ref'" select="if (exists($refi)) then $refi else '/'"/>
            
            <xsl:if test="exists($this/@bind)">
                <xsl:map-entry key="'@bind'" select="xs:string($this/@bind)" />
            </xsl:if>
            
            <xsl:map-entry key="'@mode'" select="if (exists($this/@mode)) then xs:string($this/@mode) else 'asynchronous'" />
            
            <xsl:variable name="submission-method" as="xs:string">
                <xsl:choose>
                    <xsl:when test="$this/xforms:method/@value">
                        <xsl:value-of select="$this/xforms:method/@value"/>
                    </xsl:when>
                    <xsl:when test="exists($this/@method)">
                        <xsl:sequence select="string($this/@method)"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <!-- default 'POST' method -->
                        <xsl:sequence select="'POST'"/>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>
            <xsl:map-entry key="'@method'" select="$submission-method"/>
            
            <!-- https://www.w3.org/TR/xforms11/#submit-options -->
            <xsl:variable name="serialization" as="xs:string">
                <xsl:choose>
                    <xsl:when test="exists($this/@serialization)">
                        <xsl:value-of select="$this/@serialization"/>
                    </xsl:when>
                    <xsl:when test="$submission-method = ('post','POST','put','PUT')">
                        <xsl:sequence select="'application/xml'"/>
                    </xsl:when>
                    <xsl:when test="$submission-method = ('get','GET','delete','DELETE','urlencoded-post','URLENCODED-POST')">
                        <xsl:sequence select="'application/x-www-form-urlencoded'"/>
                    </xsl:when>
                    <xsl:when test="$submission-method = ('multipart-post','MULTIPART-POST')">
                        <xsl:sequence select="'multipart/related'"/>
                    </xsl:when>
                    <xsl:when test="$submission-method = ('form-data-post','FORM-DATA-POST')">
                        <xsl:sequence select="'multipart/form-data'"/>
                    </xsl:when>
                    <xsl:when test="$submission-method = ('post','POST')">
                        <xsl:sequence select="'application/xml'"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:sequence select="'application/xml'"/>
                    </xsl:otherwise>
                </xsl:choose>
            </xsl:variable>
            
            <xsl:map-entry key="'@validate'" select="if ($this/@validate) then string($this/@validate)
                else if ($serialization = 'none') then 'false' 
                else 'true'" />
            
            
            <xsl:map-entry key="'@relevant'" select="if ($this/@relevant) then string($this/@relevant) 
                else if ($serialization = 'none') then 'false' 
                else 'true'" />
            
            <xsl:map-entry key="'@serialization'" select="$serialization" />
            
            <xsl:map-entry key="'@version'" select="if ($this/@version) then string($this/@version) else '1.0'" />
            
            <xsl:map-entry key="'@indent'" select="if ($this/@indent) then string($this/@indent) else 'false'" />
            
            
            <xsl:map-entry key="'@mediatype'" select="if ($this/@mediatype) then string($this/@mediatype) else 'application/xml'"/>
            
            
            <xsl:map-entry key="'@encoding'" select="if ($this/@encoding) then string($this/@encoding) else 'UTF-8'" />
            
            <xsl:map-entry key="'@omit-xml-declaration'" select="if ($this/@omit-xml-declaration) then string($this/@omit-xml-declaration) else 'false'" />
            
            <xsl:if test="exists($this/@standalone )">
                <xsl:map-entry key="'@standalone'" select="string($this/@standalone)" />
            </xsl:if>
            
            <xsl:map-entry key="'@cdata-section-elements'" select="if ($this/@cdata-section-elements) then string($this/@cdata-section-elements) else ''" />
            
            <xsl:map-entry key="'@replace'" select="if ($this/@replace) then string($this/@replace) else 'all'"/>
            
            <xsl:map-entry key="'@instance'" select="if ($this/@instance) then string($this/@instance) else $this-instance-id" />
           
            
            <xsl:if test="exists($this/@targetref )">
                <xsl:map-entry key="'@targetref'" select="string($this/@targetref)" />
            </xsl:if>
            
            <xsl:map-entry key="'@separator'" select="if ($this/@separator) then string($this/@separator) else '&amp;'" />
            
            <xsl:if test="exists($this/@includenamespaceprefixes)">
                <xsl:map-entry key="'@includenamespaceprefixes'" select="string($this/@includenamespaceprefixes)" />
            </xsl:if>
            
           
        </xsl:map>
        
        <xsl:message use-when="$debugMode">[setSubmission] END (submission ID '<xsl:sequence select="$submission-id"/>')</xsl:message>
        
    </xsl:template>
   
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#evt-modelConstruct">xforms-model-construct event</a></xd:p>
            <xd:p>"Perform the behaviors of xforms-rebuild, xforms-recalculate, and xforms-revalidate in sequence on this model element without dispatching events to invoke the behaviors"</xd:p>
            <xd:p>TO DO: handle instances with data provided at an external URI.</xd:p>
        </xd:desc>
        <xd:param name="model">xforms:model element to be processed.</xd:param>
        <xd:param name="default-model-id">Identifier for first model in XForm. The first instance in this model is the default instance.</xd:param>
    </xd:doc>
    <xsl:template name="xforms-model-construct">
        <xsl:param name="model" as="element(xforms:model)" required="yes" tunnel="yes"/>
        <xsl:param name="default-model-id" as="xs:string" required="no" select="$global-default-model-id" tunnel="yes"/>
        
        <xsl:variable name="model-key" as="xs:string" select="if (exists($model/@id)) then xs:string($model/@id) else $default-model-id"/>
        
        <xsl:variable name="instances" as="element(xforms:instance)*" select="$model/xforms:instance"/>       
        
        <xsl:for-each select="$instances">
            <xsl:variable name="instance-data" as="element()?">
                <xsl:choose>
                    <xsl:when test="child::*">
                        <xsl:sequence select="child::*"/>
                    </xsl:when>
                    <xsl:when test="@src">
                        <xsl:variable name="instance-path" as="xs:anyURI" select="resolve-uri(@src,base-uri($xforms-doc-global))"/>
                        <!--<xsl:message use-when="$debugMode">[xforms-model-construct] Getting instance data from <xsl:value-of select="@src"/> (relative to <xsl:sequence select="base-uri($xforms-doc-global)"/>)</xsl:message>-->
                        <xsl:sequence select="doc($instance-path)/*"/>
                    </xsl:when>
                    <xsl:otherwise/>
                </xsl:choose>
            </xsl:variable>
            <xsl:variable name="instance-with-explicit-namespaces" as="element()">
                <xsl:apply-templates select="$instance-data" mode="namespace-fix"/>
            </xsl:variable>
            <xsl:variable name="instance-key" as="xs:string" select="if (exists(@id)) then xs:string(@id) else $global-default-instance-id"/>
            <!--<xsl:message use-when="$debugMode">[xforms-model-construct] Setting instance with ID '<xsl:sequence select="$instance-key"/>': <xsl:sequence select="fn:serialize($instance-with-explicit-namespaces)"/></xsl:message>-->
            <xsl:sequence select="js:setInstance($instance-key,$instance-with-explicit-namespaces)"/>
            <xsl:if test="position() = 1">
                <xsl:sequence select="js:setModelDefaultInstanceKey($model-key,$instance-key)"/>
                <xsl:if test="$model-key = $default-model-id">
                    <xsl:sequence select="js:setDefaultInstance($instance-with-explicit-namespaces)"/>
                </xsl:if>
            </xsl:if>
        </xsl:for-each>
        
         
        <xsl:call-template name="xforms-rebuild">
            <xsl:with-param name="get-bindings" as="xs:boolean" select="true()"/>
            <xsl:with-param name="model-key" as="xs:string" select="$model-key" tunnel="yes"/>
        </xsl:call-template>
        
        <xsl:call-template name="xforms-recalculate"/>
        
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#evt-rebuild">xforms-rebuild event</a></xd:p>
            <xd:p>[MD 2020-04-13] I think the way Saxon-Forms works means that the bindings need to be constructed only once. Subsequently they are applied on the fly. </xd:p>
        </xd:desc>
        <xd:param name="get-bindings">Boolean, only true when model is being constructed.</xd:param>
        <xd:param name="model">xforms:model element to build.</xd:param>
    </xd:doc>
    <xsl:template name="xforms-rebuild">
        <xsl:param name="get-bindings" as="xs:boolean" select="false()" required="no"/>
        <xsl:param name="model" as="element(xforms:model)?" required="no" tunnel="yes"/>
        
        <xsl:if test="$get-bindings">
            <xsl:variable name="parsed-bindings" as="element(xforms:bind)*">
                <xsl:apply-templates select="$model/xforms:bind" mode="add-context"/>
            </xsl:variable>
            <xsl:for-each select="$parsed-bindings">
                <xsl:sequence select="js:setBinding(.)"/>
            </xsl:for-each>
        </xsl:if>
      
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Add context to xforms:bind element. The relevant model and instance IDs are added, and the @nodeset is set (if absent) or expanded based on the $nodeset tunnel parameter</xd:p>
            <xd:p>Called from xforms-rebuild event.</xd:p>
            <xd:p>In the <xd:a href="https://www.w3.org/community/xformsusers/wiki/XForms_2.0#The_bind_Element">XForms 2.0 spec for bind</xd:a>, @ref is the preferred synonym for @nodeset</xd:p>
        </xd:desc>
        <xd:param name="nodeset">XPath binding expression</xd:param>
        <xd:param name="model-key">ID of context model (xforms:model/@id value or default value).</xd:param>
        <xd:param name="default-instance-id">Context instance ID</xd:param>
    </xd:doc>
    <xsl:template match="xforms:bind" mode="add-context">
        <xsl:param name="nodeset" as="xs:string" select="''" tunnel="yes"/>
        <xsl:param name="model-key" as="xs:string" required="no" select="$global-default-model-id" tunnel="yes"/> 
        <xsl:param name="default-instance-id" as="xs:string" required="no" select="$global-default-instance-id" tunnel="yes"/>
        
        <!-- 
            XForms test suite uses @ref on <bind> elements,
            even though XForms 1.1 spec mentions only @nodeset
        -->
        <xsl:variable name="this-ref" as="xs:string?" select="
            if ( exists(@ref) ) 
            then normalize-space( xs:string(@ref) ) 
            else if ( exists(@nodeset) )
            then  normalize-space( xs:string(@nodeset) )
            else ()"/>
        
        <!-- resolve @nodeset to the current instance context -->
        <xsl:variable name="ref" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists($this-ref)">
                    <xsl:sequence select="xforms:resolveXPathStrings($nodeset,$this-ref)"/>
                </xsl:when>
                <xsl:when test="$nodeset != ''">
                    <xsl:sequence select="$nodeset"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="concat('instance(''',$default-instance-id,''')')"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="instance-context" as="xs:string">
            <xsl:apply-templates select="." mode="get-context-instance-id">
                <xsl:with-param name="nodeset" select="$ref"/>
            </xsl:apply-templates>
        </xsl:variable>
        
        <!-- set @nodeset to the current instance context -->
        <xsl:variable name="expanded-nodeset" as="xs:string">
            <xsl:choose>
                <xsl:when test="$ref != ''">
                    <xsl:sequence select="$ref"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="concat( 'instance(''', $instance-context ,''')' )"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:attribute name="model-context" select="$model-key"/>
            <xsl:attribute name="instance-context" select="$instance-context"/>
            <xsl:attribute name="nodeset" select="$expanded-nodeset"/>
        </xsl:copy>
        
        <!-- create a denested xforms:bind for a nested bind element -->
        <xsl:apply-templates select="xforms:bind" mode="add-context">
            <xsl:with-param name="nodeset" select="$expanded-nodeset" tunnel="yes"/>
            <xsl:with-param name="default-instance-id" select="$instance-context" tunnel="yes"/>
        </xsl:apply-templates>
    </xsl:template>
    
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#evt-recalculate">xforms-recalculate event</a></xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="xforms-recalculate">
        <xsl:message use-when="$debugMode">[xforms-recalculate] START</xsl:message>
        
        <xsl:variable name="bindings" as="element(xforms:bind)*" select="js:getBindings()"/>

        <xsl:variable name="instance-keys" select="js:getInstanceKeys()" as="item()*"/>
        <xsl:for-each select="$instance-keys">
            <xsl:variable name="instance-id" as="xs:string" select="."/>
<!--            <xsl:variable name="instanceXML" select="xforms:instance(.)"/>-->
            <xsl:variable name="instance-calculation-bindings" as="element(xforms:bind)*" select="$bindings[@instance-context = $instance-id][exists(@calculate)]"/>
            <xsl:if test="exists($instance-calculation-bindings)">
                <xsl:variable name="updatedInstanceXML" as="element()">
                    <xsl:call-template name="xforms-recalculate-binding">
                        <xsl:with-param name="instance-id" as="xs:string" select="." tunnel="yes"/>
                        <!--                    <xsl:with-param name="instanceXML" as="element()" select="$instanceXML"/>-->
                        <xsl:with-param name="calculation-bindings" as="element(xforms:bind)*" select="$instance-calculation-bindings" tunnel="yes"/>
                        <xsl:with-param name="counter" as="xs:integer" select="1"/>
                    </xsl:call-template>
                </xsl:variable>
                
                <xsl:sequence select="js:setInstance($instance-id,$updatedInstanceXML)"/>
            </xsl:if>
            
            
        </xsl:for-each>
    
        <xsl:message use-when="$debugMode">[xforms-recalculate] END</xsl:message>
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Update instance with one calculated binding, and move on to the next</xd:p>
        </xd:desc>
        <xd:param name="instance-id">ID of instance in XForm to be updated.</xd:param>
        <xd:param name="calculation-bindings">xforms:bind elements with @calculate that are relevant to this instance</xd:param>
        <xd:param name="counter">Integer identifying the binding to process in this iteration</xd:param>
        <xd:param name="match-counter">Integer identifying the node in the list matched by the binding to process in this iteration</xd:param>
    </xd:doc>
    <xsl:template name="xforms-recalculate-binding">
        <xsl:param name="instance-id" as="xs:string" required="yes" tunnel="yes"/>
        <xsl:param name="calculation-bindings" as="element(xforms:bind)*" tunnel="yes"/>
        <xsl:param name="counter" as="xs:integer" required="yes"/>
        <xsl:param name="match-counter" as="xs:integer" required="no" select="1"/>
        
        <xsl:message use-when="$debugMode">[xforms-recalculate-binding] START</xsl:message>
        
        <xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-id)"/>
        
        <xsl:variable name="this-binding" as="element(xforms:bind)?" select="$calculation-bindings[$counter]"/>
        
        <xsl:variable name="calculated-nodes" as="node()*">
            <xsl:evaluate xpath="xforms:impose($this-binding/@nodeset)" context-item="$instanceXML" namespace-context="$instanceXML"/> 
        </xsl:variable>
        <!--
                    In XForms Test Suite
                    <bind ref="prev" calculate="../index - 1" readonly=". &lt; 1"/>
                -->
        <xsl:variable name="evaluation-context" as="node()" select="$calculated-nodes[$match-counter]"/>
        
        <xsl:message use-when="$debugMode">[xforms-recalculate-binding] bound node: <xsl:sequence select="if ($evaluation-context[self::*]) then fn:serialize($evaluation-context) else if ($evaluation-context[self::attribute()]) then '@'||name($evaluation-context) else 'UNKNOWN'"/></xsl:message>
        <!-- 
                    Wrap @xpath expression in string()
                    in case calculation returns a node(set)
                -->
        <xsl:variable name="value" as="xs:string?">
            <xsl:evaluate xpath="xforms:impose('string(' || $this-binding/@calculate || ')')" context-item="$evaluation-context" namespace-context="$instanceXML"/> 
        </xsl:variable>
        <xsl:message use-when="$debugMode">[xforms-recalculate-binding] New value for <xsl:value-of select="$this-binding/@nodeset"/> (match #<xsl:value-of select="$match-counter"/>) (<xsl:value-of select="$this-binding/@calculate"/>) is <xsl:sequence select="$value"/></xsl:message>
        <xsl:variable name="updatedInstanceXML" as="element()">
            <xsl:apply-templates select="$instanceXML" mode="recalculate">
                <xsl:with-param name="updated-nodes" select="$evaluation-context" tunnel="yes"/>
                <xsl:with-param name="updated-value" select="$value" tunnel="yes"/>
            </xsl:apply-templates>
        </xsl:variable>
        <!-- 
                    move on to next calculation 
                    BUT don't just pass $updatedInstanceXML
                    Need to set it and get it
                    so that the updated node has a match
                -->
        <xsl:choose>
            <xsl:when test="$match-counter &lt; count($calculated-nodes)">
                <!-- move to next match for this binding -->
                <xsl:sequence select="js:setInstance($instance-id,$updatedInstanceXML)"/>
                <xsl:call-template name="xforms-recalculate-binding">
                    <xsl:with-param name="counter" select="$counter"/>
                    <xsl:with-param name="match-counter" select="$match-counter + 1"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:when test="$counter &lt; count($calculation-bindings)">
                <!-- move to next binding -->
                <xsl:sequence select="js:setInstance($instance-id,$updatedInstanceXML)"/>
                <xsl:call-template name="xforms-recalculate-binding">
                    <xsl:with-param name="counter" select="$counter + 1"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="$updatedInstanceXML"/>
            </xsl:otherwise>
        </xsl:choose>
        
        <xsl:message use-when="$debugMode">[xforms-recalculate-binding] END</xsl:message>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#evt-revalidate">xforms-revalidate event</a></xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="xforms-revalidate">
        
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#evt-refresh">xforms-refresh event</a></xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="xforms-refresh">
        <xsl:call-template name="refreshOutputs-JS"/>
        <xsl:call-template name="refreshRepeats-JS"/>
        <xsl:call-template name="refreshElementsUsingIndexFunction-JS"/>
        <xsl:call-template name="refreshRelevantFields-JS"/>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#evt-valueChanged">xforms-value-changed event</a></xd:p>
        </xd:desc>
        <xd:param name="when-value-changed">Action maps to apply (@ev:event = 'xforms-value-changed')</xd:param>
    </xd:doc>
    <xsl:template name="xforms-value-changed">
        <xsl:param name="when-value-changed" as="map(*)*" required="no" tunnel="yes"/>
        
        <xsl:for-each select="$when-value-changed">
            <xsl:variable name="action-map" select="."/>
            
            <xsl:call-template name="applyActions">
                <xsl:with-param name="action-map" select="$action-map" tunnel="yes"/>
            </xsl:call-template>
        </xsl:for-each> 
       
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#evt-focus">xforms-focus event</a></xd:p>
        </xd:desc>
        <xd:param name="control">Identifier of a form control to give focus to.</xd:param>
    </xd:doc>
    <xsl:template name="xforms-focus">
        <xsl:param name="control" as="xs:string"/>
        
        <xsl:variable name="xforms-control" as="element()" select="js:getXFormsDoc()//*[@id = $control]"/>
        
        <!-- if control is a repeated item, get the index of the repeat -->
         
        <xsl:choose>
            <xsl:when test="$xforms-control/ancestor::xforms:repeat">
                <xsl:variable name="context-indexes" as="xs:double*">
                    <xsl:for-each select="$xforms-control/ancestor::xforms:repeat">
                        <xsl:sort select="position()" data-type="number" order="descending"/>
                        <xsl:sequence select="js:getRepeatIndex( xs:string(@id) )"/>
                    </xsl:for-each>
                </xsl:variable>
                
                <xsl:variable name="control-index" as="xs:string" select="string-join($context-indexes,'.')"/>
<!--                <xsl:message use-when="$debugMode">[xforms-focus] Control '<xsl:sequence select="$control"/>' has index '<xsl:sequence select="$control-index"/>'</xsl:message>-->
                <xsl:sequence select="js:setFocus( concat($control, '-', $control-index ) )"/>    
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="js:setFocus( $control )"/>    
            </xsl:otherwise>
        </xsl:choose>
        
         
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <a href="https://www.w3.org/TR/xforms11/#submit-evt-submit">xforms-submit event</a></xd:p>
        </xd:desc>
        <xd:param name="submission">Identifier of a registered submission.</xd:param>
    </xd:doc>
    <xsl:template name="xforms-submit">
        <xsl:param name="submission" as="xs:string"/>
        
        <xsl:variable name="submission-map" select="js:getSubmission($submission)" as="map(*)"/>
        <xsl:variable name="actions" select="js:getAction($submission)" as="map(*)*"/>
        
        <xsl:variable name="submit-message" as="xs:string" select="
            concat('[xforms-submit] Submitting ', map:get($submission-map,'@id') )"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$submit-message"/> START</xsl:message>
        
        <xsl:variable name="refi" as="xs:string?" select="map:get($submission-map,'@ref')"/>
        <xsl:variable name="instance-id-submit" as="xs:string" select="xforms:getInstanceId($refi)"/>
        <xsl:variable name="instance-id-update" as="xs:string" select="map:get($submission-map,'@instance')"/>
        <xsl:variable name="instanceXML-submit" as="element()?" select="xforms:instance($instance-id-submit)"/>
        
        <!-- 
                    MD 2020-04-05: I think this is "the rebuild operation is performed without dispatching an event to invoke the operation."
                    
                    https://www.w3.org/TR/xforms11/#submit-evt-submit
                -->
        <xsl:variable name="required-fields-check" as="item()*" select="if (exists($instanceXML-submit)) then xforms:check-required-fields($instanceXML-submit) else ()"/>
        <xsl:variable name="constrained-fields-check" as="item()*" select="if (exists($instanceXML-submit)) then xforms:check-constraints-on-fields($instanceXML-submit) else ()"/>
        
        <!--                <xsl:message use-when="$debugMode">[xforms-submit] Submitting instance XML: <xsl:value-of select="serialize($instanceXML-submit)"/></xsl:message>                -->
        
        <xsl:choose>
            <xsl:when test="empty($required-fields-check) and empty($constrained-fields-check)">
                
                <xsl:variable name="requestBody" as="node()?" select="xforms:evaluate-xpath-with-context-node($refi,$instanceXML-submit,())"/>
                
                <!--                        <xsl:message use-when="$debugMode">[xforms-submit] Request body: <xsl:sequence select="fn:serialize($requestBody)"/></xsl:message>-->
                
                <xsl:variable name="requestBodyDoc" as="document-node()?">
                    <xsl:if test="$requestBody[self::element()]">
                        <xsl:document>
                            <xsl:sequence select="$requestBody"/>
                        </xsl:document>
                    </xsl:if>
                </xsl:variable>
                
                <xsl:variable name="method" as="xs:string" select="map:get($submission-map,'@method')"/>
                
                <xsl:variable name="serialization" as="xs:string?" select="map:get($submission-map,'@serialization')"/>
                
                <xsl:variable name="query-parameters" as="xs:string?">
                    <xsl:if test="exists($serialization) and $serialization = 'application/x-www-form-urlencoded'">
                        <!--                        <xsl:message use-when="$debugMode">[xforms-submit] Deriving form data from $requestBodyXML: <xsl:value-of select="serialize($requestBody)"/></xsl:message>-->
                        <xsl:variable name="parts" as="xs:string*">
                            <xsl:choose>
                                <xsl:when test="exists($requestBodyDoc)">
                                    <xsl:for-each select="$requestBody/*">
                                        <xsl:variable name="query-part" as="xs:string" select="concat(local-name(),'=',string())"/>
                                        <xsl:sequence select="$query-part"/>
                                        <!--                                                <xsl:message use-when="$debugMode">[xforms-submit] Query part: <xsl:value-of select="$query-part"/></xsl:message>-->
                                    </xsl:for-each>
                                </xsl:when>
                                <xsl:otherwise/>
                            </xsl:choose>
                            
                        </xsl:variable>
                        <xsl:if test="exists($parts)">
                            <xsl:sequence select="
                                string-join($parts,'&amp;') 
                                "/>
                        </xsl:if>
                        
                    </xsl:if>
                </xsl:variable>
                
                <xsl:variable name="href-base" as="xs:string?" select="map:get($submission-map,'@resource')"/>
                
                <xsl:variable name="href" as="xs:string?">
                    <xsl:choose>
                        <xsl:when test="not(exists($href-base))">
                            <xsl:variable name="error-message" select="'ERROR: no URL specified for submission'"/>
                            <xsl:sequence select="ixsl:call(ixsl:window(), 'alert', [serialize($error-message)])"/>
                        </xsl:when>
                        
                        <xsl:when test="exists($query-parameters)">
                            <xsl:message use-when="$debugMode">[xforms-submit] adding parameters '<xsl:sequence select="$query-parameters"/>' to href</xsl:message>
                            <xsl:sequence select="concat($href-base,'?',$query-parameters)"/>
                        </xsl:when>
                        <xsl:when test="$requestBody[self::text()]">
                            <xsl:message use-when="$debugMode">[xforms-submit] adding path '/<xsl:sequence select="$requestBody"/>' to href</xsl:message>
                            <xsl:sequence select="concat($href-base,'/',$requestBody)"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:sequence select="$href-base"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <xsl:message use-when="$debugMode">[xforms-submit] submitting href '<xsl:sequence select="$href"/>'</xsl:message>
                <xsl:variable name="mediatype" as="xs:string" select="map:get($submission-map,'@mediatype')"/>      
                
                <!-- http://www.saxonica.com/saxon-js/documentation/index.html#!development/http -->
                <xsl:variable name="HTTPrequest" as="map(*)">
                    <xsl:map>
                        <xsl:if test="not( upper-case($method) = 'GET')">
                            <xsl:choose>
                                <xsl:when test="exists($requestBodyDoc)">
                                    <xsl:message use-when="$debugMode">[xforms-submit] body of HTTPrequest = <xsl:sequence select="fn:serialize($requestBodyDoc)"/></xsl:message>
                                    <xsl:map-entry key="'body'" select="$requestBodyDoc"/>       
                                </xsl:when>
                                <xsl:otherwise>
                                    <xsl:map-entry key="'body'" select="$requestBody"/>
                                </xsl:otherwise>
                            </xsl:choose>
                            <xsl:map-entry key="'media-type'" select="$mediatype"/>
                            <!--                            <xsl:map-entry key="'body'" select="$requestBodyDoc"/>  -->
                        </xsl:if>
                        <xsl:map-entry key="'method'" select="$method"/>
                        <xsl:map-entry key="'href'" select="$href"/>
                        
                    </xsl:map>
                </xsl:variable>
                
                
                <ixsl:schedule-action http-request="$HTTPrequest">
                    <!-- The value of @http-request is an XPath expression, which evaluates to an 'HTTP request
                            map' - i.e. our representation of an HTTP request as an XDM map -->
                    <xsl:call-template name="HTTPsubmit">
                        <xsl:with-param name="instance-id" select="$instance-id-update" as="xs:string"/>
                        <xsl:with-param name="targetref" select="map:get($submission-map,'@targetref')"/>
                        <xsl:with-param name="replace" select="map:get($submission-map,'@replace')"/>
                        <xsl:with-param name="when-done" select="$actions[map:get(.,'@event') = 'xforms-submit-done']" tunnel="yes"/>
                    </xsl:call-template>
                </ixsl:schedule-action>
                
                
            </xsl:when>
            
            <xsl:otherwise>
                <xsl:variable name="error-message">
                    <xsl:for-each select="$constrained-fields-check">
                        <xsl:variable name="curNode" select="."/>
                        <xsl:value-of select="concat('Invalid field value: ', $curNode/@data-ref, '&#10;')"/>
                    </xsl:for-each>
                    <xsl:for-each select="$required-fields-check">
                        <xsl:variable name="curNode" select="."/>
                        <xsl:value-of select="concat('Required field is empty: ', $curNode/@data-ref, '&#10;')"/>
                    </xsl:for-each>
                </xsl:variable>
                <xsl:sequence select="ixsl:call(ixsl:window(), 'alert', [serialize($error-message)])"/>
            </xsl:otherwise>
        </xsl:choose>
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$submit-message"/> END</xsl:message>
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <xd:a href="https://www.w3.org/TR/xforms11/#submit-evt-submit-done">xforms-submit-done event</xd:a></xd:p>
        </xd:desc>
        <xd:param name="when-done">Action maps to apply (@ev:event = 'xforms-submit-done')</xd:param>
    </xd:doc>
    <xsl:template name="xforms-submit-done">
        <xsl:param name="when-done" as="map(*)*" required="no" tunnel="yes"/>
        <xsl:message use-when="$debugMode">[xforms-submit-done] START</xsl:message>
        
        <xsl:for-each select="$when-done">
            <xsl:variable name="action-map" select="."/>
            
            <xsl:call-template name="applyActions">
                <xsl:with-param name="action-map" select="$action-map" tunnel="yes"/>
            </xsl:call-template>
        </xsl:for-each> 

        <xsl:message use-when="$debugMode">[xforms-submit-done] END</xsl:message>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <xd:a href="https://www.w3.org/TR/xforms11/#evt-select">xforms-select</xd:a> event (notification only).</xd:p>
        </xd:desc>
        <xd:param name="case-id">ID of case that is now selected.</xd:param>
    </xd:doc>
    <xsl:template name="xforms-select">
        <xsl:param name="case-id" as="xs:string"/>
        <xsl:message use-when="$debugMode">[xforms-select] case ID: <xsl:sequence select="$case-id"/></xsl:message>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <xd:a href="https://www.w3.org/TR/xforms11/#evt-select">xforms-deselect</xd:a> event (notification only).</xd:p>
        </xd:desc>
        <xd:param name="case-id">ID of case that is now selected.</xd:param>
    </xd:doc>
    <xsl:template name="xforms-deselect">
        <xsl:param name="case-id" as="xs:string"/>
        <xsl:message use-when="$debugMode">[xforms-deselect] case ID: <xsl:sequence select="$case-id"/></xsl:message>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <xd:a href="https://www.w3.org/TR/xforms11/#action-deferred-update-behavior">deferred update behaviour</xd:a></xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="outermost-action-handler">
        <xsl:variable name="deferred-update-flags" as="map(*)?" select="js:getDeferredUpdateFlags()"/>
        
        <xsl:message use-when="$debugMode">[outermost-action-handler] START</xsl:message>
        <xsl:message use-when="$debugMode">[outermost-action-handler] Recalculate: <xsl:sequence select="map:get($deferred-update-flags,'recalculate') "/></xsl:message>
        <xsl:message use-when="$debugMode">[outermost-action-handler] Revalidate: <xsl:sequence select="map:get($deferred-update-flags,'revalidate') "/></xsl:message>
        <xsl:message use-when="$debugMode">[outermost-action-handler] Refresh: <xsl:sequence select="map:get($deferred-update-flags,'refresh') "/></xsl:message>
        
        <!-- not convinced there's anything to do in the xforms-rebuild event -->
        <!--<xsl:if test="map:get($deferred-update-flags,'rebuild') = 'true'">
            <xsl:call-template name="xforms-rebuild"/>
        </xsl:if>-->
        <xsl:if test="map:get($deferred-update-flags,'recalculate') = 'true'">
            <xsl:message use-when="$debugMode">[outermost-action-handler] triggering xforms-recalculate</xsl:message>
            <xsl:call-template name="xforms-recalculate"/>
        </xsl:if>
        <xsl:if test="map:get($deferred-update-flags,'revalidate') = 'true'">
            <xsl:message use-when="$debugMode">[outermost-action-handler] triggering xforms-revalidate</xsl:message>
            <xsl:call-template name="xforms-revalidate"/>
        </xsl:if>
        <xsl:if test="map:get($deferred-update-flags,'refresh') = 'true'">
            <xsl:message use-when="$debugMode">[outermost-action-handler] triggering xforms-refresh</xsl:message>
            <xsl:call-template name="xforms-refresh"/>
        </xsl:if>
       
        
        <xsl:sequence select="js:clearDeferredUpdateFlags()"/>
        
        <xsl:message use-when="$debugMode">[outermost-action-handler] END</xsl:message>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of <xd:a href="https://www.w3.org/TR/xforms11/#evt-bindingException">xforms-binding-exception</xd:a></xd:p>
        </xd:desc>
        <xd:param name="message">String to output as the error message.</xd:param>
    </xd:doc>
    <xsl:template name="xforms-binding-exception">
        <xsl:param name="message" as="xs:string" required="yes"/>
        <xsl:sequence select="ixsl:call(ixsl:window(), 'alert', [concat('[xforms-binding-exception] ', $message)] )"/>
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of a xforms-ready event</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="xforms-ready">
        <xsl:message use-when="$debugMode">[xforms-ready] START</xsl:message>
        
        <xsl:variable name="actions" select="js:getEventAction('xforms-ready')" as="map(*)*"/>
                
        <xsl:message use-when="$debugMode">[xforms-ready] Number of actions: <xsl:sequence select="count($actions)"/></xsl:message>
        
        <xsl:for-each select="$actions">
            <xsl:variable name="action-map" select="."/>
            <xsl:call-template name="applyActions">
                <xsl:with-param name="action-map" select="$action-map" tunnel="yes"/>
            </xsl:call-template>
        </xsl:for-each>                
        
        <xsl:message use-when="$debugMode">[xforms-ready] END</xsl:message>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Implementation of a DOMActivate event</xd:p>
        </xd:desc>
        <xd:param name="form-control">HTML form control with a @data-action attribute referencing registered actions.</xd:param>
    </xd:doc>
    <xsl:template name="DOMActivate">
        <xsl:param name="form-control" as="node()"/>
        <xsl:message use-when="$debugMode">[DOMActivate] START</xsl:message>
        
        <xsl:variable name="actions" select="js:getAction(string($form-control/@data-action))" as="map(*)*"/>
        
        <xsl:variable name="refi" as="xs:string" select="if (exists($form-control/@data-ref)) then xs:string($form-control/@data-ref) else ''"/>
        
        <xsl:variable name="instance-id" as="xs:string" select="xforms:getInstanceId($refi)"/>
                
        <!-- MD 2020-02-22 -->
        <xsl:variable name="instanceXML" as="element()?" select="xforms:instance($instance-id)"/>
        <xsl:variable name="instanceDoc" as="document-node()">
            <xsl:document>
                <xsl:sequence select="$instanceXML"/>
            </xsl:document>
        </xsl:variable>
        
        <xsl:variable name="updatedInstanceXML" as="element()?">
            <xsl:choose>
                <xsl:when test="exists($refi)">
                    <xsl:variable name="updatedNode" as="node()" select="xforms:evaluate-xpath-with-context-node($refi,$instanceXML,())"/>
                    <xsl:variable name="new-value" as="xs:string">
                        <xsl:apply-templates select="$form-control" mode="get-field"/>
                    </xsl:variable>
                    
                    <xsl:choose>
                        <xsl:when test="$instanceDoc//node()[. is $updatedNode]">
                            <xsl:apply-templates select="$instanceDoc" mode="recalculate">
                                <xsl:with-param name="updated-nodes" select="$updatedNode" tunnel="yes"/>
                                <xsl:with-param name="updated-value" select="$new-value" tunnel="yes"/>
                            </xsl:apply-templates>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:apply-templates select="$instanceXML" mode="recalculate">
                                <xsl:with-param name="updated-nodes" select="$updatedNode" tunnel="yes"/>
                                <xsl:with-param name="updated-value" select="$new-value" tunnel="yes"/>
                            </xsl:apply-templates>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="$instanceXML"/>
                </xsl:otherwise>
            </xsl:choose>
            
        </xsl:variable>
        
        
        <xsl:for-each select="$actions">
            <xsl:variable name="action-map" select="."/>
                      
            <!-- https://www.w3.org/TR/xslt-30/#func-map-contains -->
            <xsl:if test="map:contains($action-map,'@event')">
                <xsl:if test="map:get($action-map,'@event') = 'DOMActivate'">
                    <xsl:call-template name="applyActions">
                        <xsl:with-param name="action-map" select="$action-map" tunnel="yes"/>
                    </xsl:call-template>
                </xsl:if>
            </xsl:if>
        </xsl:for-each>                
        
        <xsl:message use-when="$debugMode">[DOMActivate] END</xsl:message>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying setvalue action. See <a href="https://www.w3.org/TR/xforms11/#action-setvalue">10.2 The setvalue Element</a></xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-setvalue">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <xsl:variable name="log-label" as="xs:string" select="'[action-setvalue]'"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        
        <xsl:variable name="instance-context" select="map:get($action-map, 'instance-context')" as="xs:string"/>
        
        <xsl:call-template name="action-setvalue-inner">
            <xsl:with-param name="instance-id" select="$instance-context" tunnel="yes"/>
        </xsl:call-template>
        
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Set value for a node in an instance</xd:p>
            <xd:p>We might be iterating over a node set. Need to update one node at a time (value may not be the same for all nodes in the set), so need to calculate the node set each time from the updated instance.</xd:p>
        </xd:desc>
        <xd:param name="instance-id">ID of instance in XForm to be updated.</xd:param>
        <xd:param name="node-counter">Integer identifying the node to update in this iteration</xd:param>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-setvalue-inner">
        <xsl:param name="instance-id" as="xs:string" required="yes" tunnel="yes"/>
        <xsl:param name="node-counter" as="xs:integer" required="no" select="1"/>
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-id)"/>
        <xsl:variable name="refz" select="map:get($action-map,'@ref')"/>
        <xsl:variable name="iterate-ref" select="map:get($action-map,'@iterate')"/>
        
        
        <xsl:variable name="updated-nodeset" as="node()*">
            <xsl:choose>
                <xsl:when test="exists($iterate-ref)">
                    <xsl:message use-when="$debugMode">[action-setvalue-inner] Applying action @iterate '<xsl:sequence select="$iterate-ref"/>'; @ref-local = <xsl:sequence select="map:get($action-map,'@ref-local')"/></xsl:message>
                    
                    <xsl:variable name="ref-local" as="xs:string?" select="map:get($action-map,'@ref-local')"/>
                    
                    <xsl:choose>
                        <xsl:when test="exists($ref-local)">
                            <!-- evaluate @ref relative to @iterate context -->
                            <xsl:variable name="ref" as="xs:string" select="xforms:resolveXPathStrings($iterate-ref,$ref-local)"/>
                            <xsl:evaluate xpath="xforms:impose($ref)" context-item="$instanceXML" namespace-context="$instanceXML"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:evaluate xpath="xforms:impose($iterate-ref)" context-item="$instanceXML" namespace-context="$instanceXML"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:when>
                <xsl:when test="exists($refz)">
                    <xsl:message use-when="$debugMode">[action-setvalue-inner] Applying action @ref '<xsl:sequence select="$refz"/>'</xsl:message>
                    <xsl:evaluate xpath="xforms:impose($refz)" context-item="$instanceXML" namespace-context="$instanceXML"/>
                </xsl:when>
            </xsl:choose>
            
        </xsl:variable>
        
        <!-- the node set over which we are iterating -->
        <xsl:variable name="iterate-nodeset" as="node()*">
            <xsl:choose>
                <xsl:when test="exists($iterate-ref)">
                    <xsl:evaluate xpath="xforms:impose($iterate-ref)" context-item="$instanceXML" namespace-context="$instanceXML"/>
                </xsl:when>
            </xsl:choose>
        </xsl:variable>
 
        
        <xsl:choose>
            <xsl:when test="exists($updated-nodeset)">
                <xsl:message use-when="$debugMode">[action-setvalue-inner]  Updating <xsl:value-of select="count($updated-nodeset)"/> matched nodes</xsl:message>
                
                <xsl:variable name="updated-node" as="node()?" select="$updated-nodeset[$node-counter]"/>
                <xsl:variable name="iterate-node" as="node()?" select="$iterate-nodeset[$node-counter]"/>
                
                <xsl:variable name="ifVar" as="xs:string?" select="xforms:getIfStatement($action-map)"/>      
                
                <xsl:variable name="ifExecuted" as="xs:boolean">
                    <xsl:choose>
                        <xsl:when test="exists($iterate-nodeset) and exists($ifVar)">
                            <xsl:message use-when="$debugMode">[action-setvalue-inner] applying @if = <xsl:sequence select="$ifVar"/> in context <xsl:sequence select="fn:serialize($iterate-node)"/></xsl:message>
                            <xsl:sequence select="xforms:evaluate-xpath-with-context-node($ifVar,$iterate-node,())"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:sequence select="true()" />
                        </xsl:otherwise>
                    </xsl:choose>                    
                </xsl:variable>
                
                <xsl:choose>
                    <xsl:when test="exists($updated-node)">
                        <xsl:message use-when="$debugMode">[action-setvalue-inner] Updating node <xsl:value-of select="$node-counter"/> of <xsl:value-of select="count($updated-nodeset)"/></xsl:message>
                        
                        <xsl:if test="$ifExecuted">
                            <xsl:variable name="updated-value" as="xs:string">
                                <xsl:choose>
                                    <xsl:when test="map:contains($action-map,'@value')">
                                        <!--                        <xsl:message use-when="$debugMode">[action-setvalue] evaluating @value '<xsl:sequence select="map:get($action-map,'@value')"/>'</xsl:message>-->
                                        
                                        <xsl:variable name="updated-item" as="item()">
                                            <xsl:evaluate xpath="xforms:impose(map:get($action-map,'@value'))" context-item="$updated-node" namespace-context="$instanceXML" />
                                        </xsl:variable>
                                        <!--                        <xsl:message use-when="$debugMode">[action-setvalue] updated item '<xsl:sequence select="serialize($updated-item)"/>'</xsl:message>-->
                                        <xsl:choose>
                                            <!-- 
                                Handle case where @value evaluates to a boolean.
                                Logic mirrors that in template for HTML input (mode="get-field")
                                
                                TO DO: handle other possible data types of @value?
                            -->
                                            <xsl:when test="xs:string($updated-item) = 'true'">
                                                <xsl:sequence select="'true'"/>
                                            </xsl:when>
                                            <!-- handle boolean false() value-->
                                            <xsl:when test="xs:string($updated-item) = 'false' and not($updated-item)">
                                                <xsl:sequence select="''"/>
                                            </xsl:when>
                                            <xsl:otherwise>
                                                <xsl:sequence select="xs:string($updated-item)"/>
                                            </xsl:otherwise>
                                        </xsl:choose>
                                    </xsl:when>
                                    <xsl:when test="map:contains(.,'value')">
                                        <xsl:sequence select="map:get($action-map,'value')"/>
                                    </xsl:when>
                                    <xsl:otherwise>
                                        <xsl:sequence select="''"/> 
                                    </xsl:otherwise>
                                </xsl:choose>                
                            </xsl:variable>
                            
                            <xsl:message use-when="$debugMode">[action-setvalue-inner] updated value (in iterate) '<xsl:sequence select="serialize($updated-value)"/>'</xsl:message>
                            
                            <xsl:variable name="updatedInstanceXML" as="element()">
                                <xsl:apply-templates select="$instanceXML" mode="recalculate">
                                    <xsl:with-param name="updated-nodes" select="$updated-node" tunnel="yes"/>
                                    <xsl:with-param name="updated-value" select="$updated-value" tunnel="yes"/>
                                </xsl:apply-templates>
                            </xsl:variable>
                            
                            <!--<xsl:message use-when="$debugMode">[action-setvalue-inner] updated instance <xsl:sequence select="serialize($updatedInstanceXML)"/></xsl:message>-->
                            <xsl:sequence select="js:setInstance($instance-id,$updatedInstanceXML)"/>
                            
                        </xsl:if>
                        
                        
                        <xsl:choose>
                            <xsl:when test="$node-counter &lt; count($updated-nodeset)">
                                <!-- move to next match for this binding -->
                                <xsl:call-template name="action-setvalue-inner">
                                    <xsl:with-param name="node-counter" select="$node-counter + 1"/>
                                </xsl:call-template>
                            </xsl:when>
                            <xsl:otherwise>
                                <xsl:sequence select="js:setDeferredUpdateFlags(('recalculate','revalidate','refresh'))" />
                            </xsl:otherwise>
                        </xsl:choose>
                        
                        
                    </xsl:when>
                </xsl:choose>
                
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="error-message" as="xs:string" select="'[setvalue] unable to find node at XPath ' || $refz"/>
                <xsl:message>
                    <xsl:sequence select="'ERROR: ' || $error-message"/>
                </xsl:message>
                <xsl:call-template name="logToPage">
                    <xsl:with-param name="level" select="'error'"/>
                    <xsl:with-param name="message" select="$error-message"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Update instance from value of form control</xd:p>
        </xd:desc>
        <xd:param name="form-control">HTML form control containing new value for updating an instance etc.</xd:param>
    </xd:doc>
    <xsl:template name="action-setvalue-form-control">
        <xsl:param name="form-control" as="node()"/>
        
        <xsl:variable name="refi" select="$form-control/@data-ref"/>
        <xsl:variable name="refElement" select="$form-control/@data-element"/>
        
        <xsl:variable name="instance-id" as="xs:string" select="xforms:getInstanceId($refi)"/>
        <xsl:variable name="actions" select="js:getAction(string($form-control/@data-action))"/>
        
        <!--        <xsl:sequence select="sfp:logInfo(concat('[xforms-value-changed] Evaluating data ref: ', $refi))"/>-->
        
        <!-- MD 2020-02-22 -->
        <xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-id)"/>
        <xsl:variable name="instanceDoc" as="document-node()">
            <xsl:document>
                <xsl:sequence select="$instanceXML"/>
            </xsl:document>
        </xsl:variable>
        <xsl:variable name="updatedNode" as="node()" select="xforms:evaluate-xpath-with-context-node($refi,$instanceXML,())"/>
        <xsl:variable name="new-value" as="xs:string">
            <xsl:apply-templates select="$form-control" mode="get-field"/>
        </xsl:variable>
        <xsl:variable name="updatedInstanceXML" as="element()">
            <xsl:choose>
                <xsl:when test="$instanceDoc//node()[. is $updatedNode]">
                    <xsl:apply-templates select="$instanceDoc" mode="recalculate">
                        <xsl:with-param name="updated-nodes" select="$updatedNode" tunnel="yes"/>
                        <xsl:with-param name="updated-value" select="$new-value" tunnel="yes"/>
                    </xsl:apply-templates>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:apply-templates select="$instanceXML" mode="recalculate">
                        <xsl:with-param name="updated-nodes" select="$updatedNode" tunnel="yes"/>
                        <xsl:with-param name="updated-value" select="$new-value" tunnel="yes"/>
                    </xsl:apply-templates>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
<!--        <xsl:message use-when="$debugMode">[xforms-value-changed] Updated XML: <xsl:sequence select="serialize($updatedInstanceXML)"/></xsl:message>-->
        
        <xsl:sequence select="js:setInstance($instance-id,$updatedInstanceXML)"/>

        <xsl:sequence select="js:setDeferredUpdateFlags(('recalculate','revalidate','refresh'))" />    

        <!-- 
            MD 2020-04-13 
            this event should be dispatched during xforms-refresh 
            but need to flag this somehow
            https://www.w3.org/TR/xforms11/#evt-valueChanged
        -->
        <xsl:call-template name="xforms-value-changed">
            <xsl:with-param name="when-value-changed" select="$actions[map:get(.,'@event') = 'xforms-value-changed']" tunnel="yes"/>
        </xsl:call-template>
              
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying insert action</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-insert">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <xsl:variable name="log-label" as="xs:string" select="'[action-insert]'"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        
        <xsl:variable name="instance-context" select="map:get($action-map, 'instance-context')" as="xs:string"/>
        <xsl:variable name="handler-status" select="map:get($action-map, 'handler-status')" as="xs:string"/>
        <xsl:variable name="ref" select="map:get($action-map,'@ref')" />
        <xsl:variable name="at" select="map:get($action-map, '@at')" as="xs:string?"/>
        <xsl:variable name="position" select="(map:get($action-map, '@position'),'after')[1]" as="xs:string?"/>
        <xsl:variable name="origin-ref" select="map:get($action-map, '@origin')" as="xs:string?"/>
        <xsl:variable name="context" select="map:get($action-map, '@context')" as="xs:string?"/>
        
        
        <xsl:variable name="ref-qualified" as="xs:string?" select="
            if (exists($ref) and $ref != '')
            then (
            if (exists($at))
            then concat($ref, '[', $at, ']')
            else $ref
            )
            else ()
            "/>
        
        <xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-context)"/>
               
                 
        <!--<xsl:message use-when="$debugMode">[action-insert] $ref = '<xsl:value-of select="$ref"/>'; inserting node at XPath <xsl:value-of select="$ref-qualified"/></xsl:message>-->
               
        
        <xsl:variable name="instance-id-origin" as="xs:string?" select="if(exists($origin-ref)) then xforms:getInstanceId($origin-ref) else ()"/>
        <xsl:variable name="instanceXML-origin" as="element()?" select="if(exists($instance-id-origin)) then xforms:instance($instance-id-origin) else ()"/>
        <xsl:variable name="instanceDoc" as="document-node()">
            <xsl:document>
                <xsl:sequence select="$instanceXML"/>
            </xsl:document>
        </xsl:variable>
        <xsl:variable name="instanceDoc-origin" as="document-node()">
            <xsl:choose>
                <xsl:when test="exists($instanceXML-origin)">
                    <xsl:document>
                        <xsl:sequence select="$instanceXML-origin"/>
                    </xsl:document>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="$instanceDoc"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="binding-nodeset" as="node()*" select="xforms:evaluate-xpath-with-context-node($ref-qualified,$instanceXML,())"/>
        
        <xsl:variable name="origin-nodeset" as="node()*">
            <xsl:choose>
                <xsl:when test="exists($origin-ref)">
                    <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $origin-ref = <xsl:sequence select="$origin-ref"/></xsl:message>-->
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node($origin-ref,$instanceXML-origin,())"/>
                </xsl:when>
                <xsl:otherwise>
                    <!-- fall back to using "Node Set Binding node-set" context -->
                    <xsl:sequence select="$binding-nodeset[last()]"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        
        <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $origin-nodeset = <xsl:sequence select="serialize($origin-nodeset)"/></xsl:message>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> $binding-nodeset = <xsl:sequence select="serialize($binding-nodeset)"/></xsl:message>-->
        
        <xsl:variable name="insert-node-location" as="node()?" select="$binding-nodeset[last()]"/> 
        
        <xsl:variable name="context-nodeset" as="node()*" select="if (exists($context)) then xforms:evaluate-xpath-with-context-node($context,$instanceXML,()) else ()"/>
        
        <xsl:variable name="context-node" as="node()?" select="$context-nodeset[1]"/>
        
        
        <xsl:variable name="nodes-to-insert" as="node()*">
            <xsl:choose>
                <xsl:when test="exists($origin-nodeset)">
                    <xsl:copy-of select="$origin-nodeset"/>
                </xsl:when>
                <!-- empty node set if origin returns empty node set -->
                <xsl:when test="exists($origin-ref)"/>
                <xsl:otherwise>
                    <xsl:copy-of select="$insert-node-location"/>
                </xsl:otherwise>
            </xsl:choose>
            
        </xsl:variable>
        
<!--        <xsl:message use-when="$debugMode">[action-insert] $insert-node-location = <xsl:value-of select="fn:serialize($insert-node-location)"/></xsl:message>-->
<!--        <xsl:message use-when="$debugMode">[action-insert] $origin-nodeset = <xsl:value-of select="fn:serialize($origin-nodeset)"/></xsl:message>-->
        
        <xsl:if test="exists($nodes-to-insert)">
            <xsl:variable name="instance-with-insert" as="element()">
                <xsl:choose>
                    <xsl:when test="$instanceDoc//node()[. intersect ($insert-node-location,$context-node)]">
                        <!--                    <xsl:message use-when="$debugMode">[action-insert] found insert location in $insertDoc</xsl:message>-->
                        <xsl:apply-templates select="$instanceDoc" mode="insert-node">
                            <xsl:with-param name="insert-node-location" select="if (exists($insert-node-location)) then $insert-node-location else $context-node" tunnel="yes"/>
                            <xsl:with-param name="nodes-to-insert" select="$nodes-to-insert" tunnel="yes"/>
                            <xsl:with-param name="position-relative" select="if (exists($insert-node-location)) then $position else 'child'" tunnel="yes"/>
                        </xsl:apply-templates>
                    </xsl:when>
                    <xsl:when test="$instanceXML//node()[. intersect ($insert-node-location,$context-node)]">
                        <!--                    <xsl:message use-when="$debugMode">[action-insert] looking for insert location in $insertXML2 (position <xsl:sequence select="$position"/>)</xsl:message>-->
                        <xsl:apply-templates select="$instanceXML" mode="insert-node">
                            <xsl:with-param name="insert-node-location" select="if (exists($insert-node-location)) then $insert-node-location else $context-node" tunnel="yes"/>
                            <xsl:with-param name="nodes-to-insert" select="$nodes-to-insert" tunnel="yes"/>
                            <xsl:with-param name="position-relative" select="if (exists($insert-node-location)) then $position else 'child'" tunnel="yes"/>
                        </xsl:apply-templates>
                    </xsl:when>
                    <xsl:otherwise>
                        <!-- the instance node is being replaced -->
                        <xsl:sequence select="$origin-nodeset"/>
                    </xsl:otherwise>
                </xsl:choose>
                
            </xsl:variable>
            
            <!--                <xsl:message use-when="$debugMode">[action-insert] Updated instance: <xsl:sequence select="fn:serialize($instance-with-insert)"/></xsl:message>-->
            
            <xsl:sequence select="js:setInstance($instance-context,$instance-with-insert)"/>
            
            
            <!-- update repeat index to that of inserted node -->
            <xsl:if test="matches($at,'index\s*\(')">
                <xsl:variable name="repeat-id" as="xs:string?" select="xforms:getRepeatID($at)"/>
                <xsl:variable name="at-position" as="xs:integer">
                    <xsl:evaluate xpath="xforms:impose($at)"/>
                </xsl:variable>
                <!--<xsl:message use-when="$debugMode">[action-insert] $repeat-id = <xsl:value-of select="$repeat-id"/></xsl:message>
            <xsl:message use-when="$debugMode">[action-insert] $at-position evaluated as <xsl:value-of select="$at-position"/></xsl:message>-->
                
                <xsl:if test="exists($repeat-id)">
                    <xsl:choose>
                        <xsl:when test="$position = 'before'">
                            <xsl:sequence select="js:setRepeatIndex($repeat-id, $at-position)"/>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:sequence select="js:setRepeatIndex($repeat-id, $at-position + 1)"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:if>
                
            </xsl:if>
            
            <xsl:if test="$handler-status = 'inner'">
                <xsl:sequence select="js:setDeferredUpdateFlags(('rebuild','recalculate','revalidate','refresh'))"/>
            </xsl:if>
            
        </xsl:if>
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
        
    </xsl:template>
    
 
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying delete action</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-delete">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <xsl:variable name="instance-context" select="map:get($action-map, 'instance-context')" as="xs:string"/>
        <xsl:variable name="handler-status" select="map:get($action-map, 'handler-status')" as="xs:string"/>
        <xsl:variable name="ref" select="map:get($action-map,'@ref')"/>
        <xsl:variable name="at" select="map:get($action-map, '@at')" as="xs:string?"/>
        
        <xsl:variable name="ref-qualified" as="xs:string?" select="
            if (exists($ref))
            then (
            if (exists($at))
            then concat($ref, '[', $at, ']')
            else $ref
            )
            else ()
            "/>
        
        <xsl:variable name="instanceXML" as="element()" select="xforms:instance($instance-context)"/>
        <xsl:variable name="instanceDoc" as="document-node()">
            <xsl:document>
                <xsl:sequence select="$instanceXML"/>
            </xsl:document>
        </xsl:variable>
        <xsl:variable name="delete-node" as="node()*" select="xforms:evaluate-xpath-with-context-node($ref-qualified,$instanceXML,())"/>
                
            <xsl:variable name="instance-with-delete" as="element()">
                <xsl:choose>
                    <xsl:when test="$instanceDoc//node()[. is $delete-node]">
                        <xsl:apply-templates select="$instanceDoc" mode="delete-node">
                            <xsl:with-param name="delete-node" select="$delete-node" tunnel="yes"/>
                        </xsl:apply-templates>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:apply-templates select="$instanceXML" mode="delete-node">
                            <xsl:with-param name="delete-node" select="$delete-node" tunnel="yes"/>
                        </xsl:apply-templates>
                    </xsl:otherwise>
                </xsl:choose>
                
            </xsl:variable> 
            
<!--            <xsl:message use-when="$debugMode">[action-delete] Updated instance: <xsl:sequence select="fn:serialize($instance-with-delete)"/></xsl:message>-->
            
            <xsl:sequence select="js:setInstance($instance-context,$instance-with-delete)"/>    
            
            <!-- set index -->
            <xsl:if test="matches($at,'index\s*\(')">
                <xsl:variable name="repeat-id" as="xs:string?" select="xforms:getRepeatID($at)"/>
                <xsl:variable name="at-position" as="xs:integer">
                    <xsl:evaluate xpath="xforms:impose($at)"/>
                </xsl:variable>
                
                <xsl:if test="exists($repeat-id)">
                    <xsl:variable name="repeat-size" as="xs:double" select="js:getRepeatSize($repeat-id)"/>
                    
<!--                    <xsl:message use-when="$debugMode">[action-delete] Size of repeat '<xsl:value-of select="$repeat-id"/>' is <xsl:value-of select="$repeat-size"/>, index is <xsl:value-of select="$at-position"/></xsl:message>-->
                    
                    <!--
                        Let XForm take care of out of bounds indexes
                        
                        <xsl:choose>
                        <xsl:when test="$at-position = $repeat-size">
                            <!-\- adjust index if it is now out of bounds -\->
                            <xsl:sequence select="js:setRepeatIndex($repeat-id, $repeat-size - 1)"/>
                        </xsl:when>
                        <xsl:otherwise/>
                    </xsl:choose>-->
                </xsl:if>
                
            </xsl:if>
            
            <xsl:if test="$handler-status = 'inner'">
                <xsl:sequence select="js:setDeferredUpdateFlags(('rebuild','recalculate','revalidate','refresh'))"/>
            </xsl:if>
        
    </xsl:template>
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying message action</xd:p>
            <xd:p>XForms 1.1 spec <xd:a href="https://www.w3.org/TR/xforms11/#action-message">message element</xd:a></xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-message">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <xsl:variable name="nested-actions-array" select="map:get($action-map, 'nested-actions')" as="array(map(*))?"/>
        <xsl:variable name="nested-actions" as="item()*">
            <xsl:sequence select="array:flatten($nested-actions-array)"/>
        </xsl:variable>
        
        <xsl:variable name="message-components" as="xs:string*">
            <!--<xsl:variable name="message-value" as="xs:string" select="map:get($action-map,'value')">
            -->
            <xsl:for-each select="$nested-actions">
                <xsl:call-template name="applyActions">
                    <xsl:with-param name="action-map" select="." tunnel="yes"/>
                </xsl:call-template>
            </xsl:for-each>
        </xsl:variable>
        
        <xsl:variable name="message-value" as="xs:string" select="string-join($message-components)"/>
        
        <!-- XForms 1.1 spec: The default is "modal" if the attribute is not specified -->
        <xsl:variable name="message-level" as="xs:string" select="(map:get($action-map,'@level'), 'modal')[1]"/>
        
<!--        <xsl:message use-when="$debugMode">[action-message] Message (level '<xsl:value-of select="$message-level"/>') reads "<xsl:value-of select="$message-value"/>"</xsl:message>-->
        
        <!-- TO DO: implement remainder of this action -->
        <xsl:choose>
            <xsl:when test="$message-level = 'ephemeral'">
                <xsl:call-template name="logToPage">
                    <xsl:with-param name="message" select="$message-value"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:when test="$message-level = 'modal'"/>
            <xsl:when test="$message-level = 'modeless'"/>
            <xsl:otherwise/>
        </xsl:choose>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying output action (i.e. return a string value)</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
        <xd:param name="context-node">Context node identified in applyActions template</xd:param>
    </xd:doc>
    <xsl:template name="action-output">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        <xsl:param name="context-node" as="node()?"/>
        
        <xsl:variable name="log-label" as="xs:string" select="'[action-output]'"/>
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> START</xsl:message>
        
        <xsl:variable name="instance-id" as="xs:string" select="map:get($action-map,'instance-context')"/>
        
        <!--<xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> context instance ID = <xsl:sequence select="$instance-id"/></xsl:message>-->
        
        <xsl:variable name="ref" as="xs:string?">
            <xsl:choose>
                <xsl:when test="map:get($action-map,'@value')">
                    <xsl:sequence select="map:get($action-map,'@value')"/>
                </xsl:when>
                <xsl:when test="map:get($action-map,'@ref')">
                    <xsl:sequence select="map:get($action-map,'@ref')"/>
                </xsl:when>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="value" as="item()?">
            <xsl:choose>
                <xsl:when test="exists($ref) and exists($context-node)">
                    <!--<xsl:message use-when="$debugMode">[action-output] evaluating <xsl:sequence select="$ref"/> against context node <xsl:sequence select="fn:serialize($context-node)"/></xsl:message>-->
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node($ref,$context-node,())"/>
                </xsl:when>
                <xsl:when test="exists($ref)">
                    <!--<xsl:message use-when="$debugMode">[action-output] evaluating <xsl:sequence select="$ref"/> against context instance</xsl:message>-->
                    <xsl:sequence select="xforms:evaluate-xpath-with-instance-id($ref,$instance-id,())"/>
                </xsl:when>
                <xsl:otherwise/>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:sequence select="string($value)"/>
        
        <xsl:message use-when="$debugMode"><xsl:sequence select="$log-label"/> END</xsl:message>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying 'text' action (i.e. return a string value)</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-text">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        <xsl:sequence select="map:get($action-map,'@value')"/>        
    </xsl:template>
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying setfocus action</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-setfocus">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>

        <!-- first apply deferred update behaviour -->
        <xsl:call-template name="outermost-action-handler"/>
        
        <xsl:variable name="control" as="xs:string" select="map:get($action-map,'@control')"/>
        
        <xsl:call-template name="xforms-focus">
            <xsl:with-param name="control" select="$control"/>
        </xsl:call-template>
        
    </xsl:template>
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying send action</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-send">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
                
<!--        <xsl:message use-when="$debugMode">[action-send] $action-map = <xsl:value-of select="serialize($action-map)"/></xsl:message>-->
        
        <xsl:variable name="submission" as="xs:string" select="map:get($action-map,'@submission')"/>
        
        <xsl:call-template name="xforms-submit">
            <xsl:with-param name="submission" select="$submission"/>
        </xsl:call-template>
         
    </xsl:template>
    

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying setindex action</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-setindex">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <!-- first apply deferred update behaviour -->
        <xsl:call-template name="outermost-action-handler"/>

        <xsl:variable name="repeatID" as="xs:string" select="map:get($action-map,'@repeat')"/>
        <xsl:variable name="new-index-ref" as="xs:string" select="map:get($action-map,'@index')"/>
        
                
        <xsl:variable name="new-index" as="xs:integer">
            <xsl:evaluate xpath="xforms:impose($new-index-ref)"/>
        </xsl:variable>
        
<!--        <xsl:message use-when="$debugMode">[action-setindex] $action-map = <xsl:value-of select="serialize($action-map)"/></xsl:message>-->
        
        <xsl:sequence select="js:setRepeatIndex($repeatID,$new-index)"/>
        
    </xsl:template>
    
    
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying recalculate action</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="action-recalculate">
        <xsl:message use-when="$debugMode">[action-recalculate] START</xsl:message>
        
        <xsl:call-template name="xforms-recalculate"/>
        <xsl:sequence select="js:clearDeferredUpdateFlag('recalculate')"/>
        
        <xsl:message use-when="$debugMode">[action-recalculate] END</xsl:message>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying refresh action</xd:p>
        </xd:desc>
    </xd:doc>
    <xsl:template name="action-refresh">
        <xsl:message use-when="$debugMode">[action-refresh] START</xsl:message>
        
        <xsl:call-template name="xforms-refresh"/>
        <xsl:sequence select="js:clearDeferredUpdateFlag('refresh')"/>
        
        <xsl:message use-when="$debugMode">[action-refresh] END</xsl:message>
    </xsl:template>

    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying reset action</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
    </xd:doc>
    <xsl:template name="action-reset">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>
        
        <xsl:message use-when="$debugMode">[action-reset] Reset triggered!</xsl:message>
        <!-- TO DO: implement remainder of this action -->
        <xsl:sequence select="js:clearDeferredUpdateFlags()"/>
    </xsl:template>
    
    <xd:doc scope="component">
        <xd:desc>
            <xd:p>Template for applying toggle action</xd:p>
        </xd:desc>
        <xd:param name="action-map">Action map</xd:param>
        <xd:param name="context-node">Context node identified in applyActions template</xd:param>
    </xd:doc>
    <xsl:template name="action-toggle">
        <xsl:param name="action-map" required="yes" as="map(*)" tunnel="yes"/>        <xsl:param name="context-node" as="node()?"/>
        
        <xsl:message use-when="$debugMode">[action-toggle] START</xsl:message>
        
        <!-- first apply deferred update behaviour -->
        <xsl:call-template name="outermost-action-handler"/>
        
        <xsl:variable name="instance-id" as="xs:string" select="map:get($action-map,'instance-context')"/>
        
        <xsl:variable name="case-id-fixed" as="xs:string?" select="map:get($action-map,'@case')"/>
        <xsl:variable name="case-id-evaluated" as="xs:string?" select="map:get($action-map,'case')"/>
        
        <!-- "The case to be selected by the toggle action is given by the case attribute or the case element. If both are given, the element takes precedence." -->
        <xsl:variable name="case-id" as="xs:string">
            <xsl:choose>
                <xsl:when test="exists($case-id-evaluated) and exists($context-node)">
                    <xsl:sequence select="xforms:evaluate-xpath-with-context-node($case-id-evaluated,$context-node,())"/>
                </xsl:when>
                <xsl:when test="exists($case-id-fixed)">
                    <xsl:sequence select="$case-id-fixed"/>
                </xsl:when>
                <xsl:otherwise/>
            </xsl:choose>
        </xsl:variable>
        
        <xsl:variable name="switch-id" as="xs:string" select="js:getCaseSwitch($case-id)"/>
        <xsl:variable name="current-switch-selection" as="xs:string" select="js:getSwitchSelection($switch-id)"/>
        
        <xsl:call-template name="xforms-deselect">
            <xsl:with-param name="case-id" as="xs:string" select="$current-switch-selection"/>
        </xsl:call-template>
        
        <xsl:sequence select="js:deselectCase($current-switch-selection)"/>
        <xsl:sequence select="js:selectCase($case-id)"/>
        <xsl:sequence select="js:setSwitchSelection($switch-id,$case-id)"/>
        
        <xsl:variable name="case-off" as="element()" select="ixsl:page()//*[@id eq $current-switch-selection]"/>
        <ixsl:set-style name="display" select="'none'" object="$case-off"/>
        
        <xsl:variable name="case-on" as="element()" select="ixsl:page()//*[@id eq $case-id]"/>
        <xsl:if test="ixsl:style($case-on)?display = 'none'">
            <ixsl:remove-property name="style.display" object="$case-on"/>
            <ixsl:remove-attribute name="style" object="$case-on"/>
        </xsl:if>
        
        <xsl:call-template name="xforms-select">
            <xsl:with-param name="case-id" as="xs:string" select="$case-id"/>
        </xsl:call-template>
        <xsl:message use-when="$debugMode">[action-toggle] END</xsl:message>
    </xsl:template>
</xsl:stylesheet>
