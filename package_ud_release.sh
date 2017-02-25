#!/bin/bash
# Prepares a UD release.
# Copyright © 2016, 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

if [ "$RELEASE" = "" ] || [ "$1" = "" ]; then
  echo "Usage: RELEASE=2.0 tools/package_ud_release.sh UD_Ancient_Greek UD_Ancient_Greek-PROIEL ..."
  echo "       UD repositories to be included in the release must be listed as arguments."
  echo "       Repositories without dev data will be skipped even if they are given as arguments."
  echo "       Use tools/check_files.pl to get the list of releasable repositories."
  exit 255
fi



#------------------------------------------------------------------------------
# Copies one UD treebank to the current folder (only files that shall be
# released). We assume that the current folder the parent of the source dir.
#------------------------------------------------------------------------------
function copy_data_repo
{
    local dstdir=release-$RELEASE/ud-treebanks-v$RELEASE
    echo Copying $1 to $dstdir
    rm -rf $dstdir/$1
    cp -r $1 $dstdir
    # Erase files that should not be released (.gitignore, .git, not-to-release).
    rm -rf $dstdir/$1/.git* $dstdir/$1/not-to-release
    # The training data in UD_Czech is split to four files because it is too large for Github.
    # However, it can be one file in our release, so join the files again in the release copy.
    if [ "$1" = "UD_Czech" ]; then
        cat $dstdir/$1/cs-ud-train-*.conllu > $dstdir/$1/cs-ud-train.conllu
        rm $dstdir/$1/cs-ud-train-*.conllu
    fi
    # Generate raw text files from CoNLL-U files. At present we do not maintain
    # the raw text files in Github repositories and only generate them for the release.
    # Also we want one cs-ud-train.txt and not four (see above).
    local lcode=$(ls $1 | grep ud-dev.conllu | perl -e '$x=<STDIN>; $x =~ m/(\S+)-ud-dev\.conllu/; print $1;')
    if [ "$lcode" = "" ] ; then echo Unknown language code ; fi
    for j in $dstdir/$1/*.conllu ; do
      tools/conllu_to_text.pl --lang $lcode < $j > $dstdir/$1/$(basename $j .conllu).txt
    done
}

#------------------------------------------------------------------------------



echo RELEASE $RELEASE

# Create the release folder.
mkdir -p release-$RELEASE/ud-treebanks-v$RELEASE

###!!! The following will no longer work since we require that all released repositories are given as arguments.
# If we received an argument, interpret it as a repository name and process only that repository.
# This is useful if maintainers of a treebank ask us to incorporate last-minute fixes.
#if [ ! -z "$1" ] ; then
#    copy_data_repo $1
#    exit
#fi

# Copy there the repositories that contain .conllu data (skip empty repositories!)
for i in $@ ; do if [ -f $i/*-ud-dev.conllu ] ; then copy_data_repo $i ; fi ; done
cd release-$RELEASE
tar czf ud-treebanks-v$RELEASE.tgz ud-treebanks-v$RELEASE
cd ..

# Prepare the current content of the tools repository as a separate package, also without .git and .gitignore.
pushd tools ; git pull --no-edit ; popd
cd release-$RELEASE
mkdir ud-tools-v$RELEASE
cp -r ../tools/* ud-tools-v$RELEASE
rm -rf ud-tools-v$RELEASE/.git* ud-tools-v$RELEASE/not-to-release
tar czf ud-tools-v$RELEASE.tgz ud-tools-v$RELEASE
cd ..

# Prepare the current content of the docs repository as a separate package, also without .git and .gitignore.
# Note that this is archiving the MarkDown source code of the documentation. See below for archiving the corresponding HTML.
pushd docs ; git checkout pages-source ; git pull --no-edit ; popd
cd release-$RELEASE
mkdir -p ud-documentation-v$RELEASE/markdown-source
cp -r ../docs/* ud-documentation-v$RELEASE/markdown-source
rm -rf ud-documentation-v$RELEASE/markdown-source/.git* ud-documentation-v$RELEASE/markdown-source/not-to-release
cd ..

# The surface form of documentation (i.e. the web content visible to the reader) is automatically generated
# in a separate Github repository. WARNING! Many folders contain generated files AUX.html and aux.html
# (besides AUX_.html and aux_.html). These should not be included in the package because that might prevent
# people from unpacking it in MS Windows (although some unpacking programs, like 7zip, will be able to overcome
# this by simply renaming the file to _aux.html before unpacking it). Note furthermore that we currently cannot
# force Jekyll (the page generator) to make all hyperlinks relative in order for the pages to work well offline.
# Many hyperlinks will be broken when viewing the pages, and the user will have to open individual pages from
# the file manager instead. However, it may still be useful to provide the HTML rendering, especially because
# of the embedded tree visualizations.
###!!!git clone git@github.com:UniversalDependencies/universaldependencies.github.io.git
pushd universaldependencies.github.io ; git pull --no-edit ; popd
cd release-$RELEASE
mkdir -p ud-documentation-v$RELEASE/html
cp -r ../universaldependencies.github.io/* ud-documentation-v$RELEASE/html
rm -rf ud-documentation-v$RELEASE/html/.git* ud-documentation-v$RELEASE/html/not-to-release
rm -f ud-documentation-v$RELEASE/html/*/*/{AUX,aux}.html
tar czf ud-documentation-v$RELEASE.tgz ud-documentation-v$RELEASE
cd ..
