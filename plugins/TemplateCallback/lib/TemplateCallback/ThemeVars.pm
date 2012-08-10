package TemplateCallback::ThemeVars;
use strict;
use warnings;
use Data::Dumper;

sub import_tv {
    my ( $element, $theme, $obj_to_apply ) = @_;
    return unless $obj_to_apply->datasource eq 'blog';
    my $app = MT->instance;
    my $scope = $obj_to_apply->class . ':' . $obj_to_apply->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    my $vars = $element->{data};
    my $param = {};
    while (my ($name, $rec) = each %$vars) {
        $rec->{name} = $name;
        $rec->{value} = $rec->{default};
        $param->{$name} = $rec;
        if ($rec->{type} eq 'color') {
            if ($rec->{value} !~ m/^(?:#[0-9A-Fa-f]+)|\w+$/) {
                return $plugin->error('Invalid color value: ' . $rec->{value});
            }
        }
        if ($rec->{type} eq 'image') {
            my $orig_loc = $rec->{default};
            my $static_src = $orig_loc =~ m!^\%ss/! ? 'static' : 'blog_static';
            $orig_loc =~ s!^\%\w+/!!;
            my @orig_dir = split '/', $orig_loc;
            require File::Spec;
            my $orig_file = File::Spec->catdir( $theme->path, $static_src, @orig_dir );
            my $dest_dir = $static_src eq 'static' 
                ? $app->support_directory_url . 'theme_static/' . $theme->id . '/'
                : $obj_to_apply->site_url;
            my $dest_url = $dest_dir . join('/', @orig_dir);
            require Image::Size;
            my ( $real_w, $real_h ) = Image::Size::imgsize( $orig_file );
            if (not defined $real_w) {
                return $plugin->error('Invalid image: ' . $rec->{value});
            }
            my ($req_w, $req_h) = $rec->{size} =~ m/w:(\d+)\s+h:(\d+)/;
            if ( ( $req_w != $real_w ) || ( $req_h != $real_h ) ) {
                return $plugin->error('Invalid image size: ' . $rec->{value});
            }
            $rec->{source} = 'default';
            $rec->{value} = $dest_url;
            $rec->{children} = { width => $real_w, height => $real_h };
        }
    }
    $cnf->data($param);
    $cnf->save();
    return 1;
}

sub info {
    my ( $element, $theme, $blog ) = @_;
    my $data = $element->{data};
    my $count = scalar keys %$data;
    my $plugin = MT->component('TemplateCallback');
    my $str = $plugin->translate( '[_1] theme variables.', $count );
    return sub { return $str; };
}

sub set_appearance {
    my $app   = shift;
    my $blog = $app->blog;
    my $scope = $blog->class . ':' . $blog->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    my %params;
    my $c_data = $cnf->data();
    if ($app->param('save')) {
        foreach my $key ( $app->param() ) {
            next unless $key =~ m/^var_(.*)$/;
            my $name = $1;
            next unless exists $c_data->{$name};
            my $rec = $c_data->{$name};
            my $value = $app->param($key);
            if ($rec->{type} eq 'color') {
                next unless $value =~ m/^(?:\w+|#[0-9A-F]+)$/;
                $rec->{value} = $value;
            }
        }
        $cnf->data($c_data);
        $cnf->save();
        $params{saved} = 1;
    }
    my @recs = values %$c_data;
    foreach my $rec ( @recs ) {
        $rec->{order} ||= 10000;
        $rec->{id} = "var_".$rec->{name};
    }
    $_->{order} ||= 10000 foreach values %$c_data;
    my @recs = sort { $a->{order} <=> $b->{order} } @recs;
    $params{variables} = \@recs;
    if (scalar(@recs) == 0) {
        $params{error} = "Your theme does not have variables defined";
    }
    return $plugin->load_tmpl('appearance.tmpl', \%params);
}

sub init {
    my ($ctx) = @_;
    my $blog = $ctx->stash('blog');
    my $scope = $blog->class . ':' . $blog->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    my $data = $cnf->data();
    while ( my ($key, $rec) = each %$data ) {
        $ctx->var($key, $rec->{value});
    }
    return 1;
}

# PHP init code:
    # $blog_id = $ctx->stash('blog_id');
    # $STDERR = fopen('php://stderr', 'w+');
    # fwrite($STDERR, "in init\n");
    # $theme_data = $mt->db()->fetch_plugin_data('TemplateCallback', 'configuration:blog:'.$blog_id);
    # if (!empty($theme_data)) {
    #     fwrite($STDERR, "in init: not empty\n");
    #     $vars =& $ctx->__stash['vars'];
    #     if (!isset($vars)) {
    #         $ctx->__stash['vars'] = array();
    #         $vars =& $ctx->__stash['vars'];
    #     }
    #     foreach ($theme_data as $key => $rec) {
    #         $vars[$key] = $rec[$value];
    #     }
    # }
    # else {
    #     fwrite($STDERR, "in init: empty\n");
    # }

1;
