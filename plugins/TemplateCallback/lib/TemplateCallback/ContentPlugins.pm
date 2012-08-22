package TemplateCallback::ContentPlugins;
use strict;
use warnings;

sub ProcessTextTag {
    my ($str, $arg, $ctx) = @_;
    my $app = MT->instance;
    my $tags_reg = $app->registry('tags');
    my $plugin_reg = $tags_reg->{content} || {};
    while ( $str =~ m/(<div\s+class="mtplugin mtplugin_(\w+)">\s*<div\s+class="mtplugin-internal_data"([^>]*)>)/g ) {
        my $whole_tag = $1;
        my $start_pos = pos($str) - length($whole_tag);
        my $plugin_name = $2;
        my $plugins_args = $3;
        my ($content, $tag_end) = $str =~ m!\G(.*?)(</div>\s+</div>)!;
        my $end_pos = $start_pos + length($whole_tag) + length($content) + length($tag_end);
        my @args;
        while ($plugins_args =~ m/(\w+)="([^"]*)"/g) {
            push @args, [$1, $2];
        }
        my $out = '';
        if (exists $plugin_reg->{$plugin_name}) {
            my $plugin_func = $app->handler_to_coderef($plugin_reg->{$plugin_name});
            $out = $plugin_func->($app, $ctx, $plugin_name, $content, \@args);
        }
        substr($str, $start_pos, $end_pos-$start_pos, $out);
        pos($str) = $start_pos + length($out);
    }
    return $str;
}

1;
