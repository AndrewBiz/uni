
function showPortalMenu(_a) {
	clearPortalMenuTimer();
    
    if (document.getElementById("portalMenu").style.display == "block") {
        document.getElementById("portalMenu").style.display = "none"
    }
    else {
    	document.getElementById("portalMenu").style.display = "block";
    }

	return false;
}
// Mouseout
var portalMenuTimer = null;
var portalMenuOutInterval = 300;
function clearPortalMenuTimer() {
	clearTimeout(portalMenuTimer);
	portalMenuTimer = null;
}
function portalMouseOutHandler(yep) {
	if (!yep) {
		portalMenuTimer = setTimeout("portalMouseOutHandler(1)", portalMenuOutInterval);
		return;
	}
	document.getElementById("portalMenu").style.display = "none";
}


function showRSSMenu(_a) {
	clearRSSMenuTimer();
    
    if (document.getElementById("rssMenu").style.display == "block") {
        document.getElementById("rssMenu").style.display = "none"
    }
    else {
    	document.getElementById("rssMenu").style.display = "block";
    }

	return false;
}
// Mouseout
var rssMenuTimer = null;
var rssMenuOutInterval = 300;
function clearRSSMenuTimer() {
	clearTimeout(rssMenuTimer);
	rssMenuTimer = null;
}
function rssMouseOutHandler(yep) {
	if (!yep) {
		rssMenuTimer = setTimeout("rssMouseOutHandler(1)", rssMenuOutInterval);
		return;
	}
	document.getElementById("rssMenu").style.display = "none";
}