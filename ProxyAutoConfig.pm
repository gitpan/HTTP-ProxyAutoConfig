##############################################################################
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Library General Public
#  License as published by the Free Software Foundation; either
#  version 2 of the License, or (at your option) any later version.
#
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Library General Public License for more details.
#
#  You should have received a copy of the GNU Library General Public
#  License along with this library; if not, write to the
#  Free Software Foundation, Inc., 59 Temple Place - Suite 330,
#  Boston, MA  02111-1307, USA.
#
#  Jabber
#  Copyright (C) 1998-1999 The Jabber Team http://jabber.org/
#
##############################################################################

package HTTP::ProxyAutoConfig;

=head1 NAME

HTTP::ProxyAutoConfig - provides a unifed way to get the proxy information

=head1 SYNOPSIS

HTTP::ProxyAutoConfig is a module that allows perl scripts that need
access to proxy servers to utilize the standard proxy settings provided
by an IT department.

=head1 DESCRIPTION

This module provides a consistent method for finding the proxy server
needed to talk to for a given URL.  It can handle parsing the http_proxy,
https_proxy, ftp_proxy, and http_auto_proxy variables to determine
what it is you want it to do.  If you set the http_auto_proxy variable
it overrides the others and fetches the PAC file from there and uses
those settings.

Access to the proxy information is provided in a single function call
to FindProxyForURL(url,host).  A string is returned that tells you what
to do, either "DIRECT", "PROXY host:port", or "SOCKS host:port".

The Proxy Auto Config format and rules are defined at Netscape:

http://home.netscape.com/eng/mozilla/2.0/relnotes/demo/proxy-live.html

The file basically works by defining a JavaScript function called
FindProxyForURL.  This module fetches that file and converts the
JavaScript function into a Perl function and then defines the Perl
function with that converted data.

=head1 METHODS

  new(url) - creates the FindProxyForURL function and the object.
             The url argument is optional, and points to the auto-proxy
             file provided on your network.  If you do not specify a
             url, then it will check the http_auto_proxy variable,
             followed by the http_proxy, https_proxy, and ftp_proxy
             variables.

  my $pac = new HTTP::ProxyAutoConfig("http://foo.bar/auto-proxy.pac");
  my $pac = new HTTP::ProxyAutoConfig();

  FindProxyForURL(url,host) - takes the url, and the host (minus
                              port) from the URL, and determines the
                              action you should take to contact that
                              host.  It returns one of three things:

                                DIRECT           - connect directly to them
                                PROXY host:port  - connect via the proxy
                                SOCKS host:port  - connect via SOCKS

  FindProxy(url) - calls the FindProxyForURL function and passes it the
                   correct options.  This is just a wrapper.

  Reload() - allows you to fetch the PAC again and regenerate the
             FindProxyForURL function based on anything you might
             have changed in the environment.

=head1 AUTHOR

By Ryan Eatmon in May of 2001

=head1 COPYRIGHT

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

use strict;
use Carp;
use Sys::Hostname;
use IO::Socket;
use POSIX;
use vars qw($VERSION );

$VERSION = "0.1";


sub new {
  my $proto = shift;
  my $self = { };

  bless($self,$proto);

  $self->{URL} = shift if ($#_ > -1);
  $self->Reload();
  return $self;
}


##############################################################################
#
# FindProxy - wrapper for FindProxyForURL function so that you don't have to
#             figure out the host.
#
##############################################################################
sub FindProxy {
  my $self = shift;
  my ($url) = @_;

  my ($host) = ($url =~ /^(\S*\:?\/?\/?[^\/:]+)/);
  $host =~ s/^[^\:]+\:\/\///;

  foreach my $proxy (split(/\s*\;\s*/,$self->FindProxyForURL($url,$host))) {
    return $proxy if ($proxy eq "DIRECT");
    my ($host,$port) = ($proxy =~ /^PROXY\s*(\S+):(\d+)$/);

    return $proxy if (new IO::Socket::INET(PeerAddr=>$host,
					   PeerPort=>$port,
					   Proto=>"tcp"));
  }

  return undef;
}


##############################################################################
#
# Reload - grok the environment variables and define the FindProxyForURL
#          function.
#
##############################################################################
sub Reload  {
  my $self = shift;

  my $url = (exists($self->{URL}) ? $self->{URL} : $ENV{"http_auto_proxy"});

  if (defined($url) && ($url ne "")) {

    my ($host,$port,$path) = ($url =~ /^http:\/\/([^\/:]+):?(\d*)\/?(.*)$/);

    $port = 80 if ($port eq "");

    my $sock = new IO::Socket::INET(PeerAddr=>$host,
				    PeerPort=>$port,
				    Proto=>"tcp");

    die("Cannot create normal socket: $!") unless defined($sock);

    my $send = "GET /$path HTTP/1.1\r\nCache-Control: no-cache\r\nHost: $host:$port\r\n\r\n";

    $sock->syswrite($send,length($send),0);

    my $buff;
    my $status = 1;
    my $function = "";
    while($status > 0) {
      $status = $sock->sysread($buff,POSIX::BUFSIZ);
      $function .= $buff;
    }

    my $chunked = ($function =~ /chunked/);

    $function =~ s/^.+?\r?\n\r?\n//s;
    if ($chunked == 1) {
      $function =~ s/\n\r\n\S+\s*\r\n/\n/g;
      $function =~ s/^\S+\s*\r\n//;
    }

    $function = $self->JavaScript2Perl($function);

    eval($function);
  } else {
    my $http_host;
    my $http_port;
    my $function = "sub FindProxyForURL { my (\$self,\$url,\$host) = \@_; ";
    $function .= "if (isResolvable(\$host)) { return \"DIRECT\"; }  ";
    if (exists($ENV{http_proxy})) {
      ($http_host,$http_port) = ($ENV{"http_proxy"} =~ /^(\S+)\:(\d+)$/);
      $http_host =~ s/^http\:\/\///;
      $function .= "if (shExpMatch(\$url,\"http://*\")) { return \"PROXY $http_host\:$http_port\"; }  ";
    }
    if (exists($ENV{https_proxy})) {
      my($host,$port) = ($ENV{"https_proxy"} =~ /^(\S+)\:(\d+)$/);
      $host =~ s/^https?\:\/\///;
      $function .= "if (shExpMatch(\$url,\"https://*\")) { return \"PROXY $host\:$port\"; }  ";
    }
    if (exists($ENV{ftp_proxy})) {
      my($host,$port) = ($ENV{"ftp_proxy"} =~ /^(\S+)\:(\d+)$/);
      $host =~ s/^ftp\:\/\///;
      $function .= "if (shExpMatch(\$url,\"ftp://*\")) { return \"PROXY $host\:$port\"; }  ";
    }
    if (defined($http_host) && defined($http_port)) {
      $function .= "  return \"PROXY $http_host\:$http_port\"; }";
    } else {
      $function .= "  return \"DIRECT\"; }";
    }
    eval($function);
  }
}


##############################################################################
#
# JavaScript2Perl - function to convert JavaScript code into Perl code.
#
##############################################################################
sub JavaScript2Perl {
  my $self = shift;
  my ($function) = @_;

  my $quoted = 0;
  my $blockComment = 0;
  my $lineComment = 0;
  my $newFunction = "";

  my %vars;
  my $variable;

  foreach my $piece (split(/(\s)/,$function)) {
    foreach my $subpiece (split(/([\"\'\=])/,$piece)) {
      next if ($subpiece eq "");
      if ($subpiece eq "=") {
	$vars{$variable} = 1;
      }
      $variable = $subpiece unless ($subpiece eq " ");

      $subpiece = "." if (($quoted == 0) && ($subpiece eq "+"));

      $lineComment = 0 if ($subpiece eq "\n");
      $quoted ^= 1 if (($blockComment == 0) &&
		       ($lineComment == 0) &&
		       ($subpiece =~ /(\"|\')/));
      if (($quoted == 0) && ($subpiece =~ /\/\*/)) {
	$blockComment = 1;
      } elsif (($quoted == 0) && ($subpiece =~ /\/\//)) {
	$lineComment = 1;
      } elsif (($blockComment == 1) && ($subpiece =~ /\*\//)) {
	$blockComment = 0;
      } else {
	$newFunction .= $subpiece
	  unless (($blockComment == 1) || ($lineComment == 1));
      }
    }
  }

  $newFunction =~ s/^\s*function\s*(\S+)\s*\(\s*([^\,]+)\s*\,\s*([^\)]+)\s*\)\s*\{/sub $1 \{\n  my \(\$self,$2,$3\) = \@_\;\n  my(\$stub);\n/;
  $vars{$2} = 2;
  $vars{$3} = 2;

  $quoted = 0;
  my $finalFunction = "";

  foreach my $piece (split(/(\s)/,$newFunction)) {
    if ($piece eq "my(\$stub);") {
      $piece = "my(\$stub";
      foreach my $var (keys(%vars)) {
	next if ($vars{$var} == 2);
	$piece .= ",\$".$var;
      }
      $piece .= ");";
    }
    foreach my $subpiece (split(/([\"\'\=\,\+\)\(])/,$piece)) {
      next if ($subpiece eq "");
      $quoted ^= 1 if (($blockComment == 0) &&
		       ($lineComment == 0) &&
		       ($subpiece =~ /(\"|\')/));
      $subpiece = "\$".$subpiece
	if (($quoted == 0) && exists($vars{$subpiece}));
      $finalFunction .= $subpiece;
    }
  }

  return $finalFunction;
}


##############################################################################
#
# isPlainHostName - PAC command that tells if this is a plain host name
#                   (no dots)
#
##############################################################################
sub isPlainHostName {
  my ($host) = @_;

  return (($host =~ /\./) ? 0 : 1);
}


##############################################################################
#
# dnsDomainIs - PAC command to tell if the host is in the domain.
#
##############################################################################
sub dnsDomainIs {
  my ($host,$domain) = @_;

  $domain =~ s/\./\\\./;
  return (($host =~ /$domain$/) ? 1 : 0);
}


##############################################################################
#
# localHostOrDomainIs - PAC command to tell if the host matches, or if it is
#                       unqaulifed and in the domain.
#
##############################################################################
sub localHostOrDomainIs {
  my ($host,$hostdom) = @_;

  return 1 if ($host eq $hostdom);
  return 0 if ($host =~ /\./);
  return 1 if ($hostdom =~ /^$host/);
}


##############################################################################
#
# isResolvable - PAC command to see if the host can be resolved via DNS.
#
##############################################################################
sub isResolvable {
  my ($host) = @_;
  return (defined(gethostbyname($host)) ? 1 : 0);
}


##############################################################################
#
# isInNet - PAC command to see if the IP address is in this network based on
#           the mask and pattern.
#
##############################################################################
sub isInNet {
  my ($host,$pattern,$mask) = @_;

  my $addr = dnsResolve($host);
  return unless defined($addr);

  my @addr = split(/\./,$addr);
  my @mask = split(/\./,$mask);
  my @pattern;

  foreach my $count (0..3) {
    my $bitAddr = dec2bin($addr[$count]);
    my $bitMask = dec2bin($mask[$count]);

    $pattern[$count] = bin2dec($bitAddr & $bitMask),"\n";
  }

  my $hostPattern = join(".",@pattern);
  return (($pattern eq $hostPattern) ? 1 : 0);
}


##############################################################################
#
# dec2bin - decimal to binary conversion
#
##############################################################################
sub dec2bin {
  my $str = unpack("B32", pack("N", shift));
  return $str;
}


##############################################################################
#
# bin2dec - binary to decimal conversion
#
##############################################################################
sub bin2dec {
  return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}


##############################################################################
#
# dnsResolve - PAC command to get the IP from the host name.
#
##############################################################################
sub dnsResolve {
  my ($host) = @_;
  return unless isResolvable($host);
  return inet_ntoa(inet_aton($host));
}


##############################################################################
#
# myIpAddress - PAC command to get your IP.
#
##############################################################################
sub myIpAddress {
  return inet_ntoa(inet_aton(hostname()));
}


##############################################################################
#
# dnsDomainLevels - PAC command to tell how many domain levels there are in
#                   the host name (number of dots).
#
##############################################################################
sub dnsDomainLevels {
  my ($host) = @_;

  my $count = 0;
  foreach my $piece (split(/(\.)/,$host)) {
    $count++ if ($piece eq ".");
  }
  return $count;
}


##############################################################################
#
# shExpMatch - PAC command to see if a URL/path matches the shell expression.
#              Shell expressions are like  */foo/*  or http://*.
#
##############################################################################
sub shExpMatch {
  my ($str,$shellExp) = @_;

  $shellExp =~ s/\//\\\//g;
  $shellExp =~ s/\*/\.\*/g;

  return (($str =~ /$shellExp/) ? 1 : 0);
}


##############################################################################
#
# weekDayRange - PAC command to see if the current weekday falls within a
#                range.
#
##############################################################################
sub weekDayRange {
  my $wd1 = shift;
  my $wd2 = "";
  $wd2 = shift if ($_[0] ne "GMT");
  my $gmt = "";
  $gmt = shift if ($_[0] eq "GMT");

  my %wd = ( SUN=>0,MON=>1,TUE=>2,WED=>3,THU=>4,FRI=>5,SAT=>6);
  my $dow = (($gmt eq "GMT") ? (gmtime)[6] : (localtime)[6]);

  if ($wd2 eq "") {
    return (($dow eq $wd{$wd1}) ? 1 : 0);
  } else {
    my @range;
    if ($wd{$wd1} < $wd{$wd2}) {
      @range = ($wd{$wd1}..$wd{$wd2});
    } else {
      @range = ($wd{$wd1}..6,0..$wd{$wd2});
    }
    foreach my $tdow (@range) {
      return 1 if ($dow eq $tdow);
    }
    return 0;
  }
  return 0;
}


##############################################################################
#
# dateRange - PAC command to see if the current date falls within a range.
#
##############################################################################
sub dateRange {
  my %mon = ( JAN=>0,FEB=>1,MAR=>2,APR=>3,MAY=>4,JUN=>5,JUL=>6,AUG=>7,SEP=>8,OCT=>9,NOV=>10,DEC=>11);

  my %args;
  my $dayCount = 1;
  my $monCount = 1;
  my $yearCount = 1;

  while ($#_ > -1) {
    if ($_[0] eq "GMT") {
      $args{gmt} = shift;
    } elsif (exists($mon{$_[0]})) {
      my $month = shift;
      $args{"mon$monCount"} = $mon{$month};
      $monCount++;
    } elsif ($_[0] > 31) {
      $args{"year$yearCount"} = shift;
      $yearCount++;
    } else {
      $args{"day$dayCount"} = shift;
      $dayCount++;
    }
  }

  my $mday = (exists($args{gmt}) ? (gmtime)[3] : (localtime)[3]);
  my $mon = (exists($args{gmt}) ? (gmtime)[4] : (localtime)[4]);
  my $year = 1900+(exists($args{gmt}) ? (gmtime)[5] : (localtime)[5]);

  if (exists($args{day1}) && exists($args{mon1}) && exists($args{year1}) &&
      exists($args{day2}) && exists($args{mon2}) && exists($args{year2})) {

    if (($args{year1} < $year) && ($args{year2} > $year)) {
      return 1;
    } elsif (($args{year1} == $year) && ($args{mon1} <= $mon)) {
      return 1;
    } elsif (($args{year2} == $year) && ($args{mon2} >= $mon)) {
      return 1;
    } else {
      return 0;
    }
    return 0;


  } elsif (exists($args{mon1}) && exists($args{year1}) &&
	   exists($args{mon2}) && exists($args{year2})) {
    if (($args{year1} < $year) && ($args{year2} > $year)) {
      return 1;
    } elsif (($args{year1} == $year) && ($args{mon1} < $mon)) {
      return 1;
    } elsif (($args{year2} == $year) && ($args{mon2} > $mon)) {
      return 1;
    } elsif (($args{year1} == $year) && ($args{mon1} == $mon) &&
	     ($args{day1} <= $mday)) {
      return 1;
    } elsif (($args{year2} == $year) && ($args{mon2} == $mon) &&
	     ($args{day2} >= $mday)) {
      return 1;
    } else {
      return 0;
    }
    return 0;
  } elsif (exists($args{day1}) && exists($args{mon1}) &&
	   exists($args{day2}) && exists($args{mon2})) {
    if (($args{mon1} < $mon) && ($args{mon2} > $mon)) {
      return 1;
    } elsif (($args{mon1} == $mon) && ($args{day1} <= $mday)) {
      return 1;
    } elsif (($args{mon2} == $mon) && ($args{day2} >= $mday)) {
      return 1;
    } else {
      return 0;
    }
    return 0;
  } elsif (exists($args{year1}) && exists($args{year2})) {
    foreach my $tyear ($args{year1}..$args{year2}) {
      return 1 if ($tyear == $year);
    }
    return 0;
  } elsif (exists($args{mon1}) && exists($args{mon2})) {
    foreach my $tmon ($args{mon1}..$args{mon2}) {
      return 1 if ($tmon == $mon);
    }
    return 0;
  } elsif (exists($args{day1}) && exists($args{day2})) {
    foreach my $tmday ($args{day1}..$args{day2}) {
      return 1 if ($tmday == $mday);
    }
    return 0;
  } elsif (exists($args{year1})) {
    return (($args{year1} == $year) ? 1 : 0);
  } elsif (exists($args{mon1})) {
    return (($args{mon1} == $mon) ? 1 : 0);
  } elsif (exists($args{day1})) {
    return (($args{day1} == $mday) ? 1 : 0);
  } else {
    return 0;
  }

  return 0;

}


##############################################################################
#
# timeRange - PAC command to see if the current time falls within a range.
#
##############################################################################
sub timeRange {
  my %args;
  my $dayCount = 1;
  my $monCount = 1;
  my $yearCount = 1;

  $args{gmt} = pop(@_) if ($_[$#_] eq "GMT");

  if ($#_ == 0) {
    $args{hour1} = shift;
  } elsif ($#_ == 1) {
    $args{hour1} = shift;
    $args{hour2} = shift;
  } elsif ($#_ == 3) {
    $args{hour1} = shift;
    $args{min1} = shift;
    $args{hour2} = shift;
    $args{min2} = shift;
  } elsif ($#_ == 5) {
    $args{hour1} = shift;
    $args{min1} = shift;
    $args{sec1} = shift;
    $args{hour2} = shift;
    $args{min2} = shift;
    $args{sec2} = shift;
  }

  my $sec = (exists($args{gmt}) ? (gmtime)[0] : (localtime)[0]);
  my $min = (exists($args{gmt}) ? (gmtime)[1] : (localtime)[1]);
  my $hour = (exists($args{gmt}) ? (gmtime)[2] : (localtime)[2]);

  if (exists($args{sec1}) && exists($args{min1}) && exists($args{hour1}) &&
      exists($args{sec2}) && exists($args{min2}) && exists($args{hour2})) {

    if (($args{hour1} < $hour) && ($args{hour2} > $hour)) {
      return 1;
    } elsif (($args{hour1} == $hour) && ($args{min1} <= $min)) {
      return 1;
    } elsif (($args{hour2} == $hour) && ($args{min2} >= $min)) {
      return 1;
    } else {
      return 0;
    }
    return 0;


  } elsif (exists($args{min1}) && exists($args{hour1}) &&
	   exists($args{min2}) && exists($args{hour2})) {
    if (($args{hour1} < $hour) && ($args{hour2} > $hour)) {
      return 1;
    } elsif (($args{hour1} == $hour) && ($args{min1} < $min)) {
      return 1;
    } elsif (($args{hour2} == $hour) && ($args{min2} > $min)) {
      return 1;
    } elsif (($args{hour1} == $hour) && ($args{min1} == $min) &&
	     ($args{sec1} <= $sec)) {
      return 1;
    } elsif (($args{hour2} == $hour) && ($args{min2} == $min) &&
	     ($args{sec2} >= $sec)) {
      return 1;
    } else {
      return 0;
    }
    return 0;
  } elsif (exists($args{sec1}) && exists($args{min1}) &&
	   exists($args{sec2}) && exists($args{min2})) {
    if (($args{min1} < $min) && ($args{min2} > $min)) {
      return 1;
    } elsif (($args{min1} == $min) && ($args{sec1} <= $sec)) {
      return 1;
    } elsif (($args{min2} == $min) && ($args{sec2} >= $sec)) {
      return 1;
    } else {
      return 0;
    }
    return 0;
  } elsif (exists($args{hour1}) && exists($args{hour2})) {
    foreach my $thour ($args{hour1}..$args{hour2}) {
      return 1 if ($thour == $hour);
    }
    return 0;
  } elsif (exists($args{min1}) && exists($args{min2})) {
    foreach my $tmin ($args{min1}..$args{min2}) {
      return 1 if ($tmin == $min);
    }
    return 0;
  } elsif (exists($args{sec1}) && exists($args{sec2})) {
    foreach my $tsec ($args{sec1}..$args{sec2}) {
      return 1 if ($tsec == $sec);
    }
    return 0;
  } elsif (exists($args{hour1})) {
    return (($args{hour1} == $hour) ? 1 : 0);
  } elsif (exists($args{min1})) {
    return (($args{min1} == $min) ? 1 : 0);
  } elsif (exists($args{sec1})) {
    return (($args{sec1} == $sec) ? 1 : 0);
  } else {
    return 0;
  }

  return 0;

}


1;
