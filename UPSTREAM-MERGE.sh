#!/bin/bash
#
# This script takes as arguments:
# $1 - [REQUIRED] upstream version as the first argument to merge
# $2 - [optional] branch to update, defaults to master. could be a versioned release branch, e.g., release-3.10
# $3 - [optional] non-openshift remote to pull code from, defaults to upstream
#
# Note: this script is only maintained in the master branch. Other branches
# should copy this script into that branch in case newer changes have been
# made. Something like this will get the file from the master branch without
# staging it: git show master:UPSTREAM-MERGE.sh > UPSTREAM-MERGE.sh
#
# Warning: this script resolves all conflicts by overwritting the conflict with
# the upstream version. If a SDK specific patch was made downstream that is
# not in the incoming upstream code, the changes will be lost.
#
# Origin remote is assumed to point to openshift/ocp-release-operator-sdk

version=$1
rebase_branch=${2:-master}
upstream_remote=${3:-upstream}

# sanity checks
if [[ -z "$version" ]]; then
  echo "Version argument must be defined."
  exit 1
fi

sdk_repo=$(git remote get-url "$upstream_remote")
if [[ $sdk_repo != "https://github.com/operator-framework/operator-sdk.git" ]]; then
  echo "Upstream remote url should be set to kubernetes-sigs repo."
  exit 1
fi

# check state of working directory
git diff-index --quiet HEAD || { printf "!! Git status not clean, aborting !!\\n\\n%s" "$(git status)"; exit 1; }

# update remote, including tags (-t)
git fetch -t "$upstream_remote"

# do work on the correct branch
git checkout "$rebase_branch"
remote_branch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u})
if [[ $? -ne 0 ]]; then
  echo "Your branch is not properly tracking upstream as required, aborting."
  exit 1
fi
git merge "$remote_branch"
git checkout -b "$version"-rebase-"$rebase_branch" || { echo "Expected branch $version-rebase-$rebase_branch to not exist, delete and retry."; exit 1; }

# do the merge, but don't commit so tweaks below are included in commit
git merge --no-commit tags/"$version"

# preserve our version of these files
# git checkout HEAD -- OWNERS Makefile .gitignore
git checkout HEAD -- OWNERS_ALIASES

# unmerged files are overwritten with the upstream copy
unmerged_files=$(git diff --name-only --diff-filter=U --exit-code)
differences=$?

if [[ $differences -eq 1 ]]; then
  unmerged_files_oneline=$(echo "$unmerged_files" | paste -s -d ' ')
  unmerged=$(git status --porcelain $unmerged_files_oneline | sed 's/ /,/')

  # both deleted => remove => DD
  # added by us => remove => AU
  # deleted by them => remove  => UD
  # deleted by us => remove => DU
  # added by them => add => UA
  # both added => take theirs => AA
  # both modified => take theirs => UU
  for line in $unmerged
  do
      IFS=","
      set $line
      case $1 in
          "DD" | "AU" | "UD" | "DU")
          git rm -- $2
          ;;
          "UA")
          git add -- $2
          ;;
          "AA" | "UU")
          git checkout --theirs -- $2
          git add -- $2
          ;;
      esac
  done

  if [[ $(git diff --check) ]]; then
    echo "All conflict markers should have been taken care of, aborting."
    exit 1
  fi

else
  unmerged_files="<NONE>"
fi

# update vendor
go mod vendor
# capture $? of go mod vendor, if it fails skip the add
git add vendor


# TODO (zeus): Service Catalog put the upstream Makefile into Makefile.sc
# # update upstream Makefile changes, but don't overwrite build patch
# # script executor must manually decline the build patch change, the diff may
# #  contain other changes that need accepting
# git show tags/"$version":Makefile > Makefile.sc
# git add --patch --interactive Makefile.sc
# git checkout Makefile.sc

# bump UPSTREAM-VERSION file
echo "$version" > UPSTREAM-VERSION
git add UPSTREAM-VERSION

# just to make sure an old version merge is not being made
git diff --staged --quiet && { echo "No changed files in merge?! Aborting."; exit 1; }

# make local commit
git commit -m "Merge upstream tag $version" -m "Operator SDK $version" -m "Merge executed via ./UPSTREAM-MERGE.sh $version $upstream_remote $rebase_branch" -m "$(printf "Overwritten conflicts:\\n%s" "$unmerged_files")"

# verify merge is correct
git --no-pager log --oneline "$(git merge-base origin/"$rebase_branch" tags/"$version")"..tags/"$version"

printf "\\n** Upstream merge complete! **\\n"
echo "View the above incoming commits to verify all is well"
echo "(mirrors the commit listing the PR will show)"
echo ""
echo "Now make a pull request."
#echo "Now make a pull request, after it's LGTMed make the tag:"
#echo "$ git checkout $rebase_branch
#$ git pull
#$ git tag <origin version>-$version
##$ git push origin <origin version>-$version"
