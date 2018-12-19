#!/usr/bin/env perl
use v5.010;
use strict;
use warnings;

use XML::LibXML;

############################
# Global config values
my $skip_empty_release = 1;
my @skip_titles;
my @skip_region;
my @preferred_region;

# Debug Output
use constant DEBUG => 0;

# Title-to-Region Mapping,
#  attempts to infer a release region
#  for those that are missing.
my %title_to_region = (
  USA => 'USA',
  Japan => 'JPN',
  Europe => 'EUR',

  Spain => 'SPA',
  Germany => 'GER',
  France => 'FRA',
  Korea => 'KOR',
  Brazil => 'BRA',
  Canada => 'CAN',
  Sweden => 'SWE',
  Italy => 'ITA',
  Australia => 'AUS',
  Netherlands => 'HOL',
  Asia => 'ASI',
  China => 'CHN',
);

############################
# Assign a numeric score to the passed title.
#  Preferred releases in order,
#  higher rev. gives bonus points,
#  skip_titles are major negative.
sub score_title
{
  my $title = shift;
  foreach my $frag (@skip_titles) {
    if (index($title, $frag) > -1) {
      return -1000;
    }
  }

  my $score = 0;
  for (my $i = 0; $i < scalar @preferred_region; $i ++) {
    my $reg = $preferred_region[$i];
    if ($title =~ m/\([^)]*$reg[^(]*\)/) {
      $score = (10000 - 100 * $i);
      last;
    }
  }

  # rev check
  if ($title =~ m/\(Rev ([^)]+)\)/) {
    $score += ord($1);
  }

  return $score;
}

# do basic / extended counts for an input xml
#  run once at start and once at end
sub counts
{
  my $doc = shift;

  # number of groups (games)
  my @groups = $doc->findnodes('/datafile/game');
  say STDERR "Group count in datafile: " . scalar @groups;

  # region for all releases
  my @releases = $doc->findnodes('/datafile/game/release/@region');
  say STDERR "Release count in datfile: " . scalar @releases;

  # number of clones
  my @clones =  $doc->findnodes('/datafile/game[@cloneof]');
  say STDERR "Clone count in datfile: " . scalar @clones;

  if (DEBUG) {
    my %region;
    map { $region{$_->toString()} ++ } @releases;
    say STDERR "Region / release count in datfile:";
    map { say STDERR "$_ = $region{$_}" } keys %region;
  }
}

############################
if (scalar @ARGV != 1) {
  die "Usage: $0 datfile\n";
}

############################
# Problematic game names
# Regions we don't want
# Preferred release
open (my $fp, '<', 'config.txt') or die "Can't open config.txt: $!\n";
my $mode = '';
while (my $line = <$fp>)
{
  chomp $line;
  $line =~ s/\s*#.*//g;
  next if $line eq '';

  if ($line eq 'NO_RELEASE') { $mode = 1; }
  elsif ($line eq 'SKIP_TITLES') { $mode = 2; }
  elsif ($line eq 'SKIP_REGIONS') { $mode = 3; }
  elsif ($line eq 'PREFERRED_REGIONS') { $mode = 4; }
  else {
    if ($mode == 1) { if ($line eq 'INFER') { $skip_empty_release = 0; } }
    elsif ($mode == 2) { push (@skip_titles, $line); }
    elsif ($mode == 3) { push (@skip_region, $line); }
    elsif ($mode == 4) { push (@preferred_region, $line); }
    else { say STDERR "Unknown line '$line' in config.txt."; }
  }
}
close($fp);

# Open the XML file and parse it.
my $parser = XML::LibXML->new();
$parser->keep_blanks(0);
my $doc = $parser->parse_file($ARGV[0]);

# Input file counts
say STDERR "Input counts:";
counts($doc);

############################
# Some entries don't have a Release...
#  Usually (Beta), (Arcade) etc
{
  say STDERR 'Removing no-release groups...';
  # Assemble search path
  my $xpath = '/datafile/game[not(release)]';

  my @nodes = $doc->findnodes($xpath);
  if ($skip_empty_release) {
    map { say STDERR " x " . $_->getAttribute('name') if DEBUG; $_->unlinkNode() } @nodes;
    say STDERR ' -> ' . (scalar @nodes) . ' groups removed.';
  } else {
    # Try to infer a release from the title.
    foreach my $game (@nodes) {
      my $name = $game->getAttribute('name');
      if ($name =~ m/\(World\)/)
      {
        # "World" release is currently classified as these three regions.
        my $node = XML::LibXML::Element->new("release");
        $node->setAttribute('name',$name);
        $node->setAttribute('region','JPN');
        $game->addChild($node);
        $node = XML::LibXML::Element->new("release");
        $node->setAttribute('name',$name);
        $node->setAttribute('region','USA');
        $game->addChild($node);
        $node = XML::LibXML::Element->new("release");
        $node->setAttribute('name',$name);
        $node->setAttribute('region','EUR');
        $game->addChild($node);
      } else {
        # Try to get a Region abbrev. back from the title.
        foreach my $region (keys %title_to_region)
        {
          if ($name =~ m/\([^)]*$region[^(]*\)/)
          {
            my $node = XML::LibXML::Element->new("release");
            $node->setAttribute('name',$name);
            $node->setAttribute('region',$title_to_region{$region});
            $game->addChild($node);
            last;
          }
        }
      }
    }
  }
}

############################
# XPath search for other things we don't like
#  (proto, sample, beta, etc)
if (scalar @skip_titles)
{
  say STDERR 'Removing disliked title groups...';
  # Assemble search path
  my $xpath = '/datafile/game[' .
    join(' or ',
      map { 'contains(./@name, "' . $_ . '")' } @skip_titles) .
    ']';

  my @nodes = $doc->findnodes($xpath);
  map { say STDERR " x " . $_->getAttribute('name') if DEBUG; $_->unlinkNode() } @nodes;
  say STDERR ' -> ' . (scalar @nodes) . ' groups removed.';
}

############################
# XPath search for regions to skip
#  (JPN etc region ... except with En language)
if (scalar @skip_region)
{
  say STDERR 'Removing disliked regions...';
  # Assemble search path
  my $xpath = '/datafile/game/release[not(contains(@name,"(En")) and (' .
    join(' or ',
      map { './@region="' . $_ . '"' } @skip_region) .
    ')]';

  # Delete releases that match problem text
  my $empty_groups = 0;

  my @nodes = $doc->findnodes($xpath);
  foreach my $release (@nodes) {
    my $parent = $release->parentNode;
    #say STDERR " x " . $release->getAttribute('name') if DEBUG;
    $release->unlinkNode();

    # Check parent to see if any other Release exists
    if (!$parent->exists('./release')) {
      # This was only release, so remove Parent above.
      say STDERR " x " . $release->getAttribute('name') if DEBUG;
      $empty_groups ++;
      $parent->unlinkNode();
    }
  }
  say STDERR ' -> ' . (scalar @nodes) . ' releases removed.';
  say STDERR ' -> ' . $empty_groups . ' groups removed.';
}

############################
# XPath search for "cloneof" and parent.
if (scalar @preferred_region)
{
  say STDERR 'Searching for all Clones...';
  my %clones;
  my $xpath = '/datafile/game[@cloneof]';
  map { push @{$clones{$_->getAttribute('cloneof')}},
          $_->getAttribute('name') }
    $doc->findnodes($xpath);

  say STDERR 'Reordering ' . (scalar keys %clones) . ' clone-groups...';
  # This hash contains a list of parent -> (clone1, clone2)
  # Identify the "best" and correct the rest
  foreach my $parent (sort keys %clones)
  {
    my @candidates = @{$clones{$parent}};
    if ($doc->exists('/datafile/game[@name="' . $parent . '"]'))
    {
      push (@candidates, $parent);
    }

    my $best_parent = -1;
    my $best_title = '';
    my $best_score = -10000;

    for(my $i = 0; $i < scalar @candidates; $i ++)
    {
      my $title_score = score_title($candidates[$i]);
      if ($title_score > $best_score) {
        $best_parent = $i;
        $best_title = $candidates[$i];
        $best_score = $title_score;
      }
    }

    if ($parent ne $best_title)
    {
      say STDERR " . BAD: $parent => $best_title (" . (scalar @candidates) . " in group)" if DEBUG;
      # Need to move the cloneof to somewhere else
      for(my $i = 0; $i < scalar @candidates; $i ++)
      {
        my ($node) = $doc->findnodes('/datafile/game[@name="' . $candidates[$i] . '"]');
        if ($i == $best_parent)
        {
          $node->removeAttribute('cloneof');
        } else {
          $node->setAttribute('cloneof' => $best_title);
        }
      }
    } else {
      say STDERR " . OK: $parent" if DEBUG;
    }
  }
}

# Output file counts
say STDERR "Output counts:";
counts($doc);

############################
# dump new XML
say STDERR "Writing final output.";
say $doc->toString(1);
