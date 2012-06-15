<?php

function __handle_widgetset($args, &$ctx) {
    // require_once('callback_lib.php');
    // require_once('function.mttemplatecallback.php');
    $blog_id = $args['blog_id'];
    $blog_id or $blog_id = $ctx->stash('blog_id');
    $blog_id or $blog_id = 0;
    $widgetmanager = $args['name'];
    $cb_name = $args['callback'];
    if (!$widgetmanager || !$cb_name) 
        return;
    $tmpl = $ctx->mt->db()->get_template_text($ctx, $widgetmanager, $blog_id, 'widgetset', $args['global']);
    if ( isset($tmpl) && $tmpl ) {
        preg_match_all('/<mt:include widget="[^"]*">/', $tmpl, $matches);
        if ($matches && count($matches)) {
            $matches = $matches[0];
        }

        if ($matches && count($matches)) {
            $step = 4.0 / count($matches);
            $priority = 3.0;
            list($i_cb_name) = explode(' ', $cb_name);
            $i_cb_name = 'publish.' . $i_cb_name;
            global $_callback_registry;
            if (!array_key_exists($i_cb_name, $_callback_registry)) {
                $_callback_registry[$i_cb_name] = array();
            }
            foreach ($matches as $m) {
                $rec = array(
                    'priority' => $priority,
                    'template' => $m,
                    'name'     => $i_cb_name,
                );
                $_callback_registry[$i_cb_name][] = $rec;
                $priority += $step;
            }
        }
    }
    return smarty_function_mttemplatecallback( array('name' => $cb_name), $ctx );
}

function __init_mtsettemplatecallback() {
    $mt = MT::get_instance();
    $ctx =& $mt->context();
	$ctx->add_token_tag('mtsettemplatecallback');
    $ctx->add_tag('widgetset', '__handle_widgetset');
}
__init_mtsettemplatecallback();

?>
