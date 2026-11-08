#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;
my $lib = shift @ARGV;
my $handle = DynaLoader::dl_load_file($lib, 0) or die "cannot load $lib\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "nowplaying_clients")
  or die "symbol nowplaying_clients not found in $lib\n";
DynaLoader::dl_install_xsub("main::nowplaying_clients", $symbol);
no strict "refs";
&{"main::nowplaying_clients"}();
