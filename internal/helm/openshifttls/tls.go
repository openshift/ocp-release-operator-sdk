// Copyright 2026 The Operator-SDK Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Package openshifttls implements the OpenShift-specific centralized TLS
// security profile support required by OCPSTRAT-2611: it reads the TLS
// profile configured in the cluster's apiservers.config.openshift.io/cluster
// resource and applies it to the helm-operator's metrics server, then
// watches for profile changes and triggers a graceful restart to pick them
// up. This package is downstream-only (never proposed upstream) and wires
// itself into the generic run.ClusterTLSPolicy extension point via a blank
// import of this package from cmd/helm-operator/main.go.
package openshifttls

import (
	"context"
	"fmt"

	configv1 "github.com/openshift/api/config/v1"
	tlspkg "github.com/openshift/controller-runtime-common/pkg/tls"
	apimachruntime "k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/rest"
	ctrlclient "sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/manager"

	"github.com/operator-framework/operator-sdk/internal/cmd/helm-operator/run"
)

var log = logf.Log.WithName("openshifttls")

func init() {
	run.RegisterClusterTLSPolicy(&clusterTLSPolicy{})
}

// clusterTLSPolicy implements run.ClusterTLSPolicy by reading the TLS
// security profile from the cluster's APIServer resource and applying it to
// the manager's metrics server TLS configuration.
type clusterTLSPolicy struct {
	// initialProfile is the profile observed in Apply, carried forward to
	// Watch so SecurityProfileWatcher can detect drift from it.
	initialProfile configv1.TLSProfileSpec
}

// Apply fetches the cluster's TLS security profile and appends the
// corresponding TLS configuration to options.Metrics.TLSOpts. It fails open:
// on any error building a client or fetching the profile (e.g. running on a
// non-OpenShift cluster, or the APIServer CRD/object doesn't exist), it logs
// a warning and falls back to the default (Intermediate) profile rather than
// blocking operator startup.
func (p *clusterTLSPolicy) Apply(ctx context.Context, cfg *rest.Config, options manager.Options) (manager.Options, error) {
	scheme := options.Scheme
	if scheme == nil {
		scheme = apimachruntime.NewScheme()
	}
	if err := configv1.AddToScheme(scheme); err != nil {
		return options, fmt.Errorf("failed to register config.openshift.io/v1 scheme: %w", err)
	}
	options.Scheme = scheme

	k8sClient, err := ctrlclient.New(cfg, ctrlclient.Options{Scheme: scheme})
	if err != nil {
		log.Error(err, "Unable to create client to fetch cluster TLS profile; falling back to default TLS profile")
		k8sClient = nil
	}

	profile := fetchProfile(ctx, k8sClient)
	p.initialProfile = profile

	tlsConfigFunc, unsupported := tlspkg.NewTLSConfigFromProfile(profile)
	if len(unsupported) > 0 {
		log.Info("Cluster TLS profile references ciphers/groups unsupported by this Go runtime; they will be ignored",
			"unsupported", unsupported)
	}

	options.Metrics.TLSOpts = append(options.Metrics.TLSOpts, tlsConfigFunc)
	log.Info("Applied cluster TLS security profile to metrics server",
		"minTLSVersion", profile.MinTLSVersion, "ciphers", profile.Ciphers)

	return options, nil
}

// fetchProfile fetches the TLS profile from the cluster's APIServer resource
// using k8sClient, falling back to the default profile if k8sClient is nil
// (client construction failed) or the fetch itself errors (e.g. running on a
// non-OpenShift cluster, or the APIServer CRD/object doesn't exist).
//
// It takes a client.Client (rather than a *rest.Config) precisely so it can
// be unit tested against a fake client instead of a real cluster connection.
func fetchProfile(ctx context.Context, k8sClient ctrlclient.Client) configv1.TLSProfileSpec {
	if k8sClient == nil {
		return defaultProfile()
	}

	profile, err := tlspkg.FetchAPIServerTLSProfile(ctx, k8sClient)
	if err != nil {
		log.Error(err, "Unable to fetch TLS profile from APIServer (not running on OpenShift, or APIServer/cluster object missing?); falling back to default TLS profile")
		return defaultProfile()
	}

	return profile
}

// Watch registers a SecurityProfileWatcher that cancels ctx (triggering a
// graceful manager shutdown, followed by a container restart that re-fetches
// the profile) whenever the cluster's TLS profile changes from what was
// observed in Apply.
func (p *clusterTLSPolicy) Watch(ctx context.Context, mgr manager.Manager, cancel context.CancelFunc) error {
	watcher := &tlspkg.SecurityProfileWatcher{
		Client:                mgr.GetClient(),
		InitialTLSProfileSpec: p.initialProfile,
		OnProfileChange: func(_ context.Context, oldProfile, newProfile configv1.TLSProfileSpec) {
			log.Info("Cluster TLS security profile changed; triggering a graceful restart to apply it",
				"old", oldProfile, "new", newProfile)
			cancel()
		},
	}
	return watcher.SetupWithManager(mgr)
}

// defaultProfile returns the profile controller-runtime-common treats as the
// default (currently Intermediate) when the cluster has none configured.
func defaultProfile() configv1.TLSProfileSpec {
	// GetTLSProfileSpec(nil) never errors in the current implementation
	// (it always returns the default profile), but check defensively
	// rather than assume that never changes.
	spec, err := tlspkg.GetTLSProfileSpec(nil)
	if err != nil {
		log.Error(err, "Unable to determine default TLS profile; TLS MinVersion will be left unset")
		return configv1.TLSProfileSpec{}
	}
	return spec
}
