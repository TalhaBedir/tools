#!/usr/bin/env perl
# Evaluates quality of a UD treebank. Should help to determine if there are
# multiple treebanks in one language, which is the best one to use.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use udlib;

my $verbose = 0;
GetOptions
(
    'verbose' => \$verbose
);

# Path to the local copy of the UD repository (e.g., UD_Czech).
my $folder = $ARGV[0];
if(!defined($folder))
{
    die("Usage: $0 path-to-ud-folder");
}
my $record = udlib::get_ud_files_and_codes($folder);
my $metadata = udlib::read_readme($folder);
my $n = 0;
my $ntrain = 0;
my $ndev = 0;
my $ntest = 0;
my %lemmas;
my %tags;
my $n_words_with_features = 0;
my %udeprels;
foreach my $file (@{$record->{files}})
{
    open(FILE, "$folder/$file") or die("Cannot read $folder/$file: $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            s/\r?\n$//;
            my @f = split(/\t/, $_);
            my $form = $f[1];
            my $lemma = $f[2];
            my $upos = $f[3];
            my $feat = $f[5];
            my $udeprel = $f[7];
            $udeprel =~ s/:.*$//;
            $n++;
            if($file =~ m/ud-train/)
            {
                $ntrain++;
            }
            elsif($file =~ m/ud-dev/)
            {
                $ndev++;
            }
            elsif($file =~ m/ud-test/)
            {
                $ntest++;
            }
            $lemmas{$lemma}++;
            $tags{$upos}++;
            $n_words_with_features++ if($feat ne '_');
            $udeprels{$udeprel}++;
        }
    }
    close(FILE);
}
# Compute partial scores.
my %score;
#------------------------------------------------------------------------------
# Size. Project size to the interval <0; 1>.
$n = 1000000 if($n > 1000000);
$n = 1 if($n <= 0);
my $lognn = log(($n/1000)**2); $lognn = 0 if($lognn < 0);
$score{size} = $lognn / log(1000000);
#------------------------------------------------------------------------------
# Split. This is also very much related to size, but per individual parts.
$score{split} = 0.01;
$score{split} += 0.33 if($ntrain > 10000);
$score{split} += 0.33 if($ndev >= 10000);
$score{split} += 0.33 if($ntest >= 10000);
#------------------------------------------------------------------------------
# Lemmas. If the most frequent lemma is '_', we infer that the corpus does not annotate lemmas.
my @lemmas = sort {$lemmas{$b} <=> $lemmas{$a}} (keys(%lemmas));
my $lsource = $metadata->{Lemmas} eq 'manual native' ? 1 : $metadata->{Lemmas} eq 'converted with corrections' ? 0.9 : $metadata->{Lemmas} eq 'converted from manual' ? 0.8 : $metadata->{Lemmas} eq 'automatic with corrections' ? 0.5 : 0.4;
$score{lemmas} = (scalar(@lemmas) < 1 || $lemmas[0] eq '_') ? 0.01 : $lsource;
#------------------------------------------------------------------------------
# Tags. How many of the 17 universal POS tags have been seen at least once?
# Some languages may not have use for some tags, and some tags may be very rare.
# But for comparison within one language this is useful. If a tag exists in the
# language but the corpus does not contain it, maybe it cannot distinguish it.
$score{tags} = scalar(keys(%tags)) / 17;
$score{tags} = 0.01 if($score{tags}<0.01);
#------------------------------------------------------------------------------
# Features. There is no universal rule how many features must be in every language.
# It is only sure that every language can have some features. It may be misleading
# to say that a treebank has features if at least one feature has been observed:
# Some treebanks have just NumType=Card with every NUM but nothing else (and this
# is just a consequence of how Interset works). Therefore we will distinguish several
# very coarse-grained degrees.
my $fsource = $metadata->{Features} eq 'manual native' ? 1 : $metadata->{Features} eq 'converted with corrections' ? 0.9 : $metadata->{Features} eq 'converted from manual' ? 0.8 : $metadata->{Features} eq 'automatic with corrections' ? 0.5 : 0.4;
$score{features} = $n_words_with_features==0 ? 0.01 : $n_words_with_features<$n/3 ? 0.3*$fsource : $n_words_with_features<$n/2 ? 0.5*$fsource : 1*$fsource;
#------------------------------------------------------------------------------
# Dependency relations. How many of the 37 universal relation types have been
# seen at least once? Some languages may not have use for some relations, and
# some relations may be very rare. But for comparison within one language this
# is useful. If a relation exists in the language but the corpus does not
# contain it, maybe it cannot distinguish it.
$score{udeprels} = scalar(keys(%udeprels)) / 37;
$score{udeprels} = 0.01 if($score{udeprels}<0.01);
#------------------------------------------------------------------------------
# Udapi MarkBugs (does the content follow the guidelines?)
# Measured only if udapy is found at the expected place.
$score{udapi} = 1;
if(-x 'udapi-python/bin/udapy')
{
    my $output = `(cat $folder/*.conllu | udapi-python/bin/udapy ud.MarkBugs 2>&1) | grep TOTAL`;
    if($output =~ m/(\d+)/)
    {
        my $nbugs = $1;
        # Evaluate the proportion of bugs to the size of the treebank.
        # If half of the tokens (or more) have bugs, it is terrible enough; let's set the ceiling at 50%.
        $nbugs = $n/2 if($nbugs>$n/2);
        $score{udapi} = 1-$nbugs/($n/2);
        $score{udapi} = 0.01 if($score{udapi}<0.01);
    }
}
#------------------------------------------------------------------------------
# Evaluate availability.
###!!! We should read the information from the README file and verify in the data that '_' is not the most frequent word form!
###!!! However, currently it is hardcoded here, based on language-treebank code.
my $availability = 1;
if($record->{ltcode} =~ m/^(ja_ktc|en_esl|ko_sejong|ar_nyuad)$/)
{
    # These treebanks are not available for free.
    $availability = 0.01;
}
elsif($record->{ltcode} eq 'fr_ftb')
{
    # This treebank is available for free but the user must obtain it separately.
    $availability = 0.1;
}
#------------------------------------------------------------------------------
# Score of empty treebanks should be zero regardless of the other features.
my $score = 0;
if($n > 1)
{
    my %weights =
    (
        'size'     => 10,
        'split'    => 2,
        'lemmas'   => 3,
        'tags'     => 3,
        'features' => 3,
        'udeprels' => 3,
        'udapi'    => 9
    );
    my @dimensions = sort(keys(%weights));
    my $wsum = 0;
    foreach my $d (@dimensions)
    {
        $wsum += $weights{$d};
    }
    foreach my $d (@dimensions)
    {
        my $nweight = $weights{$d} / $wsum;
        $score += $nweight * $score{$d};
        if($verbose)
        {
            print STDERR ("(weight=$nweight) * (score{$d}=$score{$d})\n");
        }
    }
    # The availability dimension is a show stopper. Instead of weighted combination, we multiply the score by it.
    if($verbose)
    {
        print STDERR ("(TOTAL score=$score) * (availability=$availability) = ");
    }
    $score *= $availability;
    if($verbose)
    {
        print STDERR ("$score\n");
    }
}
my $stars = sprintf("%d", $score*10+0.5)/2;
if($verbose)
{
    print STDERR ("STARS = $stars\n");
}
print("$folder\t$score\t$stars\n");