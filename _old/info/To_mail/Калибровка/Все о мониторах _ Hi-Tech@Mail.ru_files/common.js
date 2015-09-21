$(document).ready(function(){
    /* Открыть/Закрыть панель поиска */
    $('#toolbar-opener').click(showHideToolbar);
    $('#toolbar-helper a').click(function(){return showHideToolbar.apply($('#toolbar-opener'))});
     /* Действия с формой */
    $('#f_undo').click(function(){
        showHideToolbar.apply($('#toolbar-opener'));
        return false;
    });
    $('#f_reset').click(function(){
       $('#f_reset_form').val('1');
        $('#toolbar_form')[0].submit();
        return false;
    });
    /* Ошибка в тексте */
    $(document).keypress(catchKey);
});

function showHideToolbar(){
    var $obj = $(this); // link
    var $toolbar_settings = $('#toolbar_settings');
    var $toolbar = $('#toolbar');
    $toggle  =  $('#toggle_settings');
    if ($obj.hasClass('open')) {
        $toolbar_settings.addClass('hidden');
        $toolbar.removeClass('hidden');
        $obj.removeClass('open');
        $toggle.removeClass('b-settings').addClass('b-setfooter');
    }
    else {
        $toolbar_settings.removeClass('hidden');
        $toolbar.addClass('hidden');
        $obj.addClass('open');
        $toggle.removeClass('b-setfooter').addClass('b-settings');
    }
    return false
}

function ToggleCheckbox(ele, container, class_on){
        $ele = $(ele);
        klass = $ele[0].className;
        all_controll = $('#' + klass + "_all").attr('checked', ' ').parents('li').removeClass('on');
        if ($ele.attr('checked')) {
            $ele.parents(container).addClass(class_on);
        }
        else {
            $ele.parents(container).removeClass(class_on);
        }
        return false;
}
function ToggleCheckboxAll(ele, control_group, group_class_on){
        $ele = $(ele);
        control_group = $('input.' + control_group);
        if ($ele.attr('checked')) {
            $ele.parents('li').addClass('on');
            control_group.attr('checked', false).parents('.' + group_class_on).removeClass(group_class_on);
        }
        else {
            $ele.parents('li').removeClass('on');
        }
        return false;
}

function ToggleDateSelect(select){
    $obj = $(select);
    selected_value = $obj.val();
    if (selected_value == 4){
        $('#f_month').removeClass('hidden');
        $('#f_year').addClass('hidden');
    } else if (selected_value == 5){
        $('#f_month').addClass('hidden');
        $('#f_year').removeClass('hidden');        
    } else {
        $('#f_month,#f_year').addClass('hidden');
    }
   
}

function LoadMore(link){
    url = $(link).attr('href');
    current_loader = $('#loadNext');
    $.get(url, { _rnd: (new Date).valueOf() },
    function(response){
        if (response && response.lenght == 0) {
            alert('Произошла непредвиденная ошибка!');
            return;
        }
        html = response;
        $('#items_container').append(html);
        current_loader.remove();
    });
    return false;
}

function deleteFromCompare(link){
    /* Удалить из сравнения */
    $link = $(link);
    model_id = $link.attr('rev');
    if (model_id) {
        $.get('/catalog/compare/del/', { model_id: model_id}, function(response){
            if (response.lenght == 0 || !/^OK/.test(response)){
                // не удалили элемент
                return;
            }       
            // Удаляем элемент из корзины
            $('#compare_item_' + model_id).remove();
            if ($('#compare .b-idevice').size() == 0){ $('#compare_container').addClass('hidden'); }
            //  Если кликнули по ссылке из списка, то меняем ее 
            target_link = $link.hasClass('remove') ? $link : $('#compare_remove_' + model_id);
            // console.log('target: %o', target_link);
            if (target_link[0]){
                 target_link.attr('onclick','').unbind('click').click(function(){
                    return addToCompare(this)
                });
                target_link.removeClass('remove').addClass('add').attr('id', '');
                target_link[0].innerHTML = '<img src="/img/button_add.png" class="icon png"/>Добавить к сравнению';           
            }
           
        });
    }
    return false;
}


function Showpage(act, event, w, h){
	var FrontWin = window.open(act,"ShowpageSite",'width='+w+',height='+h+',location=no,resizable=1,scrollbars=yes,menubar=no,status=yes' );
    FrontWin.focus();
	return FrontWin;
}

/* Mistake */
function catchKey (event) {
	if (window.event)
		event = window.event;
	if (event.ctrlKey && event.keyCode ==13 || (event.keyCode==10))
		if (document.getSelection || document.selection.createRange().text) {
			if (document.getSelection && !document.getSelection().length)
				return;
            // use thickbox to show form
			tb_show("Сообщить об ошибке", "/mistake/?width=450&height=290");
        }
}

/* comment's count */
function countComments(id){
	var count = window['c_item_id_' + id]; 

	if (count)
		$('a[name=item_id_' + id + ']').text(count);
	else
		$('.b-balloon[name=balloon_item_id_' + id + ']').hide();
}
