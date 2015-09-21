/* обработка комментов */
var COMMENTS_URL = '/comments2';

function lazyCaptcha(obj) {
	if (typeof $(obj).attr('captcha_gen') != 'undefined')
		return;
	var form = $(obj).parents('form');
	
	genCaptcha(form);
	$(obj).attr('captcha_gen', 1);
	form.find('div[name=comments_need_captcha]').show();
}

function checkCaptchaLen(obj) {
	if ($(obj).val().length > 3)
		$(obj).parents('form').find('input[name=submitter]').attr('disabled', '');
}

function genCaptcha(obj){
	$.get("/captcha/generate/" + '?' + Math.random(), null, function(data){
			if (data == null)
				return;

			obj.find('input[name=captcha_id]').val(data.captcha_id);
			obj.find('img[name=captcha_img]').attr('src', '/captcha/' + data.captcha_id + '/');
		}, "json");
}

function addComment(obj, reload_page){
	$(obj).find(':submit').attr('disabled', 'disabled');
	$(obj).find('[name=load_notice]').show();
	
	$.post(COMMENTS_URL + '/add', $(obj).serialize(),
		function(data){
			$(obj).find(':submit').attr('disabled', '');
			$(obj).find('span[name=load_notice]').hide();
			$(obj).find("p[name=comments_message]").hide();
			$(obj).find("p[name=comments_error]").hide();
			genCaptcha( $(obj) );
			
			if (data == null){
				$(obj).find("p[name=comments_error] span").text('сбой сервера комментов');
				$(obj).find("p[name=comments_error]").fadeIn('slow').delay(10000).fadeOut('slow');
				return;
			}
			
			if (data.err_code == 0){
				if (! data.is_auth){
					//если пользователь не залогинен - редирект на swa
					window.location.replace(
							'http://swa.mail.ru/cgi-bin/auth?Login='+data.email+'&Password='+data.passwd+
							'&Page='+window.location.href
						);
					return;
				}//end if
				
				$(obj).find("input[type=text], textarea").val('');
				$(obj).find("p[name=comments_message]").text(data.err_msg);
				$(obj).find("p[name=comments_message]").fadeIn('slow').delay(2000).fadeOut('slow');
				
				//для нового коммента всегда перегружаем страничку
				if (reload_page) {
					window.location.assign(
						window.location.protocol + '//' + window.location.host + window.location.pathname + 
							'?last_page=1&comment_id=' + data.comment_id + '#comment_' + data.comment_id
						);
					return;
				}//end if
				
				//обновить список комментов
				loadComments();
			} else {
				$(obj).find("p[name=comments_error] span").text(data.err_msg);
				$(obj).find("p[name=comments_error]").fadeIn('slow');
			}
		}, "json");
	
	return false;
}//end func

function replyComment(comment_id) {
	var reply_form = $('#reply_form').contents().clone();
	var comment_key = '#comment_' + comment_id; 
	$(comment_key).find('.comment_visible .b-links').hide();
	//genCaptcha(reply_form);
	reply_form.find("a[name=close_reply]").bind('click', function() {
		$(comment_key).find('.comment_visible .b-links').show();
		reply_form.remove();
  		return false;
	});
	reply_form.find("input[name=pcomment_id]").val(comment_id);
	$(comment_key).append(reply_form);

	return false;
}

function showHint(id){
	$('#hint_' + id).show();
	return false;
}

function hideHint(id){
	$('#hint_' + id).hide();
	return false;
}

function loadComments(){
	var comments_url = COMMENTS_URL + '/' + comments_atr + '/' + comments_id_stat + '/' + 
			comments_realm + '/' + window.location.search;
	
	$.get(comments_url, function(data){
			if (data == null)
				return;
			$('#comments_body').html(data);

			if (comment_id != null)
				$(document).scrollTop( $('#comment_' + comment_id).offset().top );
		});
}

function confirm_dialog(obj, dialog_name, message) {
	var dialog = $("<div/>");
	$('#' + dialog_name).remove();
	dialog.attr('id', dialog_name);
	dialog.addClass("del_min");
	dialog.html(
			"<p>" + message + "<br/><br/>" +
			"<input name='confirm' type='button' value=' Да '>&nbsp;&nbsp;" +
			"<input name='reject'  type='button' value=' Нет '></p>"
		);
	dialog.find("input[name=reject]").bind('click', function() {
		dialog.remove();
	});
	$(obj).parent().append(dialog);
	return dialog;
}

function banUser(obj, email, callback){
	if (callback == null)
		callback = loadComments;

	var dialog = confirm_dialog(
			obj,
			'confirm_ban',
			"Добавить пользователя '" + email + "' в Черный список?"
		);
	dialog.find("input[name=confirm]").bind('click', function() {
		$.post(
				COMMENTS_URL + '/ban_user',
				{
					'email' : email,
					'realm' : comments_realm
				},
				function(data){
					if (data == null){
						dialog.html("<p>Ошибка бана пользователя '" + email + "'</p>");
					} else if (data.err_code == 0){
						dialog.remove();
						callback(); //обновить список комментов
					} else {
						dialog.html('<p>Ошибка: ' + data.err_msg + '</p>');
					}
				},
				"json"
			);
	});
	
	return false;
}

function unbanUser(obj, email, callback){
	if (callback == null)
		callback = loadComments;
		
	var dialog = confirm_dialog(
			obj,
			'confirm_unban',
			"Удалить пользователя '" + email + "' из черного списка?"
		);
	dialog.find("input[name=confirm]").bind('click', function() {
		$.post(
				COMMENTS_URL + '/unban_user',
				{
					'email' : email,
					'realm' : comments_realm
				},
				function(data){
					if (data == null){
						dialog.html("<p>Ошибка разбана пользователя '" + email + "'</p>");
					} else if (data.err_code == 0){
						dialog.remove();
						callback(); //обновить список комментов
					} else {
						dialog.html('<p>Ошибка: ' + data.err_msg + '</p>');
					}
				},
				"json"
			);
	});
	
	return false;
}

function delComment(obj, comment_id, post_id, callback){
	if (post_id == null)
		post_id = comments_post_id;

	if (callback == null)
		callback = loadComments;

	var dialog = confirm_dialog(
			obj,
			'confirm_del',
			"Удалить комментарий?"
		);
	dialog.find("input[name=confirm]").bind('click', function() {
		$.post(
				COMMENTS_URL + '/del',
				{
					'comment_id' : comment_id,
					'realm'      : comments_realm,
					'post_id'    : post_id
				},
				function(data){
					if (data == null){
						dialog.html("<p>Ошибка удаления комментария</p>");
					} else if (data.err_code == 0){
						dialog.remove();
						callback(); //обновить список комментов
					} else {
						dialog.html('<p>Ошибка: ' + data.err_msg + '</p>');
					}
				},
				"json"
			);
	});
	
	return false;
}

function hideComment(comment_id){
	$('#comment_' + comment_id + ' .comment_visible').hide();
	$('#comment_' + comment_id + ' .comment_hidden').show();
	
	key_part = comments_post_id + '_' + comment_id;
	key = $.cookie('comments_hide') || '';
	if (key.indexOf(key_part) != -1)
		return false;
		
	//store new hidden comment
	key += ((key.length > 0) ? ',' : '') + key_part;
	$.cookie('comments_hide', key, {
			expires: 14,
			path: '/'
		});
	
	$.post(
			COMMENTS_URL + '/hide',
			{
				'comment_id' : comment_id,
				'post_id'    : comments_post_id
			},
			function(data){
				if (data == null || data.err_code != 0){
					alert("Ошибка обработки скрытия комментария");
				}
			},
			"json"
		);

	return false;
}

function showComment(comment_id){
	$('#comment_' + comment_id + ' .comment_visible').show();
	$('#comment_' + comment_id + ' .comment_hidden').hide();
	
/*
key_part = comments_post_id + '_' + comment_id;
	key = $.cookie('comments_hide') || '';

	$.cookie(
			'comments_hide',
			key.replace(new RegExp(key_part + ',?', 'g'), ''),
			{
				expires: 14,
				path: '/'
			}
		);
*/
		
	return false;
}

function editComment(comment_id, post_id){
	var comment_key  = post_id + '_' + comment_id;
	$.get(
			COMMENTS_URL + '/get',
			{
				comment_id: comment_id,
				post_id: post_id
			},
			function(data){
				if (data == null)
					return;

				$textarea = $('<textarea></textarea>').css({width : '80%', height: '200px'}).attr('id', 'body_' + comment_key).val(data.comment_body);
				$button = $('<input type="button">').val('Сохранить').click(function(){
								updateComment(this, comment_id, post_id);
							});

				$('#comment_' + comment_key).html($textarea).append('<br/>', $button);
			},
			"json"
		);
	return false;
}

function updateComment(button, comment_id, post_id){
	var comment_key  = post_id + '_' + comment_id;
	comment_body = $('#body_' + comment_key).val();
	$(button).attr('disabled', true);
	
	$.post(
			COMMENTS_URL + '/update',
			{
				comment_id: comment_id,
				post_id: post_id,
				comment_body: comment_body
			},
			function(data){
				if (data == null)
					return;
				if (data.err_code != 0)
					alert('Ошибка редактирования комментария');

				$('#comment_' + comment_key).html(data.comment_body);
			},
			"json"
		);
	return false;
}

function delUserComments(obj, email, callback){
	if (callback == null)
		callback = loadComments;

	var dialog = confirm_dialog(
			obj,
			'confirm_ban',
			"Удалить все комментарии пользователя '" + email + "'?"
		);
	dialog.find("input[name=confirm]").bind('click', function() {
		$.post(
				COMMENTS_URL + '/del_user_comments',
				{
					'email' : email,
					'realm' : comments_realm
				},
				function(data){
					if (data == null){
						dialog.html("<p>Ошибка удаления комментариев пользователя '" + email + "'</p>");
					} else if (data.err_code == 0){
						dialog.remove();
						callback(); //обновить список комментов
					} else {
						dialog.html('<p>Ошибка: ' + data.err_msg + '</p>');
					}
				},
				"json"
			);
	});
	
	return false;
}
