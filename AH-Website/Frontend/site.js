var d = document;
var AHserver = 'http://astralheroes.com:2992';
var menuHeight = 48, menuShadow = 29;
var mainMode = false; // Landing or main
var loginURL = '/login';
var userID = 0;
var curMenuItem = '';
var curVirtualLink = '';
var basePageTitle = 'Astral Heroes: strategy card game';
var menuLinks = {
	Home : '/home',
	Leaderboard : '/leaderboard',
	Forum : '/forum'
}
var forumPage = 'ForumHome'; // ID of current forum page root element
var langnames = {
	EN : 'English',
	RU : 'Русский',
	CN : '中文',
	KO : '한국어',
	JA : '日本語',
	FR : 'Française',
	DE : 'Deutsch',
	IT : 'Italiano',
	ES : 'Español',
	PT : 'Português',
};
var uploader;
var attachments=''; // List of attachements in the open editor: "A1;A2;...An;"
var edoc; // frame.document текущего редактора
var curThreadID = 0; // if current page is a forum thread - here is it's ID
var curChapter = 1;
var editedMsgID = 0; // currently edited message ID

// Login window elements
var loginBtnText = '';
var loginWndLogin;
var loginWndPassword;

function LayoutLandingPage() {
	if (mainMode)
		return;
	try {
		// Adjust layout
		var wndHeight = window.innerHeight;
		var scale = wndHeight / 960;
		// Menu bar
		var obj = d.getElementById('MenuBar');
		if (obj) {
			obj.style.top = (wndHeight - menuHeight - menuShadow) + 'px';
		}
		ShowElement('MainContent', 0);
		d.getElementById('MainBackground').style.top = wndHeight + 'px';

		// Play button
		var item = d.getElementById('PlayBtnContainer');
		item.style.top = Math.round(wndHeight * 0.39) + 'px';
		var h = Math.round(wndHeight * 0.127);
		item.style.height = h + 'px';
		item.style.backgroundSize = ((scale >= 0.9) ? 500 : Math.round(500 * scale)) + 'px';
		item = d.getElementById('PlayBtn');
		item.style.fontSize = ((scale > 0.8) ? 30 : Math.round(scale * 35)) + 'px';
		item.style.height = (h / 2) + 'px';
		item.style.top = (h / 4) + 'px';
		item.style.width = Math.round(h * 2.8) + 'px';
		item = d.getElementById('PlayDesc');
		item.style.fontSize = ((scale > 0.85) ? 14 : Math.round(4 + scale * 12)) + 'px';
		// Motto
		item = d.getElementById('Motto');
		item.style.top = Math.round(wndHeight * 0.31 + 10) + 'px';
		item.style.fontSize = ((scale >= 1) ? 22 : Math.round(scale * 22)) + 'px';
		// SocialBar
		item = d.getElementById('SocialBar');
		item.style.top = Math.round(wndHeight * 0.57) + 'px';
		item.style.fontSize = ((scale >= 1) ? 22 : Math.round(scale * 22)) + 'px';

		// MediaContainer
		item = d.getElementById('MediaContainer');
		item.style.top = (scale > 0.8) ? '74%' : (57 + scale * 22) + '%';
		item.style.transform = (scale > 0.8) ? '' : 'scale(' + scale + ')';

		// Background
		item = d.getElementById('Landing');
		var value = Math.round((wndHeight + 350) * 0.85);
		//item.style.backgroundSize='auto '+value+'px';
		value = Math.round(-50 + 25 * scale);
		//item.style.backgroundPosition='center '+value+'px';
	} catch (e) {
		LogMsg(e);
	}
}

function LayoutMainPage() {
	try {
		var wndHeight = window.innerHeight;
		ShowElement('MainContent', 1);
		ShowElement('MainBackground', 1);
		var obj = d.getElementById('MainPage');
		if (obj) {
			obj.style.transition = '';
			obj.style.top = (-menuShadow) + 'px';
			obj.style.height = (menuShadow + wndHeight) + 'px';
		}
		var layerPos = (mainMode) ? 0 : wndHeight;

		// Layout content screens
		LayoutHomePage(layerPos);
		LayoutLeaderboard(layerPos);
		LayoutForum(layerPos);
	} catch (e) {
		LogMsg(e);
	}
}

function onResize() {
	var obj = d.getElementById('MainContent');
	ReplaceClass(obj, 'Animated', 'NotAnimated');
	LayoutLandingPage();
	LayoutMainPage();
	ReplaceClass(obj, 'NotAnimated', 'NotAnimated');
}

function onLoad() {
	// Load additional graphics
	ReplaceClass(d.getElementById('MainBackground'), 'MainBackgroundDelayed', 'MainBackground');
}

function HandleKeyDown(evt) {
	evt = evt || window.event;
	if (evt.keyCode == 27) {
		if (lastWindow)
			HideWindow();
		else
		if (searchBarVisible)
			SearchBar();
	}
	if (evt.keyCode == 13) {
		if (d.activeElement==d.getElementById('SearchInput')) Search();
	}
}

function HandleKeyPress(evt) {
	evt = evt || window.event;
	if ((evt.charCode>32) && 
		 (!lastWindow) && 
		 (mainMode) &&
		 ((!d.activeElement) || (d.activeElement==d.body)) &&
		 (!searchBarVisible)) {
		SearchBar();
	}
}

function HandleClick(evt) {
	evt = evt || window.event;
	// Thread moderation button
	if ((evt.button == 0) && (HasClass(evt.target,'ModThread'))) {
		ModThread(evt.target.getAttribute('thread'));
		evt.preventDefault();
		return;
	}

	// Click on link?
	if ((evt.button == 0) && (!evt.shiftKey) && (!evt.ctrlKey) && (!evt.altKey)) {
		var e = evt.target;
		var href = '';
		while (e) {
			if ((e.tagName == 'A') && (!e.hasAttribute('target')) && (!HasClass(e,'FakeLink'))) {
				href = e.href;
				break;
			}
			e = e.parentElement;
		}
		if (href.indexOf('mailto:')>=0) return;
		if ((href.indexOf(location.host) >= 0) && (href.indexOf('/files/') < 0)) {
			FollowVirtualLink(href);
			evt.preventDefault();
			return;
		}
	}
	// Voting buttons
	if ((evt.button == 0) && HasClass(evt.target,'VoteUp') || HasClass(evt.target,'VoteDown')) {
		RateMessage(evt.target);
	}
	// Validation signs
	if ((evt.button == 0) && HasClass(evt.target,'FieldNotValid')) {
		alert(evt.target.title);
	}
	// Player account name?
	if ((evt.button == 0) && HasClass(evt.target,'PlayerInfo')) {
		ShowPlayerProfile(evt.target.innerHTML);
	}
	// Guild name?
	if ((evt.button == 0) && HasClass(evt.target,'GuildInfo')) {
		ShowGuildProfile(evt.target.innerHTML);
	}
	// Thread row
	var parent = evt.target.parentElement;
	if ((evt.button == 0) && (parent) && HasClass(parent,'ThreadRow')) {
		if (parent.id.match(/THREADROW(\d+)/)) {
			FollowVirtualLink('/forum/thread/' + RegExp.$1);
		}
	}
	// Page buttons
	if ((evt.button == 0) && HasClass(evt.target,'RankingPageIndex')) {
		var id = evt.target.id;
		if (id.match(/(\d)_(\d+)/))
			ShowRankingPage(RegExp.$1, RegExp.$2);
	}
	// Forum editor buttons
	if ((evt.button == 0) && HasClass(evt.target,'EditorBtn')) {
		ForumEditorBtnClick(evt.target);
	}
	
}

function HandleCurThreadTitle() {
	var curT = d.getElementById('CurForumThread');
	if ((curMenuItem == 'Forum') && (curThreadID > 0) && (d.documentElement.scrollTop > 100))
		curT.style.top = '-36px';
	else
		curT.style.top = '-160px';
}

function HandleScroll() {
	HandleCurThreadTitle();
}

function HandleURLChange(obj) {
	LogMsg('History URL changed, state=' + obj.state);
	var url = location.href;
	FollowVirtualLink(url, true);
}

function HandleNavigator() {
	ShowElement('Navigator', (GetDocHeight() > window.innerHeight) ? 1 : 0);
	setTimeout(HandleNavigator, 100);
}

// Show content for given URL, load content if needed
function FollowVirtualLink(url, dontChangeHistory) {
	var idx = url.indexOf('//');
	if (idx >= 0) { // extract path from full url
		url = url.substr(idx + 2);
		idx = url.indexOf('/');
		url = url.substr(idx);
	}
	if (!url.match(/^\/\w\w\//))
		url = '/' + GetCookie('LANG').toLowerCase() + url; // no language -> use cookie
	LogMsg('Follow virtual link: ' + url);
	if (curVirtualLink == url)
		return;
	curVirtualLink = url;
	var list=url.split('#');
	url=list[0];
	var hash=(list[1])? list[1] : '';
	
	var items = url.split('/');
	items = items.slice(1);
	var page = 'default';
	if (items.length > 1) page = items[1].toLowerCase();
	if ((userID > 0) && (page == '')) page = 'home';
	if (page == 'welcome') {
		SwitchTo('Welcome');
		SwitchToLanding();
	}
	if (page == 'home') SwitchTo('Home');
	if (page == 'leaderboard')	ShowLeaderboard(items.slice(2),hash);
	if (page == 'forum')	ShowForum(items.slice(2));
	if (page == 'account') 
		if (userID>0)	
			ShowMyAccount();
		else {
			SwitchTo('Home');
			page='home';
		}
	
	if (!dontChangeHistory) {
		SetCurrentURL(url, GetPageTitle());
		menuLinks[curMenuItem] = url;
	}
	HandleCurThreadTitle();
	// Hide search bar
	if (searchBarVisible) SearchBar();
}

function Initialize() {
	SetEventListeners();
	LayoutLandingPage();
	LayoutMainPage();
	InitForum();
	ShowElement('MenuBar', 1);
	FollowVirtualLink(location.pathname);
	if (location.hostname == 'astralheroes.com')
		loginURL = 'https://astralheroes.com/login';
	d.getElementById('SelectLang').value = GetCookie('LANG');

	// Not logged?
	if (userID == 0) {
		loginWndLogin = d.getElementById('loginWnd_login');
		loginWndPassword = d.getElementById('loginWnd_password');
		//setTimeout("LoadScript('//ulogin.ru/js/ulogin.js');",200);
	} else {
		if (location.pathname.indexOf('/welcome') > 0) {
			var url = location.pathname.replace('/welcome', '/home');
			FollowVirtualLink(url);
		}
	}
	// Fancy warning
	if (console) {
		console.log("%cBe careful!", "color: red; font-size: 180%");
		console.log("%cIf you're not sure what exactly are you doing - you may be VERY disappointed.", "font-size: 125%");
	}
	
	// Other initialization
	setTimeout(ForumMarkMessagesRead, 500);
	setTimeout(HandleNavigator, 200);
	MonitorMsgEditor();

	if (!mainMode) {
		// Load additional scripts
		//setTimeout("LoadScript('https://www.youtube.com/iframe_api')", 50);
	}		
	LoadScript('/cardlist_'+userLang+'.js');
}

function SetEventListeners() {
	d.onkeydown = HandleKeyDown;
	d.onkeypress = HandleKeyPress;
	d.onclick = HandleClick;
	window.onpopstate = HandleURLChange;
	window.onscroll = HandleScroll;
	// Buttons
	var buttons = document.getElementsByClassName("MenuBtn");
	for (var i = 0; i < buttons.length; i++) {
		buttons[i].addEventListener('mousedown', function () {
			AddClass(this, 'MenuBtnDown');
		}, false);
		buttons[i].addEventListener('mouseup', function () {
			RemoveClass(this, 'MenuBtnDown');
		}, false);
		buttons[i].addEventListener('mouseout', function () {
			RemoveClass(this, 'MenuBtnDown');
		}, false);
	}
}

function LangChanged(obj) {
	var curLang = GetCookie('LANG');
	var newLang = obj.value;
	if (newLang != curLang) {
		SetCookie('LANG', newLang);
		var uri = window.location.href;
		uri = uri.replace('/' + curLang.toLowerCase() + '/', '/' + newLang.toLowerCase() + '/');
		window.location.href = uri;
	}
}

function GetPageTitle() {
	if (curMenuItem == 'Home')
		return basePageTitle + ' - Home';
	if (curMenuItem == 'Leaderboard')
		return basePageTitle + ' - Leaderboard';
	if (curMenuItem == 'Forum')
		return basePageTitle + ' - Forum';
}

// Switch to given menu item (content screen)
function SwitchTo(menuItem) {
	if (curMenuItem == menuItem)
		return;
	if (curMenuItem)
		RemoveClass(d.getElementById('MenuItem' + curMenuItem), 'MenuCurrent');
	ShowElement(curMenuItem + 'Screen', 0);
	curMenuItem = menuItem;
	AddClass(d.getElementById('MenuItem' + curMenuItem), 'MenuCurrent');
	if (menuItem != 'Welcome') {
		ShowElement(curMenuItem + 'Screen', 1);
		SwitchToMainMode();
	}
}

var videoPlayer, videoPlayerBig;
function onYouTubeIframeAPIReady() {
	videoPlayer = new YT.Player('VideoPlayerContainer', {
			height : '360',
			width : '640',
			videoId : 'DtJB2XQwxlM'
		});
	videoPlayerBig = new YT.Player('VideoPlayerContainerBig', {
			height : '720',
			width : '1280',
			videoId : 'DtJB2XQwxlM'
		});
}

function PlayVideo() {
	var big = ((window.innerWidth > 1400) && (window.innerHeight >= 800)) ? true : false;
	if (big) {
		ShowWindow('VideoPlayerWindowBig');
		videoPlayerBig.playVideo();
	} else {
		ShowWindow('VideoPlayerWindow');
		videoPlayer.playVideo();
	}
}

var signupStage;
var signupFace;
var signupSpec;
var specNames;
var specDesc;

function ShowSignup() {
	specNames = [str.Wizard, str.Priest];
	specDesc = [str.WizardDesc, str.PriestDesc];
	ShowWindow('SignupWindow');
	setTimeout('d.getElementById("signupWnd_login").focus()', 50);
	for (var i = 1; i <= 4; i++) {
		ShowElement('Valid' + i, 0);
		ShowElement('NotValid' + i, 0);
		SignupValidate(i);
	}
	ShowElement('SignupPage1', 1);
	ShowElement('SignupPage2', 0);
	ShowElement('SignupPage3', 0);
	ShowElement('SignupPage4', 0);
	SetElementText('SignupBtnMain', str.Next);
	signupStage = 1;
	signupFace = 1 + Math.floor(Math.random() * 20);
	SignupChangeFace(0);
	signupSpec = 0;
	SignupChangeSpec(0);
}

function Signup() {
	if (signupStage == 1) {
		if (validating) {
			setTimeout(Signup, 50);
			return;
		}
		for (var i = 1; i <= 4; i++) {
			if (d.getElementById('Valid' + i).style.display == 'none') {
				alert('Please fill all the fields properly');
				return;
			}
		}
		ShowElement('SignupPage1', 0);
		ShowElement('SignupPage2', 1);
		signupStage = 2;
		return;
	}
	if (signupStage == 2) {
		ShowElement('SignupPage2', 0);
		ShowElement('SignupPage3', 1);
		d.getElementById('SignupBtnMain').innerHTML = str.Create;
		signupStage = 3;
		return;
	}
	if (signupStage == 3) {
		var name = d.getElementById('signupWnd_name').value;
		var email = d.getElementById('signupWnd_login').value;
		var pwd = d.getElementById('signupWnd_password').value;
		var query = name + "\t" + email + "\t" + ShortMD5('AH' + pwd) + "\t" + signupFace + "\t" + (signupSpec + 1) + "\t" + GetCookie('LANG') + "\tVID=" + GetCookie('VID');
		LogMsg('NewAcc query: ' + query);
		query = 'A=' + StrToHex(query, 47, 39);
		ajax.Request(AHserver + '/newacc', '', 'SignupCompleted()', query);
		SetElementText('SignupBtnMain', "<img src='/img/ajax-loader.gif' style='margin-top:2px;'>");
	}
	if (signupStage == 4) {
		var url = loginURL;
		var login = d.getElementById('signupWnd_login').value;
		var pwd = d.getElementById('signupWnd_password').value;
		ajax.Request(url, 'Entering the site...', HandleLoginResult, 'login=' + login + '&password=' + pwd);
		SetElementText('SignupPage4', "<img src='/img/ajax-loader.gif' style='margin-top:2px;'>");
	}
	if (signupStage == 5)
		HideWindow();
}

function SignupCompleted() {
	var res = ajax.response;
	if (res == 'OK') {
		res = '<h3>Account created!</h3>';
		SetElementText('SignupBtnMain', 'Log In');
		signupStage = 4;
	} else {
		SetElementText('SignupBtnMain', 'Close');
		signupStage = 5;
		LogMsg('ERROR: ' + res);
	}
	ShowElement('SignupPage3', 0);
	ShowElement('SignupPage4', 1);
	SetElementText('SignupPage4', res);
}

var validating = false;

function SignupValidate(num) {
	LogMsg('Validate ' + num);
	validation = true;
	if (num == 1) {
		ShowElement('Valid1', 0);
		var email = d.getElementById('signupWnd_login').value;
		if (email == '')
			return;
		ajax.Request(AHserver + '/checkvalue?email=' + encodeURIComponent(email), '', "SignupValidated(1,ajax.response)");
	}
	if (num == 2) {
		ShowElement('Valid2', 0);
		var pwd = d.getElementById('signupWnd_password').value;
		if (pwd == '')
			return;
		var res = 'OK';
		if (pwd.length < 6)
			res = 'Password is too short';
		if (pwd.length > 40)
			res = 'Password is too long';
		for (var i = 0; i < pwd.length; i++) {
			var code = pwd.charCodeAt(i);
			if ((code < 32) || (code > 126))
				res = 'Unallowed character(s)';
		}
		SignupValidated(2, res);
	}
	if (num == 3) {
		ShowElement('Valid3', 0);
		var pwd = d.getElementById('signupWnd_password').value;
		var pwd2 = d.getElementById('signupWnd_password2').value;
		if (pwd2 == '')
			return;
		var res = 'OK';
		if (pwd != pwd2)
			res = "Password doesn't match!";
		SignupValidated(3, res);
	}
	if (num == 4) {
		ShowElement('Valid4', 0);
		var name = d.getElementById('signupWnd_name').value;
		if (name == '')
			return;
		ajax.Request(AHserver + '/checkvalue?name=' + encodeURIComponent(name), '', "SignupValidated(4,ajax.response)");
	}
}

function SignupValidated(num, res) {
	if (res == 'OK') {
		ShowElement('Valid' + num, 1);
		ShowElement('NotValid' + num, 0);
	} else {
		ShowElement('Valid' + num, 0);
		ShowElement('NotValid' + num, 1);
		res = res.replace(/\^/g, '');
		d.getElementById('NotValid' + num).title = res;
	}
	validating = false;
}

function SignupChangeFace(delta) {
	signupFace += delta;
	if (signupFace < 1)
		signupFace = 20;
	if (signupFace > 20)
		signupFace = 1;
	var face = d.getElementById('SignupFace');
	face.style.backgroundImage = 'url("/faces/face' + signupFace + '.jpg")';
}

function SignupChangeSpec(delta) {
	signupSpec += delta;
	if (signupSpec < 0)
		signupSpec = specNames.length - 1;
	if (signupSpec >= specNames.length)
		signupSpec = 0;
	var item = d.getElementById('SignupSpecName');
	item.innerHTML = specNames[signupSpec];
	item = d.getElementById('SignupSpecDesc');
	item.innerHTML = specDesc[signupSpec];
}

function ShowLogin() {
	ShowWindow('LoginWindow');
	SetElementText('LoginErrorMsg', '');
	setTimeout("d.getElementById('loginWnd_login').focus();", 50);
}

function Login() {
	if (loginBtnText == '') {
		var btn = d.getElementById('LoginBtnMain');
		loginBtnText = btn.innerHTML;
		btn.innerHTML = "<img src='/img/ajax-loader.gif' style='margin-top:2px;'>";
		var login = encodeURIComponent(loginWndLogin.value);
		var pwd = encodeURIComponent(loginWndPassword.value);
		var url = loginURL;
		ajax.Request(url, 'Entering the site...', HandleLoginResult, 'login=' + login + '&password=' + pwd+(tempLogin? '&temp=1':''));
		SetElementText('LoginErrorMsg', '');
		if (loginWndLogin.classList)
			loginWndLogin.classList.remove('InputFieldError');
		if (loginWndPassword.classList)
			loginWndPassword.classList.remove('InputFieldError');
	}
}

function HandleLoginResult(temp) {
	if (!ajax.response) {
		// request failed?
		SetElementText('LoginErrorMsg', 'Failed, please try once again!');
		if (loginURL != '/login') {
			loginURL = '/login';
			setTimeout(Login, 200);
		}
	} else {
		var lines = ajax.response.split("\r\n");
		if (lines[0] == 'OK') {
			// Login successful
			HideWindow();
			ajax.Request('/login?t='+lines[1]+(tempLogin? '&temp=1':''), '', 'location.reload();', '');
		} else {
			// Login failure
			if ((lines[1] == 1) && (loginWndLogin.classList))
				loginWndLogin.classList.add('InputFieldError');
			if ((lines[1] == 2) && (loginWndPassword.classList))
				loginWndPassword.classList.add('InputFieldError');
			SetElementText('LoginErrorMsg', lines[2] + '<br>');
			LogMsg('ERROR: ' + lines[2]);
		}
	}
	SetElementText('LoginBtnMain', loginBtnText);
	loginBtnText = '';
}

function Logout() {
	location.replace('/logout?backurl=' + encodeURI(location.href));
}

function SwitchToMainMode() {
	if (mainMode)
		return;
	var obj = d.getElementById('MenuBar');
	obj.style.top = -menuShadow + 'px';
	obj = d.getElementById('MainBackground');
	obj.style.top = '0px';
	ShowElement('MainContent', 1);
	mainMode = true;
	setTimeout(LayoutMainPage, 0);
	obj=d.getElementById('UserAccUI');
	if (obj) obj.style.visibility='visible';
}

function SwitchToLanding() {
	if (!mainMode) return;
	ShowElement('MainContent', 0);
	mainMode = false;
	setTimeout(LayoutLandingPage, 0);
}

// Overlays and windows
// --------------------

function ShowOverlay() {
	var overlay = d.getElementById('ScreenOverlay');
	overlay.style.display = 'block';
	setTimeout("d.getElementById('ScreenOverlay').style.backgroundColor='rgba(50,50,50,0.25)';", 0);
}

function HideOverlay() {
	var overlay = d.getElementById('ScreenOverlay');
	overlay.style.backgroundColor = 'rgba(50,50,50,0)';
	setTimeout(function () {
		overlay.style.display = 'none';
	}, 250);
}

var lastWindow;

function ShowWindow(windowName) {
	try {
		ShowOverlay();
		var wnd = d.getElementById(windowName);
		wnd.style.display = 'table';
		wnd.style.left = Math.round((window.innerWidth - wnd.offsetWidth) / 2) + 'px';
		wnd.style.top = Math.round((window.innerHeight - wnd.offsetHeight) / 2) + 'px';
		wnd.style.opacity = 1;
		wnd.style.transform = 'scale(1,1)';
		lastWindow = wnd;
	} catch (e) {
		LogMsg(e);
	}

}

function HideWindow() {
	if (!lastWindow)
		return;
	lastWindow.style.opacity = 0;
	lastWindow.style.transform = '';
	setTimeout(function () {
		lastWindow.style.display = 'none';
		lastWindow = null;
	}, 200);
	HideOverlay();
	if (videoPlayerBig)
		videoPlayerBig.stopVideo();
	if (videoPlayer)
		videoPlayer.stopVideo();
}

function HideWindowIfNeeded(evt) {
	evt = evt || window.event;
	var i = 5;
	var el = evt.target;
	while (el) {
		if (el.id == 'ScreenOverlay')
			HideWindow();
		el = el.parentElement;
		i--;
		if (i == 0)
			return;
	}
}

// Ajax Loader overlay
function ShowAjaxLoader(overItemName, fixedPos) {
	var obj = d.getElementById(overItemName);
	if (!obj)
		return;
	var pos = GetElementPos(obj);
	if (d.getElementById(overItemName + '_loader'))
		return;
	var parent = d.body;
	var loader = d.createElement('div');
	loader.setAttribute('id', overItemName + '_loader');
	loader.setAttribute('class', 'Loader');
	loader.setAttribute('style', 'left:' + pos.x + 'px; top:' + pos.y + 'px; width:' + obj.offsetWidth + 'px; height:' + obj.offsetHeight + 'px; position:' + (fixedPos ? 'fixed' : 'absolute'));
	parent.appendChild(loader);
}

function HideAjaxLoader(overItemName) {
	var obj = d.getElementById(overItemName + '_loader');
	if (obj)
		obj.parentElement.removeChild(obj);
}

// Player profile window
// ---------------------
var playerProfileElements = ['Title', 'Guild', '-', 'RN', 'Loc', '12', '11', '13', '-', '14', '22', '21', '23', '-', '24', '32', '31', '33', '-', '34', '42', '41', '44', '43'];

function ShowPlayerProfile(plrName) {
	var eNames = playerProfileElements;
	for (var i = 0; i < eNames.length; i++) {
		if (eNames[i] != '-')
			SetElementText('PlayerProfile' + eNames[i], '');
	}
	var obj = d.getElementById('ProfileAvatar');
	obj.style.backgroundImage = "url('/img/face_border.png'), url('/faces/lanface.jpg')";
	ShowWindow('ProfileWindow');
	d.getElementById('PlayerProfile_Name').innerHTML = plrName;
	AddClass(d.getElementById('PlayerProfile'), 'Loader');
	var name = DecodeHtmlString(plrName);
	ajax.Request('/profile?name=' + encodeURIComponent(name), '', ProfileLoaded);
}

function ProfileLoaded(response) {
	RemoveClass(d.getElementById('PlayerProfile'), 'Loader');
	var values = response.split("\r\n");
	if (values[0] != 'OK') {
		return;
	}
	var obj = d.getElementById('ProfileAvatar');
	obj.style.backgroundImage = "url('/img/face_border.png'), url('/faces/face" + values[3] + ".jpg')";
	values[6] = str['title'+values[6]];
	if (values[7] == '')
		values[7] = "<span class=ProfileGray>none</span>";
	if (values[9] == '')
		values[9] = "<span class=ProfileGray>unspecified</span>";
	if (values[10] == '')
		values[10] = "<span class=ProfileGray>unspecified</span>";
	if (values[15] == 0)
		values[15] = '-';
	if (values[20] == 0)
		values[20] = '-';
	if (values[25] == 0)
		values[25] = '-';
	var eNames = playerProfileElements;
	values[29] = (Number(values[13]) + Number(values[18]) + Number(values[23])) + ' / ' + (Number(values[14]) + Number(values[19]) + Number(values[24]));
	for (var i = 0; i < 3; i++) {
		values[13 + i * 5] = values[13 + i * 5] + ' / ' + values[14 + i * 5];
	}
	for (var i = 0; i < eNames.length; i++) {
		if (eNames[i] != '-')
			SetElementText('PlayerProfile' + eNames[i], values[6 + i]);
	}
}

// Guild profile
// -------------
var guildInfoTab=1;

function ShowGuildProfile(gName) {
	SetElementText("JustWindowTitle",gName);
	SetElementText("JustWindowContent",'');
	ajax.Request('/guildinfo.cgi?g='+encodeURIComponent(gName),'','SetElementText("JustWindowContent",ajax.response);');
	ShowWindow('JustWindow');
	guildInfoTab=1;
}

function ShowGuildInfoTab(n) {
	if (n!=guildInfoTab) {
		ReplaceClass('gTab'+guildInfoTab,'GuildInfoTabSel','GuildInfoTab');
		ReplaceClass('gTab'+n,'GuildInfoTab','GuildInfoTabSel');
		ShowElement('gPage'+guildInfoTab,0);
		ShowElement('gPage'+n,1);
		guildInfoTab=n;		
	}
}

// Home page
// ---------

function LayoutHomePage(startY) {
	var wndWidth = window.innerWidth;
	var wndHeight = window.innerHeight - menuHeight;	
	var layout1 = {};
	var layout2 = {};
	var layout3 = {};
	var obj0 = d.getElementById('PageFooter');
	obj0.style.top=(window.innerHeight-20)+'px';
	var obj1 = d.getElementById('HomeNews');
	var obj3 = d.getElementById('HomeAbout');
	startY += menuHeight;
	if (wndWidth > 960) {
		var w = wndWidth * 0.95;
		if (w > 1500)
			w = (w * 0.4 + 1500 * 0.6);
		var w1 = w * 0.38;
		if (w1 < 450)
			w1 = (w1 * 0.3 + 450 * 0.7);
		var x = (wndWidth - w) / 2 - 8;
		layout1.left = x;
		layout1.top = startY;
		layout1.width = w1;
		layout1.height = 'auto';

		layout3.left = x + w1 + (wndWidth * 0.01 - 10);
		layout3.top = startY;
		layout3.width = w - w1;
		layout3.height = 'auto';
		SetElementPos(obj1, layout1);
		SetElementPos(obj3, layout3);
		obj1.style.display = 'block';
	} else {
		var w = wndWidth * 0.95;
		var x = (wndWidth - w) / 2 - 8;
		layout3.left = x;
		layout3.top = startY;
		layout3.width = w;
		layout3.height = 'auto';
		SetElementPos(obj3, layout3);
		obj1.style.display = 'none';
	}
	ShowElement('HomeHeadSteam',(layout3.width>650)?1:0);
}

// Leaderboard
// -----------
var lbCount=1, lbFirst=1;

// If url is /xx/leaderboard/xxx/yyy then urlParts - is [xxx,yyy]
function ShowLeaderboard(urlParts,hash) {
	if (hash.match(/\d/)) {
		hash=Number(hash);
		if (hash<lbFirst) lbFirst=hash;
		if (hash>=lbFirst+lbCount) lbFirst=hash-lbCount+1;
	}
	LayoutLeaderboard();
	SwitchTo('Leaderboard');
}

function LayoutLeaderboard(startY) {
	var wndWidth = window.innerWidth-10;
	var wndHeight = window.innerHeight;
	
	var divHeight;
	lbCount=Math.floor(wndWidth*0.98/450);
	if (lbCount<1) lbCount=1;
	var blockWidth=Math.round(wndWidth*0.98/lbCount);
	if (blockWidth<440) blockWidth=440;
	if (blockWidth>540) blockWidth=540;
	var totalWidth=blockWidth*lbCount;
	while ((lbFirst>1) && (lbFirst+lbCount>6)) lbFirst--;
	var pos=GetElementPos('RankNav1');
	var y=pos.y+pos.height-window.pageYOffset;
	if (!y) y=menuHeight+88;
	y+=8;
	SetElementPos('RankingContainer',{left:Math.round((wndWidth-totalWidth)/2), top: y, width: totalWidth, height: wndHeight-y });
	
	for (var i = 0; i < 5; i++) {
		SetElementPos('Ranking' + i, {left:(1+i-lbFirst)*blockWidth, top:0, width: blockWidth, height: wndHeight-y+8 });
		var e=d.getElementById('RankingTable'+i);
		while (e && (e.nodeName != 'DIV')) e=e.parentElement;
		if (e) e.style.height=(wndHeight-y-133)+'px';
	}
	setTimeout(HighlightLeaderboards,1);	
}

function HighlightLeaderboards() {
	var pos1=GetElementPos('RankNav'+lbFirst);
	var pos2=GetElementPos('RankNav'+(lbFirst+lbCount-1));
	SetElementPos('RankingSel',{left: pos1.x-15, top: pos1.y-10, width: (pos2.x+pos2.width-pos1.x+30), height: pos1.height+20});	
	ShowElement('RankingSel',1);
}

function ShowRankingPage(mode, page) {
	ajax.Request('/ranking?mode=' + mode + '&start=' + (page * 100 - 99), '',
		function (res) {
		var items = res.split('<!--PAGES-->');
		SetElementText('RankingTable' + mode, items[0]);
		SetElementText('RankingPages' + mode, items[1]);
	});
}

// Account
// -------------------------
var stdAvatarList=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
var avatarList;
var avatarIndex=0;

function ShowMyAccount() {
	ajax.Request('/account','',MyAccountLoaded);	
	SwitchTo('Account');
	PrepareAvatarList();
}

function MyAccountLoaded() {
	SetElementText("MyAccountMain",ajax.response);
	var obj=d.getElementById('NotificationMode');
	if (obj) obj.value=obj.getAttribute('nMode');
}

function PrepareAvatarList() {
	avatarList=stdAvatarList.slice(0);
	avatarIndex=avatarList.indexOf(userAvatar);
	if (avatarIndex<0) {
		avatarList.unshift(userAvatar);
		avatarIndex=0;
	}
}

function AccountEdit(field,state) {
	ShowElement('Account'+field,(state==0)? 1:0);
	ShowElement('EditAccount'+field,(state==1)? 1:0);
	ShowElement('EditAccountError'+field,(state==2)? 1:0);
	if (state==1) {
		var el=d.getElementById('Account'+field+'Value');
		var inp=d.getElementById('AccountInput'+field);
		inp.value=el.innerText;
		inp.focus();
	}
}

function AccountEditSave(field) {
	AccountEdit(field,2);
	SetElementText('EditAccountErrorText'+field+'Value','<img src="/img/loader_bar.gif">');
	var inp=d.getElementById('AccountInput'+field);
	var value=encodeURIComponent(inp.value);
	ajax.Request('/account','','AccountUpdate("'+field+'","'+value+'")','f='+field+'&v='+value+'&s='+formSignature);
}

function AccountUpdate(field,oldVal) {
	var resp=ajax.response.split("\r\n");
	if (resp[0]=='OK') {
		SetElementText('Account'+field+'Value',EncodeHtmlString(resp[1]));
		AccountEdit(field,0);
		if (field=='Email') {
			var el=d.getElementById('Account'+field+'Value');
			while (el.nextSibling) { el.parentNode.removeChild(el.nextSibling); }			
			AccountVerifyEmail();
		}
	} else {
		SetElementText('EditAccountErrorText'+field,resp[1]);				
	}
}

function AccountSaveValue(param,value,container) {
	if (container) {
		SetElementText(container,str.Saving);
		ShowElement(container,1);
	} else {
		container='';
	}
	value=encodeURIComponent(value);
	ajax.Request('/account','','AccountValueSaved('+container+')','f='+param+'&v='+value+'&s='+formSignature);
}

function AccountValueSaved(container) {
	var resp=ajax.response.split("\r\n");
	var txt=str.Saved;
	if (resp[0]!='OK') txt=resp[0];
	if (container) SetElementText(container,txt);
}

function AccountChangeFace(delta) {
	avatarIndex+=delta;
	var l=avatarList.length;
	if (avatarIndex<0) avatarIndex+=l;
	if (avatarIndex>=l) avatarIndex-=l;	
	var idx=avatarList[avatarIndex];
	d.getElementById('AccountAvatar').style.backgroundImage='url("/faces/'+((idx>0)? ('face'+idx) : ('temp/face'+(-idx)))+'.jpg")';
	d.getElementById('AccountAvatarSave').disabled=(userAvatar==avatarList[avatarIndex]);	
}

function AccountSaveAvatar(response) {
	if (!HasValue(response)) {
		ajax.Request('/account','',AccountSaveAvatar,'f=avatar&v='+avatarList[avatarIndex]+'&s='+formSignature);
		return;
	}
	var res=response.split("\r\n");
	if (res[0]=='OK') {
		userAvatar=Number(res[1]);
		PrepareAvatarList();
		AccountChangeFace(0);
		d.getElementById('PlayerFaceIcon').style.backgroundImage="url('/faces/s-"+userAvatar+".jpg')";
	} else {
		alert(res[1]);
	}
}

function AccountUploadAvatar(stage) {
	if (stage==1) {
		SetElementText("JustWindowTitle",str.UploadAvatar);
		SetElementText("JustWindowContent",'');
		ajax.Request('/getpage?p=UPLOAD_AVATAR','','SetElementText("JustWindowContent",ajax.response);');
		ShowWindow('JustWindow');
	}
	if (stage==2) {
		HideWindow();
		d.getElementById('UploadAvatarFile').click();
	}	
}

function AccountVerifyEmail(response) {
	if (!HasValue(response)) { 
		ajax.Request('/verifyemail.cgi?edited=1','',AccountVerifyEmail);
	} else {
		var res=response.split("\r\n");
		if (res[0]=='OK') 
			SetElementText('AccountVerifyEmail',res[1]);	
		else 
			alert(res[1]);
	}
}

var saveUploadBtnText;
function AccountHandleFile(files) {
	if (files.length==0) return;
	if (files[0].size>512*1024) {
		alert('File is too large! 512Kb max!'); return;
	}
	var reader=new FileReader();
	reader.onload=function(evt) {
		var data=evt.target.result;
		ajax.Request('/account','',AccountAvatarUploaded,'s='+formSignature+'&f=customavatar&v='+ArrayToHex(data));
		var btn=d.getElementById("AccountAvatarUploadBtn");
		saveUploadBtnText=btn.innerHTML;
		SetElementText(btn,'<img src="/img/loader_bar.gif">');
	};
	reader.readAsArrayBuffer(files[0]);
}

function AccountAvatarUploaded(response) {
	var res=response.split("\r\n");
	SetElementText("AccountAvatarUploadBtn",saveUploadBtnText);
	if (res[0]=='OK') {
		avatarList.unshift(-res[1]);
		avatarIndex=0;
		AccountChangeFace(0);
	} else {
		alert(res[1]);
	}
}

// Forum
// ------------------------

function ShowForum(urlParts) {
	if (urlParts[0] == 'thread')
		ShowForumPage('thread', urlParts[1]);
	if (urlParts[0] == 'general')
		ShowForumChapter(1, urlParts[1]);
	if (urlParts[0] == 'problems')
		ShowForumChapter(2, urlParts[1]);
	if (urlParts[0] == 'offtopic')
		ShowForumChapter(3, urlParts[1]);
	if (urlParts[0] == 'news')
		ShowForumChapter(4, urlParts[1]);
	if (urlParts[0] == 'suggestions')
		ShowForumChapter(5, urlParts[1]);
	if (urlParts[0] == 'guilds')
		ShowForumChapter(6, urlParts[1]);
	if (urlParts[0] == 'tournaments')
		ShowForumChapter(7, urlParts[1]);
	if (urlParts.length == 0)
		ShowForumPage('ForumHome');
	LayoutForum();
	SwitchTo('Forum');
}

function ShowForumChapter(id, extra) {
	if (extra) {
		// create new thread
		curThreadID = 100000 + id;
		curChapter = id;
		DeleteElement('newthread'); // always reload
		ShowForumPage('newthread', 0);
	} else {
		ShowForumPage('chapter', id);
	}
}

function HighlightMsg(id,level) {
	var el=d.getElementById('MsgText'+id);
	if (!level) level=120;
	level--;
	if (level==0) 
		el.style.color='';
	else {
		el.style.color='rgb(0,'+level+',0)';
		setTimeout(HighlightMsg,30,id,level);
	}
}

function ShowForumPage(pageType, id) {
	ShowElement(forumPage, 0);
	forumPage = pageType;
	var hash=0;
	if (id) {
		if (String(id).match(/(\d+)#FMSG(\d+)/)) {
			id=RegExp.$1;
			hash=RegExp.$2;
		}
		forumPage = forumPage + id;
	}
	var item = d.getElementById(forumPage);
	if (!item) {
		// Page not loaded yet
		item = CreateForumPage(forumPage);
		if ((pageType == 'thread') || (pageType == 'newthread')) {
			var rid = id;
			if (rid == 0)
				rid = rid + '&chapter=' + (curThreadID % 100);
			ajax.Request('/forumthread?id=' + rid+((hash>0)? ('&msgid='+hash) : ''), '', function (res) {
				ForumPageLoaded(item, res);
			});
		}
	} else {
		// Page is already loaded
		SetCurrentThreadTitle(item.innerHTML);
		if (hash>0) {
			var el = d.getElementById('FMSG' + hash);
			if (el) {
				LogMsg('Scroll after ' + el.id);
				HighlightMsg(hash);				
				setTimeout(function () {
					el.scrollIntoView(false);
				}, 0);
			} else {
				// Reload page
				ajax.Request('/forumthread?id='+id+'&msgid='+hash, '', function (res) {
					ForumPageLoaded(item, res);
				});
			}
		}
		
	}
	item.style.display = 'block';
	var list = d.getElementsByClassName('ThreadBlockCurrent');
	if (list.length > 0)
		RemoveClass(list[0], 'ThreadBlockCurrent');

	if (pageType == 'chapter') {
		ajax.Request('/chapter?id=' + id, '', function (res) {
			ForumPageLoaded(item, res);
		});
		id = 100000 + id;
	}
	if (pageType == 'thread') {
		var tbl = d.getElementById('ThreadBlock' + id);
		AddClass(tbl, 'ThreadBlockCurrent');
	}
	curThreadID = id;
}

function ForumPageLoaded(page, res) {
	SetCurrentThreadTitle(res);
	page.innerHTML = res;
	if (curThreadID == 0)
		ForumReply(0, 0); // Create new thread
	else {
		if (location.hash.match(/FMSG(\d+)/)) {
			showMsg=RegExp.$1;
			HighlightMsg(showMsg);
		}
		var showMsg = 0;
		if (res.match(/<!-- LASTREAD=(\d+) -->/)) {
			var lastread = RegExp.$1;
			var el=d.getElementById('FMSG' + lastread);
			if (el) el=el.nextElementSibling;
			if (el) { 
				el.id.match(/(\d+)/);
				showMsg=RegExp.$1;
			}
		}		
		if (showMsg > 0) {
			var el = d.getElementById('FMSG' + showMsg);			
			if (el) {
				LogMsg('Scroll to ' + el.id);
				var pos=GetElementPos(el);
				setTimeout(function () {
					scrollTo(0,pos.y-250);
				}, 10);
			}
		}
	}
}

function SetCurrentThreadTitle(html) {
	if (html.match(/(<h2.*\/h2>)/))
		SetElementText('CurForumThreadTitle', RegExp.$1);
	SetElementText('CurForumThreadTitle', RegExp.$1);
}

// Load omited messages into a forum page (range is a string "A..B")
function ShowOmitedMessages(element, threadID, range) {
	var start = 0,
	count = 0;
	if (range.match(/(\d+)\.\.(\d+)/)) {
		start = RegExp.$1;
		count = RegExp.$2 - start + 1;
		ajax.Request('/forumthread?id=' + threadID + '&start=' + start + '&count=' + count, '',
			function (res) {
			var msgs = res.split('<!--MSGEND-->');
			var par = element.parentNode;
			for (var i = 0; i < msgs.length; i++) {
				if (msgs[i].match(/id=FMSG(\d+)>/)) {
					var newNode = d.createElement('div');
					newNode.setAttribute('id', 'FMSG' + RegExp.$1);
					if (msgs[i].match(/<div id=FMSG\d+>([\s\S]*)<\/div>/))
						newNode.innerHTML = RegExp.$1;
					par.insertBefore(newNode, element);
				}
			}
			par.removeChild(element);
		});
		id = 100000 + id;
	}
}

function CreateForumPage(name) {
	var item = d.createElement('div');
	item.setAttribute('id', forumPage);
	item.setAttribute('class', 'ForumPage');
	item.innerHTML = "<div align=center><img src='/img/loader_bar.gif' width=32 style='margin:50px;'></div>";
	var parent = d.getElementById('ForumMain');
	parent.appendChild(item);
	return item;
}

function LayoutForum(startY) {
	var wndWidth = window.innerWidth - 15;
	var wndHeight = window.innerHeight - menuHeight;
	var nav = d.getElementById('ForumThreadsPage');
	var main = d.getElementById('ForumMain');
	var curT = d.getElementById('CurForumThread');
	var navWidth = 280;
	var spacer = 0;
	var mainWidth = wndWidth - navWidth;
	if (wndWidth > 900) {
		navWidth += (wndWidth - 900) * 0.12;
		spacer = (wndWidth - 1100) * 0.02;
		if (spacer < 0)
			spacer = 0;
		if (navWidth > 420)
			navWidth = 420;
		mainWidth = wndWidth - navWidth - spacer * 5;
		if (mainWidth > 850)
			mainWidth = (mainWidth * 0.7 + 900 * 0.3);
	}
	if (wndWidth < 900) {
		navWidth = 0;
		spacer = 0;
		mainWidth = wndWidth;
	}
	var startX = (wndWidth - (navWidth + spacer + mainWidth)) / 2 - 5;
	startY += menuHeight + 5;
	nav.style.width = Math.round(navWidth) + 'px';
	nav.style.left = Math.round(startX) + 'px';
	nav.style.top = startY + 'px';
	nav.style.display = (navWidth > 0) ? "block" : "none";
	main.style.width = Math.round(mainWidth) + 'px';
	main.style.left = Math.round(startX + navWidth + spacer) + 'px';
	main.style.top = startY + 'px';
	curT.style.left = Math.round(startX + navWidth + spacer - 6) + 'px';
	curT.style.width = Math.round(mainWidth + 12) + 'px';

	if (wndWidth < 700) {
		main.style.left = '0px';
		main.style.width = '100%';
		curT.style.left = '-3%';
		curT.style.width = '106%';
		ReplaceClass(main, 'Paper', 'PaperWide');
	} else {
		ReplaceClass(main, 'PaperWide', 'Paper');
	}

	var mainStyles = d.styleSheets[0];

	// Number of suggested threads
	var threads = d.getElementById('ForumThreads');
	var item = threads.firstElementChild;
	if (item) {
		var itemHeight = item.scrollHeight;
		if (itemHeight == 0)
			itemHeight = 42;
		var numItems = Math.round((wndHeight - menuHeight - 30) / itemHeight);
		while (item) {
			item.style.display = (numItems > 0) ? 'block' : 'none';
			numItems--;
			item = item.nextElementSibling;
		}
	}
}

function ForumDeletePost(msgid, topicid) {
	if (confirm(str.askDelete)) {
		DeleteElement('FMSG' + msgid);
		ajax.Request('/delmsg.cgi?msg=' + msgid, str.deleting, function (resp) {
			if (resp.length > 5)
				alert(resp);
		}, '');
	}
}

function ForumDeleteAll(topicid) {}

function ForumMoveAll(topicid) {
	var items = d.getElementsByClassName('SelMsg');
	var list = [];
	for (var i = 0; i < items.length; i++) {
		if (items[i].checked) {
			items[i].id.match(/(\d+)/);
			list.push(RegExp.$1);
		}
	}
	if ((list.length > 0) && (confirm('Do you really want to move ' + list.length + ' messages here?'))) {
		ajax.Request('/movemsgs.cgi?target=' + topicid + '&msgs=' + list.join('_'), '', 'window.location.reload();');
	}
}

function ExtractEditableText(text) {
	// убрать вложенные цитаты
	var re = /<blockquote.*?>[\s\S]*?<\/blockquote>/i;
	while (text.match(re)) {
		text = text.replace(re, '<div>...</div>');
	}
	text = text.replace(/<div class=.*?QuoteAuthor.*?<\/div>/gi, '');
	text = text.replace(/<!--.*?-->/gi, '');
	text = text.replace(/<div class=.*?MsgButtons.*?<\/div>/gi, '');
	text = text.replace(/<table class=.*?ForumAttach.*?<\/table>/gi, '');
	text = text.replace(/<div class=[\s\S]*?small gray[\s\S]*?<\/div>/gi, '');
	text = text.replace(/<!-- .+? -->/gi, '');
	return text;
}

function ForumEditPost(msgid, topicid) {
	if (edoc)
		CloseMsgEditor();
	ForumReply(-1, topicid);
	var edittext = d.getElementById('MsgText' + msgid).innerHTML;
	editedMsgID = msgid;

	// Current attachments
	attachments='';
	if (edittext.match(/<!-- ATTACHED:(.+?)-->/)) {
		var attList=RegExp.$1.split(',');
		var uploads = d.getElementById('uploads' + curThreadID);
		uploads.style.display = 'block';
		for (i = 0; i < attList.length; i++) {
			var aid=attList[i];
			var thumb=d.getElementById('AThumb'+aid);
			if (thumb) {
				var fType=thumb.parentElement.getAttribute('href');
				fType=fType.substr(fType.lastIndexOf('.')+1,fType.length);
				// (uploads, id, filetype, filename, thumbnail, tWidth, tHeight)
				AppendAttachment(uploads, aid, fType, thumb.getAttribute('title'), thumb.getAttribute('src'), 
				  thumb.getAttribute('width'), thumb.getAttribute('height'));
			}
		}
	}
	var p=edittext.indexOf('<!-- ATTACHED:');
	if (p>=0) edittext=edittext.substr(0,p);
	edittext = edittext.replace('<!-- CUT -->', '-=cut=-');
	edittext = edittext.replace(/<div class="small gray"[\s\S]*?<\/div>/gi, '');
	setTimeout(function () {
		edoc.body.innerHTML = edittext;
	}, 1);
}

function GetSelectionCoords() {
	var win = window;
	var x = 0, y = 0;
	if (win.getSelection) {
		var sel = win.getSelection();
		if (sel.rangeCount) {
			var range = sel.getRangeAt(0).cloneRange();
			if (range.getClientRects) {
				range.collapse(true);
				var rects = range.getClientRects();
				if (rects.length > 0) {
					var rect = rects[0];
					x = rect.left;
					y = rect.top;
				}
			}
		}
	}
	return { x: x, y: y };
}

function GetSelectionText(insideNode) {
    var text = '';
    if (window.getSelection) {
		 var sel=window.getSelection();
		 var fromNode=sel.anchorNode;
		 var toNode=sel.focusNode;
		 if ((!insideNode) || 
			  (insideNode.contains(sel.anchorNode) &&
				insideNode.contains(sel.focusNode)))
			text = window.getSelection().toString();
    } else if (document.selection && document.selection.type != "Control") {
        text = document.selection.createRange().text;
    }
    return text;
}

function GetMsgIdFromNode(node) {	
	while (node) {
		if (node.nodeType==1) {
			var id=node.id || '';
			if (id.match(/MsgText(\d+)/)) return RegExp.$1;
		}
		node=node.parentNode;
	}
	return 0;
}

// добавление цитаты в уже открытый редактор
function ForumQuote(msgID,threadID) {
	if (!threadID) threadID=curThreadID;
	var quoted = GetSelectionText(d.getElementById('MsgText'+msgID));
	if (msgID==0) {
		if (window.getSelection) {
			// Find msgID containing selection
			var sel=window.getSelection();
			var msgid1=GetMsgIdFromNode(sel.anchorNode);
			var msgid2=GetMsgIdFromNode(sel.focusNode);
			if ((msgid1==msgid2) && (msgid1>0)) msgID=msgid1;
		} else 
			return;
	}
	if ((quoted=='') && (msgID > 0)) {
		var item = d.getElementById('MsgText' + msgID);
		quoted = item.innerHTML;
	}
	quoted = ExtractEditableText(quoted);	
  	if (quoted != '') {
		var qnode = edoc.createElement('blockquote');
		edoc.body.appendChild(qnode);
		qnode.title = msgID;
		qnode.innerHTML = quoted;
	}	
}

// msgid=0 - new message
function ForumReply(msgID, threadID) {
	if (!authorized) {
		ShowLogin();
		return;
	}	
	if (!(curThreadID==threadID))
		editedmsgID = 0;

	var lang = GetCookie('LANG');

	var ed = d.getElementById('EDITOR' + threadID);
	var eframe = d.getElementById('EFRAME' + threadID);
	if (!eframe) {
		// новый редактор
		ed.style.overflow = "hidden";
		ed.style.height = '40px';
		setTimeout(function () {
			ed.style.height = (threadID == 0) ? "400px" : "380px";
		}, 0);
		setTimeout(function () {
			ed.style.overflow = "visible";
			ed.style.height = "auto";
		}, 300);
		// инициализация редактора
		var title = '';
		var addbtn = d.getElementById('ADDBTN' + threadID);
		if (addbtn)
			addbtn.style.display = 'none';
		var buttons = '<td style="min-width:190px;"><table cellpadding=0 cellspacing=0 class=EditorToolbar><tr>'+
			'<td class=EditorBtn cmd=1 title="Bold">'+
			'<td class=EditorBtn cmd=2 title="Italic">'+
			'<td class=EditorBtn cmd=3 title="Underline">'+
			'<td style="width:8px">'+			
			'<td class=EditorBtn cmd=4 title="'+str.Smiles+'">'+
			'<td class=EditorBtn cmd=5 title="'+str.InsImage+'">'+
			'<td class=EditorBtn cmd=6 id="AttachBtn'+curThreadID+'" title="'+str.AttachFile+'">'+
			'<td class=EditorBtn cmd=7 title="'+str.InsDeck+'">'+
			'</table>';

		if (!authorized)
			buttons = '<td>&nbsp;' + str.Name + ':&nbsp;<td><input id="uname' + threadID + '" type=text class=inp2 maxlength=40><td><img src="/img/vsplit1.gif">' + buttons;
		if (threadID == 0) {
			buttons = '<td>&nbsp;' + str.topic + ':&nbsp;<td><input id="topic_title" type=text class=inp2 style="width:240px" maxlength=40><td><img src="/img/vsplit1.gif">' +
				'<td><select class=inp2 id=topic_lang style="width:104px;" title="Language">' +
				'<option value="En" ' + ((lang == 'EN') ? 'selected' : '') + '>English' +
				'<option value="Ru" ' + ((lang == 'RU') ? 'selected' : '') + '>Русский' +
				'<option value="Cn">中文' +
				'<option value="Ko">한국어' +
				'<option value="Ja">日本語' +
				'<option value="Fr">Française' +
				'<option value="De">Deutsch' +
				'<option value="It">Italiano' +
				'<option value="Es">Español' +
				'<option value="Pt">Português' +
				'</select><td><img src="/img/vsplit1.gif">' + buttons + '<td width=50%>';
			title = '';
		} else {
			var obj = d.getElementById('THREADLANG' + threadID);
			var lng = ((obj) ? obj.value : 'EN');
			buttons = buttons + '<td width=70% align=right title="' + str.tlangDesc + '">' + str.tLang + '<span style="color:#A00">' + langnames[lng] + '</span>&nbsp;';
		}
		var smlist = '';
		var smfiles = new Array('smile', 'sad', 'cry', 'bigeyes', 'thup', 'thumbdn', 'confused', 'laugh', 'deal', 'dont', 'fear', 'thanx', 'win', 'beer', 'furious', 'alc', 'idea', 'val');
		var smcaptions = new Array(':-)', 'Sad :-(', 'Cry :&rsquo;-(', 'Big Eyes 8-O', 'Thumbs Up', 'Thumbs Down', 'Confused :-/', 'Laugh :-D', 'Rule', "Don't", 'Fear', 'Thanks', 'Win', 'Beer', 'Furious', 'Drunk', 'Idea', 'Writer');
		for (i in smfiles) {
			smlist = smlist + '<td width=33 bgcolor=#FFFFFF class="transp trborder" onClick="InsertSmile(\'' + smfiles[i] + '\',\'' + smcaptions[i] + '\')">' +
				'<img src="/img/tr.gif" width=33 height=33 title="' + smcaptions[i] + '"></td>';
		}
		
		// Editor block HTML code
		var toolbars = '<div class=bar><table class=bar2 width=100% cellpadding=1 cellspacing=0><tr>' + buttons + '</table></div>' +
			'<div class=bar4 id="SMILESBAR' + threadID + '" style="display:none"><table cellpadding=0 cellspacing=0 width=100%><tr>' + smlist + '<td>&nbsp;</table></div>' + 
			'<div class=bar id="IMGBAR' + threadID + '" style="display:none"></div>'; 			
		var editorFrame = '<div><iframe class=docframe frameborder=NO id="EFRAME' + threadID + '"></iframe></div>';
		var uploads = '<div id="uploads' + threadID + '" class=bar5 style="display:none"></div>';
		var statusLines = '<div id="status' + threadID + '" class=bar3 style="display:none"><table width=100% height=26 cellpadding=0 cellspacing=0><tr><td id="statuscell' + threadID + '" valign=center align=center class=bar2>Posting message, pelase wait...</table></div>';		

		var privateThreadCheckbox = '<div><input type=checkbox id=GuildPrivT class=ForumCheckbox> <label for="GuildPrivT">'+str.GuildPrivateThread+'</label></div>';
		var options = ((threadID==0) && (curChapter==6) && (userGuild))? privateThreadCheckbox : '';
		var checkbox='<div style="display:none"><input type=checkbox id=subscribe# class=ForumCheckbox> <label for="subscribe#">%%</label></div>';
		var options=options+checkbox.replace(/#/g,threadID+'a').replace('%%',str.Subscribe1)+checkbox.replace(/#/g,threadID+'b').replace('%%',str.Subscribe2);
		
		var postButtons = '<div align=center style="padding-top:8px;"><input type=button class=btn4 onClick="ForumPostMessage()" value="' + str.Submit + '">' + ((threadID > 0) ? '&nbsp; &nbsp;<input type=button class=btn4 onClick="CloseMsgEditor(true)" value="' + str.Close + '">' : '') + '</div>';
			
		ed.innerHTML = title + toolbars + editorFrame + uploads + statusLines + options + postButtons;
		eframe = d.getElementById('EFRAME' + threadID);
		eframe.style.height = (threadID == 0) ? "300px" : "280px";
		edoc = eframe.contentWindow.document;
		var edstyles = 'BODY { cursor: auto; padding:0px; margin:4px; background-color: #DFD1BC; background-image:none; }' +
			'BLOCKQUOTE { font-style: italic; background-color:#E8D9C2; background-image:none; padding:0px; margin:0px; color: #444; border: 1px dashed #777 }' +
			'p { text-align: left; }';

		edoc.open('text/html');
		edoc.write('<HTML><head><link rel="Stylesheet" href="/styles.css" media="all"><style type="text/css">' + edstyles + '</style></head>\n' +
			'<body class="MainContent MainFont"></body></html>');
		edoc.close();
		edoc.designMode = 'On';
		edoc.addEventListener("paste",HandleEditorPaste);
		eframe.contentWindow.focus();
	} else {
		// редактор уже был
		edoc = eframe.contentWindow.document;
	}
	ToggleReplyButtons(threadID,2);
	// Add quote
	if (msgID>0) ForumQuote(msgID,threadID);

	ed.style.display = 'block';
	var replyPos = edoc.createElement('div');
	replyPos.innerHTML = '&nbsp;';
	edoc.body.appendChild(replyPos);
	replyPos.focus();
	SetCaretPos(eframe.contentWindow, replyPos);
	eframe.contentWindow.focus();

	for (var i = 0; i < 15; i++)
		setTimeout("window.scrollTo(0,GetDocHeight());", i * 24);
	
	setTimeout('d.getElementById("subscribe'+threadID+'a").checked='+((localStorage.getItem('subscribeMode')=='N')? 'false':'true'),0);
}

function HandleEditorPaste(evt) {
	if (evt && evt.clipboardData) {
		var data=evt.clipboardData;
		if (data.files && data.files.length>0) {
			if (data.files[0].size<1024*150)
				UploadImageFile(data.files,true);
			else
				UploadAndAttachFile(data.files);
		}
	}
}

function UploadImageFile(files,silent) {
	if (files.length==0) return;	
	if (files[0].size>1*1024*1024) {
		alert('File is too large! Max 1MB!'); return;
	}
	if (!silent && (files[0].size>65536) && (files[0].name.match(/\.png/i) || files[0].name.match(/\.gif/i))) {
		if (!confirm(str.BigFileConvert)) return;
	}
	var reader=new FileReader();
	var fileName=files[0].name;
	var fileSize=files[0].size;
	var fd=new FormData;
	fd.append('File',files[0]);
	ajax.Request('/UploadImage','',ImageFileUploaded,fd);
	AddClass('AddImageBtn'+curThreadID,'SpinBtn');
}

function ImageFileUploaded(response) {
	RemoveClass('AddImageBtn'+curThreadID,'SpinBtn');
	if (response.indexOf('ERROR:') >= 0) {
		alert(response);
		return;
	}
	var fields = response.split("\t");
	if (fields[0] != 'OK') {
		alert('Server-side error: '+response);
		return;
	}
	InsertHTML('<img src="/attach/'+fields[1]+'">');
}

function UploadAndAttachFile(files) {
	if (files.length==0) return;	
	if (files[0].size>3*1024*1024) {
		alert('File is too large! Max 3MB!'); return;
	}
	if (attachments.split(';').length>4) {
		alert('Too many files!'); return;
	}
	var reader=new FileReader();
	var fileName=files[0].name;
	var fileSize=files[0].size;
	var fd=new FormData;
	fd.append('File',files[0]);
	ajax.Request('/attach','',AttachedFileUploaded,fd);
	AddClass('AttachBtn'+curThreadID,'SpinBtn');
}

function AppendAttachment(uploads, id, filetype, filename, thumbnail, tWidth, tHeight) {
	var node = d.createElement('span');
	node.setAttribute('id', 'ATTACH' + id);
	thumbnail=thumbnail.replace('/attach/','');
	filename=filename.replace('/attach/','');
	node.innerHTML = '<a href="/attach/' + id + '.' + filetype + '" target=_blank><img src="/attach/' + thumbnail +
		'" class=attached width=' + tWidth + ' height='+tHeight+' alt="' + filename + '" title="' + filename + '"></a>' +
		'<img src="/img/delbtn.gif" class=delAttach onClick="DeleteAttach(' + id + ')" valign=top alt="Remove" title="Remove">';
	uploads.appendChild(node);
	attachments = attachments+id+';';	
}

function AttachedFileUploaded(response) {
	RemoveClass('AttachBtn'+curThreadID,'SpinBtn');
	if (response.indexOf('ERROR:') >= 0) {
		alert(response);
		return;
	}
	var fields = response.split("\t");
	if (fields[0] != 'OK') {
		alert('Server-side error: '+response);
		return;
	}
	var uploads = d.getElementById('uploads' + curThreadID);
	if (uploads) {
		uploads.style.display = 'block';
		AppendAttachment(uploads, fields[1], fields[2], fields[3], fields[5], fields[6], fields[7]);
	}
}

function DeleteAttach(id) {
	node = d.getElementById('ATTACH' + id);
	if (node)
		node.parentNode.removeChild(node);
	attachments = attachments.replace(id + ';', '');
	if (attachments == '')
		d.getElementById('uploads' + curThreadID).style.display = 'none';
}

var deckList;

function InsertDeck(btn) {
	if (deckList) {
		DeleteElement(deckList);
		deckList=null;
		return;
	}
	deckList=d.createElement('div');
	deckList.setAttribute('class','DeckList InnerScrollbar');
	var editor=d.getElementById('EDITOR'+curThreadID);
	editor.appendChild(deckList);
	var bPos=GetElementPos(btn,'ForumMain');
	deckList.style.left=(bPos.x-8)+'px';
	deckList.style.top=(bPos.y+28)+'px';
	deckList.innerHTML='<img src="/img/loader_bar.gif" style="margin:6px">';
	ajax.Request('/GetDeckList','',DeckListLoaded);
}

function DeckListLoaded(response) {
	if (deckList) {
		var lines=response.split("\t");
		if (lines[0] != 'OK') {
			deckList.innerHTML=(lines.length>1)? lines[1] : lines[0];
			return;
		}
		// name|content|price|...
		var list='';
		var cnt=0;
		for (var i=1;i<lines.length;i+=3) {
			list=list+'<tr onClick="InsertDeckBlock(this)" data="'+lines[i+1]+'"><td>'+lines[i]+'<td>'+lines[i+2];
			cnt++;
		}
		deckList.innerHTML='<table class="DeckListTable SmallFont" cellpadding=0 cellspacing=0>'+list+'</table>';
		if (cnt>8) cnt=8;
		deckList.style.height=(2+cnt*20)+'px';
	}
}

function InsertDeckBlock(obj) {
	var data=obj.getAttribute('data');
	data=data.split(',');
	var name=obj.children[0].innerHTML;
	var price=obj.children[1].innerHTML;
	var deck='<div align=center>'+name+' ('+price+')'+'</div>';
	for (var i=0;i<data.length;i++) {
		var items=data[i].split('x');
		deck=deck+'<div>'+items[0]+' x '+cardList[items[1]].name+'</div>';
	}
	InsertHTML('<div class="MainFont DeckBlock" cellpadding=1 cellspacing=0>'+deck+'</div>');
	InsertDeck();
}

// Исправляет всякие гадости в текущем редакторе
function ValidateDOM(element) {
	var validTags=['body','div','span','p','br','blockquote','strong','em','ul','ol','li','tt','a','h2','h3','h4','h5','b','i','u','s','del','img','pre','time'];
	var validAttr=['class','title','href','src','target','align','valign','id','alt','style','width','height','border'];
	var validStyle=['fontWeight','fontFamily','width','height'];
	var c=element.children;
	var i=0;
	while (i<c.length) {
		if (!ValidateDOM(c[i])) i++;
	}
	
	if (element.nodeType != 1) return;
	if (validTags.indexOf(element.nodeName.toLowerCase())<0) {
		var childNodes=element.childNodes;
		for (i=0;i<childNodes.length;i++) 
			element.parentNode.insertBefore(childNodes[i],element);
		element.parentNode.removeChild(element);
		return true;
	}		
	var a=element.attributes;	
	i=0;
	while (i<a.length) {
		if (validAttr.indexOf(a[i].name.toLowerCase())<0) 
			element.removeAttribute(a[i].name);
		else 
			i++;
	}
	
	// External image?
	
	// Ensure the last node is not quote
	var el=edoc.body.lastChild;
	if ((!el) || (el.nodeName.toLowerCase()=='blockquote')) {
		var spacer = edoc.createElement('div');
		spacer.innerHTML = '&nbsp;';
		edoc.body.appendChild(spacer);
	}
	return false;
}

// отслеживает изменения в текущем редакторе
var lastThreadID=0;
var lastEdocContent='';
function MonitorMsgEditor() {
	setTimeout(MonitorMsgEditor,50); // 
	try {
		// editor closed?
		if (!edoc) { 
			lastThreadID=0;
			lastEdocContent='';
			return;
		}
		// switched to another thread?
		if (lastThreadID != curThreadID) { 
			lastThreadID=curThreadID;
			ValidateDOM(edoc.body);
			lastEdocContent=edoc.body.innerHTML;
			ShowElement('AddQuotePopup',0);			
			return;
		}
		// Content changed?
		if (lastEdocContent != edoc.body.innerHTML) {
			ValidateDOM(edoc.body);
			lastEdocContent=edoc.body.innerHTML;			
			// mark as modified
			if (edoc.title.indexOf('(*)')<0) 
				edoc.title=edoc.title+' (*)';
		}
		// active text selection?
		var pos=GetSelectionCoords();
		var txt=GetSelectionText();
		if ((txt.length>3) && (pos.x>0)) {
			SetElementPos('AddQuotePopup',{ left: pos.x, top: pos.y-28});
			ShowElement('AddQuotePopup',1);			
		} else 
			setTimeout(ShowElement,200,'AddQuotePopup',0);

	} catch (e) {	
		alert(e);
	}
}

// Make links clickable
function LinkifyMessage(node) {
	if (node.nodeName == 'A') return;
	var c=node.childNodes;
	var i=0;
	while (i<c.length) {
		LinkifyMessage(c[i]);
		i++;
	}
	if (node.nodeType == 3) { // text node
		var txt=node.nodeValue;
		if (txt.match(/(\w+:\/\/|www\.)([\@\w\d\/\.,\-=_?&#\%+]+)/i)) {
			var st1=RegExp.leftContext;
			var st2=RegExp.rightContext;
			var url=RegExp.$1+RegExp.$2;
			var link=edoc.createElement('a');
			link.setAttribute('href',(url.match(/http/i)? '':'http://')+url);
			link.setAttribute('target','_blank');
			link.innerHTML=url;
			node.parentNode.insertBefore(link,node);
			var node1=edoc.createTextNode(st1);
			var node2=edoc.createTextNode(st2);
			if (st1 != '') node.parentNode.insertBefore(node1,link);
			node.parentNode.replaceChild(node2,node);
		}
	}	
}

// послать сообщение на сервер
function ForumPostMessage() {
	LinkifyMessage(edoc.body);
	var msgtext = edoc.body.innerHTML;
	var threadID = curThreadID;
	var data = 'topic=' + threadID + '&msg=' + encodeURIComponent(msgtext);
	var sub=0;
	if (d.getElementById('subscribe'+threadID+'a').checked) sub=1;
	if (d.getElementById('subscribe'+threadID+'b').checked) sub=2;	
	data=data+'&sub='+sub;
	localStorage.setItem('subscribeMode',(sub>0)? 'Y' : 'N');
	
	if (attachments != '')
		data = data + '&att=' + encodeURIComponent(attachments);
	var re = /<blockquote.*?>([\s\S]*?)<\/blockquote>/i;
	var tmp = msgtext;
	var quoted = '';
	while (tmp.match(re)) {
		quoted = quoted + RegExp.$1;
		tmp = tmp.replace(re, '');
	}
	tmp = tmp.replace(/<.*?>/gi, '');
	quoted = quoted.replace(/<.*?>/gi, '');
	if (quoted.length > tmp.length * 1.5 + 300)
		if (!confirm(str.Overquoted))
			return;

	if (threadID == 0) {
		// Create a new thread with this post
		var obj = d.getElementById('topic_lang');
		var tlang = (obj) ? obj.value : 'En';
		var title = d.getElementById('topic_title').value;
		if (title.length < 5) {
			ShowElement('status' + threadID, 1);
			SetElementText('statuscell' + threadID, str.BadTopicTitle);
			d.getElementById('statuscell' + threadID).focus();
			return;
		}
		data = data + '&title=' + encodeURIComponent(title) + '&ch=' + curChapter + '&lang=' + tlang;
		if (curChapter==6) 
			if (d.getElementById('GuildPrivT').checked) data=data+'&guildPrivate=1';
	} else {
		// existing message?
		if (editedMsgID > 0)
			data = data + '&msgID=' + editedMsgID;
	}
	ShowElement('status' + threadID, 1);
	SetElementText('statuscell' + threadID, str.PleaseWait);
	ajax.Request('/postmsg', 'Sending message text...', 'MessagePosted(' + curThreadID + ')', data);
}

function MessagePosted(threadID) {
	var response = ajax.response;
	var idx = response.indexOf('\r\n');
	if (idx < 0) {
		// Single line = error
		SetElementText('statuscell' + threadID, '<span style="color:#C00">' + response + '</span>');
		return;
	}
	var line = response.slice(0, idx);
	if (line.indexOf('OK') < 0) {
		SetElementText('statuscell' + threadID, '<span style="color:#C00">Server error, sorry!</span>');
		return;
	}
	response = response.slice(idx + 2);
	idx = response.indexOf('\r\n');
	var status = (response.slice(0, idx)).split(';');
	var threadID = status[0];
	var msgID = status[1];
	if (!d.getElementById('thread' + threadID)) {
		FollowVirtualLink(location.pathname.substr(0, 3) + '/forum/thread/' + threadID);
		return;
	}
	response = response.slice(idx + 2);
	var re = /<div.*?>([\s\S]*)<\/div>/i;
	var html = '';
	if (response.match(re)) {
		html = RegExp.$1;
	}
	var obj = d.getElementById('FMSG' + msgID);
	if (obj) {
		// Update existing message
		obj.innerHTML = html;
		CloseMsgEditor();
	} else {
		obj = d.getElementById('TSPLIT' + threadID);
		var item = d.createElement('div');
		item.setAttribute('id', 'FMSG' + msgID);
		obj.parentNode.insertBefore(item, obj);
		item.innerHTML = html;
		CloseMsgEditor();
	}
}

// mode: 1 - show "Reply", 2 - show "Quote"
function ToggleReplyButtons(threadID,mode) {
	var list=d.getElementsByName('BTNR'+threadID);
	for (var i=0;i<list.length;i++) list[i].style.display=(mode==1)? 'inline':'none';
	list=d.getElementsByName('BTNQ'+threadID);
	for (var i=0;i<list.length;i++) list[i].style.display=(mode==2)? 'inline':'none';
}

function CloseMsgEditor(manual) {
	if (deckList) deckList = null;
	if (edoc) {
		if (manual && (edoc.title.indexOf('(*)')>=0)) 
			if (!confirm(str.MessageChanged)) return;
		edoc.body.innerHTML='';
		edoc = null;
		editedMsgID = 0;
		attachments = '';
		SetElementText('EDITOR' + curThreadID, '');
		var addbtn = d.getElementById('ADDBTN' + curThreadID);
		if (addbtn)
			addbtn.style.display = 'block';
		ToggleReplyButtons(curThreadID,1);
		ShowElement('AddQuotePopup',0);
	}
}

function ForumEditorBtnClick(btn) {
	if (!edoc) return;
	var cmd=btn.getAttribute('cmd');
	if (cmd==1) edoc.execCommand('bold',false,'');
	if (cmd==2) edoc.execCommand('italic',false,'');
	if (cmd==3) edoc.execCommand('underline',false,'');
	if (cmd==4) ShowElement('SMILESBAR'+curThreadID,-1);
	if (cmd==5) d.getElementById('UploadImageFile'+curThreadID).click();
	if (cmd==6) d.getElementById('UploadAndAttachFile'+curThreadID).click();
	if (cmd==7) InsertDeck(btn);
}

// Insert HTML code at the currend editor pos
function InsertHTML(code) {
	var wnd = edoc.parentWindow;
	if (!wnd)
		wnd = edoc.defaultView;
	wnd.focus();
	var range;
	if (edoc.selection) {
		range = edoc.selection.createRange();
		range.pasteHTML(code);
	} else {
		range = wnd.getSelection().getRangeAt(0);
		range.deleteContents();
		var node = edoc.createElement('span');
		node.innerHTML = code;
		range.insertNode(node);
	}
}

function InsertSmile(name, title) {
	InsertHTML('<img class=smile src="/img/smiles/' + name + '.gif" valign=middle title="' + title + '">');
}

var markReadTimer = 10;
var lastReadMsgId = []; // threadID -> LastRead
var lastSentMsgId = []; // stored info (in DB)
var lastReadInitialInfo = [];

function ForumMarkMessagesRead() {
	setTimeout(ForumMarkMessagesRead, 500);

	if (markReadTimer > 0)
		markReadTimer--;
	if (markReadTimer == 0) {
		var arr = [];
		lastReadMsgId.forEach(function (item, index) {
			if ((!lastSentMsgId[index]) || (item > lastSentMsgId[index])) {
				arr.push('T' + index + '=' + item);
				lastSentMsgId[index] = item;
			}
		});
		if (arr.length > 0) {
			ajax.Request('/markread.cgi?' + arr.join('&'), '', 'HandleMarkRead()', '');
			markReadTimer = 10;
		}
	}

	if ((curMenuItem == 'Forum') && (curThreadID > 0)) {
		var container = d.getElementById('thread' + curThreadID);
		if (!container)
			return;
		var items = container.children;
		var maxY = window.innerHeight + window.scrollY - 30;
		for (var i = 0; i < items.length; i++) {
			var item = items[i];
			if (item.id.match(/FMSG(\d+)/)) {
				var msgid = Number(RegExp.$1);
				if ((!lastReadMsgId[curThreadID]) || (msgid > lastReadMsgId[curThreadID])) {
					var pos = GetElementPos(item);
					if (pos.y + item.clientHeight < maxY)
						lastReadMsgId[curThreadID] = msgid;
				}
			}
		}
	}
}

function HandleMarkRead() {}

function CreateThread() {
	DeleteElement('thread0'); // always reload
	FollowVirtualLink(location.href + '/new');
}

function InitForum() {
	if (lastReadInitialInfo.length > 1) {
		var n = lastReadInitialInfo.length / 2;
		for (var i = 1; i < n; i++) {
			lastSentMsgId[lastReadInitialInfo[i * 2 - 1]] = lastReadInitialInfo[i * 2];
		}
	}
}

function RateMessage(item) {
	if (userID == 0) {
		alert('You need to log in to access this feature');
		return;
	}
	var value = (HasClass(item,'VoteUp')) ? 2 : -1;
	var id = 0;
	var parent = item.parentElement;
	while (parent) {
		if (parent.id.match(/FMSG(\d+)/)) {
			id = RegExp.$1;
			break;
		}
		parent = parent.parentElement;
	}
	ajax.Request('/ratemsg.cgi?msg=' + id + '&value=' + value, '', 'MessageRatingUpdated(' + id + ')', '');
}

function MessageRatingUpdated(msgID) {
	var response = ajax.response;
	if (response.match('==')) {
		alert(str.alreadyRated);
		return;
	}
	if (response.match('--')) {
		alert(str.ownPostRated);
		return;
	}
	if (response.match(/(-?\d+)/)) {
		var r = RegExp.$1;
		var item = d.getElementById('MSGRATE' + msgID);
		item.innerHTML = r;
	}
}

function ModThread(threadID) {
	ShowWindow('ModThreadWindow');
	LoadFileToElement('/modtopic.cgi?t=' + threadID, 'ModThreadMain');
}

function ModThreadApply() {
	var trID = d.getElementById('ModThreadID').value;
	var trTitle = d.getElementById('ModThreadTitle').value;
	var trCh = d.getElementById('ModThreadCh').value;
	var trLang = d.getElementById('ModThreadLang').value;
	var trFlags = '';
	for (var i = 1; i <= 5; i++) {
		var obj = d.getElementById('ModThreadFlag' + i);
		if (obj.checked)
			trFlags = trFlags + '&' + obj.name;
	}
	var url = '/modtopic.cgi?update&t=' + trID + '&ch=' + trCh + '&title=' + trTitle + '&lan=' + trLang + trFlags;
	ajax.Request(url, '', function (resp) {
		SetElementText('ModThreadMain', resp);
	});
}

// Search 
// ----------------------------
var searchBarVisible=false;
function SearchBar() {
	var bar = d.getElementById('SearchBar');
	var input = d.getElementById('SearchInput');
	searchBarVisible = !searchBarVisible;
	if (searchBarVisible) {
		//SetElementText('SearchResults','');		
		if (mainMode) 
			bar.style.top = '-36px';
		else
			bar.style.top = '-82px';
		input.focus();
		AddClass('MenuSearchItem','MenuCurrent');
	} else {
		//SetElementText('SearchResults','');				
		bar.style.top = -bar.clientHeight+'px';			
		//input.value='';
		input.blur();
		RemoveClass('MenuSearchItem','MenuCurrent');
	}
}

function Search(response) {
	if (response) {
		SetElementText('SearchResults',response);		
		return;
	}
	var query=d.getElementById('SearchInput').value;
	if ((!searchBarVisible) || (query=='')) return;
	SetElementText('SearchResults','<img src="/img/loader_bar.gif" style="margin:10px;">');
	ajax.Request('/search?q='+encodeURIComponent(query)+'&cnt=6','',Search);
}

function BuyPremium(item) {
	var url='https://astralheroes.com/checkout.cgi?item='+item+'&acc='+encodeURIComponent(userName)+'&lang='+userLang;
	window.open(url);
}

// Card description hints
// -------------------------
function ShowCardHint(element,cardID) {
	var obj=d.getElementById('CardHint');
	if (obj) {
		var pos=GetElementPos(element);
		var desc=cardList[cardID].desc;
		desc=desc.replace(/~/g,'<br>');
		obj.innerHTML='<table cellpadding=0 cellspacing=0><tr><td style="width:64px; border:1px solid #986; '+
		 'background-image:url(\'/img/card/'+cardList[cardID].file+'.jpg\'); background-positon: center; background-size:cover"><div style="min-height:80px"></div>'+
		 '<td valign=top style="padding:0px 6px 0px 8px"><div class=MainFont style="color:#600; text-shadow:1px 1px 0px #ba9;"><b>'+
		 cardList[cardID].name+'</b></div>'+desc+'</table>';
		obj.style.top=(pos.y+pos.height+1)+'px';
		if (pos.x+450>window.innerWidth) pos.x=window.innerWidth-450;
		obj.style.left=(pos.x-8)+'px';
		ShowElement(obj,1);
	}
}

function HideCardHint() {
 ShowElement('CardHint',0);
}

// Misc
// ---------------------
function ShowWindowWithPage(title,pagename) {
	SetElementText("JustWindowTitle",title);
	SetElementText("JustWindowContent",'');
	ajax.Request('/getpage?p='+pagename,'','SetElementText("JustWindowContent",ajax.response);');
	ShowWindow('JustWindow');
}