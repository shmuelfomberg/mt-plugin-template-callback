<?php

require_once('callback_lib.php');

function smarty_block_mtsettemplatecallback($args, $content, &$ctx, &$repeat) {
    if (!isset($content)) {
        $name = $args['name'];
        if (!$name) return '';
        $name = 'publish.' . $name;
        $priority = $args['priority'];
        $priority or $priority = 5;
        $value = $args['token_fn'];
        global $_callback_registry;
        if (!isset($_callback_registry[$name])) {
        	$_callback_registry[$name] = array();
        }
        $_callback_registry[$name][] = array(
        	'priority' => $priority,
        	'tokens'   => $value,
        	'plugin'   => NULL,
        );
    }
    return '';
}

?>
