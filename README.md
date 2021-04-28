<img src="website/static/operator_logo_sdk_color.svg" height="125px"></img>

## Overview

This is the downstream repo for the
[Operator Framework's Operator SDK][upstream_repo]. The purpose of this repo is
to build downstream Operator SDK for OpenShift releases.

## Documentation

The downstream documentation can be found: [Downstream Docs][downstream_docs].
You can also refer to the upstream [Operator SDK website][sdk-docs].

## License

Operator SDK is under Apache 2.0 license. See the [LICENSE][license_file] file for details.

## Downstream structure

This repo is a mirror of the upstream
[`operator-framework/operator-sdk`][upstream_repo] repo plus some ci files.

The downstream ci files are as follows:

* ci - contains the CI related build files
* patches - contains the patches applied to downstream builds
* release/ansible - ansible operator release files
* release/helm - helm operator release files
* release/sdk - sdk operator release files
* vendor - unlike the upstream, we vendor in the dependencies downstream

## Syncing

When an upstream release is ready, you can sync down that release downstream.

### Verify upstream

Verify you have the upstream repo as a remote:

```
$ git remote -v
openshift       https://github.com/openshift/ocp-release-operator-sdk.git (fetch)
openshift       no_push (push)
origin  git@github.com:jmrodri/ocp-release-operator-sdk.git (fetch)
origin  git@github.com:jmrodri/ocp-release-operator-sdk.git (push)
upstream        https://github.com/operator-framework/operator-sdk.git (fetch)
upstream        no_push (push)
```

Ensure the `upstream` is up to date.

```
$ git fetch upstream
remote: Enumerating objects: 21, done.
remote: Counting objects: 100% (21/21), done.
remote: Compressing objects: 100% (15/15), done.
Unpacking objects: 100% (15/15), 17.36 KiB | 2.89 MiB/s, done.
remote: Total 15 (delta 8), reused 3 (delta 0), pack-reused 0
From https://github.com/operator-framework/operator-sdk
 * e3225a40..4c0a60dc  master                                                    -> upstream/master
```
### New release to master

Once the `upstream` has been verified. You can now sync the upstream release tag
you want. In this steps below we will sync `v1.4.1` to `master`.

To build simply use the `UPSTREAM-MERGE.sh` script.

`./UPSTREAM-MEGE.sh <UPSTREAM-TAG>`

Here is an example run using upstream tag `v1.4.1`

```
$ ./UPSTREAM-MERGE.sh v1.4.1
Already on 'master'
Your branch is up to date with 'origin/master'.
Already up to date.
Switched to a new branch 'v1.4.1-rebase-master'
Removing test/ansible/roles/inventorytest/tasks/main.yml
Removing test/ansible/requirements.yml
Removing ...
...
CONFLICT (file location): ...
...
Automatic merge failed; fix conflicts and then commit the result.
rm 'hack/generate/samples/internal/ansible/testdata/build/Dockerfile'
...
[v1.4.1-rebase-master f7bb26ab] Merge upstream tag v1.4.1
5338217e (tag: v1.4.1, upstream/latest) Release v1.4.1 (#4521)
5d6e333a [v1.4.x] docs/upgrade-sdk-version/v1.3.0.md: correct link to migration guide (#4517)
...

** Upstream merge complete! **
View the above incoming commits to verify all is well
(mirrors the commit listing the PR will show)

Now make a pull request.
```

When the script is finished, you will be in a `UPSTREAM-TAG-rebase-master`
branch. In our example above we were in `v1.4.1-rebase-master`. For more
information about the output see the [breakdown of UPSTREAM-MERGE.sh
output](#breakdown-of-upstream-merge.sh-output) section below.

At this point, verify things look okay. Ensure the patches apply, if they do not
you will have to either recreate the patch to make it apply, or remove it
entirely if it is no longer needed. This will require manual intervention and
inspection.

Once the patches have been verified, create a release PR downstream:

```
git push origin v1.4.1-rebase-master
```

#### Breakdown of UPSTREAM-MERGE.sh output

Running `UPSTREAM-MERGE.sh` will spew out a bunch of output. We'll break it down
here.

The script will verify your branch is up to date and create a new branch
`UPSTREAM-TAG-rebase-master`.

```
$ ./UPSTREAM-MERGE.sh v1.4.1
Already on 'master'
Your branch is up to date with 'origin/master'.
Already up to date.
Switched to a new branch 'v1.4.1-rebase-master'
```

Then the script will printout any files it needs to remove as part of syncing to
upstream. This can be many files when doing a major or minor update with
upstream. This is normal.

```
Removing test/ansible/roles/inventorytest/tasks/main.yml
Removing test/ansible/requirements.yml
Removing ...
```

If there are any conflicts, it will identify those files. It will *always* choose
the file from the upstream tag.

```
CONFLICT (file location): ...
...
Automatic merge failed; fix conflicts and then commit the result.
rm 'hack/generate/samples/internal/ansible/testdata/build/Dockerfile'
```

After removing and conflicted files are listed, the commits from the tags are
printed out:

```
[v1.4.1-rebase-master f7bb26ab] Merge upstream tag v1.4.1
5338217e (tag: v1.4.1, upstream/latest) Release v1.4.1 (#4521)
5d6e333a [v1.4.x] docs/upgrade-sdk-version/v1.3.0.md: correct link to migration guide (#4517)
e385e760 [v1.4.x] generate: fix multiple Go file type parsing bug (#4509)
67f9c8b8 (tag: v1.4.0) Release v1.4.0 (#4486)
26eacd81 update IMAGE_VERSION to v1.4.0 (#4484)
...
```

Finally you will get a completed message:

```
** Upstream merge complete! **
View the above incoming commits to verify all is well
(mirrors the commit listing the PR will show)

Now make a pull request.
```

### Patch release to specific release branch

There are times when you will want to bring an upstream patch release to the
downstream OpenShift release. For example, bringing down v1.3.2 to downstream
release-4.7.

We will use the same script, `UPSTREAM-MERGE.sh` except we will add the branch
we want to patch.

```
./UPSTREAM-MERGE.sh v1.3.2 release-4.7
```

Here is the output of running the above script.

```
$ ./UPSTREAM-MERGE.sh v1.3.2 release-4.7
Already on 'release-4.7'
Your branch is up to date with 'openshift/release-4.7'.
Already up to date.
Switched to a new branch 'v1.3.2-rebase-release-4.7'
Automatic merge went well; stopped before committing as requested
[v1.3.2-rebase-release-4.7 aebcb02a] Merge upstream tag v1.3.2
5dd883dc (tag: v1.3.2, upstream/v1.3.x) Release v1.3.2 (#4520)
73d76d0a [v1.3.x] docs/upgrade-sdk-version/v1.3.0.md: correct link to migration guide (#4516)
e4fc90c4 [v1.3.x] generate: fix multiple Go file type parsing bug (#4508)
0ec4b705 [v1.3.x] images/ansible-operator/Dockerfile: pin cryptography python package (#4510)
af8bc8dd (tag: v1.3.1) Release v1.3.1 (#4485)
835b648d [v1.3.x] bump IMAGE_VERSION to v1.3.1 (#4483)
9c178b76 [v1.3.x] generate: make CSV generator for Go GVKs package-aware (#4480)
9f7e16d2 [v1.3.x] Fixed invalid object names generated for long package names  (#4476)
16b8daee Align tutorial imports with test samples (#4465)
f340790f [v1.3.x]  Bug 1921727: Bundle validate should not fail because of warnings. (#4449) (#4458)
4bf11a29 [v1.3.x] Bug fix: helm operator uninstall is not properly checking for existing release (#4457)
ddcda902 Handle error when subscription doesn't match package name for `run bundle-upgrade` (#4454)
96970e9e [v1.3.x] Bug 1921458: `run bundle-upgrade` should handle error gracefully when a previous operator version doesn't exist (#4451)
4bee54fb generate: respect project version when getting package name (#4431) (#4443)
7f7cc9a6 [v1.3.x] (helm/v1,ansible/v1) fix download URLs and order of binary checks (#4412)
608aa050 [v1.3.x] Fix panic with "operator-sdk bundle validate" and OCI (#4386)
bebbbf98 testdata/go: regenerate with updated license date (#4388)
b5404095 docs: fix broken link (#4387)

** Upstream merge complete! **
View the above incoming commits to verify all is well
(mirrors the commit listing the PR will show)

Now make a pull request.
```

Just like sync to master, verify things look okay. Ensure the patches apply,
if they do not you will have to either recreate the patch to make it apply,
or remove it entirely if it is no longer needed. This will require manual
intervention and inspection.

Once the patches have been verified, create a release PR downstream:

```
git push origin v1.3.2-rebase-release-4.7
```

## Building

To build this downstream repo, you should use the `ci/prow.Makefile`. The
patches need to be applied first.

```
make -f ci/prow.Makefile patch build
```

## Patching

This downstream repo tries to maintain the upstream code as original as
possible. There are times when changes need to be made to make the upstream
source work downstream or to react to a release blocking bugzillas before they
can be merged upstream.

### `gendiff` method

This method uses the `gendiff` tool which can create patches from a set of files
that have a common backup extension. The `gendiff` tool will create a patch file
for all files in the given directory that have the matching common backup
extension. The patch is stored in the `patches` directory. They are applied
sequentially during the build process.

Let's walk through an example. Assume we need to patch
`cmd/operator-sdk/main.go` & `cmd/ansible-operator/main.go`.

1. create backup copies of *each* file with a specific extension. Note, the
   extension is used to group the changed files into a single patch.

   ```
   cp cmd/operator-sdk/main.go cmd/operator-sdk/main.go.bugxxx
   cp cmd/ansible-operator/main.go cmd/ansible-operator/main.go.bugxxx
   ```

1. make the necessary changes to the *original* files

   ```
   vi cmd/operator-sdk/main.go
   vi cmd/ansible-operator/main.go
   ```

1. once you are done create the patch using gendiff

   ```
   gendiff . .bugxxx > patches/07-bugxxx.patch
   ```

1. add the patch to the `patches` directory

   ```
   git add patches/07-bugxxx.patch
   ```

1. commit the new patch

   ```
   git commit --signoff
   ```

1. revert the changed original files

   ```
   git restore cmd/operator-sdk/main.go
   git restore cmd/ansible-operator/main.go
   ```

1. test the patch applies

   ```
   make -f ci/prow.Makefile patch
   # verify both main.go files were patched
   ```

1. restore the changed files again and push up your changes

   ```
   git restore cmd/operator-sdk/main.go
   git restore cmd/ansible-operator/main.go
   git push origin bugxxx
   ```

[downstream_docs]:https://docs.openshift.com/container-platform/4.6/operators/operator_sdk/osdk-getting-started.html
[upstream_repo]:https://github.com/operator-framework/operator-sdk/
[license_file]:./LICENSE
[sdk-docs]: https://sdk.operatorframework.io
[operator-framework-community]: https://github.com/operator-framework/community
[operator-framework-communication]: https://github.com/operator-framework/community#get-involved
[operator-framework-meetings]: https://github.com/operator-framework/community#meetings
[contribution-docs]: https://sdk.operatorframework.io/docs/contribution-guidelines/
