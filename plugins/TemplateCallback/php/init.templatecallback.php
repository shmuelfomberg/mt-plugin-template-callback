<?php


function __init_readyamlfile($filename) {
	// $cbs = yaml_parse_file($filename);
}

function __init_collectcallbacks() {

    $mt = MT::get_instance();
    $ctx =& $mt->context();
    $plugin_paths = $mt->config('PluginPath');

    foreach ($plugin_paths as $path) {
        if ( !is_dir($path) )
            $path = $mt->config('MTDir') . DIRECTORY_SEPARATOR . $path;

        if ($dh = @opendir($path)) {
			while (($file = readdir($dh)) !== false) {
				if ($file == "." || $file == "..")
					continue;
				$filename = $path . DIRECTORY_SEPARATOR . $file . DIRECTORY_SEPARATOR . 'tmpl_cb.yaml';
				if (is_file($filename))
					__init_readyamlfile($filename);
			}
			closedir($dh);
        }
    }
}

function __init_mtsettemplatecallback() {
    $mt = MT::get_instance();
    $ctx =& $mt->context();
	$ctx->add_token_tag('mtsettemplatecallback');
}
__init_mtsettemplatecallback();
__init_collectcallbacks();

?>
