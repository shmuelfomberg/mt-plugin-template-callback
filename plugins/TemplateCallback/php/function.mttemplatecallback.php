<?php
require_once('callback_lib.php');

function smarty_function_mttemplatecallback($args, &$ctx) {
    $STDERR = fopen('php://stderr', 'w+');
    fwrite($STDERR, "in tc\n");
    global $_callback_registry;
    $name = $args['name'];
    if (!$name) return '';
    $pieces = array_reverse(explode('.', $name));
    $name_part = '';
    $cb_array = array();
    while (count($pieces) > 0) {
        if ($name_part !== '') {
            $name_part .= '.';
        } 
        $name_part .= array_pop($pieces);
        if (isset($_callback_registry[$name_part])) {
            array_splice($cb_array, count($cb_array), 0, $_callback_registry[$name_part]);
        }
    }

    usort($cb_array, function($a,$b){
        if ($a['priority'] == $b['priority']) return 0;
        return ($a['priority'] < $b['priority']) ? -1 : 1;
    });

    $priority = $args['priority'];
    if (isset($priority)) {
        fwrite($STDERR, "tc: step 2.1\n");
        $p_begin = 1;
        $p_end = 10;
        if (preg_match('/^(\d+)\.\.(\d+)$/', $priority, $matches)) {
            $p_begin = $matches[1];
            $p_end = $matches[2];
        }
        else {
            $p_begin = $p_end = $priority;
        }
        $p_array = array();
        foreach ($cb_array as $rec) {
            if (($rec['priority'] >= $p_begin) && ($rec['priority'] <= $p_end)) {
                $p_array[] = $rec;
            }
        }
        $cb_array = $p_array;
    }
    fwrite($STDERR, "tc: step 3\n");

    $out = '';
    foreach ($cb_array as $rec) {
        fwrite($STDERR, "tc: step 3.1\n");
        if (array_key_exists('tokens', $rec)) {
            $func = $rec['tokens'];
            if (!is_array($func)
                && preg_match('/^smarty_fun_[a-f0-9]+$/', $func) 
                && function_exists($func)) 
            {
                ob_start();
                $func($ctx, array());
                $out .= ob_get_contents();
                ob_end_clean();
            }
        }
    }
    fwrite($STDERR, "tc: step 4\n");

    return $out;

}

?>
