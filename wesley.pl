#!/usr/bin/perl -w

#
# Wesley
#
# Version 0.1.0
#
# Recursively searches a directory path for image files (JPEG, GIF, PNG) and 
# applies lossless compression to files in-place.
#
# This script uses techniques described in this article about the use 
# of jpegtran: http://www.phpied.com/installing-jpegtran-mac-unix-linux/
# and used by the smush.it tool described here:
# http://developer.yahoo.com/yslow/smushit/faq.html
#
# Wesley makes use of gifsicle, ImageMagick, jpegtran, and pngcrush to optimize
# images.  You should make an attempt to ensure that each of these has been
# installed on your system prior to running this script.  If you are missing 
# any of these, however, Wesley will still run but will skip any optimizations
# for which the applicable software is not available.  In other words, if you 
# don't have jpegtran installed, Wesley will skip JPEG optimizations.
#
# USAGE:
#  
# Recursively optimize all images within a directory:
#
#   wesley.pl directory_path
#
# Optimize a single image:
#
#   wesley.pl filename
#

#
# *** WARNING ***
#
# Removal of copyright information from files you do not own may be a violation
# of the DMCA (http://en.wikipedia.org/wiki/Digital_Millennium_Copyright_Act).
# This script removes metadata and comments from image files.  Do not use this
# script to modify files for which you do not own the rights.
#

#
# PERMISSION NOTICE AND DISCLAIMER
# 
# Permission to use, copy, modify and distribute this software and its documentation 
# for any purpose and without fee is hereby granted. This software is provided "as is"
# without express or implied warranty.
# 
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL 
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, 
# WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT 
# OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# 

use strict;
use File::Find;
use File::Copy;

my $DEBUG = 0;

# Setup locations where we might find the necessary executables.
my @jpegtran_paths = qw( /usr/bin/jpegtran /usr/local/bin/jpegtran );
my @pngcrush_paths = qw( /usr/bin/pngcrush /usr/local/bin/pngcrush /sw/bin/pngcrush );
my @gifsicle_paths = qw( /usr/bin/gifsicle /usr/local/bin/gifsicle /sw/bin/gifsicle );
my @convert_paths  = qw( /usr/bin/convert /usr/local/bin/convert /sw/bin/convert );
my @identify_paths = qw( /usr/bin/identify /usr/local/bin/identify /sw/bin/identify );

# Turn off any of the following options you don't want to run.
my $do_jpeg_compress = 1;
my $do_png_compress  = 1;
my $do_gif_compress  = 1;
my $do_png_compare   = 1;

my $jpegtran_path;
my $pngcrush_path;
my $gifsicle_path;
my $convert_path;
my $identify_path;


# Locate paths to executables.
locateBinaries();

print "JPEG optimizations will be skipped.\n" if $DEBUG && !$do_jpeg_compress;
print "PNG optimizations will be skipped.\n" if $DEBUG && !$do_png_compress;
print "GIF optimizations will be skipped.\n" if $DEBUG && !$do_gif_compress;

# Get image search path from command-line args.
my $search_path = readInput();

# Setup default counters.
my $score = {};
$score->{'jpeg_count'} = 0;
$score->{'jpeg_modify'} = 0;
$score->{'jpeg_optimize'} = 0;
$score->{'jpeg_progressive'} = 0;
$score->{'jpeg_bytes_orig'} = 0;
$score->{'jpeg_bytes_saved'} = 0;
$score->{'png_count'} = 0;
$score->{'png_modify'} = 0;
$score->{'png_crush'} = 0;
$score->{'png_bytes_orig'} = 0;
$score->{'png_bytes_saved'} = 0;
$score->{'gif_count'} = 0;
$score->{'gif_modify'} = 0;
$score->{'gif_gifsicle'} = 0;
$score->{'gif_bytes_orig'} = 0;
$score->{'gif_bytes_saved'} = 0;
$score->{'gif2png_files'} = [];
$score->{'gif2png_bytes_orig'} = 0;
$score->{'gif2png_bytes_saved'} = 0;

# Compress image files.
find(\&compressFiles, $search_path);

# Output statistics.
writeSummary();

exit;


#
# Subroutines
#

sub compressFiles()
{
    if (m/\.jpg$/i && $do_jpeg_compress) {
        compressJPG($_);
    
    } elsif (m/\.png$/i && $do_png_compress) {
        compressPNG($_);

    } elsif (m/\.gif$/i) {
        if ($do_gif_compress) {
            compressGIF($_);
        }
        if ($do_png_compare) {
            comparePNG($_);
        }
    }
}

sub compressJPG
{
    $score->{'jpeg_count'}++;

    my $orig_size = -s $_;
    my $saved = 0;

    my $fullname = $File::Find::dir . '/' . $_;

    print "Inspecting $fullname\n";

    # Run Progressive JPEG and Huffman table optimizations, then inspect
    # which was best.

    `$jpegtran_path -copy none -optimize "$_" > "$_.opt"`; 
    my $opt_size = -s "$_.opt";

    `$jpegtran_path -copy none -progressive "$_" > "$_.prog"`; 
    my $prog_size = -s "$_.prog";

    if ($opt_size && $opt_size < $orig_size && $opt_size <= $prog_size) {
        move("$_.opt", "$_");
        $saved = $orig_size - $opt_size;
        $score->{'jpeg_bytes_saved'} += $saved;
        $score->{'jpeg_bytes_orig'} += $orig_size;
        $score->{'jpeg_modify'}++;
        $score->{'jpeg_optimize'}++;

        print " -- Huffman table optimization: "
            . "saved $saved bytes (orig $orig_size)\n" if $DEBUG;

    } elsif ($prog_size && $prog_size < $orig_size) {
        move("$_.prog", "$_");
        $saved = $orig_size - $prog_size;
        $score->{'jpeg_bytes_saved'} += $saved;
        $score->{'jpeg_bytes_orig'} += $orig_size;
        $score->{'jpeg_modify'}++;
        $score->{'jpeg_progressive'}++;

        print " -- Progressive JPEG optimization: "
            . "saved $saved bytes (orig $orig_size)\n" if $DEBUG;
    }

    # Cleanup temp files
    if (-e "$_.prog") {
         unlink("$_.prog");
    }
    if (-e "$_.opt") {
        unlink("$_.opt");
    }
}

sub compressPNG 
{
    $score->{'png_count'}++;

    my $orig_size = -s $_;
    my $saved = 0;
    
    my $fullname = $File::Find::dir . '/' . $_;

    print "Inspecting $fullname\n";

    # Run pngcrush
    `$pngcrush_path -rem alla -reduce -brute "$_" "$_.crush"`;
    my $crush_size = -s "$_.crush";

    if ($crush_size && $crush_size < $orig_size) {
        move("$_.crush", "$_");
        $saved = $orig_size - $crush_size;
        $score->{'png_bytes_saved'} += $saved;
        $score->{'png_bytes_orig'} += $orig_size;
        $score->{'png_modify'}++;
        $score->{'png_crush'}++;

        print " -- pngcrush optimization: "
            . "saved $saved bytes (orig $orig_size)\n" if $DEBUG;

    } else {
        unlink("$_.crush");
    }
}

sub compressGIF 
{
    $score->{'gif_count'}++;

    my $orig_size = -s $_;
    my $saved = 0;
    
    my $fullname = $File::Find::dir . '/' . $_;

    print "Inspecting $fullname\n";

    `$gifsicle_path --no-warnings --no-comments --optimize=2 "$_" > "$_.gifsicle"`;
    my $gifsicle_size = -s "$_.gifsicle";

    if ($gifsicle_size && $gifsicle_size < $orig_size) {
        move("$_.gifsicle", "$_");
        $saved = $orig_size - $gifsicle_size;
        $score->{'gif_bytes_saved'} += $saved;
        $score->{'gif_bytes_orig'} += $orig_size;
        $score->{'gif_modify'}++;
        $score->{'gif_gifsicle'}++;

        print " -- Gifsicle optimization: "
            . "saved $saved bytes (orig $orig_size)\n" if $DEBUG;
    } else {
        unlink("$_.gifsicle");
    }
}

sub comparePNG 
{
    my $orig_size = -s $_;
    my $saved = 0;
    my $png_size = 0;
    
    my $fullname = $File::Find::dir . '/' . $_;

    # Only try converting static GIFs.
    my $type = `$identify_path -format %m "$_"`;
    chomp $type;

    if ($type eq 'GIF') {

        print "Considering conversion to PNG: $fullname\n";

        # Try converting to PNG and crush if possible.
        `$convert_path "$_" "$_.try.png"`;
        if ($pngcrush_path) {
            `$pngcrush_path -rem alla -reduce -brute "$_.try.png" "$_.try.crush"`;
            $png_size = -s "$_.try.crush";
        } else {
            $png_size = -s "$_.try.png";
        }

        if ($png_size && $png_size < $orig_size) {
            $saved = $orig_size - $png_size;
            $score->{'gif2png_bytes_saved'} += $saved;
            $score->{'gif2png_bytes_orig'} += $orig_size;
            push @{$score->{'gif2png_files'}}, $fullname;

            print " -- Conversion to PNG would save "
                . "$saved bytes (orig $orig_size)\n" if $DEBUG;
        }
        
        # Clean up temp files.
        if (-e "$_.try.png") {
            unlink("$_.try.png");
        }
        if (-e "$_.try.crush") {
            unlink("$_.try.crush");
        }
    }
}


# Read search path from command line
sub readInput
{
    if (!$ARGV[0]) {
        print STDERR "Usage: $0 path_to_images\n";
        exit 1;
    }

    my $images_path = $ARGV[0];
    if (!-e $images_path) {
        print STDERR "Invalid path specified.\n";
        exit 1;
    }

    return $images_path;
}

sub locateBin
{
    my $name = shift;
    my @search_paths = @_;

    my $found_path;

    my $path = `/usr/bin/which $name`;
    if ($path =~ /\//) {
        chomp $path;
        $found_path = $path;
    } else {
        foreach my $path (@search_paths) {
            if (-e $path && -x $path) {
                $found_path = $path;
                last;
            }
        }
    }

    if ($found_path) {
        print "Found $name at $found_path.\n" if $DEBUG;
    } else {
        print "Warning: Could not locate $name.\n" if $DEBUG;
    }

    return $found_path;
}

#
# Locate paths to the executables we need for optimizations.  For each
# one, check the user's path (using 'which'), then try to fall back on
# search paths specified in globals at top of the script.
#
sub locateBinaries
{
    $jpegtran_path = locateBin('jpegtran', @jpegtran_paths);
    $pngcrush_path = locateBin('pngcrush', @pngcrush_paths);
    $gifsicle_path = locateBin('gifsicle', @gifsicle_paths);
    $convert_path = locateBin('convert', @convert_paths);
    $identify_path = locateBin('identify', @identify_paths);

    if (!$jpegtran_path) {
        $do_jpeg_compress = 0;
    }
    if (!$pngcrush_path) {
        $do_png_compress = 0;
    }
    if (!$gifsicle_path) {
        $do_gif_compress = 0;
    }
    if (!$identify_path || !$convert_path) {
        $do_png_compare = 0;
    }
}

sub writeSummary
{
    my $total_bytes_orig = $score->{'jpeg_bytes_orig'} + $score->{'png_bytes_orig'} + $score->{'gif_bytes_orig'};
    my $total_bytes_saved = $score->{'jpeg_bytes_saved'} + $score->{'png_bytes_saved'} + $score->{'gif_bytes_saved'};

    print "\n";
    print "----------------------------\n";
    print "  Summary\n";
    print "----------------------------\n";
    print "\n";

    if ($score->{'gif2png_bytes_saved'}) {
        print "  Converting the following GIFs to PNG would save additional file size.\n";
        print "  Bytes saved: $score->{'gif2png_bytes_saved'} "
               . "(orig $score->{'gif2png_bytes_orig'}, saved "
               . (int($score->{'gif2png_bytes_saved'}/$score->{'gif2png_bytes_orig'}*10000) / 100) 
               . "%)\n";
        print "\n";
        foreach my $file (@{$score->{'gif2png_files'}}) {
            print "    $file\n";
        }
        print "\n";
    }

    if ($score->{'jpeg_bytes_orig'}) {
        print "  Inspected $score->{'jpeg_count'} JPEG files.\n";
        print "  Modified $score->{'jpeg_modify'} files.\n";
        print "  Huffman table optimizations: $score->{'jpeg_optimize'}\n";
        print "  Progressive JPEG optimizations: $score->{'jpeg_progressive'}\n";
        print "  Bytes saved: $score->{'jpeg_bytes_saved'} "
               . "(orig $score->{'jpeg_bytes_orig'}, saved "
               . (int($score->{'jpeg_bytes_saved'}/$score->{'jpeg_bytes_orig'}*10000) / 100) 
               . "%)\n";
        print "\n";
    }
    if ($score->{'png_bytes_orig'}) {
        print "  Inspected $score->{'png_count'} PNG files.\n";
        print "  Modified $score->{'png_modify'} files.\n";
        print "  Bytes saved: $score->{'png_bytes_saved'} "
               . "(orig $score->{'png_bytes_orig'}, saved "
               . (int($score->{'png_bytes_saved'}/$score->{'png_bytes_orig'}*10000) / 100) 
               . "%)\n";
        print "\n";
    }
    if ($score->{'gif_bytes_orig'}) {
        print "  Inspected $score->{'gif_count'} GIF files.\n";
        print "  Modified $score->{'gif_modify'} files.\n";
        print "  Bytes saved: $score->{'gif_bytes_saved'} "
               . "(orig $score->{'gif_bytes_orig'}, saved "
               . (int($score->{'gif_bytes_saved'}/$score->{'gif_bytes_orig'}*10000) / 100) 
               . "%)\n";
        print "\n";
    }
    print "  Total bytes saved: $total_bytes_saved ";
    if ($total_bytes_orig) {
        print "(orig $total_bytes_orig, saved "
           . (int($total_bytes_saved/$total_bytes_orig*10000) / 100) 
           . "%)";
    }
    print "\n\n";
}

