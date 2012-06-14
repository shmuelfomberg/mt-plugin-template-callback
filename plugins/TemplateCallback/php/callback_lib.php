<?php


$GLOBALS['_callback_registry'] = array();

function __init_readyamlfile($filename) {
    // $cbs = yaml_parse_file($filename);
}

function __init_collectcallbacks_from_yaml() {

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


function __init_collectcallbacks_from_files($mt, $ctx) {

    $plugin_paths = $mt->config('PluginPath');
    global $_callback_registry;
       $STDERR = fopen('php://stderr', 'w+');

    foreach ($plugin_paths as $path) {
        if ( !is_dir($path) )
            $path = $mt->config('MTDir') . DIRECTORY_SEPARATOR . $path;

        if (($dh = @opendir($path)) === false)
            continue;

        while (($dir = readdir($dh)) !== false) {
            if ($dir == "." || $dir == "..")
                continue;
            $plugin_dir = $path . DIRECTORY_SEPARATOR . $dir;
            $plugin_cbs = $plugin_dir . DIRECTORY_SEPARATOR . 'tmpl' . DIRECTORY_SEPARATOR . 'callbacks';
            if (!is_dir($plugin_cbs))
                continue;
            if (($cb_dh = @opendir($plugin_cbs)) === false)
                continue;
            while (($cb_file = readdir($cb_dh) ) !== false) {
                if ( ! preg_match('/^(.*)\.(\d+)\.tmpl$/', $cb_file, $matches) )
                    continue;
                $cb_name = $matches[1];
                $priority = $matches[2];
                $fullname = $plugin_cbs . DIRECTORY_SEPARATOR . $cb_file;
                if (!is_file($fullname) || !is_readable($fullname))
                    continue;
                $rec = array(
                    'priority' => $priority,
                    'file'     => $fullname,
                    'name'     => $cb_name,
                );
                if (array_key_exists($cb_name, $_callback_registry)) {
                    $_callback_registry[$cb_name][] = $rec;
                }
                else {
                    $_callback_registry[$cb_name] = array($rec);
                }
            }
        }
        closedir($dh);
    }
}

function __init_collectcallbacks_from_db($mt, $ctx) {
    global $_callback_registry;
    $blog_id = $ctx->stash('blog_id');
    $where = "template_identifier = 'publish' 
        and template_type='t_callback' 
        and template_blog_id in (0, $blog_id)";
    require_once('class.mt_template.php');
    $tmpl_class = new Template();
    $tmpls = $tmpl_class->Find($where);
    if (empty($tmpls))
        return;
    foreach ($tmpls as $t) {
        if (preg_match('/^(.*)::(.*)$/', $t->name, $matches)) {
            $plugin_id = $matches[1];
            $cb_name = $matches[2];
        }
        else {
            $cb_name = $t->name;
        }
        $cb_name = 'publish.' . $cb_name;
        $rec = array(
            'priority' => $t->build_interval,
            'template' => $t->text,
            'name'     => $cb_name,
        );
        if (array_key_exists($cb_name, $_callback_registry)) {
            $ar = $_callback_registry[$cb_name];
        }
        else {
            $ar = array();
            $_callback_registry[$cb_name] = $ar;
        }
        $ar[] = $rec;
    }
}

function _init_template_callbacks() {
    $mt = MT::get_instance();
    $ctx =& $mt->context();
    __init_collectcallbacks_from_files($mt, $ctx);
    __init_collectcallbacks_from_db($mt, $ctx);
    return 1;
}

_init_template_callbacks();

?>
