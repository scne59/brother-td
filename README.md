# NAME

brother-td.pl - A script to print on Brother label printers of the TD series

# SYNOPSIS

brother-td.pl -f filename \[-r\] \[-l label\_size\] \[-t label\_type\] \[-p printer\_name\] \[-s printer\_serial\] \[-d\]

# DESCRIPTION

This script can print image files to a USB connected Brother label printer.
The following devices are supported:

- TD-4410D
- TD-4420DN
- TD-4510D
- TD-4520DN
- TD-4550DNWB
- TD-4210D

It requires the following modules to work:

- Imager
- USB:LibUSB

# Command Line Options

- `-f|--file` (required)

    File path of the image to print. Can be in any format libimager supports.

- `-t|--type` (optional, defaults to "d")

    Set label type.
    "d" - die-cut labels, "c" - continous length tape

- `-l|--label [WIDTHxHEIGHT]` (optional, defaults to "102x200")

    Set label format in mm. For continous length tape HEIGHT is ignored.

- `-r|--rotate` (optional)

    Rotate image 90 degrees.

- `-p|--product [printer_name]` (optional)

    Set printer name for USB device discovery (see list of supported printers)

- `-s|--serial` (optional)

    Set printer USB serial number (as given by \`lsusb -v\`) for USB dicovery.

- `-d|--debug` (optional)

    Enable debug output. Saves the converted image to "image.png" and the prepared raster data to "raster.dat".

# COPYRIGHT

Copyright (c) 2025 Jochen Schneider. 

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# AUTHOR

Jochen Schneider <j@lz44.de>
