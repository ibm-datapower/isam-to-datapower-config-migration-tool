ISAM-to-DataPower configuration migration tool

This perl script helps users of the IBM ISAM server or appliance migrate their
Web reverse proxy configurations onto a DataPower appliance.

Install isam2dp.pl and isam2dp.conf in a directory.

Invoke the tool using perl, passing the exported *.zip file as input.
The tool invokes the vim editor on file isam2dp.conf to allow you to 
customize some parameters that are needed for the migration: parameters that 
either cannot be found in the origin ISAM config extract, or that must be
modified from the origin ISAM config in order to fit in the new DataPower
environment (e.g., change hostname from the ISAM server hostname to the
DataPower hostname, change interface IP addresses and ports, etc).

[tommcs@tommcsW500 ~/isam-migration-tool]$ perl isam2dp.pl ../ISAM/ConfigRP/webseal_configReverseProxy3.zip 

<vim is invoked on isam2dp.conf>

Your output is in ./DPISAM_migrateReverseProxy3.zip use it in good health!
[tommcs@tommcsW500 ~/isam-migration-tool]$ ls -lt
total 148
-rw-rw-r--. 1 tommcs tommcs 96990 Mar  5 10:35 DPISAM_migrateReverseProxy3.zip
-rw-r--r--. 1 tommcs tommcs  2238 Mar  5 10:35 isam2dp.conf
-rw-rw-r--. 1 tommcs tommcs 37782 Mar  5 10:10 isam2dp.pl
-rw-rw-r--. 1 tommcs tommcs  1294 Feb  6 17:31 LICENSE.txt
-rw-rw-r--. 1 tommcs tommcs   881 Jan 15 10:24 README
[tommcs@tommcsW500 ~/isam-migration-tool]$ 

The output zip file can be Imported into your DataPower appliance!

The tool creates a temporary directory under /tmp that contains working files.
It creates a new temp directory each time it is invoked.
