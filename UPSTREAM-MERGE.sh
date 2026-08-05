#!/bin/bash
#
# This script takes as arguments:
# $1 - [REQUIRED] upstream version as the first argument to merge
# $2 - [optional] branch to update, defaults to main. could be a versioned release branch, e.g., release-3.10
# $3 - [optional] non-openshift remote to pull code from, defaults to upstream
#
# Note: this script is only maintained in the main branch. Other branches
# should copy this script into that branch in case newer changes have been
# made. Something like this will get the file from the main branch without
# staging it: git show main:UPSTREAM-MERGE.sh > UPSTREAM-MERGE.sh
#
# Warning: this script resolves all conflicts by overwritting the conflict with
# the upstream version. If a SDK specific patch was made downstream that is
# not in the incoming upstream code, the changes will be lost.
#
# Origin remote is assumed to point to openshift/ocp-release-operator-sdk

version=$1
rebase_branch=${2:-main}
upstream_remote=${3:-upstream}

# sanity checks
if [[ -z "$version" ]]; then
  echo "Version argument must be defined."
  exit 1
fi

sdk_repo=$(git remote get-url "$upstream_remote")
# Accept common URL forms for operator-framework/operator-sdk (CI may rewrite remotes).
if [[ ! "$sdk_repo" =~ ^((https?://)?(git@)?)github\.com[:/]+operator-framework/operator-sdk(\.git)?/?$ ]]; then
  echo "Upstream remote url should point at operator-framework/operator-sdk (got: $sdk_repo)."
  exit 1
fi

# check state of working directory
git diff-index --quiet HEAD || { printf "!! Git status not clean, aborting !!\n\n%s" "$(git status)"; exit 1; }

# update remote, including tags (-t)
git fetch -t "$upstream_remote"

# do work on the correct branch
git checkout "$rebase_branch" || { echo "Failed to checkout $rebase_branch, aborting."; exit 1; }
remote_branch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u})
if [[ $? -ne 0 ]]; then
  echo "Your branch is not properly tracking a remote as required, aborting."
  exit 1
fi
git merge "$remote_branch" || { echo "Failed to merge $remote_branch, aborting."; exit 1; }
# Replace a leftover local rebase branch from a prior failed attempt when running in CI.
if git show-ref --verify --quiet "refs/heads/${version}-rebase-${rebase_branch}"; then
  echo "Deleting existing local branch ${version}-rebase-${rebase_branch}"
  git branch -D "${version}-rebase-${rebase_branch}"
fi
git checkout -b "$version"-rebase-"$rebase_branch" || { echo "Expected branch $version-rebase-$rebase_branch to not exist, delete and retry."; exit 1; }

# do the merge, but don't commit so tweaks below are included in commit
git merge --no-commit tags/"$version"

# preserve our version of these files
# git checkout HEAD -- OWNERS Makefile .gitignore
git checkout HEAD -- OWNERS_ALIASES README.md

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


# TODO (zeus): Service Catalog put the upstream Makefile into Makefile.sc
# # update upstream Makefile changes, but don't overwrite build patch
# # script executor must manually decline the build patch change, the diff may
# #  contain other changes that need accepting
# git show tags/"$version":Makefile > Makefile.sc
# git add --patch --interactive Makefile.sc
# git checkout Makefile.sc

# update upstream README.md changes
git show tags/"$version":README.md > README-sdk.md
git add README-sdk.md

# bump UPSTREAM-VERSION file
echo "$version" > UPSTREAM-VERSION
git add UPSTREAM-VERSION

# Edit the version in the patch so that -ocp is properly appended
sed -i.bak -e "s/+export SIMPLE_VERSION = .*/+export SIMPLE_VERSION = ${version}-ocp/" patches/03-setversion.patch
rm -f patches/03-setversion.patch.bak
git add patches/03-setversion.patch

# just to make sure an old version merge is not being made
git diff --staged --quiet && { echo "No changed files in merge?! Aborting."; exit 1; }

# make local commit
git commit -m "Merge upstream tag $version" -m "Operator SDK $version" -m "Merge executed via ./UPSTREAM-MERGE.sh $version $rebase_branch $upstream_remote" -m "$(printf "Overwritten conflicts:\\n%s" "$unmerged_files")"

# verify merge is correct
git --no-pager log --oneline "$(git merge-base origin/"$rebase_branch" tags/"$version")"..tags/"$version"

# update vendor directory, abort if there's an error encountered
go mod tidy && go mod vendor || { echo "go mod vendor failed. Aborting!"; exit 1; }
# make sure that the vendor directory is actually updated 
if ! git diff --quiet vendor/; then
  # add the changes of go mod vendor
  git add vendor
  # make local commit
  git commit -m "UPSTREAM: <drop>: Update vendor directory"
else
  echo "No changed files in vendor directory. Skipping add."
fi

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
