<?php
require_once('callback_lib.php');

function smarty_function_mtinittemplatecallback($args, &$ctx) {
	$postfix = $args['screen'];

    $vars =& $ctx->__stash['vars'];
    if (!isset($vars)) {
        $ctx->__stash['vars'] = array();
        $vars =& $ctx->__stash['vars'];
    }

	$vars['callback_postfix'] = $postfix;
    $_callback_registry =& _init_template_callbacks($ctx);

    $blog_id = $ctx->stash('blog_id');
    $theme_data = $ctx->mt->db()->fetch_plugin_data('TemplateCallback', 'configuration:blog:'.$blog_id);
    if (!empty($theme_data)) {
        foreach ($theme_data['vars'] as $key => $rec) {
            $vars[$key] = $rec['value'];
        }
    }

	return '';
}

?>