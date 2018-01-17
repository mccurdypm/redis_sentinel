#!/usr/bin/perl -w

use strict;

chomp(my $fqdn = `hostname`);
my $slave_conf = 'conf/redis/slaveof_638';
my @hosts = split(/,/, $ENV{"redisHosts"});
my @ports = split(/,/, $ENV{"ports"});
my @sentinels = ('3', '4');
my @others;
my @masters;
my %host_map;


# build cluster config
foreach my $host (@hosts) {
    @others = grep(!/$host/, @hosts);
    @others = sort @others;
    foreach my $port (@ports) {
        $host_map{"$host:$port"} = shift(@others);
    }
}

# get master hosts based on val
while (my ($k, $v) = each %host_map) {
    push(@masters, $k) if $v eq $fqdn;
}

# create redis conf on per host basis
foreach my $s (@sentinels) {
    open (my $fh, ">", "$slave_conf$s.conf");
    my ($host, $port) = split(/:/, shift(@masters));
    print $fh "slaveof $host $port\n";
}
