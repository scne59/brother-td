#!/usr/bin/perl
use strict;
use warnings;
use USB::LibUSB;
use Imager;
use Getopt::Long;
use POSIX 'ceil';
use File::Temp ();
use File::Type;
use List::Util 'min';

=pod

=head1 NAME

brother-td.pl - A script to print on Brother label printers of the TD series

=head1 SYNOPSIS

brother-td.pl -f filename [-r] [-l label_size] [-t label_type] [-p printer_name] [-s printer_serial] [-d] [-m [dither_algo]] [-b] [-i] [-n num_copies]

=head1 DESCRIPTION

This script can print image files to a USB connected Brother label printer.
The following devices are supported:

=over

=item TD-4410D

=item TD-4420DN

=item TD-4510D

=item TD-4520DN

=item TD-4550DNWB

=item TD-4210D

=back

It requires the following modules to work:

=over

=item Imager

=item USB::LibUSB

=back

=head1 Command Line Options

=over 12

=item C<-f|--file> (required)

File path of the image to print. Can be in any format libimager supports.

=item C<-t|--type> (optional, defaults to "d")

Set label type.
"d" - die-cut labels, "c" - continuous length tape

=item C<-l|--label [WIDTHxHEIGHT]> (optional, defaults to "102x200")

Set label format in mm. For continuous length tape HEIGHT is ignored.

=item C<-r|--rotate> (optional)

Rotate image 90 degrees.

=item C<-m|--dither> (optional)

Apply dither to color/grayscale images.
Defaults to "floyd".
Accepts "floyd", "stucki" and "jarvis" as dither values.

=item C<-b> (optional)

Use black margin pixels.

=item C<-i> (optional)

Invert colors.

=item C<-p|--product [printer_name]> (optional)

Set printer name for USB device discovery (see list of supported printers)

=item C<-s|--serial> (optional)

Set printer USB serial number (as given by `lsusb -v`) for USB discovery.

=item C<-n|--number> (optional)

Set number of copies.

=item C<-d|--debug> (optional)

Enable debug output. Saves the converted image to "image.png", the prepared raster data to "raster.dat", and the printer commands to "commands.prn".

=back

=head1 COPYRIGHT

Copyright (c) 2025 Jochen Schneider. 

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=head1 AUTHOR

Jochen Schneider <j@lz44.de>

=cut

# Printer settings for the Brother TD series
my $VENDOR_ID = 0x04f9;
my %devices = (
    0x20f2 => { name => 'TD-4210D',    dpi => 203 },
    0x20b6 => { name => 'TD-4410D',    dpi => 203 },
    0x20b7 => { name => 'TD-4420DN',   dpi => 203 },
    0x20b8 => { name => 'TD-4510D',    dpi => 300 },
    0x20b9 => { name => 'TD-4520DN',   dpi => 300 },
    0x20ba => { name => 'TD-4550DNWB', dpi => 300 },
);

my %dither_modes = map { $_ => 1 } qw(floyd jarvis stucki);

my $MM_PER_INCH = 25.4;
my $MAX_TAPE_LENGTH_MM = 3000;
my $EP_OUT = 0x02;

my $image_file = '';
my $label_size = '102x200';
my $label_type = 'd';
my $label_width;
my $label_height = 0;
my $rotate = 0;
my $printer_serial = '';
my $printer_name = '';
my $debug = 0;
my $dither;
my $margin_color = 0;
my $inverted = 0;
my $num_copies = 1;

Getopt::Long::Configure('auto_help', 'no_auto_abbrev');
GetOptions(
    'file|f=s'    => \$image_file,
    'rotate|r!'   => \$rotate,
    'label|l=s'   => \$label_size,
    'type|t=s'    => \$label_type,
    'product|p=s' => \$printer_name,
    'serial|s=s'  => \$printer_serial,
    'debug|d!'    => \$debug,
    'dither|m:s'  => \$dither,
    'b!'          => \$margin_color,
    'number|n=i'  => \$num_copies,
    'i!'          => \$inverted,
) or die "Invalid command line arguments\n";

if (defined $dither) {
    $dither = 'floyd' if $dither eq '';
    die "Unknown dither mode '$dither' (use floyd, jarvis or stucki)\n"
        unless $dither_modes{$dither};
}

die "No image file given (use -f|--file)\n" if $image_file eq '';
die "Image file '$image_file' not found\n" unless -e $image_file;

die "Label type must be 'd' (die-cut) or 'c' (continuous)\n"
    unless $label_type eq 'd' || $label_type eq 'c';

die "Number of copies must be at least 1\n" if $num_copies < 1;

if ($label_type eq 'c') {
    die "Label width not recognized in '$label_size'\n"
        unless $label_size =~ /^(\d+)/;
    $label_width = $1;
}
else {
    die "Label option not recognized: '$label_size'\n"
        unless $label_size =~ /^(\d+)x(\d+)/;
    ($label_width, $label_height) = ($1, $2);
}

die "Label width must be greater than zero\n" unless $label_width > 0;
die "Label height must be greater than zero\n"
    if $label_type eq 'd' && $label_height <= 0;

my $label_type_cmd = ($label_type eq 'c') ? "\x0a" : "\x0b";

my $usb = USB::LibUSB->init();
my $printer = find_printer($usb, $VENDOR_ID, $printer_name, $printer_serial)
    or die "Printer not found\n";
my $dev = $printer->get_device();
my $desc = $dev->get_device_descriptor();
my $pid = $desc->{idProduct};

my $device = $devices{$pid}
    or die sprintf("Unsupported printer (USB PID 0x%04x)\n", $pid);

my $DPI = $device->{dpi};
my $RASTER_PIXELS = ($DPI == 203) ? 832 : 1280;

my $MAX_WIDTH = int($label_width * $DPI / $MM_PER_INCH);
my $MAX_HEIGHT = int($label_height * $DPI / $MM_PER_INCH) - 48;
$MAX_HEIGHT = int($MAX_TAPE_LENGTH_MM / $MM_PER_INCH * $DPI)
    if $label_type eq 'c';

eval {
    $printer->claim_interface(0);
    $printer->set_interface_alt_setting(0, 0);
    1;
} or do {
    my $error = $@;
    $printer->close();
    die "Interface claim failed: $error\n";
};

eval {
    my $input = prepare_input($image_file);
    print_image($printer, $input);
    1;
} or do {
    my $error = $@;
    $printer->release_interface(0);
    $printer->close();
    die $error;
};

$printer->release_interface(0);
$printer->close();

sub find_printer {
    my ($usb, $vid, $name, $serial) = @_;

    print "using serial $serial\n" if $serial ne '';

    for my $pid (keys %devices) {
        next if $serial eq '' && $name ne '' && $devices{$pid}{name} ne $name;

        my $handle = ($serial ne '')
            ? eval { $usb->open_device_with_vid_pid_serial($vid, $pid, $serial) }
            : eval { $usb->open_device_with_vid_pid($vid, $pid) };
        next unless $handle;

        eval {
            $handle->detach_kernel_driver(0) if $handle->kernel_driver_active(0);
        };
        return $handle;
    }

    return undef;
}

# Convert PDF and SVG input to a PNG that Imager can read. Returns either a
# temporary file handle (kept alive by the caller) or the original filename.
sub prepare_input {
    my ($filename) = @_;

    my $ft = File::Type->new();
    my $type = $ft->checktype_filename($filename);

    if ($type eq 'application/pdf') {
        my $png = File::Temp->new(SUFFIX => '.png');
        system('convert', '-density', $DPI, '-units', 'pixelsperinch',
            '-alpha', 'off', $filename, "$png") == 0
            or die "convert failed for '$filename'\n";
        return $png;
    }

    if ($filename =~ /\.svg\z/i) {
        my $png = File::Temp->new(SUFFIX => '.png');
        my $w = ($rotate ? $label_height : $label_width) . 'mm';
        my $h = ($rotate ? $label_width : $label_height) . 'mm';
        system('rsvg-convert', "--width=$w", "--height=$h",
            '--keep-aspect-ratio', "--dpi-x=$DPI", "--dpi-y=$DPI",
            $filename, '-o', "$png") == 0
            or die "rsvg-convert failed for '$filename'\n";
        return $png;
    }

    return $filename;
}

sub print_image {
    my ($printer, $filename) = @_;

    my $image = Imager->new(file => $filename)
        or die "Can't load image '$filename': " . Imager->errstr . "\n";

    $image = $image->rotate(degrees => 90) if $rotate;

    my ($width, $height) = ($image->getwidth(), $image->getheight());
    die "Image '$filename' has no pixels\n" unless $width && $height;

    my $scalefactor = min($MAX_WIDTH / $width, $MAX_HEIGHT / $height);
    if ($scalefactor < 1) {
        $image = $image->scale(scalefactor => $scalefactor);
        ($width, $height) = ($image->getwidth(), $image->getheight());
    }

    my $page_height = $label_height;
    $page_height = ceil($height / $DPI * $MM_PER_INCH) if $label_type eq 'c';

    if ($dither) {
        $image = $image->to_paletted({
            make_colors => 'mono',
            translate   => 'errdiff',
            errdiff     => $dither,
        });
    }
    else {
        $image = $image->convert(preset => 'gray');
    }

    if ($debug) {
        $image->write(file => 'image.png')
            or die "Can't write image.png: " . $image->errstr . "\n";
    }

    my $margin = $RASTER_PIXELS - $width;
    die "Image is wider than the print head ($width > $RASTER_PIXELS pixels)\n"
        if $margin < 0;

    my $margin_bit   = $margin_color ^ $inverted;
    my $left_margin  = int($margin / 2);
    my $right_margin = $margin - $left_margin;

    my @rows;
    for my $row (0 .. $height - 1) {
        my $line = $margin_bit x $left_margin;

        for (my $col = $width - 1; $col >= 0; $col--) {
            my $color = $image->getpixel(x => $col, y => $row);
            my ($r) = $color->rgba;
            $line .= (($r > 128) ? 0 : 1) ^ $inverted;
        }

        $line .= $margin_bit x $right_margin;
        push @rows, pack('B*', $line);
    }

    my $raster_data = join('', map { "\x67\x00\x68" . $_ } @rows);

    if ($debug) {
        write_file('raster.dat', $raster_data);
    }

    my $commands = create_printer_commands(
        raster_data  => $raster_data,
        height       => $height,
        label_width  => $label_width,
        label_height => $page_height,
        num_copies   => $num_copies,
    );

    my $bytes_sent = $printer->bulk_transfer_write($EP_OUT, $commands, 5000);
    unless ($bytes_sent == length $commands) {
        die "Failed to send data. Sent $bytes_sent/" . length($commands) . " bytes\n";
    }

    print "Printed successfully ($width x $height dots at $DPI DPI)\n";
}

sub create_printer_commands {
    my (%args) = @_;

    my $commands = pack('C350', 0)      # send 350 null bytes to invalidate
                 . "\x1b\x40";          # ESC @ - Initialize

    my $print_information = "\x1b\x69\x7a"
        . "\x8e"                        # PI_KIND 0x02, PI_WIDTH 0x04, PI_LENGTH 0x08, PI_RECOVER 0x80
        . $label_type_cmd               # 0x0b - die-cut label, 0x0a - continuous length tape (n2)
        . pack('C', $args{label_width})  # label width in mm (n3)
        . pack('C', $args{label_height}) # label length in mm (n4)
        . pack('V', $args{height})       # 4 bytes of raster length (n5-n8)
        . "\x00"                        # starting page: 0 - other pages: 1 (n9)
        . "\x00";                       # fixed (n10)

    my $page_commands = "\x1b\x69\x61\x01"      # switch printer to raster mode
                      . "\x1b\x69\x21\x00"      # switch automatic status notification off
                      . $print_information
                      . "\x1b\x69\x64\x18\x00"
                      . "\x4d\x00";

    for my $page (0 .. $args{num_copies} - 1) {
        $commands .= $page_commands . $args{raster_data};
        $commands .= "\x0c" if $page < $args{num_copies} - 1;  # print without LF
    }
    $commands .= "\x1a";                # print with feeding

    write_file('commands.prn', $commands) if $debug;

    return $commands;
}

sub write_file {
    my ($filename, $data) = @_;

    open my $fh, '>', $filename
        or die "Can't write '$filename': $!\n";
    print {$fh} $data;
    close $fh
        or die "Can't close '$filename': $!\n";
}
