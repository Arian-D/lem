'use strict';

const rpc = require('vscode-jsonrpc');
const cp = require('child_process');
const utf8 = require('utf-8')
//const ipcRenderer = require('electron').ipcRenderer;
const {ipcRenderer, screen} = require('electron');
const getCurrentWindow = require('electron').remote.getCurrentWindow;
const keyevent = require('./keyevent');
const { option } = require('./option');

class FontAttribute {
    constructor(name, size) {
        const font = `${size}px ${name}`;
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d', { alpha: false });
        ctx.font = font;
        const width = ctx.measureText('W').width;
        this.update(font, name, size, width, size);
    }
    update(font, name, pixel, width, height) {
        this.font = font;
        this.name = name;
        this.pixel = pixel;
        this.width = width;
        this.height = height + 2;
    }
}

let fontAttribute = new FontAttribute(option.fontName, option.fontSize);

const kindAbort = 0;
const kindKeyEvent = 1;
const kindResize = 2;
const kindCommand = 3;
const kindMethod = 4;

const viewTable = {};


let width_tweak = 0;
let height_tweak = 0;
switch (process.platform) {
  case 'win32':
    width_tweak = 2;
    height_tweak = 3;
    break;
  case 'darwin':
    width_tweak = 1;
    height_tweak = 1;
    break;
  case 'linux':
    width_tweak = 1;
    height_tweak = 1;
    break;
  default:
    width_tweak = 0;
    height_tweak = 0;
}

function calcDisplayCols(width) {
    return Math.floor(width / fontAttribute.width) - width_tweak;
}

function calcDisplayRows(height) {
    return Math.floor(height / fontAttribute.height) - height_tweak;
}

function getCurrentWindowSize() {
    return getCurrentWindow().getSize();
}

function getCurrentWindowWidth() {
    return getCurrentWindowSize()[0];
}

function getCurrentWindowHeight() {
    return getCurrentWindowSize()[1];
}

class LemEditorPane extends HTMLElement {
    constructor() {
        super();
    }
}

class LemSidePane extends HTMLElement {
    constructor() {
        super();
        this.elements = [];
    }

    append(element) {
        const div = document.createElement('div');
        div.style.overflow = 'hidden';
        div.appendChild(element);
        this.appendChild(div);
        this.elements.push(div);
        this.elements.forEach((e, i) => {
            e.style.height = `${100 / this.elements.length}%`;
        });
    }

    deleteAll() {
        this.elements.forEach((e) => this.removeChild(e));
    }
}

class LemEditor extends HTMLElement {
    constructor() {
        super();

        const childProcess = cp.spawn("lem-rpc");
        this.rpcConnection = rpc.createMessageConnection(
            new rpc.StreamMessageReader(childProcess.stdout),
            new rpc.StreamMessageWriter(childProcess.stdin)
        );

        this.on('update-foreground', this.updateForeground.bind(this));
        this.on('update-background', this.updateBackground.bind(this));
        this.on('make-view', this.makeView.bind(this));
        this.on('delete-view', this.deleteView.bind(this));
        this.on('resize-view', this.resizeView.bind(this));
        this.on('move-view', this.moveView.bind(this));
        this.on('clear', this.clear.bind(this));
        this.on('clear-eol', this.clearEol.bind(this));
        this.on('clear-eob', this.clearEob.bind(this));
        this.on('put', this.put.bind(this));
        this.on('modeline-put', this.modelinePut.bind(this));
        this.on('touch', this.touch.bind(this));
        this.on('move-cursor', this.moveCursor.bind(this));
        this.on('scroll', this.scroll.bind(this));
        this.on('update-display', this.updateDisplay.bind(this));
        this.on('js-eval', this.jsEval.bind(this));
        this.on('set-pane', this.setHtmlPane.bind(this));
        this.on('delete-pane', this.deletePane.bind(this));
        this.on('import', this.importModule.bind(this));
        this.on('set-font', this.setFont.bind(this));
        this.on('exit', this.exit.bind(this));

        this.rpcConnection.listen();

        this.lemEditorPane = document.createElement('lem-editor-pane');
        this.lemEditorPane.style.float = 'left';
        this.appendChild(this.lemEditorPane);

        this.lemSidePane = null;

        const [width, height] = getCurrentWindowSize();
        this.width = width;
        this.height = height;

        this.rpcConnection.sendRequest('ready', {
            "width": calcDisplayCols(this.width),
            "height": calcDisplayRows(this.height),
            "foreground": option.foreground,
            "background": option.background,
        });

        const mainWindow = getCurrentWindow();

        // will updated by setFont()
        this.fontWidth = fontAttribute.width;
        this.fontHeight = fontAttribute.height;

        // 'will-resize' event handling.
        // Linux: Not supported
        // MacOS: Does not work properly e.g. https://github.com/electron/electron/issues/21777
        if (process.platform === 'win') {
            mainWindow.on('will-resize', (_, newBounds) => {
                const { x, y, width, height } = mainWindow.getBounds();
                const nw = this.fontWidth * Math.round(newBounds.width / this.fontWidth);
                const nh = this.fontHeight * Math.round(newBounds.height / this.fontHeight);
                const nx = newBounds.x === x ? x : x - (nw - width);
                const ny = newBounds.y === y ? y : y - (nh - height);
                mainWindow.setBounds({x: nx, y: ny, width: nw, height: nh});
            });
        }

        let timeoutId = null;
        const resizeHandler = () => {
            const { width, height } = mainWindow.getBounds();
            this.resize(width, height);
        };
        mainWindow.on('resize', () => {
            if (timeoutId) {
                clearTimeout(timeoutId);
            }
            timeoutId = setTimeout(resizeHandler, 200);
        });

        ipcRenderer.on('command', (event, message) => {
            this.emitInput(kindCommand, message);
        })
        
        // create input text box;
        this.picker = new Picker(this);
    }

    on(method, handler) {
        this.rpcConnection.onNotification(method, handler);
    }

    setPane(e) {
        if (this.lemSidePane === null) {
            this.lemSidePane = document.createElement('lem-side-pane');
            this.appendChild(this.lemSidePane);
            this.resize(this.width, this.height);
        }
        this.lemSidePane.append(e);
    }

    setHtmlPane(params) {
        try {
            const div = document.createElement('div');
            div.innerHTML = utf8.getStringFromBytes(params.html);
            this.setPane(div);
        } catch (e) {
            console.log(e);
        }
    }

    deletePane() {
        this.removeChild(this.lemSidePane);
        this.lemSidePane = null;
        this.resize(...getCurrentWindowSize());
    }

    importModule(params) {
        try {
            require(params.name);
        } catch (e) { console.log(e); }
    }

    setFont(params) {
        try {
            fontAttribute = new FontAttribute(params.name, params.size);
            this.fontWidth = fontAttribute.width;
            this.fontHeight = fontAttribute.height;
        } catch (e) { console.log(e); }
    }

    exit(params) {
        try {
            ipcRenderer.send('exit');
        } catch (e) { console.log(e); }
    }

    sendNotification(method, params) {
        this.emitInput(kindMethod, {"method": method, "params": params});
    }

    emitInput(kind, value) {
        //console.log(kind, value);
        this.rpcConnection.sendNotification('input', {
            "kind": kind,
            "value": value
        });
    }

    resize(width, height) {
        if (this.lemSidePane !== null) {
            width /= 2;
        }
        this.width = width;
        this.height = height;
        this.emitInput(kindResize, {
            "width": calcDisplayCols(width),
            "height": calcDisplayRows(height)
        });
        this.lemEditorPane.style.width = width;
        this.lemEditorPane.style.height = height;
    }

    updateForeground(params) {
        option.foreground = params;
        this.picker.updateForeground(params);
    }

    updateBackground(params) {
        option.background = params;
        this.picker.updateBackground(params);
    }

    makeView(params) {
        try {
            const { id, x, y, width, height, use_modeline, kind } = params;
            const view = new View(id, x, y, width, height, use_modeline, kind);
            view.allTags().forEach((child) => { this.lemEditorPane.appendChild(child); });
            viewTable[id] = view;
        } catch (e) { console.log(e); }
    }

    deleteView(params) {
        try {
            const { id } = params.viewInfo;
            const view = viewTable[id];
            view.delete();
            delete viewTable[id];
        } catch (e) { console.log(e); }
    }

    resizeView(params) {
        try {
            const { viewInfo, width, height } = params;
            const view = viewTable[viewInfo.id];
            view.resize(width, height);
        } catch (e) { console.log(e); }
    }

    moveView(params) {
        try {
            const { x, y, viewInfo } = params;
            const view = viewTable[viewInfo.id];
            view.move(x, y);
        } catch (e) { console.log(e); }
    }

    clear(params) {
        try {
            const view = viewTable[params.viewInfo.id];
            view.clear();
        } catch (e) { console.log(e); }
    }

    clearEol(params) {
        try {
            const { viewInfo, x, y } = params;
            const view = viewTable[viewInfo.id];
            view.clearEol(x, y);
        } catch (e) { console.log(e); }
    }

    clearEob(params) {
        try {
            const { viewInfo, x, y } = params;
            const view = viewTable[viewInfo.id];
            view.clearEob(x, y);
        } catch (e) { console.log(e); }
    }

    put(params) {
        try {
            const { viewInfo, x, y, chars, attribute } = params;
            const view = viewTable[viewInfo.id];
            view.put(x, y, chars, attribute);
        } catch (e) { console.log(e); }
    }

    modelinePut(params) {
        try {
            const { viewInfo, x, y, chars, attribute } = params;
            const view = viewTable[viewInfo.id];
            view.modelinePut(x, chars, attribute);
        } catch (e) { console.log(e); }
    }

    touch(params) {
        try {
            const { viewInfo } = params;
            const view = viewTable[viewInfo.id];
            view.touch();
        } catch (e) { console.log(e); }
    }

    moveCursor(params) {
        try {
            const { viewInfo, x, y } = params;
            const view = viewTable[viewInfo.id];
            view.setCursor(x, y);
            const left = view.editSurface.canvas.offsetLeft + x * fontAttribute.width + 3;
            const top = view.editSurface.canvas.offsetTop + y * fontAttribute.height + 3;
            //console.log(view.editSurface.canvas.style);
            this.picker.movePicker(left, top);
        } catch (e) { console.log(e); }
    }

    scroll(params) {
        try {
            const { viewInfo, n } = params;
            const view = viewTable[viewInfo.id];
            view.scroll(n);
        } catch (e) { console.log(e); }
    }

    updateDisplay(params) {
        try {
        } catch (e) { console.log(e); }
    }

    jsEval(params) {
        try {
            eval(params.string);
        } catch (e) { console.log(e); }
    }
}

class Picker {
  constructor(editor) {
    this.__composition = false;

    this.editor = editor;

    this.measure = document.createElement('span');
    this.picker = document.createElement('input');
    this.picker.style.backgroundColor = 'transparent';
    this.picker.style.color = 'transparent';
    this.picker.style.width = '0';
    this.picker.style.padding = '0';
    this.picker.style.margin = '0';
    this.picker.style.border = 'none';
    this.picker.style.position = 'absolute';
    this.picker.style.zIndex = '-10';

 
    this.measure.style.color = option.foreground;
    this.measure.style.backgroundColor = option.background;
    this.measure.style.position = 'absolute';
    this.measure.style.zIndex = '';

    this.picker.style.top = '0';
    this.picker.style.left = '0';
    this.picker.style.font = fontAttribute.font;
    this.measure.style.top = '0';
    this.measure.style.left = '0';
    this.measure.style.font = fontAttribute.font;

    this.picker.addEventListener('blur', () => {this.picker.focus()});
    this.picker.addEventListener('keydown', (event) => {
      event.preventDefault();
      if (event.isComposing !== true && event.code !== '') {
        const k = keyevent.convertKeyEvent(event);
        this.editor.emitInput(kindKeyEvent, k);
        this.picker.value = '';
        return false;
      }
    });
    
    this.picker.addEventListener('input', (event) => {
      if (this.__composition === false) {
        this.picker.value = '';
        this.measure.innerHTML = this.picker.value;
        this.picker.style.width = '0';
      }
    });
    this.picker.addEventListener('compositionstart', (event) => {
      this.__composition = true;
      console.log(event);
      this.measure.innerHTML = this.picker.value;
      this.picker.style.width = this.measure.offsetWidth + 'px';
    });
    this.picker.addEventListener('compositionupdate', (event) => {
      this.measure.innerHTML = event.data;
      this.picker.style.width = this.measure.offsetWidth + 'px';
    });
    this.picker.addEventListener('compositionend', (event) => {
      this.__composition = false;
      console.log(this.picker.value); // TODO
      let chars = this.picker.value.split('').map((char) =>  utf8.setBytesFromString(char));
      this.editor.emitInput(kindCommand, ['input-string', chars]);
      this.picker.value = '';
      this.measure.innerHTML = this.picker.value;
      this.picker.style.width = '0';
    });
    document.body.appendChild(this.picker);
    document.body.appendChild(this.measure);
    this.picker.focus();
  }
  
  movePicker(left, top) {
    this.measure.style.top = top + 'px';
    this.measure.style.left = left + 'px';
    // picker follow measure
    this.picker.style.top = this.measure.offsetTop + 'px';
    this.picker.style.left = this.measure.offsetLeft + 'px';
  }

  updateForeground(color) {
    this.measure.style.color = color;
  }

  updateBackground(color) {
    this.measure.style.backgroundColor = color;
  }
}

class Surface {
    constructor(x, y, width, height, styles) {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        this.canvas = document.createElement('canvas');
        this.canvas.style.position = 'absolute';
        for (let key in styles) {
            this.canvas.style[key] = styles[key];
        }
        this.ctx = this.canvas.getContext('2d', { alpha: false });
        this.ctx.textBaseline = 'top';
        this.ctx.font = fontAttribute.font;
        this.canvas2 = document.createElement('canvas');
        this.ctx2 = this.canvas2.getContext('2d', { alpha: false });
        this.ctx2.textBaseline = 'top';
        this.ctx2.font = fontAttribute.font;
        this.dirtyRectangles = [];
    }

    move(x, y) {
        this.x = x;
        this.y = y;
        this.canvas.style.left = x * fontAttribute.width;
        this.canvas.style.top = y * fontAttribute.height;
    }

    resize(width, height) {
        this.width = width;
        this.height = height;
        this.canvas.width = width * fontAttribute.width;
        this.canvas.height = height * fontAttribute.height;
        this.canvas2.width = width * fontAttribute.width;
        this.canvas2.height = height * fontAttribute.height;
    }

    drawBlock(x, y, w, h, color) {
        this.dirtyRectangles.push([x, y, w, h]);
        this.ctx2.fillStyle = color || option.background;
        this.ctx2.fillRect(
            x * fontAttribute.width,
            y * fontAttribute.height,
            w * fontAttribute.width + 1,
            h * fontAttribute.height,
        );
    }

    drawChars(x, y, chars, font, color) {
        this.ctx2.fillStyle = color;
        this.ctx2.font = font;
        this.ctx2.textBaseline = 'top';
        x *= fontAttribute.width;
        y *= fontAttribute.height;
        for (let bytes of chars) {
            const str = utf8.getStringFromBytes(bytes, 1);
            this.ctx2.fillText(str, x, y);
            x += fontAttribute.width * bytes[0];
        }
    }

    drawUnderline(x, y, length, color) {
        this.ctx2.strokeStyle = color;
        this.ctx2.lineWidth = 1;
        this.ctx2.setLineDash([]);
        this.ctx2.beginPath();
        x *= fontAttribute.width;
        y = (y + 1) * fontAttribute.height - 3;
        this.ctx2.moveTo(x, y);
        this.ctx2.lineTo(x + fontAttribute.width * length, y);
        this.ctx2.stroke();
    }

    static calcCharsWidth(chars) {
        return chars.reduce((w, bytes) => { return w + bytes[0] }, 0);
    }

    put(x, y, chars, attribute) {
        const charsWidth = Surface.calcCharsWidth(chars);
        if (attribute === null) {
            this.drawBlock(x, y, charsWidth, 1, option.background);
            this.drawChars(x, y, chars, fontAttribute.font, option.foreground);
        } else {
            let font = fontAttribute.font;
            let foreground = attribute.foreground || option.foreground;
            let background = attribute.background || option.background;
            const { bold, reverse, underline } = attribute;
            if (reverse) {
                const tmp = foreground;
                foreground = background;
                background = tmp;
            }
            if (bold) {
                font = 'bold ' + font;
            }
            this.drawBlock(x, y, charsWidth, 1, background);
            this.drawChars(x, y, chars, font, foreground);
            if (underline) {
                this.drawUnderline(x, y, chars.length, foreground);
            }
        }
    }

    touch() {
        for (let rect of this.dirtyRectangles) {
            const [x, y, w, h] = rect;
            if (w > 0 && h > 0) {
                const x1 = Math.ceil(x * fontAttribute.width);
                const y1 = y * fontAttribute.height;
                const w1 = Math.ceil(w * fontAttribute.width);
                const h1 = h * fontAttribute.height;
                const image = this.ctx2.getImageData(x1, y1, w1, h1);
                this.ctx.putImageData(image, x1, y1);
            }
        }
        this.dirtyRectangles = [];
    }

    scroll(n) {
        if (n > 0) {
            const image = this.ctx2.getImageData(
                0,
                n * fontAttribute.height,
                this.width * fontAttribute.width,
                (this.height - n) * fontAttribute.height,
            );
            this.ctx2.putImageData(image, 0, 0);
        } else {
            n = -n;
            const image = this.ctx2.getImageData(0,
                0,
                this.width * fontAttribute.width,
                (this.height - n) * fontAttribute.height
            );
            this.ctx2.putImageData(
                image,
                x * fontAttribute.width,
                (y + n) * fontAttribute.height
            );
        }
    }
}

const viewStyleTable = {
    "minibuffer": {},
    "popup": { "zIndex": 2 },
};

class View {
    constructor(id, x, y, width, height, use_modeline, kind) {
        this.id = id;
        this.width = width;
        this.height = height;
        this.use_modeline = use_modeline;
        this.editSurface = new Surface(x, y, width, height, viewStyleTable[kind] || {});
        if (use_modeline) {
            this.modelineSurface = new Surface(x, y + height, width, 1, { "zIndex": 1 });
        } else {
            this.modelineSurface = null;
        }
        this.move(x, y);
        this.resize(width, height);
        this.cursor = { x: null, y: null, color: option.foreground };
    }

    allTags() {
        if (this.modelineSurface !== null) {
            return [this.editSurface.canvas, this.modelineSurface.canvas];
        } else {
            return [this.editSurface.canvas];
        }
    }

    delete() {
        this.editSurface.canvas.parentNode.removeChild(this.editSurface.canvas);
        if (this.modelineSurface !== null) {
            this.modelineSurface.canvas.parentNode.removeChild(this.modelineSurface.canvas);
        }
    }

    move(x, y) {
        this.editSurface.move(x, y);
        if (this.modelineSurface !== null) {
            this.modelineSurface.move(x, y + this.height);
        }
    }

    resize(width, height) {
        this.width = width;
        this.height = height;
        this.editSurface.resize(width, height);
        if (this.modelineSurface !== null) {
            this.modelineSurface.move(this.x, this.editSurface.y + this.editSurface.height);
            this.modelineSurface.resize(width, 1);
        }
    }

    clear() {
        this.editSurface.drawBlock(0, 0, this.width, this.height);
    }

    clearEol(x, y) {
        this.editSurface.drawBlock(x, y, this.width - x, 1);
    }

    clearEob(x, y) {
        this.clearEol(x, y);
        this.editSurface.drawBlock(x, y + 1, this.width, this.height - y - 1);
    }

    put(x, y, chars, attribute) {
        this.editSurface.put(x, y, chars, attribute);
    }

    modelinePut(x, chars, attribute) {
        if (this.modelineSurface !== null) {
            this.modelineSurface.put(x, 0, chars, attribute);
        }
    }

    touch() {
        this.editSurface.touch();
        if (this.modelineSurface !== null) {
            this.modelineSurface.touch();
        }
    }

    setCursor(x, y) {
        this.cursor.x = x;
        this.cursor.y = y;
    }

    scroll(n) {
        this.editSurface.scroll(n);
    }
}

customElements.define('lem-editor', LemEditor);
customElements.define('lem-side-pane', LemSidePane);
customElements.define('lem-editor-pane', LemEditorPane);
