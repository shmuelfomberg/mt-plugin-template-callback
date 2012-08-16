package TemplateCallback::ThemeVars;
use strict;
use warnings;
use Data::Dumper;

sub pre_apply_theme {
    my ($cb, $theme, $blog) = @_;
    my $scope = $blog->class . ':' . $blog->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    $cnf->data({});
    $cnf->save();
    return 1;
}

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
        }
        if ($rec->{type} eq 'checkbox') {
            if (($rec->{value}!=0) and ($rec->{value}!=1)) {
                return $plugin->error('Checkbox can accept only 0 or 1: ' . $name);
            }
        }
        if ($rec->{type} =~ m/^(?:radio|dropdown)$/) {
            if (not exists $rec->{choices}->{$rec->{value}}) {
                return $plugin->error('Radio/dropdown default should be one of the choices: ' . $name);
            }
        }
    }
    $cnf->data({vars => $param});
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
    my $full_data = $cnf->data();
    my $c_data = $full_data->{vars};
    if ($app->param('save')) {
        while (my ($name, $rec) = each %$c_data) {
            my $rec = $c_data->{$name};
            my $value = $app->param("var_".$name);
            if ($rec->{type} eq 'color') {
                next unless $value =~ m/^(?:\w+|#[0-9A-F]+)$/i;
                $rec->{value} = $value;
            }
            if ($rec->{type} eq 'image') {
                $rec->{source} = $value;
                if ($value =~ m/^asset:(\d+)$/) {
                    my $asset_id = $1;
                    my $asset = $app->model('image')->load($asset_id);
                    return $app->errtrans('Invalid Request.')
                        unless $asset->blog_id == $blog->id;
                    my ($req_w, $req_h) = $rec->{size} =~ m/w:(\d+)\s+h:(\d+)/;
                    my ( $real_w, $real_h ) = ($asset->image_width, $asset->image_height);
                    if ( ( $req_w != $real_w ) || ( $req_h != $real_h ) ) {
                        # TODO: make a screen of picture scaling / chopping
                        # in the meantime, lets just scale the image
                        $rec->{value} = __make_thumbnail($app, $blog, $asset, $req_w, $req_h);
                    }
                    else {
                        $rec->{value} = $asset->url;
                    }
                }
            }
            if ($rec->{type} eq 'checkbox') {
                $rec->{value} = $value ? 1 : 0;
            }
            if ($rec->{type} =~ m/^(?:radio|dropdown)$/) {
                if (not exists $rec->{choices}->{$value}) {
                    return $app->errtrans('Invalid Request.');
                }
                $rec->{value} = $value;
            }
        }
        $cnf->data($full_data);
        $cnf->save();
        if (my $layout = $app->param('page_layout')) {
            $blog->page_layout($layout);
            $blog->save();
        }
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

    my @page_layouts = (
        { value => 'layout-wt', label => '2-Columns, Wide, Thin', },
        { value => 'layout-tw', label => '2-Columns, Thin, Wide', },
        { value => 'layout-wm', label => '2-Columns, Wide, Medium', },
        { value => 'layout-mw', label => '2-Columns, Medium, Wide', },
        { value => 'layout-wtt', label => '3-Columns, Wide, Thin, Thin', },
        { value => 'layout-twt', label => '3-Columns, Thin, Wide, Thin', },
        { value => 'layout-ttw', label => '3-Columns, Thin, Thin, Wide', },
        { value => 'layout-w-b', label => '1-Column, Wide, Bottom', },
    );
    foreach my $rec (@page_layouts) {
        if ($blog->page_layout eq $rec->{value}) {
            $rec->{current} = 1;
        }
    }
    $params{page_layouts} = \@page_layouts;

    return $plugin->load_tmpl('appearance.tmpl', \%params);
}

sub init {
    my ($ctx) = @_;
    my $blog = $ctx->stash('blog');
    my $scope = $blog->class . ':' . $blog->id;
    my $plugin = MT->component('TemplateCallback');
    my $cnf = $plugin->get_config_obj($scope);
    my $data = $cnf->data();
    return 1 unless $data;
    my $vars = $data->{vars};
    while ( my ($key, $rec) = each %$vars ) {
        $ctx->var($key, $rec->{value});
    }
    return 1;
}

sub __make_thumbnail {
    my ($app, $blog, $asset, $req_w, $req_h) = @_;
    # based on MT::Asset::Image/thumbnail_file
    require MT::FileMgr;
    my $fmgr = $blog->file_mgr;
    my $file = $asset->thumbnail_filename(Width => $req_w, Height =>$req_h);
    my $asset_cache_path = $asset->_make_cache_path();
    my $thumbnail = File::Spec->catfile( $asset_cache_path, $file );
    my $file_path = $asset->file_path;

    if (!$fmgr->exists($thumbnail) || ( $fmgr->file_mod_time($thumbnail) < $fmgr->file_mod_time($file_path) ) ) {
        require MT::Image;
        my $img = new MT::Image( Filename => $file_path )
            or return $asset->error( MT::Image->errstr );
        my ($data) = $img->scale( Height => $req_h, Width => $req_w )
            or return $asset->error(
            MT->translate( "Error scaling image: [_1]", $img->errstr ) );

        return undef 
            unless $fmgr->can_write($asset_cache_path);

        $fmgr->put_data( $data, $thumbnail, 'upload' )
            or return $app->errtrans( "Error creating thumbnail file: [_1]", $fmgr->errstr );
    }
    # based on MT::Asset/thumbnail_url
    my $basename = File::Basename::basename($thumbnail);
    require MT::Util;
    my $path = MT::Util::caturl( MT->config('AssetCacheDir'), unpack( 'A4A2', $asset->created_on ) );
    $basename = MT::Util::encode_url($basename);
    return MT::Util::caturl( $blog->site_url, $path, $basename );
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
    my $vars = $cnf->data()->{vars};
    my $rec = $vars->{$variable_name};
    return $app->errtrans('Invalid Request.')
        unless $rec and $rec->{type} eq 'image';

    my ($req_w, $req_h) = $rec->{size} =~ m/w:(\d+)\s+h:(\d+)/;
    my ( $real_w, $real_h ) = ($asset->image_width, $asset->image_height);
    if ( ( $req_w != $real_w ) || ( $req_h != $real_h ) ) {
        # TODO: make a screen of picture scaling / chopping
        # in the meantime, lets just scale the image
        $rec->{value} = __make_thumbnail($app, $blog, $asset, $req_w, $req_h);
    }
    else {
        $rec->{value} = $asset->url;
    }

    $rec->{source} = 'asset:'.$asset_id;
    my $params = {
        field => $variable_name,
        field_value => $rec->{value},
        field_source => $rec->{source},
    };
    return $plugin->load_tmpl('dialog_asset_set.tmpl', $params);
}


1;
