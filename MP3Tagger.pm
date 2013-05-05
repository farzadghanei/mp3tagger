#!/usr/bin/env perl
package MP3Tagger;

my $VERSION = "0.1.1";

use strict;
use warnings;
use Carp;
use File::Spec;
use File::Basename;
use File::Find;

use MP3::Tag;

my $_empty_tag = {
        title => undef,
        track => undef,
        artist => undef,
        album => undef,
        year => undef,
    };

sub new {
    my $class = shift;
    my $self = {
        'default_title' => undef,
        'default_track' => undef,
        'default_artist' => undef,
        'default_album' => undef,
        'default_year' => undef,
        'clear' => 0,
        'force_default' => 0,
    };
    bless $self, $class;
    return $self;
}

sub _get_mp3tag_obj {
    my $self = shift;
    my $filename = shift or confess('no filename specified');
    my $mp3 = MP3::Tag->new($filename);
    $mp3->config('autoinfo', 'ID3v2', 'ID3v1');
    return $mp3;
}

sub read_file_tags {
    my $self = shift;
    my $filename = shift or confess('no filename specified');
    $filename = File::Spec->rel2abs(File::Spec->canonpath($filename));
    croak("failed to read tags. file '$filename' is not readable") if !-r $filename;
    my $mp3 = $self->_get_mp3tag_obj($filename);
    my %tag = %$_empty_tag;
    my $_info = $mp3->autoinfo();
    for my $k (keys %tag) {
        $tag{$k} = $_info->{$k} if $_info->{$k};
    }
    return \%tag;
}

sub detect_tags_from_filename {
    my $self = shift;
    my $filename = shift or confess('no filename specified');
    $filename = File::Spec->rel2abs(File::Spec->canonpath($filename));
    croak("failed to detect tags. file '$filename' does not exist") if !-e $filename;
    my %tag = %$_empty_tag;
    my ($name, $dir, $ext) = fileparse($filename, qw(.mp3));
    my $album_dir = basename($dir);
    if ($name =~ '^(\d+)[-\._](.+)') {
       $tag{track} = $1;
       $tag{title} = $2;
    }
    else {
        $tag{title} = $name;
    }
    return \%tag if !$album_dir;
    if ($album_dir =~ '^(\d+)[-\._](.+)') {
        $tag{year} = $1;
        $tag{album} = $2;
    }
    else {
        $tag{album} = $album_dir;
    }
    my $artist_dir = basename(File::Spec->rel2abs(dirname(dirname($filename))));
    $tag{artist} = $artist_dir if $artist_dir;
    return \%tag;
}

sub tag_file {
    my $self = shift;
    my $filename = shift or confess('no filename specified');
    $filename = File::Spec->rel2abs(File::Spec->canonpath($filename));
    croak("failed to tag file. '$filename' is not writable") if !-w $filename;
    my $tags = {};
    if (!$self->{clear}) {
        my $file_tags = $self->read_file_tags($filename);
        for my $k (keys %$file_tags) {
            $tags->{$k} = ucfirst($file_tags->{$k}) if $file_tags->{$k};
        }
    }
    my $detected_tags = $self->detect_tags_from_filename($filename);

    for my $k (keys %$detected_tags) {
        my $_default = $self->{"default_${k}"};
        if ($self->{force_default} && defined $_default) {
            $tags->{$k} = ucfirst($_default);
            next;
        }
        if ($detected_tags->{$k}) {
            $tags->{$k} = ucfirst($detected_tags->{$k});
        }
        elsif(defined $_default) {
            $tags->{$k} = ucfirst($_default);
        }
    }

    my $mp3 = $self->_get_mp3tag_obj($filename);
    if ($self->{clear}) {
        $mp3->delete_tag('ID3v1');
        $mp3->delete_tag('ID3v2');
    }
    for my $k (keys %$tags) {
        my $method = "${k}_set";
        $mp3->$method($tags->{$k});
    }
    $mp3->update_tags();
    return $tags;
}

sub tag_files {
    my $self = shift;
    my $files = shift || return;
    my $verbose = shift;
    my $total = scalar @$files;
    my $count = 1;
    for my $f (@$files) {
        print "$count/$total) $f ..." if $verbose;
        $self->tag_file($f);
        print "ok!\n" if $verbose;
        $count++;
    }
    return $files;
}

sub tag_album_dir {
    my $self = shift;
    my $dir = shift or File::Spec->curdir();
    my $verbose = shift;
    $dir = File::Spec->rel2abs(File::Spec->canonpath($dir));
    confess("Invalid album dir. $dir does not exist") if ! -e $dir;
    my @files = glob("'$dir'/*.mp3");
    return $self->tag_files(\@files, $verbose);
}

sub tag_artist_dir {
    my $self = shift;
    my $dir = shift or File::Spec->curdir();
    my $verbose = shift;
    $dir = File::Spec->rel2abs(File::Spec->canonpath($dir));
    confess("Invalid artist dir. $dir dies not exist") if ! -e $dir;
    my @files = glob("'$dir'/*");
    my @albums = grep { -d $_ } @files;
    for my $album (@albums) {
        $self->tag_album_dir($album, $verbose);
    }
}


my $_usage = <<ENDOFHELP;
MP3Tagger v${VERSION}
Usage:
$0 [options] [filename]
Options:
    -h, --help      show this help
    --clear         clear all previous id3 tags
    --show          only show id3 tags. requires
                    a filename argument.
    --track         default track number
    --title         default title
    --artist        default artist
    --album         default album
    --year          default year
    --artist-dir    consider dir as artist album archive
    --album-dir     consider dir as an album
    --force-default overwrite other values by the specified
                    defauls
ENDOFHELP

__PACKAGE__->run( @ARGV ) unless caller;

sub run {
    my($class, @args) = @_;
    use Getopt::Long qw(GetOptionsFromArray);
    use Pod::Usage;
    my $help = 0;

    my $clear = 0;
    my $show = 0;
    my $force_default = 0;

    my $track = undef;
    my $title = undef;
    my $artist = undef;
    my $album = undef;
    my $year = undef;

    my $album_dir = undef;
    my $artist_dir = undef;

    GetOptionsFromArray(\@args,
        'help|h' => \$help,
        'clear' => \$clear,
        'force-default' => \$force_default,
        'show' => \$show,
        'track=i' => \$track,
        'title=s' => \$title,
        'artist=s' => \$artist,
        'album=s' => \$album,
        'year=i' => \$year,
        'album-dir=s' => \$album_dir,
        'artist-dir=s' => \$artist_dir,
    );
    if ($help) {
        print $_usage;
        exit(64);
    }

    my $tagger = $class->new();

    if ($show) {
        my $total = scalar @args;
        if (!$total) {
            print STDERR "please specify the filename\n";
            exit(78);
        }
        my $count = 1;
        for my $file (@args) {
            my $tags = $tagger->read_file_tags($file);
            print "$count/$total) $file\n";
            for my $k (keys %$tags) {
                next if ! defined $tags->{$k};
                print "$k: " . $tags->{$k} . "\n";
            }
            print "--------------\n" if $count < $total;
            $count++;
        }
        exit(0);
    }

    $tagger->{clear} = 1 if $clear;
    $tagger->{force_default} = 1 if $force_default;
    $tagger->{default_track} = $track if defined $track;
    $tagger->{default_title} = $title if defined $title;
    $tagger->{default_artist} = $artist if defined $artist;
    $tagger->{default_album} = $album if defined $album;
    $tagger->{default_year} = $year if defined $year;

    if ($artist_dir) {
        $tagger->tag_artist_dir($artist_dir, 1);
    }
    elsif ($album_dir) {
        $tagger->tag_album_dir($album_dir, 1);
    }
    else {
        my $total = scalar @args;
        if (!$total) {
            print STDERR "please specify files to tag\n";
            exit(78);
        }
        $tagger->tag_files(\@args, 1);
    }
}
1;
