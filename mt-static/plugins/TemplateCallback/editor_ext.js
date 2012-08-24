(function($) {

var config   = MT.Editor.TinyMCE.config;
var base_url = StaticURI + 'plugins/TemplateCallback/';

$.extend(config, {
    content_css: config.content_css + ',' + base_url + 'editor_ext.css',
});

})(jQuery);
