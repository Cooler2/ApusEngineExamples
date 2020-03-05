d = document;

var ajax = {
	// ro - global request object
	response : '', // last request response text
	inProgress : false,
	queue : new Array(),

	// Request URL and call FUNC when done. Post DATA if specified
	// DATA can be either STRING => sent as application/x-www-form-urlencoded
	// or OBJECT { param1:value1,... paramN:valueN } => sent as multipart/form-data
	Request : function (url, caption, func, data) {
		try {
			LogMsg('Request for ' + url);
			req = new ajax.Req(url, caption, func, data);
			ajax.queue.push(req);
			if (!ajax.inProgress)
				ajax.ProcessNew();
		} catch (e) {
			alert(e);
		}
	},

	// INTERNAL CODE
	// --------------------------------
	Req : function (url, caption, func, data) {
		this.url = url;
		this.caption = caption;
		this.func = func;
		if (data)
			this.data = data;
	},
	HandleResponse : function () {
		if (ajax.ro.readyState == 4) {
			var req = ajax.queue.shift();
			ajax.response = ajax.ro.responseText;
			LogMsg('Request done');
			if (req.func) {
				if (typeof req.func === 'function')
					req.func(ajax.ro.responseText);
				else
					eval(req.func);
			}
			ajax.inProgress = false;
			window.status = '';
			if (ajax.queue.length > 0)
				ajax.ProcessNew();
		}
	},
	ProcessNew : function () {
		if (ajax.queue.length == 0)
			return;
		ajax.inProgress = true;
		window.status = 'loading: ' + ajax.queue[0].caption;
		ajax.ro = new XMLHttpRequest();
		if ((ajax.queue[0].data) && (ajax.queue[0] != '')) {
			ajax.ro.open('POST', ajax.queue[0].url);
			ajax.ro.onreadystatechange = ajax.HandleResponse;
			if (typeof ajax.queue[0].data == "string") 
				ajax.ro.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
			ajax.ro.send(ajax.queue[0].data);
		} else {
			ajax.ro.open('GET', ajax.queue[0].url);
			ajax.ro.onreadystatechange = ajax.HandleResponse;
			ajax.ro.send(null);
		}
	}
}

// Put text message to web log
function LogMsg(msg) {
	try {
		if (console)
			console.log(msg);
	}
	finally {}
}

// Load content from URL and insert it into the given element
function LoadFileToElement(url, elementID) {
	ajax.Request(url, "", function () {
		d.getElementById(elementID).innerHTML = ajax.response;
	});
}

// Load Javascript file and run it
function LoadScript(url,keepIfLoaded) {
	var name = url.replace(/\W/g, '_');
	var s = d.getElementById('SCRIPT-' + name);
	if (s) {
		if (keepIfLoaded) return;
		d.getElementsByTagName('head')[0].removeChild(s);
		LogMsg('Script removed');
	}
	var script = d.createElement('script');
	script.setAttribute('type', 'text/javascript');
	script.setAttribute('src', url);
	script.setAttribute('id', 'SCRIPT-' + name);
	d.getElementsByTagName('head')[0].appendChild(script);
	LogMsg('Script ' + url + ' appended');
}

// Prevent event bubbling
var allowPropagation = false;
function StopPropagation(event) {
	if (allowPropagation) {
		allowPropagation = false;
		return true;
	}
	event = event || window.event;
	if (event)
		event.stopPropagation();
	return false;
}

// Use empty value to delete cookie
function SetCookie(name, value) {
	if (value)
		d.cookie = name + '=' + value + '; path=/; expires=31-Dec-2099 00:00:00 GMT';
	else
		d.cookie = name + '=; path=/; expires=1-Jan-2000 00:00:00 GMT';
}

function GetCookie(cname) {
	var name = cname + "=";
	var ca = document.cookie.split(';');
	for (var i = 0; i < ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0) == ' ')
			c = c.substring(1);
		if (c.indexOf(name) == 0)
			return c.substring(name.length, c.length);
	}
	return "";
}

function AddClass(element, classname) {
	if (typeof(element) != "object")
		element = d.getElementById(element);
	if (element) {
		if (element.classList) {
			element.classList.add(classname);
		} else {
			var cList=element.className.split(' ');
			var idx=cList.indexOf(classname);
			if (idx<0) {
				cList.push(classname);
				element.className=cList.join(' ');
			}			
		}
	}
}

function RemoveClass(element, classname) {
	if (typeof(element) != "object")
		element = d.getElementById(element);
	if (element) {
		if (element.classList) {
			element.classList.remove(classname);
		} else {
			var cList=element.className.split(' ');
			var idx=cList.indexOf(classname);
			if (idx>=0) {
				cList.splice(idx,1);
				element.className=cList.join(' ');
			}
		}
	}
}

function HasClass(element, classname) {
	if (typeof(element) != "object")
		element = d.getElementById(element);
	if (element) {
		if (element.classList) {
			if (element.classList.contains(classname)) return true;
		} else {
			if (element.className.split(' ').indexOf(classname)>=0) return true;
		}
	}
	return false;
}

// Замена одного класса на другой у элемента и всех вложенных в него
function ReplaceClass(rootItem, oldClass, newClass) {
	if (HasClass(rootItem,oldClass)) {
		RemoveClass(rootItem,oldClass);
		AddClass(rootItem,newClass);
	} 
	var nodes = rootItem.childNodes;
	for (var i = 0; i < nodes; i++)
		ReplaceClass(nodes[i], oldClass, newClass);
}

// Show/hide/toggle element by name or value
function ShowElement(element, value) {
	var item;
	if (typeof(element) == "object")
		item = element;
	else
		item = d.getElementById(element);
	if (item) {
		if (value == 1)
			if (item.style.display != 'block') item.style.display = 'block';
		if (value == 0)
			item.style.display = 'none';
		if (value == -1)
			item.style.display = (item.style.display == 'block') ? 'none' : 'block';
	}
}

function DeleteElement(element) {
	var item;
	if (typeof(element) == "object")
		item = element;
	else
		item = d.getElementById(element);
	if (item)
		item.parentNode.removeChild(item);
}

function SetCurrentURL(url, title) {
	LogMsg('Set current URL: ' + url);
	try {
		if (history) {
			history.pushState(new String(url), (title) ? title : '', url);
			if (title)
				d.title = title;
		} else {
			location.hash = encodeURI(url);
		}
	} catch (e) {
		location.hash = encodeURI(url);
	}
}

function GetDocHeight() {
	return Math.max(
		Math.max(d.body.scrollHeight, d.documentElement.scrollHeight),
		Math.max(d.body.offsetHeight, d.documentElement.offsetHeight),
		Math.max(d.body.clientHeight, d.documentElement.clientHeight));
}

// Calculate element absolute position left-top border pixel {x,y,width,height} 
function GetElementPos(element,relativeTo) {
	if (typeof(element) != "object")
		element = d.getElementById(element);
	var xPosition = 0;
	var yPosition = 0;
	var w=element.offsetWidth;
	var h=element.offsetHeight;
	if (element.getBoundingClientRect) {
		var r=element.getBoundingClientRect();
		w=r.width;
		h=r.height;
		xPosition=r.left+window.pageXOffset;
		yPosition=r.top+window.pageYOffset;
	} else {
		while (element) {
			xPosition += (element.offsetLeft - element.scrollLeft + element.clientLeft);
			yPosition += (element.offsetTop - element.scrollTop + element.clientTop);
			element = element.offsetParent;
			if (element==d.body) break;
		}
	}
	if (relativeTo) {
		if (typeof(relativeTo) != "object")
			relativeTo = d.getElementById(relativeTo);
		var rPos=GetElementPos(relativeTo);
		xPosition-=(rPos.x+relativeTo.clientLeft);
		yPosition-=(rPos.y+relativeTo.clientTop);
	}
	return {
		x: xPosition,
		y: yPosition,
		width: w,
		height: h
	};
}

// pos = {width, height, left, top }
function SetElementPos(element, pos) {
	var dim={ width:pos.width, height:pos.height };
	if (typeof(element) != "object")
		element = d.getElementById(element);
	if (!element)
		return;
	if (typeof dim.width == 'number')
		dim.width = Math.round(dim.width) + 'px';
	if (typeof dim.height == 'number')
		dim.height = Math.round(dim.height) + 'px';
	element.style.width = dim.width;
	element.style.height = dim.height;
	element.style.top = Math.round(pos.top) + 'px';
	element.style.left = Math.round(pos.left) + 'px';
}

function SetElementText(element, text) {
	if (typeof(element) != "object")
		element = d.getElementById(element);
	if (!element) {
		LogMsg('Element ' + element + ' not found!');
		return;
	}
	element.innerHTML = text;
}

// Set caret (cursor) into the given element inside editable element
function SetCaretPos(wnd, element) {
	var doc = element.ownerDocument;
	var range = doc.createRange();
	range.setStart(element, 0);
	range.setEnd(element, 0);
	var sel = wnd.getSelection();
	sel.removeAllRanges();
	sel.addRange(range);
}

// Set element size to its current size in pixels
function SetFixedSize(obj) {
	obj.style.width = obj.offsetWidth + 'px';
	obj.style.height = obj.offsetHeight + 'px';
}

// Convert HTML representation to regular string
function DecodeHtmlString(str) {
	str = str.replace(/&lt;/g, '<');
	str = str.replace(/&gt;/g, '>');
	str = str.replace(/&amp;/g, '&');
	return str;
}

// Convert string so it can be inserted into HTML code
function EncodeHtmlString(str) {
	str = str.replace(/&/g, '&amp;');
	str = str.replace(/</g, '&lt;');
	str = str.replace(/>/g, '&gt;');
	return str;
}

// Convert binary data array to HEX string (each byte -> 2 digits)
function ArrayToHex(data) {
	var res='';	
	var str=new Uint8Array(data);
	for (i = 0; i < str.length; i++) {
		var code = str[i].toString(16);
		if (code.length < 2)	code = '0' + code;
		res = res + code;
	}
	return res; 
}

// Convert binary data array to HEX string (each byte -> 2 digits)
function ArrayToHex(data) {
	var res='';	
	var str=new Uint8Array(data);
	for (i = 0; i < str.length; i++) {
		var code = str[i].toString(16);
		if (code.length < 2)	code = '0' + code;
		res = res + code;
	}
	return res; 
}

function StrToHex(str, base, delta) {
	var res = '';
	if (!base) base=0;
	if (!delta) delta=0;
	for (i = 0; i < str.length; i++) {
		var code = str.charCodeAt(i);
		if (base) {
			code = code^base;
			base = (base + delta) & 255;
		}
		code = code.toString(16);
		if (code.length < 2)
			code = '0' + code;
		res = res + code;
	}
	return res;
}

function HasValue(v) {
	return !(typeof v === 'undefined');
}

function ShortMD5(str) {
	var hash = MD5(str);
	return hash.substr(0, 10);
}

/**
 *
 *  MD5 (Message-Digest Algorithm)
 *  http://www.webtoolkit.info/
 *
 **/

var MD5 = function (string) {

	function RotateLeft(lValue, iShiftBits) {
		return (lValue << iShiftBits) | (lValue >>> (32 - iShiftBits));
	}

	function AddUnsigned(lX, lY) {
		var lX4,
		lY4,
		lX8,
		lY8,
		lResult;
		lX8 = (lX & 0x80000000);
		lY8 = (lY & 0x80000000);
		lX4 = (lX & 0x40000000);
		lY4 = (lY & 0x40000000);
		lResult = (lX & 0x3FFFFFFF) + (lY & 0x3FFFFFFF);
		if (lX4 & lY4) {
			return (lResult^0x80000000^lX8^lY8);
		}
		if (lX4 | lY4) {
			if (lResult & 0x40000000) {
				return (lResult^0xC0000000^lX8^lY8);
			} else {
				return (lResult^0x40000000^lX8^lY8);
			}
		} else {
			return (lResult^lX8^lY8);
		}
	}

	function F(x, y, z) {
		return (x & y) | ((~x) & z);
	}
	function G(x, y, z) {
		return (x & z) | (y & (~z));
	}
	function H(x, y, z) {
		return (x^y^z);
	}
	function I(x, y, z) {
		return (y^(x | (~z)));
	}

	function FF(a, b, c, d, x, s, ac) {
		a = AddUnsigned(a, AddUnsigned(AddUnsigned(F(b, c, d), x), ac));
		return AddUnsigned(RotateLeft(a, s), b);
	};

	function GG(a, b, c, d, x, s, ac) {
		a = AddUnsigned(a, AddUnsigned(AddUnsigned(G(b, c, d), x), ac));
		return AddUnsigned(RotateLeft(a, s), b);
	};

	function HH(a, b, c, d, x, s, ac) {
		a = AddUnsigned(a, AddUnsigned(AddUnsigned(H(b, c, d), x), ac));
		return AddUnsigned(RotateLeft(a, s), b);
	};

	function II(a, b, c, d, x, s, ac) {
		a = AddUnsigned(a, AddUnsigned(AddUnsigned(I(b, c, d), x), ac));
		return AddUnsigned(RotateLeft(a, s), b);
	};

	function ConvertToWordArray(string) {
		var lWordCount;
		var lMessageLength = string.length;
		var lNumberOfWords_temp1 = lMessageLength + 8;
		var lNumberOfWords_temp2 = (lNumberOfWords_temp1 - (lNumberOfWords_temp1 % 64)) / 64;
		var lNumberOfWords = (lNumberOfWords_temp2 + 1) * 16;
		var lWordArray = Array(lNumberOfWords - 1);
		var lBytePosition = 0;
		var lByteCount = 0;
		while (lByteCount < lMessageLength) {
			lWordCount = (lByteCount - (lByteCount % 4)) / 4;
			lBytePosition = (lByteCount % 4) * 8;
			lWordArray[lWordCount] = (lWordArray[lWordCount] | (string.charCodeAt(lByteCount) << lBytePosition));
			lByteCount++;
		}
		lWordCount = (lByteCount - (lByteCount % 4)) / 4;
		lBytePosition = (lByteCount % 4) * 8;
		lWordArray[lWordCount] = lWordArray[lWordCount] | (0x80 << lBytePosition);
		lWordArray[lNumberOfWords - 2] = lMessageLength << 3;
		lWordArray[lNumberOfWords - 1] = lMessageLength >>> 29;
		return lWordArray;
	};

	function WordToHex(lValue) {
		var WordToHexValue = "",
		WordToHexValue_temp = "",
		lByte,
		lCount;
		for (lCount = 0; lCount <= 3; lCount++) {
			lByte = (lValue >>> (lCount * 8)) & 255;
			WordToHexValue_temp = "0" + lByte.toString(16);
			WordToHexValue = WordToHexValue + WordToHexValue_temp.substr(WordToHexValue_temp.length - 2, 2);
		}
		return WordToHexValue;
	};

	function Utf8Encode(string) {
		string = string.replace(/\r\n/g, "\n");
		var utftext = "";

		for (var n = 0; n < string.length; n++) {

			var c = string.charCodeAt(n);

			if (c < 128) {
				utftext += String.fromCharCode(c);
			} else if ((c > 127) && (c < 2048)) {
				utftext += String.fromCharCode((c >> 6) | 192);
				utftext += String.fromCharCode((c & 63) | 128);
			} else {
				utftext += String.fromCharCode((c >> 12) | 224);
				utftext += String.fromCharCode(((c >> 6) & 63) | 128);
				utftext += String.fromCharCode((c & 63) | 128);
			}

		}

		return utftext;
	};

	var x = Array();
	var k,
	AA,
	BB,
	CC,
	DD,
	a,
	b,
	c,
	d;
	var S11 = 7,
	S12 = 12,
	S13 = 17,
	S14 = 22;
	var S21 = 5,
	S22 = 9,
	S23 = 14,
	S24 = 20;
	var S31 = 4,
	S32 = 11,
	S33 = 16,
	S34 = 23;
	var S41 = 6,
	S42 = 10,
	S43 = 15,
	S44 = 21;

	string = Utf8Encode(string);

	x = ConvertToWordArray(string);

	a = 0x67452301;
	b = 0xEFCDAB89;
	c = 0x98BADCFE;
	d = 0x10325476;

	for (k = 0; k < x.length; k += 16) {
		AA = a;
		BB = b;
		CC = c;
		DD = d;
		a = FF(a, b, c, d, x[k + 0], S11, 0xD76AA478);
		d = FF(d, a, b, c, x[k + 1], S12, 0xE8C7B756);
		c = FF(c, d, a, b, x[k + 2], S13, 0x242070DB);
		b = FF(b, c, d, a, x[k + 3], S14, 0xC1BDCEEE);
		a = FF(a, b, c, d, x[k + 4], S11, 0xF57C0FAF);
		d = FF(d, a, b, c, x[k + 5], S12, 0x4787C62A);
		c = FF(c, d, a, b, x[k + 6], S13, 0xA8304613);
		b = FF(b, c, d, a, x[k + 7], S14, 0xFD469501);
		a = FF(a, b, c, d, x[k + 8], S11, 0x698098D8);
		d = FF(d, a, b, c, x[k + 9], S12, 0x8B44F7AF);
		c = FF(c, d, a, b, x[k + 10], S13, 0xFFFF5BB1);
		b = FF(b, c, d, a, x[k + 11], S14, 0x895CD7BE);
		a = FF(a, b, c, d, x[k + 12], S11, 0x6B901122);
		d = FF(d, a, b, c, x[k + 13], S12, 0xFD987193);
		c = FF(c, d, a, b, x[k + 14], S13, 0xA679438E);
		b = FF(b, c, d, a, x[k + 15], S14, 0x49B40821);
		a = GG(a, b, c, d, x[k + 1], S21, 0xF61E2562);
		d = GG(d, a, b, c, x[k + 6], S22, 0xC040B340);
		c = GG(c, d, a, b, x[k + 11], S23, 0x265E5A51);
		b = GG(b, c, d, a, x[k + 0], S24, 0xE9B6C7AA);
		a = GG(a, b, c, d, x[k + 5], S21, 0xD62F105D);
		d = GG(d, a, b, c, x[k + 10], S22, 0x2441453);
		c = GG(c, d, a, b, x[k + 15], S23, 0xD8A1E681);
		b = GG(b, c, d, a, x[k + 4], S24, 0xE7D3FBC8);
		a = GG(a, b, c, d, x[k + 9], S21, 0x21E1CDE6);
		d = GG(d, a, b, c, x[k + 14], S22, 0xC33707D6);
		c = GG(c, d, a, b, x[k + 3], S23, 0xF4D50D87);
		b = GG(b, c, d, a, x[k + 8], S24, 0x455A14ED);
		a = GG(a, b, c, d, x[k + 13], S21, 0xA9E3E905);
		d = GG(d, a, b, c, x[k + 2], S22, 0xFCEFA3F8);
		c = GG(c, d, a, b, x[k + 7], S23, 0x676F02D9);
		b = GG(b, c, d, a, x[k + 12], S24, 0x8D2A4C8A);
		a = HH(a, b, c, d, x[k + 5], S31, 0xFFFA3942);
		d = HH(d, a, b, c, x[k + 8], S32, 0x8771F681);
		c = HH(c, d, a, b, x[k + 11], S33, 0x6D9D6122);
		b = HH(b, c, d, a, x[k + 14], S34, 0xFDE5380C);
		a = HH(a, b, c, d, x[k + 1], S31, 0xA4BEEA44);
		d = HH(d, a, b, c, x[k + 4], S32, 0x4BDECFA9);
		c = HH(c, d, a, b, x[k + 7], S33, 0xF6BB4B60);
		b = HH(b, c, d, a, x[k + 10], S34, 0xBEBFBC70);
		a = HH(a, b, c, d, x[k + 13], S31, 0x289B7EC6);
		d = HH(d, a, b, c, x[k + 0], S32, 0xEAA127FA);
		c = HH(c, d, a, b, x[k + 3], S33, 0xD4EF3085);
		b = HH(b, c, d, a, x[k + 6], S34, 0x4881D05);
		a = HH(a, b, c, d, x[k + 9], S31, 0xD9D4D039);
		d = HH(d, a, b, c, x[k + 12], S32, 0xE6DB99E5);
		c = HH(c, d, a, b, x[k + 15], S33, 0x1FA27CF8);
		b = HH(b, c, d, a, x[k + 2], S34, 0xC4AC5665);
		a = II(a, b, c, d, x[k + 0], S41, 0xF4292244);
		d = II(d, a, b, c, x[k + 7], S42, 0x432AFF97);
		c = II(c, d, a, b, x[k + 14], S43, 0xAB9423A7);
		b = II(b, c, d, a, x[k + 5], S44, 0xFC93A039);
		a = II(a, b, c, d, x[k + 12], S41, 0x655B59C3);
		d = II(d, a, b, c, x[k + 3], S42, 0x8F0CCC92);
		c = II(c, d, a, b, x[k + 10], S43, 0xFFEFF47D);
		b = II(b, c, d, a, x[k + 1], S44, 0x85845DD1);
		a = II(a, b, c, d, x[k + 8], S41, 0x6FA87E4F);
		d = II(d, a, b, c, x[k + 15], S42, 0xFE2CE6E0);
		c = II(c, d, a, b, x[k + 6], S43, 0xA3014314);
		b = II(b, c, d, a, x[k + 13], S44, 0x4E0811A1);
		a = II(a, b, c, d, x[k + 4], S41, 0xF7537E82);
		d = II(d, a, b, c, x[k + 11], S42, 0xBD3AF235);
		c = II(c, d, a, b, x[k + 2], S43, 0x2AD7D2BB);
		b = II(b, c, d, a, x[k + 9], S44, 0xEB86D391);
		a = AddUnsigned(a, AA);
		b = AddUnsigned(b, BB);
		c = AddUnsigned(c, CC);
		d = AddUnsigned(d, DD);
	}

	var temp = WordToHex(a) + WordToHex(b) + WordToHex(c) + WordToHex(d);
	return temp.toUpperCase();
}

function Random(n) {
	return Math.floor(Math.random()*n);
}