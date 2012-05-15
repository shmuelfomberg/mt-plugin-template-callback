<?php

require_once('callback_lib.php');

function smarty_block_mtsettemplatecallback($args, $content, &$ctx, &$repeat) {
    $STDERR = fopen('php://stderr', 'w+');
    fwrite($STDERR, "in set_tc\n");
    // var_dump($args);
    // parameters: name, value
    if (!isset($content)) {
        $name = $args['name'];
        if (!$name) return '';
        $priority = $args['priority'];
        $priority or $priority = 5;
        $value = $args['token_fn'];
        fwrite($STDERR, "set_tc: |". $value . "|\n");
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