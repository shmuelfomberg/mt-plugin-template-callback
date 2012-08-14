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
            if ($rec->{type} eq 'image') {
                $rec->{source} = $value;
                if ($value =~ m/^asset:(\d+)$/) {
                    my $asset_id = $1;
                    my $asset = $app->model('image')->load($asset_id);
                    return $app->errtrans('Invalid Request.')
                        unless $asset->blog_id == $blog->id;
                    $rec->{value} = $asset->url;
                }
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
    @recs = sort { $a->{order} <=> $b->{order} } @recs;
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

sub dialog_list_asset {
    my $app = shift;

    my $blog_id = $app->param('blog_id');
    return $app->return_to_dashboard( redirect => 1 )
        unless $blog_id;

    my $blog = $app->model('blog')->load($blog_id);
    return $app->permission_denied()
        unless $app->can_do('access_to_insert_asset_list');

    my %terms;
    my %args = ( sort => 'created_on', direction => 'descend' );

    my $blog_ids = $app->_load_child_blog_ids($blog_id);
    push @$blog_ids, $blog_id;
    $terms{blog_id} = $blog_ids;

    require MT::CMS::Asset;
    my $hasher = MT::CMS::Asset::build_asset_hasher(
        $app,
        PreviewWidth  => 120,
        PreviewHeight => 120
    );

    my $class_filter;
    if ( ( $app->param('filter') || '' ) eq 'class' ) {
        $class_filter = $app->param('filter_val');
        my $asset_pkg = MT::Asset->class_handler($class_filter);
        $terms{class} = $asset_pkg->type_list;
    }
    else {
        $terms{class} = '*';    # all classes
    }

    # identifier => name
    my $classes = MT::Asset->class_labels;
    my @class_loop;
    foreach my $class ( keys %$classes ) {
        next if $class eq 'asset';
        push @class_loop,
            {
            class_id    => $class,
            class_label => $classes->{$class},
            };
    }

    # Now, sort it
    @class_loop
        = sort { $a->{class_label} cmp $b->{class_label} } @class_loop;

    my $dialog    = 1;
    my %carry_params = map { $_ => $app->param($_) || '' }
        (qw( edit_field upload_mode require_type asset_select ));
    MT::CMS::Asset::_set_start_upload_params( $app, \%carry_params )
        if $app->can_do('upload');
    my ( $ext_from, $ext_to )
        = ( $app->param('ext_from'), $app->param('ext_to') );
    my $plugin = MT->component('TemplateCallback');

    $app->listing(
        {   terms    => \%terms,
            args     => \%args,
            type     => 'asset',
            code     => $hasher,
            template => $plugin->load_tmpl('dialog_asset_list.tmpl'),
            params => {
                (   $blog
                    ? ( blog_id      => $blog_id,
                        blog_name    => $blog->name || '',
                        edit_blog_id => $blog_id,
                        ( $blog->is_blog ? ( blog_view => 1 ) : () ),
                        )
                    : (),
                ),
                is_image => defined $class_filter
                    && $class_filter eq 'image' ? 1 : 0,
                dialog_view      => 1,
                dialog           => 1,
                search_label     => MT::Asset->class_label_plural,
                search_type      => 'asset',
                class_loop       => \@class_loop,
                can_delete_files => $app->can_do('delete_asset_file') ? 1 : 0,
                nav_assets       => 1,
                panel_searchable => 1,
                next_mode        => 'tc_examine_image',
                saved_deleted    => $app->param('saved_deleted') ? 1 : 0,
                object_type      => 'asset',
                (     ( $ext_from && $ext_to )
                    ? ( ext_from => $ext_from, ext_to => $ext_to )
                    : ()
                ),
                %carry_params,
            },
        }
    );
}

sub examine_image {
    my $app = shift;
    my $blog = $app->blog;
    my $blog_id = $blog->id;
    my $asset_id = $app->param('id');
    my $asset = $app->model('asset.image')->load($asset_id);
    if ($asset->blog_id != $blog_id) {
        return $app->errtrans('Invalid Request.');
    }
    my $variable_name = $app->param('edit_field');

    my $scope = $blog->class . ':' . $blog->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    my $vars = $cnf->data();
    my $rec = $vars->{$variable_name};
    return $app->errtrans('Invalid Request.')
        unless $rec and $rec->{type} eq 'image';

    my ( $real_w, $real_h ) = ($asset->image_width, $asset->image_height);
    my ($req_w, $req_h) = $rec->{size} =~ m/w:(\d+)\s+h:(\d+)/;
    if ( ( $req_w != $real_w ) || ( $req_h != $real_h ) ) {
        return $plugin->error('Invalid image size: ' . $rec->{value});
    }
    $rec->{source} = 'asset:'.$asset_id;
    $rec->{value} = $asset->url;
    $rec->{children} = { width => $real_w, height => $real_h };
    my $params = {
        field => $variable_name,
        field_value => $rec->{value},
        field_source => $rec->{source},
    };
    return $plugin->load_tmpl('dialog_asset_set.tmpl', $params);
}


1;
