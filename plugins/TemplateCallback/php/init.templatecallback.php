<?php

function __init_mtsettemplatecallback() {
    $mt = MT::get_instance();
    $ctx =& $mt->context();
	$ctx->add_token_tag('mtsettemplatecallback');
}
__init_mtsettemplatecallback();

?>
