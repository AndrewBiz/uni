var rb_rnd = Math.round(Math.random() * 1000000000);
var rb_vars_arr = Array();
for (var n=1; true; n++)
  if (typeof(window['rb_link'+n]) != 'undefined' && window['rb_link'+n] != null) {
    rb_vars_arr.push('link'+n+'='+escape(window['rb_link'+n]).replace(/\\+/g,'%2B'));
    window['rb_link'+n] = null;
  }
  else
    break;
for (var n=1; true; n++)
  if (typeof(window['rb_video'+n]) != 'undefined' && window['rb_video'+n] != null) {
    rb_vars_arr.push('video'+n+'='+escape(window['rb_video'+n]).replace(/\\+/g,'%2B'));
    window['rb_video'+n] = null;
  }
  else
    break;
var rb_vars = rb_vars_arr.join('&');
document.write('<object classid="clsid:D27CDB6E-AE6D-11cf-96B8-444553540000" codebase="http://active.macromedia.com/flash2/cabs/swflash.cab#version='+rb_fver+',0,0,0" id="getmov'+rb_rnd+'" width="'+rb_width+'" height="'+rb_height+'"><param name="movie" value="'+rb_swf+'" /><param name="quality" value="high" /><param name="wmode" value="opaque" /><param name="FlashVars" value="'+rb_vars+'" /><embed name="embed_getmov'+rb_rnd+'" flashvars="'+rb_vars+'" src="'+rb_swf+'" quality="high" wmode="opaque" width="'+rb_width+'" height="'+rb_height+'" type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/shockwave/download/index.cgiP1_Prod_Version=ShockwaveFlash" /></object>');
