package TemplateCallback::ContentPlugins;
use strict;
use warnings;

sub ProcessTextTag {
    my ($str, $arg, $ctx) = @_;
    return $str unless $arg;
    my $app = MT->instance;
    my $tags_reg = $app->registry('tags');
    my $plugin_reg = $tags_reg->{content} || {};
    while ( $str =~ m/(<div\s+class="mtplugin mtplugin_(\w+)">\s*<div\s+([^>]+)>)/g ) {
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
        my ($class_arg) = grep { $_->[0] eq 'class' } @args;
        # malformed html plugin code if..
        next unless $class_arg and $class_arg->[1] eq 'plugin_internal_data';
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

sub ProcessBodyTag {
    my ( $ctx, $args, $cond ) = @_;
    defined( my $result = $ctx->super_handler( $args, $cond ) )
        or return $ctx->error( $ctx->errstr );
    if ((not exists $args->{content_plugins}) or ($args->{content_plugins} == 1)) {
        $result = ProcessTextTag($result, 1, $ctx);
    }
    return $result;    
}

sub presave_process_string {
    my ($str) = @_;
    return $str unless $str;
    return $str unless $str =~ m/<div class="mtplugin mtplugin_/;

    require HTML::TreeBuilder;
    my $root = HTML::TreeBuilder->new();
    $root->no_expand_entities(1);

    $str = '<html><head></head><body>' . $str . '</body></html>';

    $root->parse_content($str);
    my @divs = $root->look_down(
        _tag => 'div',
        class => qr/\bmtplugin\b/,
    );
    foreach my $div (@divs) {
        my @old_content = $div->detach_content();
        foreach my $child (@old_content) {
            next unless ref $child;
            if (($child->tag eq 'div') and ($child->attr('class') eq 'plugin_internal_data')) {
                $div->insert_element($child);
            }
            else {
                $child->delete;             
            }
        }
    }
    my $new_str = $root->as_HTML;
    $new_str =~ s!^<html><head></head><body>!!;
    $new_str =~ s!</body></html>$!!;
    $root = $root->delete;
    return $new_str;
}


sub entry_presave {
    my ($cb, $app, $obj, $orig_obj) = @_;
    $obj->text(presave_process_string($obj->text));
    $obj->text_more(presave_process_string($obj->text_more));    
    return 1;
}

1;
