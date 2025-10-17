sudo npx xslt3-he \
-t -xsl:/Users/mark/GitHub/Saxon-Forms/src/saxon-xforms.xsl \
-export:/Users/mark/GitHub/Saxon-Forms/sef/saxon-xforms.sef.json \
-nogo \
-ns:##html5
cp /Users/mark/GitHub/Saxon-Forms/sef/saxon-xforms.sef.json /Users/mark/GitHub/exist-db-recipes/recipes/resources/sef/.