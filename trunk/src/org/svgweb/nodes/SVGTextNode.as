/*
 Copyright (c) 2009 by contributors:

 * James Hight (http://labs.zavoo.com/)
 * Richard R. Masters
 * Google Inc. (Brad Neuberg -- http://codinginparadise.org)

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

package org.svgweb.nodes
{
    import org.svgweb.SVGViewerWeb;
    import org.svgweb.core.SVGNode;
    import org.svgweb.utils.SVGColors;
    import org.svgweb.utils.SVGUnits;
    
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.text.TextField;
    import flash.text.TextFieldAutoSize;
    import flash.text.TextFormat;
    import flash.text.TextLineMetrics;
    
    import flash.filters.GlowFilter;
    
    /** SVG Text element node **/
    public class SVGTextNode extends SVGNode
    {    
        /**
         * Hold text path node if text follows a path
         **/
        private var _textPath:SVGNode = null;
        
        /**
         * TextFields to render nodes text
         **/
        private var _textFields:Array = null;
        private var _svgFont:SVGFontNode;
        
        private var _text:String = '';

        protected var newGlyphs:Array = null;
        protected var newViewBoxSprite:Sprite = new Sprite();
        protected var lastGlyph:SVGNode;
        
        public function SVGTextNode(svgRoot:SVGSVGNode, xml:XML, original:SVGNode = null):void {
            super(svgRoot, xml, original);
        }    

        protected override function onAddedToStage(event:Event):void {
            super.onAddedToStage(event);
            svgRoot.registerFontListener(this);
        }

        protected override function onRemovedFromStage(event:Event):void {
            svgRoot.unregisterFontListener(this);
            super.onRemovedFromStage(event);
        }

        override public function onRegisterFont(fontFamily:String):void {
            if (fontFamily == this.getStyleOrAttr('font-family')) {
                invalidateDisplay();
            }
        }
       
         /**
         * Need to recreate child glyphs when redrawing text
         **/
        override public function invalidateDisplay():void {
            super.invalidateDisplay();
            // Need to recreate child glyphs when redrawing text
            this._parsedChildren = false;
        }

        override public function hasText():Boolean {
            return true;
        }
        
        override public function setText(newValue:String):void {
            //this.dbg('setText, newValue='+newValue);
            this._xml.setChildren(newValue);
            this._text = newValue;
        }
        
        protected function removeOldTextFields():void {
            var i:int = 0;
            var child:Object;
            while (i < this.drawSprite.numChildren) {
                child = this.drawSprite.getChildAt(i);
                if (child is TextField) this.drawSprite.removeChildAt(i);
                else i++;
            }
        }

        protected function removeOldSVGFontGlyphs():void {
            var i:int = 0;
            while (i < this.svgChildren.length) {
                if (this.svgChildren[i] is SVGGlyphNode)
                    removeSVGChild(this.svgChildren[i]);
                else i++
            }
        }

        protected function addTextFieldChunk(chunk:String,
                                             startPos:Object,
                                             currentPos:Object,
                                             fontFamily:String,
                                             fontSizeNum:Number,
                                             textAnchor:String,
                                             fontWeight:String,
                                             fill:String):void {
            var textField:TextField = new TextField();
            textField.text = chunk;
            textField.autoSize = TextFieldAutoSize.LEFT;
            var textFormat:TextFormat = new TextFormat();

            if (fontWeight != null && fontWeight != 'normal') {
                textFormat.bold = true;
            }

            if (fontFamily != null) {
                fontFamily = fontFamily.replace("'", '');
                textFormat.font = fontFamily;
            }
            // choose a (nominal) size
            var nomSize:Number = 100.0;
            textFormat.size = nomSize;
            var fontScale:Number = fontSizeNum / nomSize;  // used to scale the TextField to produce the correct size

            if (fill != null) {
                textFormat.color = SVGColors.getColor(fill);
            }
            textField.setTextFormat(textFormat);
            var textLineMetrics:TextLineMetrics = textField.getLineMetrics(0);

            // apply text anchor
            var advance:Number = 0.0;  // add to current text position
            var x:Number;
            var y:Number;
            switch (textAnchor) {
                case 'middle':
                    x = - textField.width/2.0;
                    advance = textLineMetrics.width * fontScale / 2.0;
                    break;
                case 'end':
                    x = 2.0 - textField.width;
                    // advance = 0.0
                    break;
                default: //'start'
                    x = -2.0;  //gutter
                    advance = textLineMetrics.width * fontScale;
                    break;
            }
            y = -textLineMetrics.ascent - 2.0;

            // reposition the TextField to account for scaling and offset from startPos
            textField.y = fontScale * y + (currentPos.y - startPos.y);
            textField.x = fontScale * x + (currentPos.x - startPos.x);

            // scale the TextField to the required size
            textField.scaleX = fontScale;
            textField.scaleY = fontScale;

            // add textField to _textFields
            _textFields.push(textField);
            // update current text position
            currentPos.x += advance;
        }

        protected function addSVGFontChunk(chunk:String,
                                           startPos:Object,
                                           currentPos:Object,
                                           fontSizeNum:Number,
                                           textAnchor:String,
                                           fill:String):void {
            var i:uint;
            var chunkWidth:Number = 0.0;
            var glyphChar:String;
            var glyph:SVGGlyphNode;
            // calculate the width of the chunk
            for (i = 0; i < chunk.length; i++) {
                glyphChar = chunk.charAt(i);
                glyph = this._svgFont.getGlyph(glyphChar);
                chunkWidth += SVGUnits.cleanNumber(glyph.getAttribute('horiz-adv-x'));
            }

            var startOffsetX:Number = 0.0;
            var advance:Number = 0.0;
            // apply text anchor
            switch (textAnchor) {
                case 'middle':
                    startOffsetX = - chunkWidth / 2.0;
                    advance = chunkWidth / 2.0;
                    break;
                case 'end':
                    startOffsetX = -chunkWidth;
                    // advance = 0.0;
                    break;
                default: //'start'
                    // startOffsetX = 0.0
                    advance = chunkWidth;
                    break;
            }
            //Add a glyph for each character in the text chunk
            var glyphX:Number = startOffsetX + (currentPos.x - startPos.x) * (2048/fontSizeNum);
            var glyphY:Number = (currentPos.y - startPos.y) * (-2048/fontSizeNum);
            for (i = 0; i < chunk.length; i++) {
                glyphChar = chunk.charAt(i);
                glyph = this._svgFont.getGlyph(glyphChar);
                var glyphClone:SVGNode = glyph.clone();
                if (fill !=null) {
                    glyphClone.setAttribute('fill', fill);
                }
                glyphClone.setAttribute('transform',
                          'scale(' + (fontSizeNum / 2048) + ') scale(1,-1)');

                glyphClone.setAttribute('x', String(glyphX));
                glyphClone.setAttribute('y', String(glyphY));

                glyphX += SVGUnits.cleanNumber(glyph.getAttribute('horiz-adv-x'));

                glyphClone.topSprite.visible=false;
                newGlyphs.push(glyphClone);
                addSVGChild(glyphClone);
                lastGlyph=glyphClone;
            }
            // update current text position
            currentPos.x += chunkWidth * (fontSizeNum / 2048);
        }

        /**
         * Get any child text (not text inside child nodes)
         * If this node has any text create a TextField at this._textField
         * Call SVGNode.parse()
         **/
        override protected function parseChildren():void {
            var i:uint;

            super.parseChildren();
            
            //Check for SVGFont
            var fontFamily:String = this.getStyleOrAttr('font-family');
            this._svgFont = this.svgRoot.getFont(fontFamily);
            if (this._svgFont != null) {
                removeOldTextFields();
                newGlyphs = new Array();
                }
            else {
                removeOldSVGFontGlyphs();
                _textFields = new Array();
            }

            var fontSize:String = this.getStyleOrAttr('font-size');
            var fontSizeNum:Number = 12.0;  // default
            if (fontSize != null) {
                fontSizeNum = SVGUnits.cleanNumber(fontSize);
                //Font size can be in user units, pixels (px), or points (pt); if no
                //measurement type given defaults to user units
                if (SVGUnits.getType(fontSize) == SVGUnits.PT) {
                    fontSizeNum = SVGUnits.pointsToPixels(fontSizeNum);
                }
            }

            var fill:String = this.getStyleOrAttr('fill');
            if (fill == 'currentColor') {
                fill = this.getStyleOrAttr('color');
            }
            var fontWeight:String = this.getStyleOrAttr('font-weight');

                var textAnchor:String = this.getStyleOrAttr('text-anchor');
                var currentNode:SVGNode = this;
                while (textAnchor == 'inherit') {
                    if (currentNode.svgParent != null) {
                        currentNode = currentNode.svgParent;
                        textAnchor = currentNode.getStyleOrAttr('text-anchor');
                    }
                    else {
                        textAnchor = null;
                    }
                }

            // process text chunks
            var glyphXOffsets:Array = new Array();
            var xString:String = super.getAttribute('x', '0');
            xString = xString.replace(/,/sg," "); //Replace commas with spaces
            glyphXOffsets = xString.split(/\s+/);

            var glyphYOffsets:Array = new Array();
            var yString:String = super.getAttribute('y', '0');
            yString = yString.replace(/,/sg," "); //Replace commas with spaces
            glyphYOffsets = yString.split(/\s+/);

            var startGlyphX:Number = glyphXOffsets[0];
            var startGlyphY:Number = glyphYOffsets[0];
            // startPos is the x,y position assigned to drawSprite at setAttributes()
            // all positioning of TextFields or glyphClones is set relative to startPos
            var startPos:Object = {x:startGlyphX, y:startGlyphY};
            var currentPos:Object = {x:startGlyphX, y:startGlyphY};  // Current Text Position

            var numChunks:int = Math.max(glyphXOffsets.length, glyphYOffsets.length);
            numChunks = Math.min(numChunks, this._text.length);
            var chunk:String = "";
            for (i=0; i < numChunks; i++) {
                if (i < glyphXOffsets.length) {
                    currentPos.x = Number(glyphXOffsets[i]);
                    }
                if (i < glyphYOffsets.length) {
                    currentPos.y = Number(glyphYOffsets[i]);
                    }
                if (i == numChunks-1) { // lastchunk
                    chunk = this._text.slice(i);
                    }
                else { // single glyph
                    chunk = this._text.charAt(i);
                }
                if (this._svgFont != null) addSVGFontChunk(chunk, startPos, currentPos, fontSizeNum, textAnchor, fill);
                else addTextFieldChunk(chunk, startPos, currentPos, fontFamily, fontSizeNum, textAnchor, fontWeight, fill);
            }
                }
        
        public function onDrawGlyph(glyph:SVGNode):void {
            // when they are ready, unhide the new characters,
            // and remove the old
            if (glyph == lastGlyph && newGlyphs != null) {
                for (var i:uint=0; i < this.svgChildren.length; i++) {
                    if (this.svgChildren[i] is SVGGlyphNode
                        && newGlyphs.indexOf(this.svgChildren[i]) == -1) {
                        removeSVGChild(this.svgChildren[i]);
                        i--;
                    }
                    else {
                        this.svgChildren[i].topSprite.visible=true;
                    }
                }
                newGlyphs = null;
            }
        }

        override public function getAttribute(name:String, defaultValue:* = null,
                                              inherit:Boolean = true,
                                              applyAnimations:Boolean = true,
                                              useStyle:Boolean = false):* {
            if (name == 'stroke-width' && this._svgFont != null) {
                // Relevant to SVG Fonts only
                var fontSize:String = this.getStyleOrAttr('font-size');
                var fontSizeNum:Number = SVGUnits.cleanNumber(fontSize);
                var strokeWidthStr:String = super.getAttribute(name, defaultValue, inherit, true, true);
                var strokeWidth:Number = SVGUnits.cleanNumber(strokeWidthStr);
                strokeWidth = strokeWidth * (1024 / fontSizeNum);
                return String(strokeWidth);  
            } else if ( (name == "x" || name == "y") ) {
                var xString:String = super.getAttribute(name, defaultValue, inherit, applyAnimations, false);
                if (xString != null) {
                    xString = xString.replace(/,/sg," "); //Replace commas with spaces
                    if (xString.split(/\s+/).length >= 2) {
                            return xString.split(/\s+/)[0];
                        }
                    else {
                        return xString;
                    }
                }
                else {
                    return xString;
                }
            }
            else {
                return super.getAttribute(name, defaultValue, inherit, applyAnimations, useStyle);
            }
        }
        
        override protected function setVisibility(visible:String, 
                                                  recursive:Boolean = false):void {
            // Surprisingly, this.alpha does not work as expected on
            // text system fonts; a work around is needed. See
            // http://oddhammer.com/tutorials/alpha_dynamic_text/
            // for details. Basically you have to embed the text into
            // a filter which turns it into a bitmap, and then apply the
            // alpha!
            if (visible == 'hidden') {
                var filter:GlowFilter = new GlowFilter(0x000000, .1, 16, 16, 
                                                       0, 3, false, false);
                this.drawSprite.filters = new Array(filter);
                this.drawSprite.alpha = 0;
            }
            else {
                this.drawSprite.filters = new Array();
                super.setVisibility(visible);
            }
        }
        
        override protected function draw():void {
            super.draw();
            removeOldTextFields();
            // add the new textFields
            if (_textFields != null) {
                for (var i:uint=0; i<this._textFields.length; i++) {
                    drawSprite.addChild(this._textFields[i]);
                }
            }
            _textFields = null;
        }
    }
}
