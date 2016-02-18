# <@LICENSE>
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to you under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# </@LICENSE>

=head1 NAME

OLE2Macro - Look for Macro Embedded Microsoft Word and Excel Documents

=head1 SYNOPSIS

  loadplugin     ole2macro.pm
  body MICROSOFT_OLE2MACRO eval:check_microsoft_ole2macro()
  score MICROSOFT_OLE2MACRO 4

=head1 DESCRIPTION

Detects embedded OLE2 Macros embedded in Word and Excel Documents. Based on:
https://blog.rootshell.be/2015/01/08/searching-for-microsoft-office-files-containing-macro/

10/12/2015 - Jonathan Thorpe - jthorpe@conexim.com.au

=back

=cut

package OLE2Macro;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Util;
use IO::Uncompress::Unzip;

use strict;
use warnings;
use bytes;
use re 'taint';

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

#File types and markers
my $match_types = qr/(?:xls|ppt|doc|docm|dot|dotm|xlsm|xlsb|pptm|ppsm)$/;

#Markers in the other in which they should be found.
my @markers = ("\xd0\xcf\x11\xe0", "\x00\x41\x74\x74\x72\x69\x62\x75\x74\x00");

# limiting the number of files within archive to process
my $archived_files_process_limit = 3;
# limiting the amount of bytes read from a file
my $file_max_read_size = 102400;
# limiting the amount of bytes read from an archive
my $archive_max_read_size = 1024000;

# constructor: register the eval rule
sub new {
  my $class = shift;
  my $mailsaobject = shift;

  # some boilerplate...
  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsaobject);
  bless ($self, $class);

  $self->register_eval_rule("check_microsoft_ole2macro");

  return $self;
}

sub check_microsoft_ole2macro {
  my ($self, $pms) = @_;

  _check_attachments(@_) unless exists $pms->{nomacro_microsoft_ole2macro};
  return $pms->{nomacro_microsoft_ole2macro};
}

sub _match_markers {
   my ($data) = @_;

   my $matched=0;
   foreach(@markers){
     if(index($data, $_) > -1){
        $matched++;
     } else {
        last;
     }
   }

   return $matched == @markers;
}

sub _check_attachments {
  my ($self, $pms) = @_;

  my $processed_files_counter = 0;
  $pms->{nomacro_microsoft_ole2macro} = 0;

  foreach my $p ($pms->{msg}->find_parts(qr/./, 1)) {
    my ($ctype, $boundary, $charset, $name) =
      Mail::SpamAssassin::Util::parse_content_type($p->get_header('content-type'));

    $name = lc($name || '');
    if ($name =~ $match_types) {
          my $contents = $p->decode($file_max_read_size);
          if(_match_markers($contents)){
             $pms->{nomacro_microsoft_ole2macro} = 1;
             last;
          }
    } elsif ($name =~ /(?:zip)$/) {
          my $contents = $p->decode($archive_max_read_size);
          my $z = new IO::Uncompress::Unzip \$contents;

          my $status;
          my $buff;
          for ($status = 1; $status > 0; $status = $z->nextStream()) {
             if (lc $z->getHeaderInfo()->{Name} =~ $match_types) {
                 $processed_files_counter += 1;
                 if ($processed_files_counter > $archived_files_process_limit) {
                     dbg( "Stopping processing archive on file ".$z->getHeaderInfo()->{Name}.": processed files count limit reached\n" );
                     last;
                 }
                 my $attachment_data = "";
                 my $read_size = 0;
                 while (($status = $z->read( $buff )) > 0) {
                     $attachment_data .= $buff;
                     $read_size += length( $buff );
                     if ($read_size > $file_max_read_size) {
                         dbg( "Stopping processing file ".$z->getHeaderInfo()->{Name}." in archive: processed file size overlimit\n" );
                         last;
                     }
                 }

                 if (_match_markers( $attachment_data )) {
                     $pms->{nomacro_microsoft_ole2macro} = 1;
                     last;
                 }
             }
          }
    }
  }
}

1;
