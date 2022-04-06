module github.com/operator-framework/operator-sdk

go 1.16

require (
	github.com/Microsoft/hcsshim v0.8.23 // indirect
	github.com/blang/semver/v4 v4.0.0
	github.com/fatih/structtag v1.1.0
	github.com/go-logr/logr v0.4.0
	github.com/go-task/slim-sprig v0.0.0-20210107165309-348f09dbbbc0
	github.com/google/uuid v1.2.0 // indirect
	github.com/iancoleman/strcase v0.2.0
	github.com/kr/text v0.2.0
	github.com/markbates/inflect v1.0.4
	github.com/maxbrunsfeld/counterfeiter/v6 v6.2.2
	github.com/onsi/ginkgo v1.16.5
	github.com/onsi/gomega v1.17.0
	github.com/operator-framework/api v0.11.1-0.20220110184307-ff6b5ebe3c25
	github.com/operator-framework/helm-operator-plugins v0.0.9-0.20211214200107-a423feffba25
	github.com/operator-framework/java-operator-plugins v0.1.0
	github.com/operator-framework/operator-lib v0.6.0
	github.com/operator-framework/operator-manifest-tools v0.1.6
	github.com/operator-framework/operator-registry v1.17.4
	github.com/prometheus/client_golang v1.11.0
	github.com/prometheus/client_model v0.2.0
	github.com/sergi/go-diff v1.1.0
	github.com/sirupsen/logrus v1.8.1
	github.com/spf13/afero v1.6.0
	github.com/spf13/cobra v1.3.0
	github.com/spf13/pflag v1.0.5
	github.com/spf13/viper v1.10.0
	github.com/stretchr/testify v1.7.0
	github.com/thoas/go-funk v0.8.0
	golang.org/x/mod v0.5.1
	golang.org/x/tools v0.1.8
	gomodules.xyz/jsonpatch/v3 v3.0.1
	helm.sh/helm/v3 v3.6.2
	k8s.io/api v0.23.1
	k8s.io/apiextensions-apiserver v0.23.0
	k8s.io/apimachinery v0.23.1
	k8s.io/apiserver v0.23.1 // indirect
	k8s.io/cli-runtime v0.22.1
	k8s.io/client-go v0.23.1
	k8s.io/kubectl v0.22.1
	sigs.k8s.io/controller-runtime v0.11.0
	sigs.k8s.io/controller-tools v0.7.0
	sigs.k8s.io/kubebuilder/v3 v3.2.0
	sigs.k8s.io/yaml v1.3.0
)

replace (
	// TODO(ryantking): investigate further, v1.5 breaks github.com/deislabs/oras, might be able to update whatever uses the old version of oras
	github.com/containerd/containerd => github.com/containerd/containerd v1.4.11
	// latest tag resolves to a very old version. this is only used for spinning up local test registries
	github.com/docker/distribution => github.com/docker/distribution v0.0.0-20191216044856-a8371794149d
	github.com/mattn/go-sqlite3 => github.com/mattn/go-sqlite3 v1.10.0
	k8s.io/api => k8s.io/api v0.22.1
	k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.22.1
	k8s.io/apimachinery => k8s.io/apimachinery v0.22.1
	k8s.io/apiserver => k8s.io/apiserver v0.22.1
	k8s.io/client-go => k8s.io/client-go v0.22.1
	sigs.k8s.io/controller-runtime => sigs.k8s.io/controller-runtime v0.10.0
)

// TODO(ryantking): Remove once https://github.com/operator-framework/operator-manifest-tools/pull/25 is merged and released
replace github.com/operator-framework/operator-manifest-tools => github.com/ryantking/operator-manifest-tools v0.1.7-0.20220125175539-7b851b6bddbb
