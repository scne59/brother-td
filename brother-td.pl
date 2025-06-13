#!/usr/bin/perl
use strict;
use warnings;
use USB::LibUSB;
use Imager;
use Getopt::Long;
use POSIX 'ceil';
use File::Temp qw/ :POSIX /;
use File::Type;

no warnings "experimental::for_list";

=pod

=head1 NAME

brother-td.pl - A script to print on Brother label printers of the TD series

=head1 SYNOPSIS

brother-td.pl -f filename [-r] [-l label_size] [-t label_type] [-p printer_name] [-s printer_serial] [-d] [-m [dither_algo]] [-b] [-n num_copies]

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

=item USB:LibUSB

=back

=head1 Command Line Options

=over 12

=item C<-f|--file> (required)

File path of the image to print. Can be in any format libimager supports.

=item C<-t|--type> (optional, defaults to "d")

Set label type.
"d" - die-cut labels, "c" - continous length tape

=item C<-l|--label [WIDTHxHEIGHT]> (optional, defaults to "102x200")

Set label format in mm. For continous length tape HEIGHT is ignored.

=item C<-r|--rotate> (optional)

Rotate image 90 degrees.

=item C<-m|--dither> (optional)

Apply dither to color/grayscale images.
Defaults to "floyd".
Accepts "floyd", "stucki" and "jarvis" as dither values.

=item C<-b> (optional)

Use black margin pixels.

=item C<-p|--product [printer_name]> (optional)

Set printer name for USB device discovery (see list of supported printers)

=item C<-s|--serial> (optional)

Set printer USB serial number (as given by `lsusb -v`) for USB dicovery.

=item C<-n|--number> (optional)

Set number of copies.

=item C<-d|--debug> (optional)

Enable debug output. Saves the converted image to "image.png" and the prepared raster data to "raster.dat".

=back

=head1 COPYRIGHT

Copyright (c) 2025 Jochen Schneider. 

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=head1 AUTHOR

Jochen Schneider <j@lz44.de>

=cut

my $image_file = '';
my $label_size = '102x200';
my $label_type = 'd';
my $label_type_cmd = "\x0b";
my $rotate = '';
my $label_width;
my $label_height=0;
my $printer_serial='';
my $printer_name='';
my $debug = '';
my $dither;
my %dither_modes = ( 'floyd' => 'floyd',
                    'jarvis' => 'jarvis',
                    'stucki' => 'stucki' );
my $margin_color = 0;
my $num_pages = 1;

Getopt::Long::Configure ("auto_help", "no_auto_abbrev");
GetOptions(
    "file|f=s" => \$image_file,
    "rotate|r!" => \$rotate,
    "label|l=s" => \$label_size,
    "type|t=s" => \$label_type,
    "product|p=s" => \$printer_name,
    "serial|s=s" => \$printer_serial,
    "debug|d!" => \$debug,
    "dither|m:s" => \$dither,
    "b!" => \$margin_color,
    "number|n=i", \$num_pages,
);

$dither = 'floyd' if defined($dither) && $dither eq '';

#if ($image_file eq '') { die "no image file\n"};

if ($label_type eq 'c') {
    $label_size=~/(\d*)/;
    $label_width=$1;
}
else {
    if ($label_size=~/(\d*)x(\d*)/) {
        ($label_width, $label_height) = ($1,$2);
    }
    else {
        die "label option not recognized\n";
    }
}

# Printer settings for Brother TD-4210D
my $VENDOR_ID  = 0x04f9;    # Brother vendor ID
my %devices = (
    0x20f2 => {'name' => 'TD-4210D',    'dpi' => 203, 'model' => '\x43'},
    0x20b6 => {'name' => 'TD-4410D',    'dpi' => 203, 'model' => '\x37'},
    0x20b7 => {'name' => 'TD-4420DN',   'dpi' => 203, 'model' => '\x38'},
    0x20b8 => {'name' => 'TD-4510D',    'dpi' => 300, 'model' => '\x39'},
    0x20b9 => {'name' => 'TD-4520DN',   'dpi' => 300, 'model' => '\x41'},
    0x20ba => {'name' => 'TD-4550DNWB', 'dpi' => 300, 'model' => '\x42'},
);

my $usb = USB::LibUSB->init();
my $printer = find_printer($usb, $VENDOR_ID, $printer_name, $printer_serial) or die "Printer not found\n";
my $dev = $printer->get_device();
my $desc = $dev->get_device_descriptor();
my $pid = $desc->{idProduct};

my $EP_OUT     = 0x02;
my $DPI        = $devices{$pid}{dpi};
my $MM_PER_INCH = 25.4;
my $RASTER_PIXELS = ( $DPI==203 ) ? 832 : 1280;
my $MAX_LENGTH = 3000 / $MM_PER_INCH * $DPI;

my $MAX_WIDTH  = int($label_width * $DPI / $MM_PER_INCH);
my $MAX_HEIGHT = int($label_height * $DPI / $MM_PER_INCH)-48;

if ($label_type eq 'c'){
    $MAX_HEIGHT = $MAX_LENGTH;
    $label_type_cmd = "\x0a";
}

eval {
    $printer->claim_interface(0);
    $printer->set_interface_alt_setting(0, 0);
};
if ($@) {
    $printer->close();
    die "Interface claim failed: $@\n";
}

my $ft = File::Type->new();
my $type = $ft->checktype_filename($image_file);
#print $type,"\n";exit;
if ($type eq 'application/pdf') {
    my $png_tmp = File::Temp->new(SUFFIX => '.png');
    `convert -density $DPI -units pixelsperinch $image_file $png_tmp`;
    print_image($printer, $png_tmp);
} elsif ($image_file=~/.*\.svg/i){
    my $png_tmp = File::Temp->new(SUFFIX => '.png');
    `convert -density $DPI -units pixelsperinch $image_file $png_tmp`;
    print_image($printer, $png_tmp);
} else {
    print_image($printer, $image_file);
}

$printer->release_interface(0);
$printer->close();

exit 0;

sub find_printer {
    my ($usb, $vid, $name, $serial) = @_;
    my $handle;
    if ($name eq '' && $serial eq '') {
        foreach my ($pid) (%devices) {
            $handle = eval { $usb->open_device_with_vid_pid($vid, $pid) } or next;
            eval {
                if ($handle->kernel_driver_active(0)) {
                    $handle->detach_kernel_driver(0);
                }
            };
            return $handle;
        }
    } elsif ($name ne '' && $serial eq '') {
        foreach my ($pid) (%devices) {
            if ($devices{$pid}{'name'} eq $name) {
                $handle = eval { $usb->open_device_with_vid_pid($vid, $pid) } or next;
                eval {
                    if ($handle->kernel_driver_active(0)) {
                        $handle->detach_kernel_driver(0);
                    }
                };
                return $handle;
            }
        }
    } elsif ($serial ne '') {
        print "using serial $serial\n";
        foreach my ($pid) (%devices) {
            $handle = eval { $usb->open_device_with_vid_pid_serial($vid, $pid, $serial) } or next;
            eval {
                if ($handle->kernel_driver_active(0)) {
                    $handle->detach_kernel_driver(0);
                }
            };
            return $handle;
        }
    } else {
        return undef;
    }
}

sub print_image {
    my ($printer, $filename) = @_;
    my $width_ratio=0;
    my $height_ratio=0;
    my $scalefactor=0;

    my $image = Imager->new(file => $filename) or die "Can't load image $filename : $!";
    if($rotate) {
        $image = $image->rotate(degrees => 90);
    }
    my ($width, $height) = ($image->getwidth(), $image->getheight());

    $width_ratio  = $MAX_WIDTH/$width;
    $height_ratio = $MAX_HEIGHT/$height;
    $scalefactor = ($width_ratio < $height_ratio) ? $width_ratio : $height_ratio;
    
    if ($scalefactor < 1){
        $image = $image->scale(scalefactor => $scalefactor);
        ($width, $height) = ($image->getwidth(), $image->getheight());
    }

    if ($label_type eq 'c') {
        $label_height = ceil($height/$DPI*$MM_PER_INCH);
    }

    if ($dither) {
        my $errdiff;
        if ($dither_modes{$dither} ne '') {$errdiff = $dither_modes{$dither}}
        $image = $image->to_paletted({    make_colors => 'mono',
                                          translate => 'errdiff',
                                          errdiff => $errdiff });
    } else {
        $image = $image->convert(preset => 'gray');
    }
    if ($debug) {
        $image->write(file=>"image.png");
    }

    my $raster_data;

    my $margin_pixels = $RASTER_PIXELS-$width;

    for my $raster_line (0 .. $height-1) {
        my $line;
        for(1..$margin_pixels/2){
            $line.=$margin_color;    
        }
        for (my $raster_column = $width-1;$raster_column>=0;$raster_column--) {
            my $color = $image->getpixel(x => $raster_column,y => $raster_line);
            my ($r) = $color->rgba;
            $line.= ($r > 128) ? 0 : 1;
        }
        for(1..($RASTER_PIXELS-length($line))){
            $line.=$margin_color;    
        }
        $raster_data.="\x67\x00\x68";
        my $cursor=0;
        while ($cursor<=$RASTER_PIXELS-8){
            my $bitsring=substr($line,$cursor,8);
            $raster_data.=pack("B8",$bitsring);
            $cursor+=8;
        }
    }

    if ($debug) {
        open RASTER,">raster.dat";
        print RASTER $raster_data;
        close RASTER;
    }
    
    my $commands = create_printer_commands($width, $height, $raster_data);
    my $bytes_sent = $printer->bulk_transfer_write($EP_OUT, $commands, 5000);
    unless ($bytes_sent == length($commands)) {
        die "Failed to send data. Sent $bytes_sent/".length($commands)." bytes\n";
    }
    
    print "Printed successfully ($width x $height dots at $DPI DPI)\n";
}

sub create_printer_commands {
    my ($width, $height, $image_data) = @_;
    
    my $commands = "";
    my $init_commands = "";
    my $control_commands = "";
    my $raster_commands = "";
    $init_commands .= pack('C350',0);                           # send 350 null bytes to invalidate
    $init_commands .= "\x1b\x40";                               # ESC @ - Initialize
    $control_commands .= "\x1b\x69\x61\x01";                       # switch printer to raster mode
    $control_commands .= "\x1b\x69\x21\x00";                       # switch automatic status notification to off
    my $print_information_command = "\x1b\x69\x7a";
    $print_information_command .= "\x8e";                  # #define PI_KIND 0x02// Media type #define PI_WIDTH 0x04// Media width #define PI_LENGTH 0x08// Media length #define PI_RECOVER 0x80// Printer recovery always on (n1)
    $print_information_command .= $label_type_cmd;                  # 0x0b - die cut label, 0x0a - continous length tape (n2)
    $print_information_command .= pack('C', $label_width); # label width (mm) (n3)
    $print_information_command .= pack('C', $label_height);# label length (mm) (n4)
    $print_information_command .= pack('V', $height);      # 4 bytes of raster length (n5-n8)
    $print_information_command .= "\x00";                  # Starting page: 0 - Other pages: 1 (n9)
    $print_information_command .= "\x00";                  # fixed (n10)
    $control_commands .= $print_information_command;
    $control_commands .= "\x1b\x69\x64\x18\x00";                  
    $control_commands .= "\x4d\x00";

    $commands.=$init_commands;
    for (my $i=0;$i<=$num_pages;$i++) {
            print "printing page $i\n";
            $commands .= $control_commands;
            $commands .= $image_data;
            if ($i < $num_pages) {
                $commands .= "\x0c";                       # print without LF
                print "next\n";
            }
    }                              
    $commands .= "\x1a";                                  # print with feeding
    print "last\n";
    
    if($debug) {
        open(COMMANDS,">commands.prn");
        print COMMANDS $commands;
        close COMMANDS;
    }
    #exit;

    return $commands;
}
