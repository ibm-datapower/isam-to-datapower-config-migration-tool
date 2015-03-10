#!perl
#
# Copyright (c) 2015, IBM Corporation
# All rights reserved.
#
use MIME::Base64;
use Digest::SHA;
 
#----------------------------------------------------------------------
# parse an input file containing stanzas, parms and values, e.g.:
#    [stanza]
#    parm = value
# into a hash of hashes.  
#----------------------------------------------------------------------
sub parse_config_file {
   my($configfile, $unused) = @_;
   open(LISTA, $configfile) || die "Cannot open $configfile\n";
   print LOG "Parsing config file $configfile\n";
    
   while ( <LISTA> ) {     # read line into $_
     chomp;                # remove line end char
     next if ( /^\s*\#/ ); # ignore comment lines
     next if ( /^\s*$/ );  # ignore blank lines
     if ( /^\[(\S+)\]/ ) { # capture the stanza
        $stanza = $1;      
        $parms{$stanza} = () unless (keys %{$parms{$stanza}} > 0);
     } elsif ( /^\s*(\S*)\s*\=\s*(.*)$/ ) {
        my ($parm, $val) = ($1, $2); # capture the parm and value
        $val =~ s/\s*\r*$//g;        # strip trailing whitespace and carriage returns added by DOS editors
 
        # if multiple values for a parm are not allowed, just save the last parm specified, otherwise append
        if (!defined $config_file_vectors{$stanza}{$parm} && !defined $config_file_vectors{$stanza}{"*"}) {
           $parms{$stanza}{$parm} = $val;
        } else {
           $parms{$stanza}{$parm} .= "$val^";
        }
     } else {
        print LOG "ignoring (not a stanza or parm): $_ \n";
     }
   }
   close LISTA;
}
 
#----------------------------------------------------------------------
# dump the parms collected to the log
#----------------------------------------------------------------------
sub dump_parms {
   print LOG "\nParsed stanzas, keys and values\n";
   foreach $stanza ( sort keys %parms ) {
      if (keys %{ $parms{$stanza} } == 0) {
          print LOG "[$stanza]\n";
      } else {
          for $parm ( sort keys %{ $parms{$stanza} } ) {
              print LOG "[$stanza] $parm = $parms{$stanza}{$parm}\n";
          }
      }
   }
   print LOG "\n";
}
 
#----------------------------------------------------------------------
# return the value for a given [stanza] parm
#----------------------------------------------------------------------
sub parmvalue {
   my($stanza, $parm, $unused) = @_;
   return $parms{$stanza}{$parm};
}
 
#----------------------------------------------------------------------
# print an XML property using a value from the hash of hashes
#----------------------------------------------------------------------
sub printXMLsp { 
   my($xprop, $stanza, $parm, $unused) = @_;
   $pv = parmvalue($stanza, $parm);
   if ( $pv eq "" ) {
#     print OUTXML "<$xprop/>\n";  # ------ $stanza $parm
      print LOG "ignoring (not in imported config): [$stanza] $parm <$xprop/>\n";
   } else {
      $pv =~ tr/\<\>/\'\'/;  # if value has <> replace with '' so output XML will parse OK
      $pv =~ s/\/var\/pdweb\/.*\///;     # eliminate file paths
      print OUTXML "<$xprop>$pv</$xprop>\n";
   }
}
 
#----------------------------------------------------------------------
# special case for a key file, the property describes where to find the file 
#----------------------------------------------------------------------
sub printXMLkf {
   my($xprop, $stanza, $parm, $outdir, $unused) = @_;
   $pv = parmvalue($stanza, $parm);
   if ( $pv eq "" ) {
#     print OUTXML "<$xprop/>\n";  # ------ $stanza $parm
      print LOG "ignoring (not in imported config): [$stanza] $parm <$xprop/>\n";
   } else {
      $pv =~ s/.*\///;
      print OUTXML "<$xprop>$DPdir{$outdir}:///$outdir/$pv</$xprop>\n"
   }
}
 
#----------------------------------------------------------------------
# special case for yes/no values, convert to on/off
#----------------------------------------------------------------------
sub printXMLyn {
   my($xprop, $stanza, $parm, $unused) = @_;
   $pv = parmvalue($stanza, $parm);
   if ( $pv eq "" ) {
#     print OUTXML "<$xprop/>\n";  # ------ $stanza $parm
      print LOG "ignoring (not in imported config): [$stanza] $parm <$xprop/>\n";
   } else {
      if ($pv eq "yes") {
         $pv = "on";
      } else {
         $pv = "off";
      }
      print OUTXML "<$xprop>$pv</$xprop>\n"
   }
}
 
#----------------------------------------------------------------------
# special case for vector entries, print multiple XML properties using 
# accumulated values
#----------------------------------------------------------------------
sub printXMLve {
   my($xprop, $stanza, $parm, $unused) = @_;
   $pv = parmvalue($stanza, $parm);
   if ($pv ne "") {
      my @vecvals = split('\^', $pv);
      for $vecval (@vecvals) {
         if ($config_file_vectors{$stanza}{$parm} eq "*" || $config_file_vectors{$stanza}{$parm} =~ / $vecval /) {
            $vecval =~ tr/\<\>/\'\'/;  # if value has <> replace with '' so output XML will parse OK
            print OUTXML "<$xprop>$vecval</$xprop>\n";
         } else {
            print LOG "ignoring (not a valid value): [$stanza] $parm = $vecval\n";
         }
      }
   } else {
      print LOG "ignoring (not in imported config): [$stanza] $parm <$xprop/>\n";
   }
}
 
#----------------------------------------------------------------------
# rewrite config file using modified values from the hash of hashes
#----------------------------------------------------------------------
sub rewrite_config_file {
   my($configfile, $outfile, $unused) = @_;

   my %bl = (); # blacklist entries, don't write these into the output file!
   $bl{"meta-info"}{"*"} = "";
   $bl{"pdrte"}{"*"} = "";
   $bl{"manager"}{"*"} = "";
   $bl{"pdconfig"}{"*"} = "";
   $bl{"cgi"}{"*"} = "";
   $bl{"cgi-types"}{"*"} = "";
   $bl{"cgi-environment-variables"}{"*"} = "";
   $bl{"content-index-icons"}{"*"} = "";
   $bl{"icons"}{"*"} = "";
   $bl{"audit-configuration"}{"*"} = "";
   $bl{"ldap"}{"enabled"} = "";
   $bl{"uraf-registry"}{"enabled"} = "";
   $bl{"server"}{"unix-user"} = "";
   $bl{"server"}{"unix-group"} = "";
   $bl{"server"}{"unix-pid-file"} = "";
   $bl{"server"}{"server-root"} = "";
   $bl{"server"}{"jctdb-base-path"} = "";
   $bl{"server"}{"cfgdb-base-path"} = "";
   $bl{"server"}{"request-module-library"} = "";
   $bl{"server"}{"cfgdb-archive"} = "";
   $bl{"ldap"}{"ldap-server-config"} = "";
   $bl{"ldap"}{"bind-dn"} = "";
   $bl{"ldap"}{"bind-pwd"} = "";
   $bl{"uraf-registry"}{"uraf-registry-config"} = "";
   $bl{"uraf-registry"}{"bind-id"} = "";
   $bl{"uraf-registry"}{"bind-pwd"} = "";
   $bl{"ssl"}{"pkcs11-driver-path"} = "";
   $bl{"ssl"}{"pkcs11-symmetric-cipher-support"} = "";
   $bl{"ssl"}{"pkcs11-keyfile"} = "";
   $bl{"ssl"}{"ssl-local-domain"} = "";
   $bl{"ssl"}{"ssl-keyfile"} = "";
   $bl{"ssl"}{"ssl-keyfile-stash"} = "";
   $bl{"ssl"}{"ssl-keyfile-pwd"} = "";
   $bl{"ssl"}{"ssl-keyfile-label"} = "";
   $bl{"ssl"}{"webseal-cert-keyfile-pwd"} = "";
   $bl{"junction"}{"junction-db"} = "";
   $bl{"junction"}{"jct-cert-keyfile-pwd"} = "";
   $bl{"junction"}{"ltpa-base-path"} = "";
   $bl{"junction"}{"fsso-base-path"} = "";
   $bl{"junction"}{"local-junction-file-path"} = "";
   $bl{"junction"}{"enable-local-junction-scripts"} = "";
   $bl{"http-headers"}{"*"} = "";
   $bl{"auth-headers"}{"*"} = "";
   $bl{"auth-cookies"}{"*"} = "";
   $bl{"ipaddr"}{"*"} = "";
   $bl{"interfaces"}{"*"} = "";
   $bl{"authentication-mechanisms"}{"*"} = "";
   $bl{"content"}{"doc-root"} = "";
   $bl{"content"}{"delete-trash-dir"} = "";
   $bl{"content"}{"error-dir"} = "";
   $bl{"content"}{"directory-index"} = "";
   $bl{"acnt-mgt"}{"mgt-pages-root"} = "";
   $bl{"arm"}{"*"} = "";
   $bl{"token"}{"*"} = "";
   $bl{"logging"}{"server-log"} = "";
   $bl{"logging"}{"config-data-log"} = "";
   $bl{"aznapi-configuration"}{"db-file"} = "";
   $bl{"aznapi-configuration"}{"auditlog"} = "";
   $bl{"aznapi-configuration"}{"azn-app-host"} = "";
   $bl{"aznapi-configuration"}{"pd-user-name"} = "";
   $bl{"aznapi-configuration"}{"pd-user-pwd"} = "";
   $bl{"aznapi-configuration"}{"trace-admin-args"} = "";
   $bl{"aznapi-entitlement-services"}{"*"} = "";
   $bl{"aznapi-admin-services"}{"*"} = "";
   $bl{"aznapi-external-authzn-services"}{"*"} = "";
   $bl{"policy-director"}{"*"} = "";
   $bl{"webseal-config"}{"*"} = "";
   $bl{"configuration-database"}{"*"} = "";
   $bl{"PAM"}{"pam-distribution-directory"} = "";
   $bl{"PAM"}{"pam-library-directory"} = "";
   $bl{"PAM"}{"pam-log-path"} = "";
   $bl{"PAM"}{"pam-statistics-db-path"} = "";
   $bl{"flow-data"}{"flow-data-db-path"} = "";
   $bl{"logging"}{"server-log"} = "";
   $bl{"system-environment-variables"}{"PD_SVC_ROUTING_FILE"} = "";
   $bl{"http-updates"}{"update-cmd"} = "";
 
   my %blwc = (); # blacklist entries with wildcards
   $blwc{"ssl"}{"pkcs11-token-.*"} = "";
   $blwc{"ssl"}{".*bsafe\$"} = "";
   $blwc{"logging"}{".*-file\$"} = "";
   $blwc{"translog.*"}{"file-path"} = "";
   $blwc{"aznapi-configuration"}{".*-entitlement-services\$"} = "";
 
   my %reqd = (); # required entries to be added to the config file if missing
   $reqd{"junction"}{"basicauth-dummy-passwd"} = "dummy";

   open(OUTF, ">", $outfile) || die "Could not open output file $outfile\n";
   open(LISTA, $configfile) || die "Cannot open $configfile\n";
   print LOG "Rewriting config file $configfile to $outfile\n";
    
   my $stanza = "="; # initialize to a value that is not a stanza
   while ( <LISTA> ) {     # read line into $_
     if ( /^\s*\#/ || /^\s*$/ ) { # print comment and blank lines
        print OUTF;
     } elsif ( /^\[(\S+)\]/ ) { # capture the stanza
        # print required values for previous stanza
        for my $reqp (keys %{$reqd{$stanza}}) {
           if (defined ($reqd{$stanza}{$reqp})) {
              print OUTF "$reqp = $reqd{$stanza}{$reqp}\n";
              print LOG "Inserted: [$stanza] $reqp = $reqd{$stanza}{$reqp}\n";
              undef $reqd{$stanza}{$reqp};
           }
        }
        $stanza = $1;
        if (defined $bl{$stanza}{"*"}) {
           print LOG "Blacklisted: [$stanza]\n";
        } else {
           print OUTF; 
        }
     } elsif ( /^\s*(\S*)\s*\=\s*(.*)$/ ) {
        my ($parm, $val) = ($1, $2); # capture the parm and value
        for my $skey (keys %blwc) {
           for my $pkey (keys %{$blwc{$skey}}) {
               if ($stanza =~ /$skey/ && $parm =~ /$pkey/) {
                  $bl{$stanza}{$parm} = "";
               }
           }
        }
        if (defined $bl{$stanza}{$parm} || defined $bl{$stanza}{"*"}) {
           print LOG "Blacklisted: [$stanza] $parm = $val\n";
        } elsif (defined $parms{$stanza}{$parm}) {
           if (defined $config_file_vectors{$stanza}{$parm} || defined $config_file_vectors{$stanza}{"*"}) {
              my @vecvals = split('\^', $parms{$stanza}{$parm});
              for  $vecval (@vecvals) {
                 print OUTF "$parm = $vecval\n";
              }
           } else {
              $pv = $parms{$stanza}{$parm};
              $pv =~ s/\/var\/pdweb\/.*\///;     # eliminate file paths
              print OUTF "$parm = $pv\n";
           }
        }
        undef $parms{$stanza}{$parm};
        undef $reqd{$stanza}{$parm};
     }
   }
   close LISTA;
   close OUTF;
}
 
#----------------------------------------------------------------------
# read a junction XML file's properties and values into a hash
#----------------------------------------------------------------------
sub parse_junctionxml_file {
   my($jxmlfile, $unused) = @_;
   open(LISTA,$jxmlfile) || die "Cannot open $jxmlfile\n";
   print LOG "Parsing junction file $jxmlfile\n";
   $_ = <LISTA>;
   die "Junction file $jxmlfile does not start with <JUNCTION>\n" if ( ! /^\s*\<JUNCTION\>/ );
   while ( <LISTA> ) {     # read line into $_
     chomp;
     if ( /^\s*\<(\S+)\>(.*)\<\/\1\>/ ) { # capture the property and value
        $junct{$1} = $2;
     } elsif ( /^\s*\<(.*)\/\>/ ) {       # property specified with null value
        $junct{$1} = "";
     } elsif ( /^\s*\<\/JUNCTION\>/ ) {
        break;
     } else {
        print LOG "ignoring (not an XML property): $_ \n";
     }
   }
   close LISTA;
}
 
#----------------------------------------------------------------------
# dump the junction hash out to the log
#----------------------------------------------------------------------
sub dump_junct {
    print LOG "Junction:\n";
    for $parm ( sort keys %junct ) { 
        print LOG "$parm = $junct{$parm}\n"; 
    } 
    print LOG "\n";
}
 
#----------------------------------------------------------------------
# print an XML property using a value from the junction hash
#----------------------------------------------------------------------
sub printXMLjp { 
   my($xprop, $parm, $unused) = @_;
   $pv = $junct{$parm};
   if (!defined $junct{$parm}) {
      print LOG "ignoring (not in imported config): $parm <$xprop/>\n";
   } elsif ( $pv eq "" ) {
      print OUTXML "<$xprop/>\n";
   } else {
      print OUTXML "<$xprop>$pv</$xprop>\n";
   }
}
 
#----------------------------------------------------------------------
# print an XML property as 'on' if a value exists in the junction hash
#----------------------------------------------------------------------
sub printXMLje { 
   my($xprop, $parm, $unused) = @_;
   $pv = $junct{$parm};
   if (!defined $junct{$parm}) {
      print LOG "ignoring (not in imported config): $parm <$xprop/>\n";
   } else {
      print OUTXML "<$xprop>on</$xprop>\n";
   }
}
 
#----------------------------------------------------------------------
# special case for a file ref, the property describes where to find the file 
#----------------------------------------------------------------------
sub printXMLjf {
   my($xprop, $parm, $outdir, $unused) = @_;
   $pv = $junct{$parm};
   if ( $pv eq "" ) {
#     print OUTXML "<$xprop/>\n";
      print LOG "ignoring (not in imported config): $parm <$xprop/>\n";
   } else {
      $pv =~ s/.*\///;
      print OUTXML "<$xprop>$DPdir{$outdir}:///$outdir/$pv</$xprop>\n"
   }
}
 
#----------------------------------------------------------------------
# print the top part of the XML output file
#----------------------------------------------------------------------
sub print_XML_header {
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon += 1;
print OUTXML
"<datapower-configuration version=\"3\">
<export-details>
<description>Exported Configuration</description>
<user>admin</user>
<domain>".parmvalue("configure", "DPdomain")."</domain>
<comment>Generated from ISAM config files @ARGV</comment>
<product-id>(unknown)</product-id>
<product>XI50</product>
<display-product>XI50</display-product>
<model>DataPower XI50</model>
<display-model>DataPower XI50</display-model>
<device-name>DataPower XI50</device-name>
<serial-number>(unknown)</serial-number>
<firmware-version>XI50.7.1.0.0</firmware-version>
<display-firmware-version>XI50.7.1.0.0</display-firmware-version>
<firmware-build>(unknown)</firmware-build>
<firmware-timestamp>2014/10/31 13:08:43</firmware-timestamp>
<current-date>$year-$mon-$mday</current-date>
<current-time>$hour:$min:$sec</current-time>
<login-message/>
<custom-ui-file/>
</export-details>
<configuration domain=\"".parmvalue("configure", "DPdomain")."\">\n";
}
 
#----------------------------------------------------------------------
# print an ISAMJunction object 
#----------------------------------------------------------------------
sub print_ISAMJunction {
# remove leading slash from name and change other slashes to _
my $name = $junct{"NAME"}; $name =~ s/^\///; $name =~ tr/\//_/;
return if ("$name" eq "");
@jnames = (@jnames, $name);
 
print OUTXML "<ISAMReverseProxyJunction name=\"$name\" xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:dp=\"http://www.datapower.com/schemas/management\">\n";
 if ($junct{"OPERATIONALMODE"} eq "online") {
     $junct{"OPERATIONALMODE"} = "enabled";
 } else {
     $junct{"OPERATIONALMODE"} = "disabled";
 }
 printXMLjp("mAdminState","OPERATIONALMODE");
 printXMLjp("JunctionPointName", "NAME");
 my $backsrvtype = "Standard";
 if (defined $junct{"VIRTUALHOSTJCT"}) {
    print OUTXML "<JunctionType>virtual</JunctionType>\n";
    printXMLjp("JunctionTypeVirtual","JUCTYPE");
    $backsrvtype = "Virtual";
    printXMLjp("VirtualHostLabel", "PARTNER");
    if ($junct{"VIRTHOSTNM"} =~ /(.*):(.*)/) {
       $junct{"VIRTHOSTPORT"} = $2;
       $junct{"VIRTHOSTNM"} = $1;
    } else {
       $junct{"VIRTHOSTPORT"} = "0";
    }
    printXMLjp("VirtualHost","VIRTHOSTNM");
    printXMLjp("VirtualHostPort","VIRTHOSTPORT");
 #  printXMLjp("DSCEnvironment", "dsc-environment");
 } else {
    print OUTXML "<JunctionType>standard</JunctionType>\n";
    printXMLjp("JunctionTypeStandard","JUCTYPE");
    printXMLje("TransparentPathJunction", "TRANSPARENTPATH");
 }
 
 if ( $junct{"JUCTYPE"} =~ /proxy/ ) {
    $backsrvtype .= "Proxy";
 } elsif ( $junct{"JUCTYPE"} eq "mutual" ) {
    $backsrvtype .= "Mutual";
 }
 print OUTXML "<TargetBackendServers$backsrvtype>\n";
    printXMLjp("Hostname","HOST");
    if ( $junct{"JUCTYPE"} eq "mutual" ) {
       printXMLjp("HTTPPort","PORT");
       printXMLjp("HTTPSPort","MUTUALSSLPORT");
    } else {
       printXMLjp("Port","PORT");
    }
    if ( $junct{"JUCTYPE"} =~ /proxy/ ) {
       printXMLjp("ProxyHostname", "TCPHOST");
       printXMLjp("ProxyPort", "TCPPORT");
    }
    if ( $backsrvtype =~ /Standard/ ) {
       if ($junct{"VIRTHOSTNM"} =~ /(.*):(.*)/) {
          $junct{"VIRTHOSTPORT"} = $2;
          $junct{"VIRTHOSTNM"} = $1;
       } else {
          $junct{"VIRTHOSTPORT"} = "0";
       }
       printXMLjp("VirtualHost","VIRTHOSTNM");
       printXMLjp("VirtualHostPort","VIRTHOSTPORT");
 
       if ( $junct{"JUCTYPE"} eq "mutual" ) {
          printXMLjp("VirtualSSLHost", "MUTUALSSLVIRTHOSTNM");
          printXMLjp("VirtualSSLHostPort", "MUTUALSSLPORT");
       }
    }
    printXMLjp("LocalAddress","LOCALADDRESS");
#   print OUTXML "<ResolvedLocalAddress/>\n";
    printXMLjp("QueryContents", "URLQC");
    printXMLjp("DN","SERVERDN");
    printXMLje("WindowsFSSupport", "WIN32SUP");
    printXMLje("URLCaseInsensitive", "CASEINS");
 print OUTXML "</TargetBackendServers$backsrvtype>\n";

 if (defined $junct{"STATEFUL"}) {
    print OUTXML "<StatefulJunction>on</StatefulJunction>\n";
    printXMLjp("ServerUUID","UUID");  # only print UUID for Stateful junctions
 }
 printXMLjp("BasicAuthHeader", "BASICAUTH");
 if ($junct{"BASICAUTH"} eq "gso") {
    printXMLjp("GSOResource", "GSOTARGET");
 } 
 if (defined $junct{"MUTAUTHBA"}) { 
    print OUTXML "<BasicAuth>on</BasicAuth>\n";
    my $baup = decode_base64($junct{"MUTAUTHBAUP"});
    $baup =~ /(\w+)\n([ -~]+)/; # truncate unprintable chars from decode_base64 output
    my ($user, $pass) = ($1, $2);
    print OUTXML "<BasicAuthUser>$user</BasicAuthUser>\n"; 
    print OUTXML "<BasicAuthPass>$pass</BasicAuthPass>\n"; 
 } else {
    print OUTXML "<BasicAuth>off</BasicAuth>\n";
 } 
 if (defined $junct{"MUTAUTHCERT"}) { 
    print OUTXML "<MutualAuth>on</MutualAuth>\n";
  # printXMLjp("MutualAuthKeyFile", "?");
    printXMLjp("MutualAuthKeyLabel", "MUTAUTHCERTLABEL");
 } else {
    print OUTXML "<MutualAuth>off</MutualAuth>\n";
 }

 if ($junct{"CLIENTID"} eq "do not insert") {
    undef $junct{"CLIENTID"};
 }
 if (defined $junct{"CLIENTID"}) {  # insert_pass_user (us) insert_pass_groups (gr) insert_pass_creds (cr) insert_pass_longname (ln) insert_all
   print OUTXML "<HeaderIdentityInfo>\n";
   if ($junct{"CLIENTID"} =~ /(insert_all|insert_pass_users|insert_.*us)/) {
      print OUTXML "<iv-user>on</iv-user>\n";
   }
   if ($junct{"CLIENTID"} =~ /(insert_all|insert_pass_groups|insert_.*gr)/) {
      print OUTXML "<iv-groups>on</iv-groups>\n";                           
   }
   if ($junct{"CLIENTID"} =~ /(insert_all|insert_pass_creds|insert_.*cr)/) {
      print OUTXML "<iv-creds>on</iv-creds>\n";                           
   }
   if ($junct{"CLIENTID"} =~ /(insert_all|insert_pass_longname|insert_.*ln)/) {
      print OUTXML "<iv-user-l>on</iv-user-l>\n";
   }
   print OUTXML "</HeaderIdentityInfo>\n";
 }

 # printXMLjp("?", "TARGETIV");
 # printXMLjp("?", "IVSSL");

 printXMLjp("HeaderEncoding","REQUESTENCODING");
 if (defined $junct{"SCRIPTCOOKIEHEAD"}) {
    print OUTXML "<JunctionCookieJSBlock>inhead</JunctionCookieJSBlock>\n";
 } elsif (defined $junct{"SCRIPTCOOKIETRAILER"}) {
    print OUTXML "<JunctionCookieJSBlock>trailer</JunctionCookieJSBlock>\n";
 } elsif (defined $junct{"SCRIPTCOOKIEUSEFOCUS"}) {
    print OUTXML "<JunctionCookieJSBlock>onfocus</JunctionCookieJSBlock>\n";
 } elsif (defined $junct{"SCRIPTCOOKIETOSPEC"}) {
    print OUTXML "<JunctionCookieJSBlock>xhtml10</JunctionCookieJSBlock>\n";
 } else {
    print OUTXML "<JunctionCookieJSBlock>none</JunctionCookieJSBlock>\n";
 }
 print OUTXML "<UniqueCookieNames>off</UniqueCookieNames>\n"; 
 printXMLje("PreserveJuncName", "PRESERVECOOKIENAMES");
 printXMLje("IncludeSessionCookie", "SESSIONCOOKIE");
 printXMLje("IncludeJuncName", "COOKIENAMEINCLUDEPATH");
 printXMLje("InsertClientIP", "REMOTEADDRESS");
 printXMLje("TFIMSSO", "TFIMJCTSSO");
 printXMLjf("FSSOConfigFile", "FSSOCONFFILE", "fsso");
 if (defined $junct{"LTPAKEYFILE"}) {
    print OUTXML "<LTPACookie>on</LTPACookie>\n";
    printXMLje("LTPAV2Cookie", "LTPAVERSION2");
    printXMLjf("LTPAKeyFile", "LTPAKEYFILE", "ltpa-keys");
    printXMLjp("LTPAKeyFilePw", "LTPAKEYFILEPASSWD");
 }
 printXMLjp("PercentHardLimitWT", "HARDLIMIT");
 printXMLjp("PercentSoftLimitWT", "SOFTLIMIT");
 printXMLje("IncludeAuthRules", "RULEREASON");
print OUTXML "</ISAMReverseProxyJunction>\n";
}
 
#----------------------------------------------------------------------
# print an ISAMReverseProxy object 
#----------------------------------------------------------------------
sub print_ISAMReverseProxy {
print OUTXML "<ISAMReverseProxy name=\"$instancename\" xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:dp=\"http://www.datapower.com/schemas/management\">\n";
print OUTXML "<mAdminState>enabled</mAdminState>\n";
print OUTXML "<ISAMRuntime class=\"ISAMRuntime\">default</ISAMRuntime>\n";
 printXMLsp("LocalHost", "configure", "hostname");
 printXMLsp("LocalPort", "configure", "listen-port");
 printXMLsp("Administrator", "configure", "administrator");
 printXMLsp("Password", "configure", "password");
 printXMLsp("ResolvedPassword", "configure", "resolved-password");
 printXMLsp("ISAMDomain", "configure", "ISAMdomain");
 printXMLsp("PrimaryInterface", "server", "network-interface");
#printXMLsp("ResolvedPrimaryInterface", "server", "network-interface");
 printXMLyn("EnableHTTP", "server", "http");
 printXMLsp("HTTPPort", "server", "http-port");
 printXMLyn("EnableHTTPS", "server", "https");
 printXMLsp("HTTPSPort", "server", "https-port");
 # If there are secondary interfaces defined, they need special parsing
 if (keys %{$parms{"interfaces"}} > 0) {
    for $iface (keys %{$parms{"interfaces"}}) {
       $idef = $parms{"interfaces"}{$iface};
       @iparms = split(';', $idef);
       for $iparm (@iparms) {
          if ($iparm =~ /(\S+)=(\S+)/) {
             $parms{$iface}{$1} = "$2";
             print LOG "$iface $1 $2\n"
          }
       }
       print OUTXML "<SecondaryInts>\n";
       printXMLsp("SecondaryInterface", $iface, "network-interface");
       printXMLsp("HTTPPort", $iface, "http-port");
       printXMLsp("HTTPSPort", $iface, "https-port");
       printXMLsp("WebHTTPPort", $iface, "web-http-port");
       printXMLsp("WebHTTPProtocol", $iface, "web-http-protocol");
       printXMLsp("CertLabel", $iface, "certificate-label");
       printXMLsp("ClientCertAccept", $iface, "accept-client-certs");
       printXMLsp("WorkerThreads", $iface, "worker-threads");
       print OUTXML "</SecondaryInts>\n";
       undef $parms{$iface};
    }
 }
 $parms{"cluster"}{"is-master"} = "yes";
 printXMLyn("ClusterMaster", "cluster", "is-master");
 printXMLsp("MasterInstance", "cluster", "master-name");
 printXMLsp("ClientPersistentConnTimeout", "server", "persistent-con-timeout");
 printXMLsp("WorkerThreads", "server", "worker-threads");
 printXMLkf("SSLCertKeyFile", "ssl", "webseal-cert-keyfile", "keytab");
 printXMLkf("SSLCertKeyFileStash", "ssl", "webseal-cert-keyfile-stash", "keytab");
 printXMLsp("SSLServerCert", "ssl", "webseal-cert-keyfile-label");
#printXMLsp("SSLCryptoProfile", "?", "");
 for $jname (@jnames) {
    print OUTXML "<Junctions class=\"ISAMReverseProxyJunction\">$jname</Junctions>\n";
 }
 printXMLkf("JunctionCertKeyFile", "junction", "jct-cert-keyfile", "keytab");
 printXMLkf("JunctionCertKeyFileStash", "junction", "jct-cert-keyfile-stash", "keytab");
#printXMLsp("JunctionCryptoProfile", "?", "");
 printXMLsp("JunctionHTTPTimeout", "junction", "http-timeout");
 printXMLsp("JunctionHTTPSTimeout", "junction", "https-timeout");
 printXMLsp("JunctionMaxCachedPersistentConns", "junction", "max-cached-persistent-connections");
 printXMLsp("JunctionPersistentConnTimeout", "junction", "persistent-con-timeout");
 printXMLsp("ManagedCookieList", "junction", "managed-cookies-list");
 printXMLsp("HealthCheckPingInterval", "junction", "ping-time");
 printXMLsp("HealthCheckPingMethod", "junction", "ping-method");
 printXMLsp("HealthCheckPingURI", "junction", "ping-uri");
 printXMLsp("BasicAuthTransport", "ba", "ba-auth");
 printXMLsp("BasicAuthRealm", "ba", "basic-auth-realm");
 if ( parmvalue("certificate", "accept-client-certs") eq "prompt_as_needed" ) {
    $parms{"certificate"}{"accept-client-certs"} = "prompt";
 }   
 printXMLsp("ClientCertAccept", "certificate", "accept-client-certs");
 printXMLsp("ClientCertEAIURI", "certificate", "eai-uri");
# printXMLve("ClientCertData", "certificate", "eai-data");
# create a ClientCertData struct for each eai-data entry
 my $cdata = parmvalue("certificate", "eai-data");
 if ($cdata ne "") {
    my @vecvals = split('\^', $cdata);
    for $vecval (@vecvals) {
        if ($vecval =~ /(\S+)\:(\S+)/) {
           print OUTXML "<ClientCertData>\n";
           print OUTXML "<CertData>$1</CertData>\n";
           print OUTXML "<Header>$2</Header>\n";
           print OUTXML "</ClientCertData>\n";
        }
    }
 }
 printXMLsp("EAITransport", "eai", "eai-auth");
 printXMLve("EAITriggerURL", "eai-trigger-urls", "trigger");
 printXMLve("AuthLevels", "authentication-levels", "level");
 printXMLsp("FormsAuthTransport", "forms", "forms-auth");
 printXMLsp("KerberosTransport", "spnego", "spnego-auth");
 printXMLkf("KerberosKeytab", "spnego", "spnego-krb-keytab-file", "kerberos");
 printXMLyn("KerberosUseQDN", "spnego", "use-domain-qualified-name");
 printXMLve("KerberosServiceNames", "spnego", "spnego-krb-service-name");
 printXMLyn("SessionReauthenForInactive", "reauthentication", "reauth-for-inactive");
 printXMLsp("SessionMaxCacheEntries", "session", "max-entries");
 printXMLsp("SessionLifetimeTimeout", "session", "timeout");
 printXMLsp("SessionInactiveTimeout", "session", "inactive-timeout");
 printXMLsp("SessionTCPCookie", "session", "tcp-session-cookie-name");
 printXMLsp("SessionSSLCookie", "session", "ssl-session-cookie-name");
 printXMLyn("SessionUseSame", "session", "use-same-session");
 printXMLyn("HTMLRedirect", "acnt-mgt", "enable-html-redirect");
 printXMLyn("LocalRespRedirect", "acnt-mgt", "enable-local-response-redirect");
 printXMLsp("LocalRespRedirectURI", "local-response-redirect", "local-response-redirect-uri");
 printXMLve("LocalRespRedirectMacros", "local-response-macros", "macro");
 printXMLsp("FailoverTransport", "failover", "failover-auth");
 printXMLsp("FailoverCookiesLifetime", "failover", "failover-cookie-lifetime");
 printXMLkf("FailoverCookiesKeyFile", "failover", "failover-cookies-keyfile", "tam-keys");
 printXMLsp("CDSSOTransport", "cdsso", "cdsso-auth");
 printXMLsp("CDSSOTransportGen", "cdsso", "cdsso-create");
#printXMLsp("CDSSOPeers", "cdsso-peers", "*");
 if (keys %{ $parms{"cdsso-peers"} } > 0) {
     for $fqhn ( keys %{ $parms{"cdsso-peers"} } ) {
         print OUTXML "<CDSSOPeers>\n";
         print OUTXML "<hostname>$fqhn</hostname>\n";
         printXMLkf("keyfile", "cdsso-peers", $fqhn, "tam-keys");
         print OUTXML "</CDSSOPeers>\n";
     }
 }
 printXMLsp("LTPATransport", "ltpa", "ltpa-auth");
 printXMLsp("LTPACookie", "ltpa", "cookie-name");
 printXMLkf("LTPAKeyFile", "ltpa", "keyfile", "ltpa-keys");
 printXMLsp("LTPAKeyFilePw", "ltpa", "keyfile-password");
 printXMLsp("ECSSOTransport", "e-community-sso", "e-community-sso-auth");
 printXMLsp("ECSSOName", "e-community-sso", "e-community-name");
 if ( parmvalue("e-community-sso","is-master-authn-server") eq "yes" ) {
    printXMLyn("ECSSOIsMasterAuthServer", "e-community-sso", "is-master-authn-server");
 } elsif ( parmvalue("e-community-sso", "master-authn-server") ne "" ) {
    $parm{"e-community-sso"}{"is-master-authn-server"} = "no";
    printXMLyn("ECSSOIsMasterAuthServer", "e-community-sso", "is-master-authn-server");
    printXMLsp("ECSSOMasterAuthServer", "e-community-sso", "master-authn-server");
 }
#printXMLsp("ECSSODomains", "e-community-domains", "*");
 if (keys %{ $parms{"e-community-domains"} } > 0) {
     for $dom ( keys %{ $parms{"e-community-domains"} } ) {
         print OUTXML "<ECSSODomains>\n";
         print OUTXML "<domain>$dom</domain>\n";
         printXMLkf("keyfile", "e-community-domain-keys:$dom", $dom, "tam-keys");
         print OUTXML "</ECSSODomains>\n";
     }
 }
#printXMLsp("ECSSODomains", "e-community-domain-keys", "*");
 if (keys %{ $parms{"e-community-domain-keys"} } > 0) {
     for $dom ( keys %{ $parms{"e-community-domain-keys"} } ) {
         print OUTXML "<ECSSODomains>\n";
         print OUTXML "<domain>$dom</domain>\n";
         printXMLkf("keyfile", "e-community-domain-keys", $dom, "tam-keys");
         print OUTXML "</ECSSODomains>\n";
     }
 }
 printXMLyn("AgentLogging", "logging", "agents");
 printXMLyn("RefererLogging", "logging", "referers");
 printXMLyn("RequestLogging", "logging", "requests");
 printXMLsp("RequestLogFormat", "logging", "request-log-format");
 if ( parmvalue("logging", "max-size") > 2097152 ) {
    $parms{"logging"}{"max-size"} = 2097152;
 }
 printXMLsp("MaxLogSize", "logging", "max-size");
 printXMLsp("FlushLogTime", "logging", "flush-time");
 printXMLyn("AuditLogging", "aznapi-configuration", "logaudit");
 printXMLve("AuditLogType", "aznapi-configuration", "auditcfg");
 if ( parmvalue("aznapi-configuration", "logsize") > 2097152 ) {
    $parms{"aznapi-configuration"}{"logsize"} = 2097152;
 }
 printXMLsp("MaxAuditLogSize", "aznapi-configuration", "logsize");
 printXMLsp("FlushAuditLogTime", "aznapi-configuration", "logflush");
 printXMLyn("UserRegistrySSL", "ldap", "ssl-enabled");
 if (parmvalue("ldap", "ssl-enabled") eq "yes") {
    printXMLsp("UserRegistrySSLPort", "ldap", "ssl-port");
    printXMLkf("UserRegistryCertDB", "ldap", "ssl-keyfile", "keytab");
    printXMLsp("UserRegistryCertLabel", "ldap", "ssl-keyfile-dn");
 }
 print OUTXML "<ConfigFile>isamconfig:///webseald-$instancename.conf</ConfigFile>\n";
 print OUTXML "<RoutingFile>isamconfig:///routing-$instancename</RoutingFile>\n";
print OUTXML "</ISAMReverseProxy>\n";
} 
 
#----------------------------------------------------------------------
# print a <file> entry for each file in $opath/$destdir/$subdir
# including the digest
#----------------------------------------------------------------------
sub print_file_entries {
   my ($opath, $destdir, $subdir, $unused) = @_;
   opendir (my $dh, "$opath/$destdir/$subdir") || return;
   while (my $dirent = readdir $dh) {
      if ( -f "$opath/$destdir/$subdir/$dirent" ) {
         my $hash = Digest::SHA->new(1)->addfile("$opath/$destdir/$subdir$dirent")->b64digest();
         while (length($hash) % 4) {
             $hash .= "=";
         }
         print OUTXML "<file name=\"$destdir:///$subdir$dirent\" src=\"$destdir/$subdir$dirent\" location=\"$destdir/$subdir\" hash=\"$hash\"/>\n";
      }
   }
   closedir $dh;
}
 
#----------------------------------------------------------------------
# print the bottom part of the XML output file, 
# especially the <file> entries
#----------------------------------------------------------------------
sub print_XML_footer {
   print OUTXML "</configuration>\n";
   print OUTXML "<files>\n";
   print_file_entries ($opath, "isamconfig", "");
   for my $dir (keys %DPdir) {
      print_file_entries ($opath, "$DPdir{$dir}", "$dir/");
   }
   print OUTXML "</files>\n";
   print OUTXML "</datapower-configuration>\n";
}
 
 
# =============================================================================
#                                   main
# =============================================================================
 
# just a little validation of input parms 
for $zipfile (@ARGV) {
   die "Input file $zipfile is not a zip file!\n" if (! $zipfile =~ /.zip$/);
   die "Can't read input file $zipfile\n" if (! -r $zipfile);
}
 
# create a working directory under /tmp using the PID for uniqueness
$tpath = "/tmp/migISAM$$";
mkdir $tpath || die "Could not make temporary directory $tpath\n";
$log = "$tpath/isam2dp.log";
 
for $zipfile (@ARGV) {
   system "unzip -d $tpath $zipfile >> $log" || die "Error unzipping $zipfile!\n";
}
 
$opath = "$tpath/DP";
mkdir $opath || die "Could not make output directory $opath\n";
$isamconfdir = "$opath/isamconfig";
mkdir $isamconfdir || die "Could not make output directory $isamconfdir\n";

# these subdirs will exist under a particular directory on the DP appliance 
%DPdir = ();
$DPdir{"db"} = "isamconfig";
$DPdir{"kerberos"} = "isamconfig";
$DPdir{"keytab"} = "isamcert";
$DPdir{"tam-keys"} = "isamcert";
$DPdir{"ltpa-keys"} = "isamcert";
$DPdir{"fsso"} = "isamconfig";
 
# these are the [stanza] parms that may have multiple values specified
%config_file_vectors = ();
$config_file_vectors{"ssl"}{"listen-interface"} = "*";
$config_file_vectors{"eai-trigger-urls"}{"trigger"} = "*";
$config_file_vectors{"spnego"}{"spnego-krb-service-name"} = "*";
$config_file_vectors{"process-root-filter"}{"root"} = "*";
$config_file_vectors{"filter-url"}{"*"} = "*";
$config_file_vectors{"filter-events"}{"*"} = "*";
$config_file_vectors{"filter-schemes"}{"scheme"} = "*";
$config_file_vectors{"filter-content-types"}{"type"} = "*";
$config_file_vectors{"ssl-qop-mgmt-default"}{"default"} = "*";
$config_file_vectors{"aznapi-configuration"}{"resource-manager-provided-adi"} = "*";
$config_file_vectors{"aznapi-configuration"}{"cred-attribute-entitlement-services"} = "*";
$config_file_vectors{"user-agents"}{"*"} = "*";
$config_file_vectors{"cgi-environment-variables"}{"ENV"} = "*";
$config_file_vectors{"p3p-header"}{"purpose"} = "*";
$config_file_vectors{"cfg-db-cmd:files"}{"file"} = "*";
$config_file_vectors{"authentication-mechanisms"}{"passwd-strength"} = "*";
$config_file_vectors{"certificate"}{"eai-data"} = "*";
# for these, each value must be one of the strings in the list, or it will be ignored
$config_file_vectors{"authentication-levels"}{"level"} = " unauthenticated password ssl extauthinterface ";
$config_file_vectors{"local-response-macros"}{"macro"} = " USERNAME METHOD URL REFERER HOSTNAME AUTHNLEVEL FAILREASON PROTOCOL ERRORCODE ERRORTEXT OLDSESSION EXPIRESECS ";
$config_file_vectors{"aznapi-configuration"}{"auditcfg"} = " azn authn http ";
 
open(LOG, ">>", $log);
%parms = ();
 
# parse the config files from the input zip
$instancename = "";
opendir (my $dh, "$tpath/etc") || die "Cannot find config files!\n";
while (my $conf = readdir $dh) {
   if ( $conf =~ /webseald\-(.*)\.conf$/ ) {  # only one file should match this pattern
      $instancename = $1;
      parse_config_file("$tpath/etc/$conf");
      break;
   }
}
closedir $dh;
die "No WebSEAL instance config file found!\n" if ($instancename eq "");

# append the secondary interface definitions to the isam2dp.conf file
if (keys %{$parms{"interfaces"}} > 0) {
   open(MCONF, ">>", "./isam2dp.conf");
   print MCONF "\n[interfaces]\n";
   for $iface (keys %{$parms{"interfaces"}}) {
      $idef = $parms{"interfaces"}{$iface};
      print MCONF "$iface = $idef\n";
   }
   close MCONF;
}

# edit isam2dp.conf to force the user to look at what might need to be overridden
$EDITOR = $ENV{'EDITOR'};
if ("$EDITOR" eq "") {
   $EDITOR="vim";
}
system "$EDITOR ./isam2dp.conf";
 
# Before reading isam2dp.conf, undefine the [ssl] listen-interface value.
# We need to erase whatever was in the original config for that value
# since it is a vector - new values added from the isam2dp.conf will 
# just be appended to the current set of values.
undef $parms{"ssl"}{"listen-interface"};

# add in the additional [stanza] parm values from the override file
parse_config_file("./isam2dp.conf");
 
# manually override a few things
$parms{"server"}{"server-name"} = parmvalue("configure","hostname")."-$instancename";
$parms{"aznapi-configuration"}{"azn-server-name"} = "$instancename-webseald-".parmvalue("configure","hostname");
$parms{"ssl"}{"ssl-listening-port"} = $parms{"configure","listen-port"};

# log what was read
dump_parms();
 
# start generating output!
$oxml = "$opath/export.xml";
open(OUTXML, ">>", $oxml) || die "Cannot open output file $oxml\n";
 
print_XML_header();
 
# print the junctions, and collect their object names 
@jnames = ();
opendir (my $dh, "$tpath/junctions") || die "Cannot read junctions!\n";
while (my $xmlfile = readdir $dh) {
   if ( $xmlfile =~ /\.xml$/ ) {
      %junct = ();
      parse_junctionxml_file("$tpath/junctions/$xmlfile");
      dump_junct();
      print_ISAMJunction();
   }
}
closedir $dh;
 
# print the ISAMReverseProxy, referring to the junctions printed earlier
print_ISAMReverseProxy();
 
# copy files that DataPower needs into the output directory
rewrite_config_file("$tpath/etc/webseald-$instancename.conf", "$isamconfdir/webseald-$instancename.conf");

for $dir ( keys %DPdir ) {
   if ( -d "$tpath/$dir" ) {
      my $destdir = "$opath/$DPdir{$dir}";
      mkdir $destdir || die "Could not make output directory $destdir\n";
      system "cp -r $tpath/$dir $destdir" || die "Error copying $dir files to $destdir\n";
   }
}
 
# print the footer and file entries, now that the files are in place
print_XML_footer();
close OUTXML; 
 
close LOG;
 
system "cd $opath && zip -r DPISAM_$instancename * >> $log" || die "Error zipping up final file\n";
system "mv -f $opath/DPISAM_$instancename.zip ." || die "Error moving final file\n";
#system "rm -rf $tpath";  # uncomment this line to erase the /tmp working directory
print "Your output is in ./DPISAM_$instancename.zip use it in good health!\n";
