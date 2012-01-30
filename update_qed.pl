#!/usr/bin/perl

#use strict;
#use warnings;

############################
# NOTE: Changed by Russ Welti in 1/2012 because NEIC no longer produces
# the FINGER product http://neic.usgs.gov/neis/finger/quake.asc ,
# which is what this script consumed previously
#
# Access new events 
#    via http://earthquake.usgs.gov/earthquakes/catalogs/eqs7day-M2.5.txt
#    take only those >= M4.5
#    convert them into the format this script expects (legacy of when
#       it consumed "quake.asc" a FINGER-related product that has gone
#       away).
#    remove logic for duplicates or revisions to events (not needed).
#    just get the file, convert, draw, every time invoked.
#
#    set file to be fetched here:
$fileToFetch = 
   "http://earthquake.usgs.gov/earthquakes/catalogs/eqs7day-M2.5.txt";
############################ end Russ Welti

# Add them to the
# qed file.  Do the above only if the earthquake bulletin has been updated
# since the last check.  Update the maps and the QED list when this occurs.
# Meant to be run in the background and loops forever.  If qedfile does not
# exist it will be created.

# Procedure for updating the qed file:
# 
# Find the first QED event in the bulletin.
# Leave all events in qed file older than this event.
# Add the bulletin exactly as it stands to the QED file.  This will allow for
# new events , updates, and removed events.

# The time and date of the last change to the QED file is stored in
# update_qed.log

# The bulletin is screened for valid events.  Events are only saved which
# satisfy the following format:
# <2 digits>/<2 digits>/<2 digits><some white space><2 digits>:<2 digits>:<2 digits><some white space><1 or more digits>.<2 digits><N or S><some white space><1 or more digits>.<2 digits><E or W><some white space><1 or more digits>.<1 digit><some white space><1 or more digits>.<1 digit><2 alpha characters><more characters (optional)>

# Note that this does not protect against errors within the format fields only
# against improperly formatted events.

# Usage: update_qed.pl qedfile [update_interval]
# in seconds;  how often the bulletin gets checked. Default 60.

die "update_qed.pl:  Usage: update_qed.pl qedfile [update_interval]\n" 
    unless $ARGV[0];

$update_interval = $ARGV[1] or $update_interval = 60;  

#loop indefinitely
 MAIN_LOOP: {

     #this code is here for watchproc in case finger hangs
     die "Could not make pid file in dir /tmp " 
         unless open (PID , '>/tmp/update_qed.pid');
     print PID "$$ ",time,"\n";
     close PID;
     #if finger fails wait and try again

     sleep ($update_interval) , redo MAIN_LOOP 
         unless open (FINGER , "wget -q $fileToFetch -O - |");

     # sample of input stream expected:
     # Src,Eqid,Version,Datetime,Lat,Lon,Magnitude,Depth,NST,Region
     # us,c0007kbm,4,"Friday, January 13, 2012 16:02:28 UTC",-60.5909,-27.0717,5.2,54.20,40,"South Sandwich Islands region"
     # us,c0007kbj,6,"Friday, January 13, 2012 15:54:48 UTC",-60.5604,-27.2758,5.1,67.30,39,"South Sandwich Islands region"
     # ci,11053557,2,"Friday, January 13, 2012 15:50:00 UTC",34.3427,-118.4670,2.7,5.20,60,"Greater Los Angeles area, California"
     # ci,11053549,2,"Friday, January 13, 2012 15:49:34 UTC",34.3397,-118.4552,2.7,5.90,55,"Greater Los Angeles area, California"

     open QED , ">$ARGV[0]" or die "could not open $ARGV[0] for output";

     $_ = (<FINGER>) ;
     die "first line of events feed is not expected header line"
        unless m/Src,/;

     my $line = 0;
     my @lines = ();   # accumulate output here so can emit in reverse chrono order (recent first)

     READEVENT: while(<FINGER>) {

        # can't split on comma just yet, date has commas!
        ($pre, $dateTime, $post, $region) = split('"');
        # pre=hv,60299406,1,
        # dateTime=Friday, January 13, 2012 18:22:58 UTC
        # post=,19.1918,-155.5172,2.5,39.40,56,

        $_ = "$pre$post";
        $_ =~ s/,,/,/g;
        # $_ = hv,60299406,1,19.1918,-155.5172,2.5,39.40,56,

        ($src, $id, $vers,
         $lat, $lon, $mag, $depth, 
         $nst ) = split(',');

        #print "$src, $id, $vers, $dateTime, $lat, $lon, $mag, $depth, $nst, $region\n";
        next READEVENT if $mag < 4.5;
     
        #print ("parsing event of mag $mag\n");

        # convert input to look like old input:  (spaces not tabs)
        # date is wrong and region text needs to be all caps and shortened from
        # this new event source, which uses significantly longer regions
# 12/01/12 06:59:02   0.52N  79.71W  56.3 4.4M     NEAR COAST OF ECUADOR
# 12/01/12 07:08:13  18.06S 173.11W  35.1 5.2M     TONGA

        # dateTime=Friday, January 13, 2012 18:22:58 UTC
        ($dateStr, $timeStr) =longDateToShort($dateTime);

        $lonStr = sprintf("%3.2f", $lon);
        $latStr = sprintf("%3.2f", $lat);

        if($lat < 0) {
           $latStr =~ s/-//g;
           $latStr .= "S";
        }
        if($lat > 0) {
           $latStr .= "N";
        }
        if($lon < 0) {
           $lonStr =~ s/-//g;
           $lonStr .= "E";
        }
        if($lon > 0) {
           $lonStr .= "W";
        }

        # shorten the region to be like old event feed so fits on screen

        # shorten region by looking it up in the file provided
        # by Richard Husband, for going from long to short regions.
        # alternatively do this another way, commented out below

        open(REGIONSSHORT,"<USGS_region_long_2_short.txt") or die "could not long2short file";

        #print "PRE: $region\n";
        while($xlate = <REGIONSSHORT>) {
           chomp($xlate);
           my ($x, $y) = split(';', $xlate);
#debug:
#if( $region =~ /South Island/) {
  #print "$region =~ s/$x/$y/  \n";
#}
           $region =~ s/$x/$y/i;
        }
        close REGIONSSHORT;
        chomp($region);

        # another way: shorten via common substitutions

        #$region =~ s/near the coast of /off of /g;
        #$region =~ s/near the south coast of /off of /g;
        #$region =~ s/near the north coast of /off of /g;
        #$region =~ s/near the east coast of /off of /g;
        #$region =~ s/near the west coast of /off of /g;

        #$region =~ s/off the coast of /off of /g;
        #$region =~ s/off the south coast of /off of /g;
        #$region =~ s/off the north coast of /off of /g;
        #$region =~ s/off the east coast of /off of /g;
        #$region =~ s/off the west coast of /off of /g;

        #$region =~ s/ region//g;
        #$region =~ s/region //g;
        #$region =~ s/region,//g;

        $region = uc($region); # make all caps

#       $finalLine = sprintf("%8s %8s %7s %7s %5.1f %2.1fM     %-35s\n",
        $finalLine = sprintf("%8s %8s %7s %7s %5.1f %2.1fM     %s\n",
                             $dateStr,
                             $timeStr,
                             $latStr,
                             $lonStr,
                             $depth,
                             $mag,
                             $region);

        #printf(QED $finalLine);
        $lines[$line++] = $finalLine;

    }


    $lines = reverse($lines);  # output needs to be reverse order from input
    foreach (@lines) {
        printf (QED  $_);
    } 
    close(QED);


    system('./update_eventlist');
    open (LOG, '>update_qed.log');

    print LOG "Time of latest update to event list (QED.gif):\n", time , 
    "\t" , ucfirst localtime, "\n";
    close LOG;
#close finger, start updating the maps and QED list, and wait until next check
    close FINGER;
    sleep $update_interval;
    redo;
} #end MAIN_LOOP


########################################
# longDateToShort() - convert time() value to date string
# long format: Wednesday, January 1, 2001
# returns: 01/01/2001

# NOTE: this expects the exact format that USGS provides right now,
# namely "Thursday, January 12, 2012" as input.
# any variation or change will cause this script to abort!

sub longDateToShort {
   my ($longdate) = @_;

   my %months = ("January" , 1,
                 "February", 2,
                 "March", 3,
                 "April", 4,
                 "May", 5,
                 "June", 6,
                 "July", 7,
                 "August", 8,
                 "September", 9,
                 "October", 10,
                 "November", 11,
                 "December", 12);

#print($months{"January"}, "\n");
#print($months{"February"}, "\n");
#print($months{"March"}, "\n");
#print($months{"April"}, "\n");
#print($months{"May"}, "\n");
#print($months{"June"}, "\n");
#print($months{"July"}, "\n");
#print($months{"August"}, "\n");
#print($months{"September"}, "\n");
#print($months{"October"}, "\n");
#print($months{"November"}, "\n");
#print($months{"December"}, "\n");

   # date is like -- Monday, May 25, 2012
   # grab the month
  #$longdate =~ m{(\w+).\s+(\w+)\s+(\d+).\s+(\d+)};
   $longdate =~ m{(\w+).\s+(\w+)\s+(\d+).\s+(\d+)\s+(\d+:\d+:\d+)\s+\w+};

   # print "1=$1, 2=$2, 3=$3, 4=$4 5=$5\n";
   # 1=Friday, 2=January, 3=13, 4=2012 5=21:25:09

   my $d = $3;
   my $m = $months{$2};
   my $y = $4;
   my $utc = $5;

   die "invalid day in $longdate" if (length($d) == 0 || length($d) > 2);
   die "invalid year in $longdate" if (length($y) == 0 || length($y) > 4);
   #if(length($y) == 4) {
      #$y = substr($y,1);
   #}
   #else {
      #die "invalid year in $longdate" if (length($y) == 0 || length($y) > 4);
   #}
   if($y > 2000) {
      $y -= 2000;
   }
   else {
      die "invalid year in $longdate";
   }

   # date number -- 5/25/2012
   $shortdate = sprintf("%02d/%02d/%02d", $y, $m, $d);

   #print "$shortdate \n";

   return ($shortdate, $utc);
}
